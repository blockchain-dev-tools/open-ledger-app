//! 阶段 2c 切片 2/3 验收：`E0 04 SIGN_ETH_TRANSACTION` 与 `E0 0C SIGN_EIP_712`。
//!
//! 交易覆盖 legacy / EIP-1559 的字段提取、多块收集与 v 编码；EIP-712 覆盖
//! V0 单步与 V1 拒绝。批准结果与旧 Dart 路径逐字节一致（RFC6979 确定性）。

use std::sync::{Arc, Mutex};

use chain_app_api::*;
use chain_app_ethereum::EthereumFactory;
use chain_app_runtime::{ReviewDecision, Runtime, RuntimeReply};

const MNEMONIC: &str =
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
const EXPECTED_ADDRESS: &str = "0x9858EfFD232B4033E47d90003D41EC34EcaEda94";

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

    fn private_key(&self) -> Vec<u8> {
        open_ledger_biz::hdkey::derive_secp256k1_private_key(&self.seed, "m/44'/60'/0'/0/0")
            .unwrap()
    }
}

impl KeyService for CryptoKeys {
    fn public_key(&self, _request: &PublicKeyRequest) -> Result<PublicKey, HostError> {
        let key = open_ledger_crypto::secp256k1::public_key_bytes(&self.private_key(), false)
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
        *self.sign_calls.lock().unwrap() += 1;
        let SignScheme::EcdsaPrehash { digest_len, .. } = operation.scheme else {
            return Err(HostError::Denied("unsupported scheme".into()));
        };
        if usize::from(digest_len) != operation.input.len() || digest_len != 32 {
            return Err(HostError::Denied("digest length".into()));
        }
        let mut digest = [0u8; 32];
        digest.copy_from_slice(&operation.input);
        let signature = open_ledger_crypto::secp256k1::sign_prehash_recoverable(
            &self.private_key(),
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

fn path_bytes() -> Vec<u8> {
    let path = [0x8000_002Cu32, 0x8000_003C, 0x8000_0000, 0, 0];
    let mut out = vec![path.len() as u8];
    for component in path {
        out.extend_from_slice(&component.to_be_bytes());
    }
    out
}

fn apdu(ins: u8, p1: u8, p2: u8, data: &[u8]) -> Vec<u8> {
    let mut out = vec![0xE0, ins, p1, p2, data.len() as u8];
    out.extend_from_slice(data);
    out
}

fn tx_block(p1: u8, p2: u8, rlp: &[u8], take: usize) -> Vec<u8> {
    let mut data = if p1 == 0x00 { path_bytes() } else { Vec::new() };
    data.extend_from_slice(&rlp[..take]);
    apdu(0x04, p1, p2, &data)
}

/// 续块只带 RLP 尾部，不带路径。
fn tx_continuation(rlp: &[u8], skip: usize) -> Vec<u8> {
    apdu(0x04, 0x80, 0x00, &rlp[skip..])
}

fn legacy_tx() -> Vec<u8> {
    let mut stream = rlp::RlpStream::new_list(6);
    stream.append(&0u64); // nonce
    stream.append(&2_000_000_000u64); // gasPrice
    stream.append(&21_000u64); // gas
    stream.append(&[0x35u8; 20].as_ref()); // to
    stream.append(&1234u64); // value
    stream.append_empty_data(); // data
    stream.out().to_vec()
}

fn eip1559_tx() -> Vec<u8> {
    let mut stream = rlp::RlpStream::new_list(9);
    stream.append(&1u64); // chainId
    stream.append(&0u64); // nonce
    stream.append(&1_000_000_000u64); // maxPriorityFeePerGas
    stream.append(&2_000_000_000u64); // maxFeePerGas
    stream.append(&21_000u64); // gas
    stream.append(&[0x35u8; 20].as_ref()); // to
    stream.append(&1234u64); // value
    stream.append_empty_data(); // data
    // 空 accessList 就是 RLP 的 0xC0。
    stream.append_raw(&[0xC0], 1);
    let mut out = vec![0x02];
    out.extend_from_slice(&stream.out());
    out
}

fn submit(fixture: &mut Fixture, bytes: Vec<u8>) -> RuntimeReply {
    fixture
        .runtime
        .submit_wire(fixture.session, Wire::LedgerApdu, bytes)
        .unwrap()
}

fn ack_collecting(fixture: &mut Fixture, reply: &RuntimeReply) {
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

fn expect_review(reply: RuntimeReply) -> (ReviewId, ReviewDocument, ReviewAction) {
    match reply {
        RuntimeReply::Review {
            review_id,
            document,
            action,
        } => (review_id, document, action),
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

fn field<'a>(document: &'a ReviewDocument, label: &str) -> &'a FieldValue {
    document
        .sections
        .iter()
        .flat_map(|section| section.fields.iter())
        .find(|field| field.label_key == label)
        .map(|field| &field.value)
        .unwrap_or_else(|| panic!("missing field {label}"))
}

// ── 交易 ──────────────────────────────────────────────────────────────

#[test]
fn legacy_transaction_review_shows_recipient_value_and_fees() {
    let mut fixture = setup();
    let tx = legacy_tx();
    let (_, document, action) = expect_review(submit(&mut fixture, tx_block(0x00, 0x00, &tx, tx.len())));

    assert_eq!(document.operation, OperationKind::Transaction);
    assert_eq!(document.account.as_deref(), Some(EXPECTED_ADDRESS));
    assert_eq!(
        field(&document, "review.field.to"),
        &FieldValue::Address {
            value: "0x3535353535353535353535353535353535353535".into(),
            network: "Ethereum".into(),
            role: "recipient".into(),
        }
    );
    assert!(matches!(
        field(&document, "review.field.value"),
        FieldValue::Amount { raw, decimals: 18, .. } if raw == "1234"
    ));
    assert!(matches!(
        field(&document, "review.field.gas"),
        FieldValue::Text { value } if value == "21000"
    ));
    assert!(matches!(
        field(&document, "review.field.gas_price"),
        FieldValue::Amount { raw, .. } if raw == "2000000000"
    ));
    assert!(matches!(action, ReviewAction::Sign(ref plan) if plan.operations.len() == 1));
    assert_eq!(*fixture.keys.sign_calls.lock().unwrap(), 0);
}

#[test]
fn legacy_transaction_signature_matches_the_legacy_path() {
    let mut fixture = setup();
    let tx = legacy_tx();
    let (review_id, _, _) = expect_review(submit(&mut fixture, tx_block(0x00, 0x00, &tx, tx.len())));

    let payload = approve(&mut fixture, review_id);
    assert_eq!(payload.len(), 67);
    assert_eq!(&payload[65..], &[0x90, 0x00]);
    assert!(payload[0] == 27 || payload[0] == 28);

    let legacy = open_ledger_biz::eth::sign_transaction(&fixture.keys.private_key(), &tx).unwrap();
    assert_eq!(payload[..65], legacy[..]);
    assert_eq!(*fixture.keys.sign_calls.lock().unwrap(), 1);
}

#[test]
fn typed_transaction_uses_the_raw_recovery_id_as_v() {
    let mut fixture = setup();
    let tx = eip1559_tx();
    let (review_id, document, _) =
        expect_review(submit(&mut fixture, tx_block(0x00, 0x00, &tx, tx.len())));

    assert_eq!(document.network.chain_id, Some(1));
    let payload = approve(&mut fixture, review_id);
    assert!(payload[0] <= 1, "typed tx v must be 0/1, got {}", payload[0]);

    let legacy = open_ledger_biz::eth::sign_transaction(&fixture.keys.private_key(), &tx).unwrap();
    assert_eq!(payload[..65], legacy[..]);
}

#[test]
fn multi_block_transaction_is_collected_before_review() {
    let mut fixture = setup();
    let tx = legacy_tx();

    let first = submit(&mut fixture, tx_block(0x00, 0x00, &tx, 10));
    assert_eq!(expect_emit(first.clone()), vec![0x90, 0x00]);
    ack_collecting(&mut fixture, &first);

    let (review_id, _, _) = expect_review(submit(&mut fixture, tx_continuation(&tx, 10)));
    let payload = approve(&mut fixture, review_id);

    let legacy = open_ledger_biz::eth::sign_transaction(&fixture.keys.private_key(), &tx).unwrap();
    assert_eq!(payload[..65], legacy[..]);
}

#[test]
fn store_only_transaction_is_acknowledged_without_signing() {
    let mut fixture = setup();
    let tx = legacy_tx();
    assert_eq!(
        expect_emit(submit(&mut fixture, tx_block(0x00, 0x01, &tx, tx.len()))),
        vec![0x90, 0x00]
    );
    assert_eq!(fixture.runtime.pending_reviews(), 0);
    assert_eq!(*fixture.keys.sign_calls.lock().unwrap(), 0);
}

#[test]
fn start_flow_is_acknowledged_without_state() {
    let mut fixture = setup();
    assert_eq!(
        expect_emit(submit(&mut fixture, apdu(0x04, 0x00, 0x02, &[]))),
        vec![0x90, 0x00]
    );
    assert_eq!(fixture.runtime.pending_reviews(), 0);
}

#[test]
fn closing_the_session_drops_a_half_collected_transaction() {
    let mut fixture = setup();
    let tx = legacy_tx();

    let first = submit(&mut fixture, tx_block(0x00, 0x00, &tx, 10));
    assert_eq!(expect_emit(first.clone()), vec![0x90, 0x00]);
    ack_collecting(&mut fixture, &first);

    // 锁定会关闭会话；I9 要求半条交易不得留在内存里。
    fixture.runtime.lock();
    let (session, _) = fixture.runtime.open_app("openledger.ethereum").unwrap();
    fixture.session = session;

    assert_eq!(
        expect_emit(submit(&mut fixture, tx_continuation(&tx, 10))),
        vec![0x6A, 0x80]
    );
}

#[test]
fn malformed_rlp_is_rejected_without_a_review() {
    let mut fixture = setup();
    let mut stream = rlp::RlpStream::new_list(3);
    stream.append(&1u64);
    stream.append(&2u64);
    stream.append(&3u64);
    let bad = stream.out().to_vec();

    assert_eq!(
        expect_emit(submit(&mut fixture, tx_block(0x00, 0x00, &bad, bad.len()))),
        vec![0x6A, 0x80]
    );
    assert_eq!(fixture.runtime.pending_reviews(), 0);
}

// ── EIP-712 ───────────────────────────────────────────────────────────

fn eip712_block(p2: u8, domain: [u8; 32], structure: [u8; 32]) -> Vec<u8> {
    let mut data = path_bytes();
    data.extend_from_slice(&domain);
    data.extend_from_slice(&structure);
    apdu(0x0C, 0x00, p2, &data)
}

#[test]
fn eip712_v0_signs_the_typed_data_digest() {
    let mut fixture = setup();
    let domain = [0xABu8; 32];
    let structure = [0xCDu8; 32];

    let (review_id, document, _) = expect_review(submit(
        &mut fixture,
        eip712_block(0x00, domain, structure),
    ));
    assert_eq!(document.operation, OperationKind::Message);
    assert!(matches!(
        field(&document, "review.field.domain_hash"),
        FieldValue::Text { value } if value.starts_with("0xabab")
    ));

    let payload = approve(&mut fixture, review_id);
    assert_eq!(payload.len(), 67);
    assert!(payload[0] == 27 || payload[0] == 28);

    let legacy = open_ledger_biz::eth::sign_eip712(
        &fixture.keys.private_key(),
        &domain,
        &structure,
    )
    .unwrap();
    assert_eq!(payload[..65], legacy[..]);
}

#[test]
fn eip712_v1_streaming_is_refused() {
    let mut fixture = setup();
    assert_eq!(
        expect_emit(submit(
            &mut fixture,
            eip712_block(0x01, [0u8; 32], [0u8; 32])
        )),
        vec![0x6A, 0x86]
    );
}

#[test]
fn eip712_requires_exactly_two_hashes() {
    let mut fixture = setup();
    let mut data = path_bytes();
    data.extend_from_slice(&[0u8; 32]);
    assert_eq!(
        expect_emit(submit(&mut fixture, apdu(0x0C, 0x00, 0x00, &data))),
        vec![0x6A, 0x80]
    );
}
