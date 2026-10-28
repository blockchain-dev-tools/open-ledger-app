//! 阶段 3 验收：Bitcoin 地址与多输入签名。
//!
//! 地址与 `open_ledger_biz::btc::derive_address`（独立代码路径）比对；
//! 签名直接对 32 字节 sighash 进行（不再多套一层 keccak），与
//! `sign_prehash_recoverable` 逐字节一致。

use std::sync::{Arc, Mutex};

use chain_app_api::*;
use chain_app_bitcoin::BitcoinFactory;
use chain_app_runtime::{ReviewDecision, Runtime, RuntimeReply};

const MNEMONIC: &str =
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
const BTC_PATH: &str = "m/84'/0'/0'/0/0";

struct CryptoKeys {
    seed: Vec<u8>,
    sign_calls: Mutex<usize>,
}

impl CryptoKeys {
    fn new() -> Self {
        Self {
            seed: open_ledger_crypto::bip39::mnemonic_to_seed(MNEMONIC, "")
                .unwrap()
                .to_vec(),
            sign_calls: Mutex::new(0),
        }
    }

    /// 按模块请求的路径派生；测试替身不能忽略路径，否则默认路径的缺陷会被掩盖。
    fn private_key_at(&self, path: &[u32]) -> Vec<u8> {
        let mut text = String::from("m");
        for component in path {
            if *component >= 0x8000_0000 {
                text.push_str(&format!("/{}'", component - 0x8000_0000));
            } else {
                text.push_str(&format!("/{component}"));
            }
        }
        open_ledger_biz::hdkey::derive_secp256k1_private_key(&self.seed, &text).unwrap()
    }
}

impl KeyService for CryptoKeys {
    fn public_key(&self, request: &PublicKeyRequest) -> Result<PublicKey, HostError> {
        let compressed = request.output == KeyOutput::CompressedSecp256k1;
        let bytes = open_ledger_crypto::secp256k1::public_key_bytes(
            &self.private_key_at(&request.path),
            compressed,
        )
        .map_err(|e| HostError::Unavailable(e.to_string()))?;
        Ok(PublicKey {
            bytes,
            chain_code: None,
        })
    }

    fn sign(
        &self,
        _auth: &SignAuthorization,
        operation: &SignOperation,
    ) -> Result<Signature, HostError> {
        *self.sign_calls.lock().unwrap() += 1;
        let mut digest = [0u8; 32];
        if operation.input.len() != 32 {
            return Err(HostError::Denied("btc expects a 32-byte sighash".into()));
        }
        digest.copy_from_slice(&operation.input);
        // 直接签 sighash —— 不再多套一层 keccak。
        let signature = open_ledger_crypto::secp256k1::sign_prehash_recoverable(
            &self.private_key_at(&operation.path),
            &digest,
            |v| v,
        )
        .map_err(|e| HostError::Unavailable(e.to_string()))?;
        Ok(Signature {
            operation_id: operation.operation_id,
            bytes: signature[1..65].to_vec(),
            recovery_id: Some(signature[0]),
        })
    }
}

struct NoStorage;

impl StorageService for NoStorage {
    fn read(&mut self, _scope: &StorageScope, _key: &str) -> Result<Option<Vec<u8>>, HostError> {
        Ok(None)
    }
    fn write(&mut self, _: &StorageScope, _: &str, _: Vec<u8>) -> Result<(), HostError> {
        Ok(())
    }
    fn delete(&mut self, _: &StorageScope, _: &str) -> Result<(), HostError> {
        Ok(())
    }
}

fn policy() -> CapabilitySet {
    CapabilitySet {
        derivation_rules: vec![DerivationRule {
            derivation_scheme: DerivationScheme::Bip32Secp256k1,
            curve: Curve::Secp256k1,
            depth: 5,
            hardened_positions: vec![0, 1, 2],
            max_index: 1000,
        }],
        allow_chain_code: false,
        allow_signing: true,
        allow_storage: false,
    }
}

struct Fixture {
    runtime: Runtime,
    session: SessionId,
}

fn setup() -> Fixture {
    let mut runtime = Runtime::new(
        "vault-a",
        Default::default(),
        Arc::new(CryptoKeys::new()),
        Box::new(NoStorage),
    );
    runtime
        .register_module(Arc::new(BitcoinFactory), &policy())
        .unwrap();
    let (session, _) = runtime.open_app("openledger.bitcoin").unwrap();
    Fixture { runtime, session }
}

fn path_bytes() -> Vec<u8> {
    let mut out = vec![5u8];
    for component in [0x8000_0054u32, 0x8000_0000, 0x8000_0000, 0, 0] {
        out.extend_from_slice(&component.to_be_bytes());
    }
    out
}

fn apdu(ins: u8, data: &[u8]) -> Vec<u8> {
    let mut out = vec![0xE1, ins, 0x00, 0x00, data.len() as u8];
    out.extend_from_slice(data);
    out
}

fn sign_apdu(sighashes: &[[u8; 32]]) -> Vec<u8> {
    let mut data = path_bytes();
    data.push(sighashes.len() as u8);
    for sighash in sighashes {
        data.extend_from_slice(sighash);
    }
    apdu(0x44, &data)
}

fn submit(fixture: &mut Fixture, bytes: Vec<u8>) -> RuntimeReply {
    fixture
        .runtime
        .submit_wire(fixture.session, Wire::LedgerApdu, bytes)
        .unwrap()
}

fn expect_emit(reply: RuntimeReply) -> Vec<u8> {
    match reply {
        RuntimeReply::Emit { payload, .. } => payload,
        other => panic!("expected emit, got {other:?}"),
    }
}

fn expect_review(reply: RuntimeReply) -> ReviewId {
    match reply {
        RuntimeReply::Review { review_id, .. } => review_id,
        other => panic!("expected review, got {other:?}"),
    }
}

fn approve(fixture: &mut Fixture, review_id: ReviewId) -> Vec<u8> {
    expect_emit(
        fixture
            .runtime
            .resolve_review(fixture.session, review_id, ReviewDecision::Approve)
            .unwrap(),
    )
}

fn expected_address() -> String {
    let seed = open_ledger_crypto::bip39::mnemonic_to_seed(MNEMONIC, "").unwrap();
    open_ledger_biz::btc::derive_address(&seed, BTC_PATH).unwrap()
}

// ── 用例 ──────────────────────────────────────────────────────────────

#[test]
fn address_matches_the_library_derivation() {
    let mut fixture = setup();
    let payload = expect_emit(submit(&mut fixture, apdu(0x40, &path_bytes())));

    let address = String::from_utf8(payload[..payload.len() - 2].to_vec()).unwrap();
    assert_eq!(&payload[payload.len() - 2..], &[0x90, 0x00]);
    assert_eq!(address, expected_address());
    assert!(address.starts_with("bc1q"), "{address}");
}

#[test]
fn empty_data_uses_the_default_bip84_path() {
    let mut fixture = setup();
    let payload = expect_emit(submit(&mut fixture, apdu(0x40, &[])));
    let address = String::from_utf8(payload[..payload.len() - 2].to_vec()).unwrap();
    assert_eq!(address, expected_address());
}

#[test]
fn single_input_signature_matches_prehash_signing() {
    let mut fixture = setup();
    let sighash = [0x11u8; 32];
    let review_id = expect_review(submit(&mut fixture, sign_apdu(&[sighash])));
    let payload = approve(&mut fixture, review_id);

    assert_eq!(payload.len(), 67);
    assert_eq!(&payload[65..], &[0x90, 0x00]);
    assert!(payload[0] == 27 || payload[0] == 28);

    let seed = open_ledger_crypto::bip39::mnemonic_to_seed(MNEMONIC, "").unwrap();
    let private_key = open_ledger_biz::hdkey::derive_secp256k1_private_key(&seed, BTC_PATH).unwrap();
    let expected =
        open_ledger_crypto::secp256k1::sign_prehash_recoverable(&private_key, &sighash, |v| v)
            .unwrap();
    assert_eq!(payload[0], 27 + expected[0]);
    assert_eq!(&payload[1..65], &expected[1..65]);
}

#[test]
fn multi_input_returns_one_signature_per_input() {
    let mut fixture = setup();
    let sighashes = [[0x21u8; 32], [0x22u8; 32], [0x23u8; 32]];
    let review_id = expect_review(submit(&mut fixture, sign_apdu(&sighashes)));
    let payload = approve(&mut fixture, review_id);

    assert_eq!(payload.len(), 3 * 65 + 2);
    assert_eq!(&payload[3 * 65..], &[0x90, 0x00]);

    let seed = open_ledger_crypto::bip39::mnemonic_to_seed(MNEMONIC, "").unwrap();
    let private_key = open_ledger_biz::hdkey::derive_secp256k1_private_key(&seed, BTC_PATH).unwrap();
    for (index, sighash) in sighashes.iter().enumerate() {
        let expected =
            open_ledger_crypto::secp256k1::sign_prehash_recoverable(&private_key, sighash, |v| v)
                .unwrap();
        let start = index * 65;
        assert_eq!(payload[start], 27 + expected[0], "input {index} v");
        assert_eq!(&payload[start + 1..start + 65], &expected[1..65], "input {index}");
    }
}

#[test]
fn rejecting_returns_user_denied_for_every_input() {
    let mut fixture = setup();
    let review_id = expect_review(submit(&mut fixture, sign_apdu(&[[0x31u8; 32], [0x32u8; 32]])));
    let payload = expect_emit(
        fixture
            .runtime
            .resolve_review(fixture.session, review_id, ReviewDecision::Reject)
            .unwrap(),
    );
    assert_eq!(payload, vec![0x69, 0x85]);
}

#[test]
fn zero_inputs_are_rejected() {
    let mut fixture = setup();
    assert_eq!(
        expect_emit(submit(&mut fixture, sign_apdu(&[]))),
        vec![0x6A, 0x80]
    );
}

#[test]
fn more_than_sixteen_inputs_are_rejected() {
    let mut fixture = setup();
    let mut data = path_bytes();
    data.push(17);
    data.extend_from_slice(&[0x41u8; 32]);
    assert_eq!(
        expect_emit(submit(&mut fixture, apdu(0x44, &data))),
        vec![0x6A, 0x80]
    );
}

#[test]
fn non_zero_p1_is_rejected() {
    let mut fixture = setup();
    let mut bytes = apdu(0x40, &path_bytes());
    bytes[2] = 0x01;
    assert_eq!(expect_emit(submit(&mut fixture, bytes)), vec![0x6A, 0x86]);
}

#[test]
fn unknown_ins_is_rejected() {
    let mut fixture = setup();
    assert_eq!(
        expect_emit(submit(&mut fixture, apdu(0x99, &[]))),
        vec![0x6D, 0x00]
    );
}
