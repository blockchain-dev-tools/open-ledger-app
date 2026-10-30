//! 阶段 4 验收：Solana 地址与 Ed25519 签名。
//!
//! 地址与 `open_ledger_biz::solana` 比对；签名用 ed25519-dalek 独立验签。

use std::sync::Arc;

use chain_app_api::*;
use chain_app_runtime::{ReviewDecision, Runtime, RuntimeReply};
use chain_app_solana::SolanaFactory;
use ed25519_dalek::{Signature as DalekSignature, VerifyingKey};

const MNEMONIC: &str =
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
const SOL_PATH: &str = "m/44'/501'/0'/0'";

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
        open_ledger_biz::hdkey::derive_ed25519_private_key(&self.seed, SOL_PATH).unwrap()
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
            depth: 4,
            hardened_positions: vec![0, 1, 2, 3],
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
        .register_module(Arc::new(SolanaFactory), &policy())
        .unwrap();
    let (session, _) = runtime.open_app("openledger.solana").unwrap();
    Fixture { runtime, session }
}

fn path_bytes() -> Vec<u8> {
    let mut out = vec![4u8];
    for component in [0x8000_002Cu32, 0x8000_01F5, 0x8000_0000, 0x8000_0000] {
        out.extend_from_slice(&component.to_be_bytes());
    }
    out
}

fn apdu(ins: u8, p1: u8, p2: u8, data: &[u8]) -> Vec<u8> {
    let mut out = vec![0xE0, ins, p1, p2, data.len() as u8];
    out.extend_from_slice(data);
    out
}

fn submit(fixture: &mut Fixture, bytes: Vec<u8>) -> RuntimeReply {
    let reply = fixture
        .runtime
        .submit_wire(fixture.session, Wire::LedgerApdu, bytes)
        .unwrap();
    // 与真实宿主一致：Emit 立即确认投递。
    if let RuntimeReply::Emit { exchange_id, .. } = &reply {
        let _ = fixture.runtime.delivery_result(
            fixture.session,
            *exchange_id,
            DeliveryAck::Acknowledged,
        );
    }
    reply
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

fn resolve(fixture: &mut Fixture, review_id: ReviewId, decision: ReviewDecision) -> Vec<u8> {
    let reply = fixture
        .runtime
        .resolve_review(fixture.session, review_id, decision)
        .unwrap();
    if let RuntimeReply::Emit { exchange_id, .. } = &reply {
        let _ = fixture.runtime.delivery_result(
            fixture.session,
            *exchange_id,
            DeliveryAck::Acknowledged,
        );
    }
    expect_emit(reply)
}

fn expected_pubkey() -> Vec<u8> {
    let keys = EdKeys::new();
    open_ledger_crypto::ed25519::public_key_bytes(&keys.private_key()).unwrap()
}

/// 构造一个 System Program Transfer 的 legacy 消息（单签名）。
fn transfer_message(lamports: u64) -> Vec<u8> {
    let mut msg = vec![1u8, 0, 1]; // required sigs / readonly signed / readonly unsigned
    msg.push(3); // account count
    for byte in [0x01u8; 32] {
        msg.push(byte);
    }
    for byte in [0x02u8; 32] {
        msg.push(byte);
    }
    msg.extend_from_slice(&[0u8; 32]); // system program
    msg.extend_from_slice(&[0x09u8; 32]); // blockhash
    msg.push(1); // instruction count
    msg.push(2); // program index
    msg.push(2); // account index count
    msg.push(0);
    msg.push(1);
    msg.push(12); // data length
    msg.extend_from_slice(&[2, 0, 0, 0]);
    msg.extend_from_slice(&lamports.to_le_bytes());
    msg
}

// ── 用例 ──────────────────────────────────────────────────────────────

#[test]
fn app_configuration_matches_the_official_five_byte_layout() {
    let mut fixture = setup();
    // [allow_blind_sign=0][pubkey_display=1][major=0][minor=1][patch=0] + 9000
    assert_eq!(
        expect_emit(submit(&mut fixture, apdu(0x04, 0, 0, &[]))),
        vec![0x00, 0x01, 0x00, 0x01, 0x00, 0x90, 0x00]
    );
}

#[test]
fn address_is_the_bare_32_byte_pubkey() {
    let mut fixture = setup();
    let payload = expect_emit(submit(&mut fixture, apdu(0x05, 0, 0, &path_bytes())));
    assert_eq!(payload.len(), 34);
    assert_eq!(&payload[..32], expected_pubkey().as_slice());
    assert_eq!(&payload[32..], &[0x90, 0x00]);
}

#[test]
fn address_matches_the_library_base58_derivation() {
    let mut fixture = setup();
    let _ = expect_emit(submit(&mut fixture, apdu(0x05, 0, 0, &path_bytes())));
    let seed = open_ledger_crypto::bip39::mnemonic_to_seed(MNEMONIC, "").unwrap();
    let address = open_ledger_biz::solana::derive_address(&seed, SOL_PATH).unwrap();
    let pubkey = expected_pubkey();
    assert_eq!(address, open_ledger_crypto::base58::encode(&pubkey));
}

#[test]
fn confirm_address_requires_a_review() {
    let mut fixture = setup();
    let (review_id, document, action) =
        expect_review(submit(&mut fixture, apdu(0x05, 1, 0, &path_bytes())));
    assert_eq!(document.operation, OperationKind::AddressConfirmation);
    assert!(matches!(action, ReviewAction::DisplayAddress { .. }));
    let payload = resolve(&mut fixture, review_id, ReviewDecision::Approve);
    assert_eq!(&payload[..32], expected_pubkey().as_slice());
    assert_eq!(&payload[32..], &[0x90, 0x00]);
}

#[test]
fn rejecting_the_address_returns_user_denied() {
    let mut fixture = setup();
    let (review_id, _, _) = expect_review(submit(&mut fixture, apdu(0x05, 1, 0, &path_bytes())));
    assert_eq!(
        resolve(&mut fixture, review_id, ReviewDecision::Reject),
        vec![0x69, 0x85]
    );
}

#[test]
fn sign_review_shows_the_transfer_and_signs_the_raw_message() {
    let mut fixture = setup();
    let message = transfer_message(1_500_000_000);
    let mut data = path_bytes();
    data.extend_from_slice(&message);
    let (review_id, document, action) = expect_review(submit(&mut fixture, apdu(0x06, 0, 0, &data)));

    assert_eq!(document.network.name, "Solana");
    assert_eq!(document.sections[0].title_key, "review.section.solana");
    let values: Vec<String> = document.sections[0]
        .fields
        .iter()
        .map(|field| match &field.value {
            FieldValue::Text { value } => value.clone(),
            FieldValue::Address { value, .. } => value.clone(),
            FieldValue::Amount { raw, .. } => raw.clone(),
            other => panic!("unexpected field {other:?}"),
        })
        .collect();
    assert!(values.contains(&"1500000000".to_string()));
    assert!(values.contains(&open_ledger_crypto::base58::encode(&[0x02u8; 32])));
    assert_eq!(document.parse_status, ParseStatus::Complete);
    assert!(matches!(action, ReviewAction::Sign(_)));

    let payload = resolve(&mut fixture, review_id, ReviewDecision::Approve);
    assert_eq!(payload.len(), 66);
    assert_eq!(&payload[64..], &[0x90, 0x00]);

    // 独立验签：ed25519-dalek 直接验证原始消息。
    let signature = DalekSignature::from_slice(&payload[..64]).unwrap();
    let public_key = VerifyingKey::from_bytes(&expected_pubkey().try_into().unwrap()).unwrap();
    public_key.verify_strict(&message, &signature).unwrap();
}

#[test]
fn multi_chunk_message_is_assembled_before_signing() {
    let mut fixture = setup();
    let message = transfer_message(42);
    let first = path_bytes();
    let split = message.len() / 2;

    let mut head = first.clone();
    head.extend_from_slice(&message[..split]);
    // 首块 + MORE：只回 9000，不结束会话。
    let reply = submit(&mut fixture, apdu(0x06, 0, 0x02, &head));
    match reply {
        RuntimeReply::Emit { payload, state, .. } => {
            assert_eq!(payload, vec![0x90, 0x00]);
            assert_eq!(state, OperationState::Collecting);
        }
        other => panic!("expected collecting emit, got {other:?}"),
    }

    // 续块 + EXTEND（没有 MORE）：收满后进入审阅。
    let (review_id, document, _) =
        expect_review(submit(&mut fixture, apdu(0x06, 0, 0x01, &message[split..])));
    assert_eq!(document.sections[0].title_key, "review.section.solana");
    let payload = resolve(&mut fixture, review_id, ReviewDecision::Approve);
    assert_eq!(payload.len(), 66);

    let keys = EdKeys::new();
    let expected = open_ledger_crypto::ed25519::sign(&keys.private_key(), &message).unwrap();
    assert_eq!(&payload[..64], expected.as_slice());
}

#[test]
fn okx_num_signers_prefix_is_stripped() {
    let mut fixture = setup();
    let message = transfer_message(7);
    let mut data = vec![0x01]; // OKX：路径前的标志字节
    data.extend_from_slice(&path_bytes());
    data.extend_from_slice(&message);
    let (review_id, _, _) = expect_review(submit(&mut fixture, apdu(0x06, 0, 0, &data)));
    let payload = resolve(&mut fixture, review_id, ReviewDecision::Approve);
    let keys = EdKeys::new();
    let expected = open_ledger_crypto::ed25519::sign(&keys.private_key(), &message).unwrap();
    assert_eq!(&payload[..64], expected.as_slice());
}

#[test]
fn rejecting_a_signature_returns_user_denied() {
    let mut fixture = setup();
    let message = transfer_message(1);
    let mut data = path_bytes();
    data.extend_from_slice(&message);
    let (review_id, _, _) = expect_review(submit(&mut fixture, apdu(0x06, 0, 0, &data)));
    assert_eq!(
        resolve(&mut fixture, review_id, ReviewDecision::Reject),
        vec![0x69, 0x85]
    );
}

#[test]
fn path_outside_the_granted_rule_fails_without_signing() {
    let mut fixture = setup();
    let mut data = vec![5u8];
    for component in [0x8000_002Cu32, 0x8000_01F5, 0x8000_0000, 0x8000_0000, 0x8000_0000] {
        data.extend_from_slice(&component.to_be_bytes());
    }
    assert_eq!(
        expect_emit(submit(&mut fixture, apdu(0x05, 0, 0, &data))),
        vec![0x6F, 0x00]
    );
}

#[test]
fn empty_sign_payload_is_rejected() {
    let mut fixture = setup();
    assert_eq!(
        expect_emit(submit(&mut fixture, apdu(0x06, 0, 0, &path_bytes()))),
        vec![0x6A, 0x80]
    );
}

#[test]
fn unknown_ins_is_rejected() {
    let mut fixture = setup();
    assert_eq!(
        expect_emit(submit(&mut fixture, apdu(0x99, 0, 0, &[]))),
        vec![0x6D, 0x00]
    );
}
