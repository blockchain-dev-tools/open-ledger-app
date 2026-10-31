//! 官方 `app-sui` 协议对齐的验收：Block Protocol、命令表、地址/签名线格式。
//!
//! 真值来源：`LedgerHQ/app-sui`（`docs/apdu.md`、`docs/block-protocol.md`、
//! `tests/application_client/client.py`、`rust-app/src/interface.rs`）。
//! 这里的主机侧实现**独立**于被测模块：块链、哈希校验、参数编码都按官方客户端写。

use std::collections::HashMap;
use std::sync::Arc;

use chain_app_api::*;
use chain_app_runtime::{ReviewDecision, Runtime, RuntimeReply};
use chain_app_sui::{bcs, SuiFactory};
use ed25519_dalek::{Signature as DalekSignature, VerifyingKey};
use open_ledger_crypto::sha256;

const MNEMONIC: &str =
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
const SUI_PATH: &str = "m/44'/784'/0'/0'/0'";

const CLA: u8 = 0x00;
const INS_GET_VERSION: u8 = 0x00;
const INS_VERIFY_ADDRESS: u8 = 0x01;
const INS_GET_PUBKEY: u8 = 0x02;
const INS_SIGN_TX: u8 = 0x03;
const INS_TOKEN_DESCRIPTOR: u8 = 0x22;

const SW_OK: u16 = 0x9000;
const SW_DENIED: u16 = 0x6985;
const SW_NOT_SUPPORTED: u16 = 0x6808;
const SW_BAD_CLA: u16 = 0x6e00;
const SW_BAD_INS: u16 = 0x6e01;
const SW_BAD_LEN: u16 = 0x6e03;
const SW_UNKNOWN: u16 = 0x6d00;

// ── 主机侧 Block Protocol（与官方客户端同一算法） ──────────────────────────

#[derive(Default)]
struct Host {
    blocks: HashMap<[u8; 32], Vec<u8>>,
}

impl Host {
    /// 把一个参数切成 180 字节的块链，返回首块哈希。
    fn add_param(&mut self, param: &[u8]) -> [u8; 32] {
        let mut last = [0u8; 32];
        for chunk in param.chunks(180).collect::<Vec<_>>().into_iter().rev() {
            let mut block = Vec::with_capacity(32 + chunk.len());
            block.extend_from_slice(&last);
            block.extend_from_slice(chunk);
            last = sha256::hash(&block);
            self.blocks.insert(last, block);
        }
        last
    }

    fn start(&mut self, params: &[Vec<u8>]) -> Vec<u8> {
        let mut payload = vec![0x00u8];
        for param in params {
            payload.extend_from_slice(&self.add_param(param));
        }
        payload
    }

    fn chunk_reply(&self, hash: &[u8]) -> Option<Vec<u8>> {
        let key: [u8; 32] = hash.try_into().ok()?;
        let block = self.blocks.get(&key)?;
        let mut payload = vec![0x01u8];
        payload.extend_from_slice(block);
        Some(payload)
    }
}

fn apdu(ins: u8, data: &[u8], p1: u8, p2: u8, cla: u8) -> Vec<u8> {
    let mut out = vec![cla, ins, p1, p2, data.len() as u8];
    out.extend_from_slice(data);
    out
}

/// 路径编码：`[n][u32 **little-endian**]*n`（官方 `Bip32Key`）。
fn encode_path(path: &str) -> Vec<u8> {
    let parts: Vec<&str> = path.split('/').skip(1).collect();
    let mut out = vec![parts.len() as u8];
    for part in parts {
        let raw = part.trim_end_matches('\'');
        let mut value: u32 = raw.parse().unwrap();
        if part.ends_with('\'') {
            value |= 0x8000_0000;
        }
        out.extend_from_slice(&value.to_le_bytes());
    }
    out
}

// ── 运行时夹具 ──────────────────────────────────────────────────────────

struct EdKeys {
    seed: Vec<u8>,
}

impl EdKeys {
    fn new() -> Self {
        Self {
            seed: open_ledger_crypto::bip39::mnemonic_to_seed(MNEMONIC, "")
                .unwrap()
                .to_vec(),
        }
    }

    fn private_key(&self) -> Vec<u8> {
        open_ledger_biz::hdkey::derive_ed25519_private_key(&self.seed, SUI_PATH).unwrap()
    }
}

impl KeyService for EdKeys {
    fn public_key(&self, _request: &PublicKeyRequest) -> Result<PublicKey, HostError> {
        let key = open_ledger_crypto::ed25519::public_key_bytes(&self.private_key())
            .map_err(|e| HostError::Unavailable(e.to_string()))?;
        Ok(PublicKey {
            bytes: key,
            chain_code: None,
        })
    }

    fn sign(
        &self,
        _auth: &SignAuthorization,
        operation: &SignOperation,
    ) -> Result<Signature, HostError> {
        let bytes = open_ledger_crypto::ed25519::sign(&self.private_key(), &operation.input)
            .map_err(|e| HostError::Unavailable(e.to_string()))?;
        Ok(Signature {
            operation_id: operation.operation_id,
            bytes,
            recovery_id: None,
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
            derivation_scheme: DerivationScheme::Slip10Ed25519,
            curve: Curve::Ed25519,
            depth: 5,
            hardened_positions: vec![0, 1, 2, 3, 4],
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
        Arc::new(EdKeys::new()),
        Box::new(NoStorage),
    );
    runtime
        .register_module(Arc::new(SuiFactory), &policy())
        .unwrap();
    let (session, _) = runtime.open_app(chain_app_sui::MODULE_ID).unwrap();
    Fixture { runtime, session }
}

impl Fixture {
    fn submit(&mut self, bytes: Vec<u8>) -> RuntimeReply {
        let reply = self
            .runtime
            .submit_wire(self.session, Wire::LedgerApdu, bytes)
            .unwrap();
        if let RuntimeReply::Emit { exchange_id, .. } = &reply {
            let _ = self.runtime.delivery_result(
                self.session,
                *exchange_id,
                DeliveryAck::Acknowledged,
            );
        }
        reply
    }

    fn resolve(&mut self, review_id: ReviewId, decision: ReviewDecision) -> RuntimeReply {
        let reply = self
            .runtime
            .resolve_review(self.session, review_id, decision)
            .unwrap();
        if let RuntimeReply::Emit { exchange_id, .. } = &reply {
            let _ = self.runtime.delivery_result(
                self.session,
                *exchange_id,
                DeliveryAck::Acknowledged,
            );
        }
        reply
    }
}

enum Outcome {
    /// 成功：去掉 `RESULT_FINAL` 指令与状态字后的结果。
    Result(Vec<u8>),
    /// 失败：只有状态字。
    Status(u16),
    /// 需要用户在确认页上决定。
    Review(ReviewId, ReviewDocument),
}

fn split_status(payload: &[u8]) -> (Vec<u8>, u16) {
    if payload.len() >= 2 {
        let sw = u16::from_be_bytes([payload[payload.len() - 2], payload[payload.len() - 1]]);
        (payload[..payload.len() - 2].to_vec(), sw)
    } else {
        (payload.to_vec(), 0)
    }
}

/// 从 `START` 开始驱动整条 Block Protocol，直到拿到最终结果或审批请求。
fn drive(fixture: &mut Fixture, ins: u8, params: &[Vec<u8>]) -> Outcome {
    let mut host = Host::default();
    let mut reply = fixture.submit(apdu(ins, &host.start(params), 0, 0, CLA));
    loop {
        match reply {
            RuntimeReply::Review {
                review_id,
                document,
                ..
            } => return Outcome::Review(review_id, document),
            RuntimeReply::Emit { payload, .. } => {
                let (body, sw) = split_status(&payload);
                if sw != SW_OK {
                    return Outcome::Status(sw);
                }
                match body.first().copied() {
                    Some(0x02) => {
                        let Some(next) = host.chunk_reply(&body[1..]) else {
                            panic!("device asked for a chunk we never built");
                        };
                        reply = fixture.submit(apdu(ins, &next, 0, 0, CLA));
                    }
                    Some(0x01) => return Outcome::Result(body[1..].to_vec()),
                    other => panic!("unexpected LedgerToHost instruction {other:?}"),
                }
            }
            other => panic!("unexpected runtime reply {other:?}"),
        }
    }
}

fn expect_result(outcome: Outcome) -> Vec<u8> {
    match outcome {
        Outcome::Result(result) => result,
        Outcome::Status(sw) => panic!("expected result, got SW {sw:04X}"),
        Outcome::Review(..) => panic!("expected result, got a review"),
    }
}

fn expect_status(outcome: Outcome) -> u16 {
    match outcome {
        Outcome::Status(sw) => sw,
        Outcome::Result(_) => panic!("expected an error status, got a result"),
        Outcome::Review(..) => panic!("expected an error status, got a review"),
    }
}

fn expect_review(outcome: Outcome) -> (ReviewId, ReviewDocument) {
    match outcome {
        Outcome::Review(id, document) => (id, document),
        Outcome::Result(_) => panic!("expected a review, got a result"),
        Outcome::Status(sw) => panic!("expected a review, got SW {sw:04X}"),
    }
}

// ── 向量 ────────────────────────────────────────────────────────────────

fn sui_address_bytes(public_key: &[u8]) -> [u8; 32] {
    let mut input = vec![0u8];
    input.extend_from_slice(public_key);
    open_ledger_crypto::blake2b::hash(&input)
}

fn expected_pubkey() -> Vec<u8> {
    let seed = open_ledger_crypto::bip39::mnemonic_to_seed(MNEMONIC, "").unwrap();
    let private = open_ledger_biz::hdkey::derive_ed25519_private_key(&seed, SUI_PATH).unwrap();
    open_ledger_crypto::ed25519::public_key_bytes(&private).unwrap()
}

fn push_u64(out: &mut Vec<u8>, value: u64) {
    out.extend_from_slice(&value.to_le_bytes());
}

fn push_argument(out: &mut Vec<u8>, argument: &[u8]) {
    out.extend_from_slice(argument);
}

const ARG_GAS: [u8; 1] = [0x00];
const ARG_INPUT_0: [u8; 3] = [0x01, 0x00, 0x00];
const ARG_INPUT_1: [u8; 3] = [0x01, 0x01, 0x00];
const ARG_RESULT_0: [u8; 3] = [0x02, 0x00, 0x00];

/// 原生 SUI 转账：`SplitCoins(GasCoin, [Input(0)])` + `TransferObjects([Result(0)], Input(1))`。
/// `pad` 追加若干个未被引用的 32 字节 Pure 输入，用来把交易撑到需要多块传输。
fn native_transfer_tx_padded(
    amount: u64,
    recipient: [u8; 32],
    budget: u64,
    price: u64,
    pad: usize,
) -> Vec<u8> {
    let sender = sui_address_bytes(&expected_pubkey());
    let mut tx = vec![0x00, 0x00, 0x00, 0x00, 0x00];
    tx.push(2 + pad as u8); // inputs
    tx.extend_from_slice(&[0x00, 0x08]);
    push_u64(&mut tx, amount);
    tx.extend_from_slice(&[0x00, 0x20]);
    tx.extend_from_slice(&recipient);
    for index in 0..pad {
        tx.extend_from_slice(&[0x00, 0x20]);
        tx.extend_from_slice(&[index as u8; 32]);
    }
    tx.push(2); // commands
    tx.push(0x02); // SplitCoins
    push_argument(&mut tx, &ARG_GAS);
    tx.push(1);
    push_argument(&mut tx, &ARG_INPUT_0);
    tx.push(0x01); // TransferObjects
    tx.push(1);
    push_argument(&mut tx, &ARG_RESULT_0);
    push_argument(&mut tx, &ARG_INPUT_1);
    tx.extend_from_slice(&sender);
    tx.push(0); // gas payment: empty (SIP-58)
    tx.extend_from_slice(&sender); // gas owner
    push_u64(&mut tx, price);
    push_u64(&mut tx, budget);
    tx.push(0x00); // expiration: None
    tx
}

fn native_transfer_tx(amount: u64, recipient: [u8; 32], budget: u64, price: u64) -> Vec<u8> {
    native_transfer_tx_padded(amount, recipient, budget, price, 0)
}

/// 代币转账：拆分源是一个 coin object（`Input(0)`），金额 `Input(1)`，收款方 `Input(2)`。
fn token_transfer_tx(amount: u64, recipient: [u8; 32]) -> Vec<u8> {
    let sender = sui_address_bytes(&expected_pubkey());
    let mut tx = vec![0x00, 0x00, 0x00, 0x00, 0x00];
    tx.push(3); // inputs
    tx.extend_from_slice(&[0x01, 0x00]); // CallArg::Object / ImmOrOwnedObject
    tx.extend_from_slice(&[0x11; 32]);
    push_u64(&mut tx, 7);
    tx.extend_from_slice(&[0x22; 32]);
    tx.extend_from_slice(&[0x00, 0x08]);
    push_u64(&mut tx, amount);
    tx.extend_from_slice(&[0x00, 0x20]);
    tx.extend_from_slice(&recipient);
    tx.push(2);
    tx.push(0x02); // SplitCoins(Input(0), [Input(1)])
    push_argument(&mut tx, &ARG_INPUT_0);
    tx.push(1);
    tx.push(0x01);
    tx.push(0x01);
    tx.push(0x00);
    tx.push(0x01); // TransferObjects([Result(0)], Input(2))
    tx.push(1);
    push_argument(&mut tx, &ARG_RESULT_0);
    tx.push(0x01);
    tx.push(0x02);
    tx.push(0x00);
    tx.extend_from_slice(&sender);
    tx.push(1); // gas payment: 1 coin
    tx.extend_from_slice(&[0x33; 32]);
    push_u64(&mut tx, 9);
    tx.extend_from_slice(&[0x44; 32]);
    tx.extend_from_slice(&sender);
    push_u64(&mut tx, 1);
    push_u64(&mut tx, 5_000_000);
    tx.push(0x00);
    tx
}

// ── 用例 ────────────────────────────────────────────────────────────────

#[test]
fn get_version_matches_the_official_app() {
    let mut fixture = setup();
    let result = expect_result(drive(&mut fixture, INS_GET_VERSION, &[vec![0x00]]));
    assert_eq!(result, b"\x01\x05\x0bsui");
}

#[test]
fn get_public_key_returns_the_official_layout() {
    let mut fixture = setup();
    let result = expect_result(drive(&mut fixture, INS_GET_PUBKEY, &[encode_path(SUI_PATH)]));
    let pubkey = expected_pubkey();
    assert_eq!(result[0] as usize, 32);
    assert_eq!(&result[1..33], pubkey.as_slice());
    assert_eq!(result[33] as usize, 32);
    assert_eq!(&result[34..66], sui_address_bytes(&pubkey));
}

#[test]
fn verify_address_asks_for_confirmation_then_returns_the_key() {
    let mut fixture = setup();
    let (review_id, document) = expect_review(drive(
        &mut fixture,
        INS_VERIFY_ADDRESS,
        &[encode_path(SUI_PATH)],
    ));
    assert_eq!(document.operation, OperationKind::AddressConfirmation);
    let expected_address = format!("0x{}", hex::encode(sui_address_bytes(&expected_pubkey())));
    assert_eq!(document.account.as_deref(), Some(expected_address.as_str()));

    let reply = fixture.resolve(review_id, ReviewDecision::Approve);
    let (body, sw) = match reply {
        RuntimeReply::Emit { payload, .. } => split_status(&payload),
        other => panic!("unexpected reply {other:?}"),
    };
    assert_eq!(sw, SW_OK);
    assert_eq!(body, {
        let pubkey = expected_pubkey();
        let mut expected = vec![32u8];
        expected.extend_from_slice(&pubkey);
        expected.push(32);
        expected.extend_from_slice(&sui_address_bytes(&pubkey));
        let mut framed = vec![0x01u8];
        framed.extend_from_slice(&expected);
        framed
    });
}

#[test]
fn native_transfer_is_parsed_and_signed_over_the_raw_bytes() {
    let recipient = [0xAB; 32];
    let tx = native_transfer_tx(1_500_000_000, recipient, 2_000_000, 1);
    let parsed = bcs::parse_transaction(&tx);
    let bcs::Parsed::Transfer(transfer) = parsed else {
        panic!("native transfer must parse");
    };
    assert_eq!(transfer.asset, bcs::Asset::Native);
    assert_eq!(transfer.amount, 1_500_000_000);
    assert_eq!(transfer.recipient, recipient);
    assert_eq!(transfer.gas_budget, 2_000_000);
    assert_eq!(transfer.gas_payments, 0);

    let mut fixture = setup();
    let mut data = Vec::new();
    data.extend_from_slice(&(tx.len() as u32).to_le_bytes());
    data.extend_from_slice(&tx);
    let (review_id, document) = expect_review(drive(
        &mut fixture,
        INS_SIGN_TX,
        &[data, encode_path(SUI_PATH)],
    ));
    assert_eq!(document.sections[0].title_key, "review.section.sui");
    assert_eq!(document.parse_status, ParseStatus::Complete);
    assert!(document.risks.is_empty());

    let reply = fixture.resolve(review_id, ReviewDecision::Approve);
    let (body, sw) = match reply {
        RuntimeReply::Emit { payload, .. } => split_status(&payload),
        other => panic!("unexpected reply {other:?}"),
    };
    assert_eq!(sw, SW_OK);
    assert_eq!(body.len(), 1 + 64);
    assert_eq!(body[0], 0x01);

    let verifying = VerifyingKey::from_bytes(
        expected_pubkey().as_slice().try_into().unwrap(),
    )
    .unwrap();
    let signature = DalekSignature::from_slice(&body[1..]).unwrap();
    verifying.verify_strict(&tx, &signature).unwrap();
}

#[test]
fn token_transfer_parses_with_base_units() {
    let recipient = [0xCD; 32];
    let tx = token_transfer_tx(42, recipient);
    let bcs::Parsed::Transfer(transfer) = bcs::parse_transaction(&tx) else {
        panic!("token transfer must parse");
    };
    assert_eq!(transfer.asset, bcs::Asset::Token);
    assert_eq!(transfer.amount, 42);
    assert_eq!(transfer.gas_payments, 1);
}

#[test]
fn unrecognized_transactions_are_rejected_without_a_review() {
    let mut fixture = setup();
    let mut data = Vec::new();
    let junk = vec![0xEEu8; 40];
    data.extend_from_slice(&(junk.len() as u32).to_le_bytes());
    data.extend_from_slice(&junk);
    assert_eq!(
        expect_status(drive(&mut fixture, INS_SIGN_TX, &[data, encode_path(SUI_PATH)])),
        SW_NOT_SUPPORTED
    );
}

#[test]
fn rejecting_the_signature_returns_user_denied() {
    let tx = native_transfer_tx(1, [0x01; 32], 1_000, 1);
    let mut data = Vec::new();
    data.extend_from_slice(&(tx.len() as u32).to_le_bytes());
    data.extend_from_slice(&tx);

    let mut fixture = setup();
    let (review_id, _) = expect_review(drive(
        &mut fixture,
        INS_SIGN_TX,
        &[data, encode_path(SUI_PATH)],
    ));
    let reply = fixture.resolve(review_id, ReviewDecision::Reject);
    let (_, sw) = match reply {
        RuntimeReply::Emit { payload, .. } => split_status(&payload),
        other => panic!("unexpected reply {other:?}"),
    };
    assert_eq!(sw, SW_DENIED);
}

#[test]
fn multi_chunk_transactions_are_accepted() {
    // 大于 180 字节的交易会跨多个块，`GET_CHUNK` 必须逐块续收。
    let tx = native_transfer_tx_padded(7_000_000_000, [0x5A; 32], 9_000_000, 3, 4);
    assert!(tx.len() > 180);
    let mut data = Vec::new();
    data.extend_from_slice(&(tx.len() as u32).to_le_bytes());
    data.extend_from_slice(&tx);

    let mut fixture = setup();
    let (_, document) = expect_review(drive(
        &mut fixture,
        INS_SIGN_TX,
        &[data, encode_path(SUI_PATH)],
    ));
    assert_eq!(document.sections[0].title_key, "review.section.sui");
}

/// 官方 INS 表：每一条要么按官方语义实现，要么被显式拒绝。
///
/// `0x22` 依赖 Ledger PKI/CAL，本期声明为缺口（`6D00`）；未分配的编号回 `6E01`。
#[test]
fn official_ins_table_is_not_silently_reinterpreted() {
    for ins in [0x04u8, 0x10, 0x50, 0xA0] {
        let mut fixture = setup();
        assert_eq!(
            expect_status(drive(&mut fixture, ins, &[])),
            SW_BAD_INS,
            "INS 0x{ins:02X} 属于官方协议，不能被我们的实现接管"
        );
    }

    let mut fixture = setup();
    assert_eq!(
        expect_status(drive(&mut fixture, INS_TOKEN_DESCRIPTOR, &[vec![0x00]])),
        SW_UNKNOWN,
        "0x22 需要 Ledger PKI/CAL，本期是显式缺口"
    );
}

#[test]
fn wrong_cla_and_non_zero_p1_p2_are_rejected() {
    let mut fixture = setup();
    let payload = {
        let reply = fixture.submit(apdu(INS_GET_VERSION, &[0x00], 0, 0, 0x07));
        match reply {
            RuntimeReply::Emit { payload, .. } => payload,
            other => panic!("unexpected reply {other:?}"),
        }
    };
    assert_eq!(split_status(&payload).1, SW_BAD_CLA);

    let mut fixture = setup();
    let payload = {
        let reply = fixture.submit(apdu(INS_GET_PUBKEY, &[0x00], 0x01, 0, CLA));
        match reply {
            RuntimeReply::Emit { payload, .. } => payload,
            other => panic!("unexpected reply {other:?}"),
        }
    };
    assert_eq!(split_status(&payload).1, SW_BAD_INS);

    let mut fixture = setup();
    let payload = {
        let reply = fixture.submit(apdu(INS_GET_PUBKEY, &[], 0, 0, CLA));
        match reply {
            RuntimeReply::Emit { payload, .. } => payload,
            other => panic!("unexpected reply {other:?}"),
        }
    };
    assert_eq!(split_status(&payload).1, 0x6982);
}

#[test]
fn paths_must_be_five_hardened_components() {
    let mut fixture = setup();
    assert_eq!(
        expect_status(drive(&mut fixture, INS_GET_PUBKEY, &[encode_path("m/44'/784'/0'")])),
        SW_BAD_LEN
    );

    let mut fixture = setup();
    assert_eq!(
        expect_status(drive(
            &mut fixture,
            INS_GET_PUBKEY,
            &[encode_path("m/44'/784'/0'/0/0")]
        )),
        SW_BAD_LEN
    );
}

#[test]
fn block_protocol_rejects_a_tampered_block() {
    let mut fixture = setup();
    let mut host = Host::default();
    let start = host.start(&[encode_path(SUI_PATH)]);
    let reply = fixture.submit(apdu(INS_GET_PUBKEY, &start, 0, 0, CLA));
    let RuntimeReply::Emit { payload, .. } = reply else {
        panic!("expected a chunk request");
    };
    let (body, sw) = split_status(&payload);
    assert_eq!(sw, SW_OK);
    assert_eq!(body[0], 0x02);
    let mut chunk = host.chunk_reply(&body[1..]).unwrap();
    let last = chunk.len() - 1;
    chunk[last] ^= 0xFF;
    let reply = fixture.submit(apdu(INS_GET_PUBKEY, &chunk, 0, 0, CLA));
    let RuntimeReply::Emit { payload, .. } = reply else {
        panic!("expected a status reply");
    };
    assert_eq!(split_status(&payload).1, SW_UNKNOWN);
}
