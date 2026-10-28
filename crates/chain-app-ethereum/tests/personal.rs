//! 阶段 2c 切片 1 验收：`E0 08 SIGN_PERSONAL_MESSAGE`。
//!
//! 覆盖单块、多块收集、批准后的字节布局、拒绝与协议边界；批准结果与旧
//! Dart 路径（`open_ledger_biz::eth::sign_personal_message`）逐字节一致。

use std::sync::{Arc, Mutex};

use chain_app_api::*;
use chain_app_ethereum::EthereumFactory;
use chain_app_runtime::{ReviewDecision, Runtime, RuntimeReply};

const MNEMONIC: &str =
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
const EXPECTED_ADDRESS: &str = "0x9858EfFD232B4033E47d90003D41EC34EcaEda94";
const MESSAGE: &[u8] = b"Hello Open Ledger App";

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

    fn private_key(&self, path: &[u32]) -> Vec<u8> {
        open_ledger_biz::hdkey::derive_secp256k1_private_key(&self.seed, &path_string(path)).unwrap()
    }
}

fn path_string(path: &[u32]) -> String {
    let mut out = String::from("m");
    for component in path {
        if *component >= 0x8000_0000 {
            out.push_str(&format!("/{}'", component - 0x8000_0000));
        } else {
            out.push_str(&format!("/{component}"));
        }
    }
    out
}

impl KeyService for CryptoKeys {
    fn public_key(&self, request: &PublicKeyRequest) -> Result<PublicKey, HostError> {
        let private_key = self.private_key(&request.path);
        let bytes = open_ledger_crypto::secp256k1::public_key_bytes(&private_key, false)
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
        let SignScheme::EcdsaPrehash { digest_len, .. } = operation.scheme else {
            return Err(HostError::Denied("unsupported scheme".into()));
        };
        if usize::from(digest_len) != operation.input.len() || digest_len != 32 {
            return Err(HostError::Denied("digest length".into()));
        }
        let private_key = self.private_key(&operation.path);
        let mut digest = [0u8; 32];
        digest.copy_from_slice(&operation.input);
        let signature =
            open_ledger_crypto::secp256k1::sign_prehash_recoverable(&private_key, &digest, |v| v)
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
            max_index: 100,
        }],
        allow_chain_code: false,
        allow_signing: true,
        allow_storage: false,
    }
}

struct Fixture {
    runtime: Runtime,
    keys: Arc<CryptoKeys>,
    session: SessionId,
}

fn setup() -> Fixture {
    let keys = Arc::new(CryptoKeys::new());
    let mut runtime = Runtime::new(
        "vault-a",
        Default::default(),
        keys.clone(),
        Box::new(NoStorage),
    );
    runtime
        .register_module(Arc::new(EthereumFactory), &policy())
        .unwrap();
    let (session, _) = runtime.open_app("openledger.ethereum").unwrap();
    Fixture {
        runtime,
        keys,
        session,
    }
}

fn default_path() -> Vec<u32> {
    vec![0x8000_002C, 0x8000_003C, 0x8000_0000, 0, 0]
}

fn path_bytes() -> Vec<u8> {
    let path = default_path();
    let mut out = vec![path.len() as u8];
    for component in path {
        out.extend_from_slice(&component.to_be_bytes());
    }
    out
}

fn apdu(p1: u8, p2: u8, data: &[u8]) -> Vec<u8> {
    let mut out = vec![0xE0, 0x08, p1, p2, data.len() as u8];
    out.extend_from_slice(data);
    out
}

/// 首块：`[path][length u32 BE][chunk]`。
fn first_block(message: &[u8], declared: usize, chunk_len: usize) -> Vec<u8> {
    let mut data = path_bytes();
    data.extend_from_slice(&(declared as u32).to_be_bytes());
    data.extend_from_slice(&message[..chunk_len]);
    apdu(0x00, 0x00, &data)
}

fn more_block(chunk: &[u8]) -> Vec<u8> {
    apdu(0x80, 0x00, chunk)
}

fn submit(fixture: &mut Fixture, bytes: Vec<u8>) -> RuntimeReply {
    fixture
        .runtime
        .submit_wire(fixture.session, Wire::LedgerApdu, bytes)
        .unwrap()
}

/// 投递确认：`Collecting` 之后 Runtime 仍可继续收下一块。
fn ack(fixture: &mut Fixture, reply: &RuntimeReply) {
    if let RuntimeReply::Emit {
        exchange_id, state, ..
    } = reply
    {
        assert_eq!(*state, OperationState::Collecting);
        fixture
            .runtime
            .delivery_result(fixture.session, *exchange_id, DeliveryAck::Acknowledged)
            .unwrap();
    }
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

// ── 用例 ──────────────────────────────────────────────────────────────

#[test]
fn single_block_message_parks_a_sign_review() {
    let mut fixture = setup();
    let reply = submit(&mut fixture, first_block(MESSAGE, MESSAGE.len(), MESSAGE.len()));

    match reply {
        RuntimeReply::Review {
            review_id,
            document,
            action,
        } => {
            assert_eq!(document.operation, OperationKind::Message);
            assert_eq!(document.account.as_deref(), Some(EXPECTED_ADDRESS));
            assert_eq!(document.parse_status, ParseStatus::Complete);
            assert!(matches!(action, ReviewAction::Sign(ref plan) if plan.operations.len() == 1));
            assert_eq!(fixture.runtime.pending_reviews(), 1);
            // 审阅阶段还没有签名。
            assert_eq!(*fixture.keys.sign_calls.lock().unwrap(), 0);
            let _ = review_id;
        }
        other => panic!("expected review, got {other:?}"),
    }
}

#[test]
fn approving_returns_the_same_bytes_as_the_legacy_path() {
    let mut fixture = setup();
    let review_id = expect_review(submit(
        &mut fixture,
        first_block(MESSAGE, MESSAGE.len(), MESSAGE.len()),
    ));

    let payload = approve(&mut fixture, review_id);
    assert_eq!(payload.len(), 65 + 2);
    assert_eq!(&payload[65..], &[0x90, 0x00]);
    assert!(payload[0] == 27 || payload[0] == 28);

    let private_key = fixture.keys.private_key(&default_path());
    let legacy = open_ledger_biz::eth::sign_personal_message(&private_key, MESSAGE).unwrap();
    assert_eq!(payload[..65], legacy[..]);
    assert_eq!(*fixture.keys.sign_calls.lock().unwrap(), 1);
}

#[test]
fn multi_block_message_is_acknowledged_until_complete() {
    let mut fixture = setup();
    let message = vec![0x41u8; 300];

    let first = submit(&mut fixture, first_block(&message, message.len(), 100));
    assert_eq!(expect_emit(first.clone()), vec![0x90, 0x00]);
    ack(&mut fixture, &first);

    let review_id = expect_review(submit(&mut fixture, more_block(&message[100..])));
    let payload = approve(&mut fixture, review_id);

    let private_key = fixture.keys.private_key(&default_path());
    let legacy = open_ledger_biz::eth::sign_personal_message(&private_key, &message).unwrap();
    assert_eq!(payload[..65], legacy[..]);
}

#[test]
fn rejecting_returns_user_denied_without_signing() {
    let mut fixture = setup();
    let review_id = expect_review(submit(
        &mut fixture,
        first_block(MESSAGE, MESSAGE.len(), MESSAGE.len()),
    ));

    let payload = expect_emit(
        fixture
            .runtime
            .resolve_review(fixture.session, review_id, ReviewDecision::Reject)
            .unwrap(),
    );
    assert_eq!(payload, vec![0x69, 0x85]);
    assert_eq!(*fixture.keys.sign_calls.lock().unwrap(), 0);
}

#[test]
fn declared_length_smaller_than_the_chunk_is_rejected() {
    let mut fixture = setup();
    let payload = expect_emit(submit(
        &mut fixture,
        first_block(MESSAGE, MESSAGE.len() - 1, MESSAGE.len()),
    ));
    assert_eq!(payload, vec![0x6A, 0x80]);
}

#[test]
fn zero_length_message_is_rejected() {
    let mut fixture = setup();
    assert_eq!(
        expect_emit(submit(&mut fixture, first_block(MESSAGE, 0, 0))),
        vec![0x6A, 0x80]
    );
}

#[test]
fn oversized_message_is_rejected() {
    let mut fixture = setup();
    assert_eq!(
        expect_emit(submit(&mut fixture, first_block(MESSAGE, 4097, 1))),
        vec![0x6A, 0x80]
    );
}

#[test]
fn non_zero_p2_is_rejected_before_touching_the_key() {
    let mut fixture = setup();
    let data = path_bytes();
    assert_eq!(
        expect_emit(submit(&mut fixture, apdu(0x00, 0x01, &data))),
        vec![0x6A, 0x86]
    );
}

#[test]
fn continuation_without_a_first_block_is_rejected() {
    let mut fixture = setup();
    assert_eq!(
        expect_emit(submit(&mut fixture, more_block(b"tail"))),
        vec![0x6A, 0x80]
    );
}
