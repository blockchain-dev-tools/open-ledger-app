//! T-021 验收：Tron 地址 + 0x04/0x05/0x08 签名 + 最小 protobuf 解析。

use std::sync::Arc;

use chain_app_api::*;
use chain_app_runtime::{ReviewDecision, Runtime, RuntimeReply};
use chain_app_tron::TronFactory;
use k256::ecdsa::signature::hazmat::PrehashVerifier;
use k256::ecdsa::{Signature as K256Signature, VerifyingKey};

const MNEMONIC: &str =
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
const TRON_PATH: &str = "m/44'/195'/0'/0/0";

struct SecpKeys {
    seed: Vec<u8>,
}

impl SecpKeys {
    fn new() -> Self {
        Self {
            seed: open_ledger_crypto::bip39::mnemonic_to_seed(MNEMONIC, "")
                .unwrap()
                .to_vec(),
        }
    }

    fn path_text(&self, path: &[u32]) -> String {
        let mut text = String::from("m");
        for component in path {
            if *component >= 0x8000_0000 {
                text.push_str(&format!("/{}'", component - 0x8000_0000));
            } else {
                text.push_str(&format!("/{component}"));
            }
        }
        text
    }

    fn private_key_at(&self, path: &[u32]) -> Vec<u8> {
        open_ledger_biz::hdkey::derive_secp256k1_private_key(&self.seed, &self.path_text(path))
            .unwrap()
    }
}

impl KeyService for SecpKeys {
    fn public_key(&self, request: &PublicKeyRequest) -> Result<PublicKey, HostError> {
        let private = self.private_key_at(&request.path);
        let bytes = open_ledger_crypto::secp256k1::public_key_bytes(
            &private,
            request.output == KeyOutput::CompressedSecp256k1,
        )
        .map_err(|e| HostError::Unavailable(e.to_string()))?;
        let chain_code = if request.include_chain_code {
            let (_, chain_code) = open_ledger_biz::hdkey::derive_secp256k1_extended(
                &self.seed,
                &self.path_text(&request.path),
            )
            .map_err(|e| HostError::Unavailable(e.to_string()))?;
            Some(chain_code.to_vec())
        } else {
            None
        };
        Ok(PublicKey { bytes, chain_code })
    }

    fn sign(
        &self,
        _auth: &SignAuthorization,
        operation: &SignOperation,
    ) -> Result<Signature, HostError> {
        let mut digest = [0u8; 32];
        if operation.input.len() != 32 {
            return Err(HostError::Denied("tron expects a 32-byte digest".into()));
        }
        digest.copy_from_slice(&operation.input);
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

    fn ecdh(&self, request: &EcdhRequest) -> Result<Vec<u8>, HostError> {
        open_ledger_crypto::secp256k1::ecdh_shared_point(
            &self.private_key_at(&request.path),
            &request.peer_public_key,
        )
        .map_err(|e| HostError::Unavailable(e.to_string()))
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

fn policy_with_chain_code() -> CapabilitySet {
    let mut policy = policy();
    policy.allow_chain_code = true;
    policy
}

struct Fixture {
    runtime: Runtime,
    keys: Arc<SecpKeys>,
    session: SessionId,
}

fn setup() -> Fixture {
    setup_with(policy())
}

fn setup_with(policy: CapabilitySet) -> Fixture {
    let keys = Arc::new(SecpKeys::new());
    let mut runtime = Runtime::new(
        "vault-a",
        Default::default(),
        keys.clone(),
        Box::new(NoStorage),
    );
    runtime
        .register_module(Arc::new(TronFactory), &policy)
        .unwrap();
    let (session, _) = runtime.open_app("openledger.tron").unwrap();
    Fixture {
        runtime,
        keys,
        session,
    }
}

fn path_bytes() -> Vec<u8> {
    let mut out = vec![5u8];
    for component in [0x8000_002Cu32, 0x8000_00C3, 0x8000_0000, 0, 0] {
        out.extend_from_slice(&component.to_be_bytes());
    }
    out
}

fn apdu(ins: u8, p1: u8, data: &[u8]) -> Vec<u8> {
    apdu_p2(ins, p1, 0x00, data)
}

fn apdu_p2(ins: u8, p1: u8, p2: u8, data: &[u8]) -> Vec<u8> {
    let mut out = vec![0xE0, ins, p1, p2, data.len() as u8];
    out.extend_from_slice(data);
    out
}

fn submit(fixture: &mut Fixture, bytes: Vec<u8>) -> RuntimeReply {
    let reply = fixture
        .runtime
        .submit_wire(fixture.session, Wire::LedgerApdu, bytes)
        .unwrap();
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

fn expect_review(reply: RuntimeReply) -> (ReviewId, ReviewDocument) {
    match reply {
        RuntimeReply::Review {
            review_id,
            document,
            ..
        } => (review_id, document),
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

fn field_value(document: &ReviewDocument, label: &str) -> Option<String> {
    for section in &document.sections {
        for field in &section.fields {
            if field.label_key == label {
                return Some(match &field.value {
                    FieldValue::Text { value } => value.clone(),
                    FieldValue::Address { value, .. } => value.clone(),
                    FieldValue::Amount { raw, .. } | FieldValue::Fee { raw: Some(raw), .. } => {
                        raw.clone()
                    }
                    FieldValue::Bytes { value } => value.iter().map(|b| format!("{b:02x}")).collect(),
                    other => format!("{other:?}"),
                });
            }
        }
    }
    None
}

/// 按官方 `v` 编码（0/1）与 r||s 验签。
fn verify_signature(fixture: &Fixture, payload: &[u8], digest: &[u8; 32]) {
    assert_eq!(payload.len(), 67, "r||s||v + SW");
    let v = payload[64];
    assert!(v <= 1, "Tron v must be 0/1, got {v}");
    assert_eq!(&payload[65..], &[0x90, 0x00]);

    let public_key = open_ledger_crypto::secp256k1::public_key_bytes(
        &fixture.keys.private_key_at(&default_path()),
        false,
    )
    .unwrap();
    let verifying = VerifyingKey::from_sec1_bytes(&public_key).unwrap();
    let signature = K256Signature::from_slice(&payload[..64]).unwrap();
    verifying.verify_prehash(digest, &signature).unwrap();

    // 与宿主签名器的原始输出逐字节一致（v 不做 27 偏移）。
    let expected = open_ledger_crypto::secp256k1::sign_prehash_recoverable(
        &fixture.keys.private_key_at(&default_path()),
        digest,
        |r| r,
    )
    .unwrap();
    assert_eq!(v, expected[0]);
    assert_eq!(&payload[..64], &expected[1..65]);
}

fn default_path() -> Vec<u32> {
    vec![0x8000_002C, 0x8000_00C3, 0x8000_0000, 0, 0]
}

// ── protobuf 构造 ─────────────────────────────────────────────────────

fn varint(mut value: u64) -> Vec<u8> {
    let mut out = Vec::new();
    loop {
        let byte = (value & 0x7f) as u8;
        value >>= 7;
        if value == 0 {
            out.push(byte);
            return out;
        }
        out.push(byte | 0x80);
    }
}

fn tag(field: u32, wire: u8) -> Vec<u8> {
    varint((u64::from(field) << 3) | u64::from(wire))
}

fn len_field(field: u32, payload: &[u8]) -> Vec<u8> {
    let mut out = tag(field, 2);
    out.extend_from_slice(&varint(payload.len() as u64));
    out.extend_from_slice(payload);
    out
}

fn varint_field(field: u32, value: u64) -> Vec<u8> {
    let mut out = tag(field, 0);
    out.extend_from_slice(&varint(value));
    out
}

fn address(byte: u8) -> Vec<u8> {
    let mut raw = vec![0x41];
    raw.extend_from_slice(&[byte; 20]);
    raw
}

const TRANSFER_CONTRACT: u64 = 1;
const TRIGGER_CONTRACT: u64 = 31;

fn contract_tx(contract_type: u64, type_name: &str, value: &[u8], fee_limit: Option<u64>) -> Vec<u8> {
    let mut any = len_field(1, format!("type.googleapis.com/protocol.{type_name}").as_bytes());
    any.extend_from_slice(&len_field(2, value));
    let mut contract = varint_field(1, contract_type);
    contract.extend_from_slice(&len_field(2, &any));

    let mut raw = len_field(11, &contract);
    if let Some(fee) = fee_limit {
        raw.extend_from_slice(&varint_field(18, fee));
    }
    len_field(1, &raw)
}

fn transfer_tx(amount: u64) -> Vec<u8> {
    let mut value = len_field(1, &address(0x01));
    value.extend_from_slice(&len_field(2, &address(0x02)));
    value.extend_from_slice(&varint_field(3, amount));
    contract_tx(TRANSFER_CONTRACT, "TransferContract", &value, Some(10_000_000))
}

fn trc20_transfer_tx() -> Vec<u8> {
    let mut call = hex::decode("a9059cbb").unwrap();
    let mut to = vec![0u8; 32];
    to[12..].copy_from_slice(&[0x03u8; 20]);
    call.extend_from_slice(&to);
    let mut amount = [0u8; 32];
    amount[28..].copy_from_slice(&1_000_000u32.to_be_bytes());
    call.extend_from_slice(&amount);

    let mut value = len_field(1, &address(0x01));
    value.extend_from_slice(&len_field(2, &address(0x09)));
    value.extend_from_slice(&len_field(4, &call));
    contract_tx(TRIGGER_CONTRACT, "TriggerSmartContract", &value, Some(20_000_000))
}

fn unknown_contract_tx() -> Vec<u8> {
    contract_tx(5, "WitnessCreateContract", &len_field(1, &address(0x01)), None)
}

/// 两个合约拼在同一笔交易里（T-022 多合约审阅）。
fn two_contract_tx() -> Vec<u8> {
    let mut transfer = len_field(1, &address(0x01));
    transfer.extend_from_slice(&len_field(2, &address(0x02)));
    transfer.extend_from_slice(&varint_field(3, 7));
    let mut witness = len_field(1, &address(0x01));
    witness.extend_from_slice(&len_field(2, b"witness-url"));

    let mut raw = Vec::new();
    for (id, name, value) in [
        (1u64, "TransferContract", transfer),
        (5u64, "WitnessCreateContract", witness),
    ] {
        let mut any = len_field(1, format!("type.googleapis.com/protocol.{name}").as_bytes());
        any.extend_from_slice(&len_field(2, &value));
        let mut contract = varint_field(1, id);
        contract.extend_from_slice(&len_field(2, &any));
        raw.extend_from_slice(&len_field(11, &contract));
    }
    len_field(1, &raw)
}

fn critical_contract_tx() -> Vec<u8> {
    // AccountPermissionUpdateContract（46），载荷用通用字段即可。
    let mut value = len_field(1, &address(0x01));
    value.extend_from_slice(&varint_field(2, 2));
    contract_tx(46, "AccountPermissionUpdateContract", &value, None)
}

/// TRC-10 `TransferAssetContract`（type 2）：asset_name(1) / owner(2) / to(3) / amount(4)。
fn transfer_asset_tx(name: &str, amount: u64, permission: Option<u64>) -> Vec<u8> {
    let mut value = len_field(1, name.as_bytes());
    value.extend_from_slice(&len_field(2, &address(0x01)));
    value.extend_from_slice(&len_field(3, &address(0x04)));
    value.extend_from_slice(&varint_field(4, amount));

    let mut any = len_field(1, b"type.googleapis.com/protocol.TransferAssetContract");
    any.extend_from_slice(&len_field(2, &value));
    let mut contract = varint_field(1, 2);
    contract.extend_from_slice(&len_field(2, &any));
    if let Some(permission) = permission {
        contract.extend_from_slice(&varint_field(5, permission));
    }
    let mut raw = len_field(11, &contract);
    raw.extend_from_slice(&varint_field(18, 10_000_000));
    len_field(1, &raw)
}

// ── 用例 ──────────────────────────────────────────────────────────────

#[test]
fn address_matches_the_library_derivation_and_wire_layout() {
    let mut fixture = setup();
    let payload = expect_emit(submit(&mut fixture, apdu(0x02, 0x00, &path_bytes())));
    assert_eq!(&payload[payload.len() - 2..], &[0x90, 0x00]);

    let body = &payload[..payload.len() - 2];
    assert_eq!(body[0], 65);
    assert_eq!(body[1], 0x04);
    let addr_len = body[66] as usize;
    let address = String::from_utf8(body[67..67 + addr_len].to_vec()).unwrap();

    let seed = open_ledger_crypto::bip39::mnemonic_to_seed(MNEMONIC, "").unwrap();
    let expected = open_ledger_biz::tron::derive_address(&seed, TRON_PATH).unwrap();
    assert_eq!(address, expected);
    assert!(address.starts_with('T'));
}

#[test]
fn configuration_reports_data_and_contract_support() {
    let mut fixture = setup();
    // bit0 allowData | bit1 allowContract | bit3 signByHash，truncateAddress = 0。
    assert_eq!(
        expect_emit(submit(&mut fixture, apdu(0x06, 0x00, &[]))),
        vec![0x0B, 0x00, 0x05, 0x00, 0x90, 0x00]
    );
}

#[test]
fn sign_hash_signs_the_digest_and_returns_v_as_zero_or_one() {
    let mut fixture = setup();
    let digest = [0x5au8; 32];
    let mut data = path_bytes();
    data.extend_from_slice(&digest);

    let (review_id, document) = expect_review(submit(&mut fixture, apdu(0x05, 0x00, &data)));
    assert_eq!(document.sections[0].title_key, "review.section.tron");
    assert_eq!(document.parse_status, ParseStatus::Partial);
    assert!(document.risks.iter().any(|r| r.code == "tron.sign_by_hash"));

    let payload = resolve(&mut fixture, review_id, ReviewDecision::Approve);
    verify_signature(&fixture, &payload, &digest);
}

#[test]
fn sign_hash_requires_exactly_32_bytes() {
    let mut fixture = setup();
    let mut data = path_bytes();
    data.extend_from_slice(&[0u8; 31]);
    assert_eq!(
        expect_emit(submit(&mut fixture, apdu(0x05, 0x00, &data))),
        vec![0x6A, 0x80]
    );
}

#[test]
fn personal_message_uses_the_tron_prefix_and_keccak() {
    let mut fixture = setup();
    let message = b"hello tron";
    let mut data = path_bytes();
    data.extend_from_slice(&(message.len() as u32).to_be_bytes());
    data.extend_from_slice(message);

    let (review_id, document) = expect_review(submit(&mut fixture, apdu(0x08, 0x00, &data)));
    assert_eq!(document.operation, OperationKind::Message);
    assert_eq!(
        field_value(&document, "review.field.message").as_deref(),
        Some("hello tron")
    );

    let payload = resolve(&mut fixture, review_id, ReviewDecision::Approve);
    let mut preimage = b"\x19TRON Signed Message:\n".to_vec();
    preimage.extend_from_slice(message.len().to_string().as_bytes());
    preimage.extend_from_slice(message);
    verify_signature(&fixture, &payload, &open_ledger_crypto::keccak256::hash(&preimage));
}

#[test]
fn personal_message_is_assembled_across_chunks() {
    let mut fixture = setup();
    let message = b"chunked personal message";
    let split = 7;
    let mut first = path_bytes();
    first.extend_from_slice(&(message.len() as u32).to_be_bytes());
    first.extend_from_slice(&message[..split]);

    let reply = submit(&mut fixture, apdu(0x08, 0x00, &first));
    match reply {
        RuntimeReply::Emit { payload, state, .. } => {
            assert_eq!(payload, vec![0x90, 0x00]);
            assert_eq!(state, OperationState::Collecting);
        }
        other => panic!("expected collecting emit, got {other:?}"),
    }

    let (review_id, _) = expect_review(submit(&mut fixture, apdu(0x08, 0x80, &message[split..])));
    let payload = resolve(&mut fixture, review_id, ReviewDecision::Approve);
    let mut preimage = b"\x19TRON Signed Message:\n".to_vec();
    preimage.extend_from_slice(message.len().to_string().as_bytes());
    preimage.extend_from_slice(message);
    verify_signature(&fixture, &payload, &open_ledger_crypto::keccak256::hash(&preimage));
}

#[test]
fn transfer_transaction_is_reviewed_with_to_and_amount() {
    let mut fixture = setup();
    let raw = transfer_tx(1_500_000);
    let mut data = path_bytes();
    data.extend_from_slice(&raw);

    // P1=0x10：单块即签。
    let (review_id, document) = expect_review(submit(&mut fixture, apdu(0x04, 0x10, &data)));
    assert_eq!(document.sections[0].title_key, "review.section.tron");
    assert_eq!(
        field_value(&document, "review.field.contract_type").as_deref(),
        Some("TransferContract")
    );
    assert_eq!(
        field_value(&document, "review.field.amount").as_deref(),
        Some("1500000")
    );
    assert!(field_value(&document, "review.field.to")
        .unwrap()
        .starts_with('T'));
    assert_eq!(document.parse_status, ParseStatus::Complete);

    let payload = resolve(&mut fixture, review_id, ReviewDecision::Approve);
    verify_signature(&fixture, &payload, &open_ledger_crypto::sha256::hash(&raw));
}

#[test]
fn transfer_transaction_is_assembled_across_chunks() {
    let mut fixture = setup();
    let raw = transfer_tx(42);
    let split = raw.len() / 2 + 1;

    let mut first = path_bytes();
    first.extend_from_slice(&raw[..split]);
    let reply = submit(&mut fixture, apdu(0x04, 0x00, &first));
    match reply {
        RuntimeReply::Emit { payload, state, .. } => {
            assert_eq!(payload, vec![0x90, 0x00]);
            assert_eq!(state, OperationState::Collecting);
        }
        other => panic!("expected collecting emit, got {other:?}"),
    }

    let (review_id, _) = expect_review(submit(&mut fixture, apdu(0x04, 0x90, &raw[split..])));
    let payload = resolve(&mut fixture, review_id, ReviewDecision::Approve);
    verify_signature(&fixture, &payload, &open_ledger_crypto::sha256::hash(&raw));
}

#[test]
fn trc20_transfer_decodes_the_recipient_and_amount() {
    let mut fixture = setup();
    let raw = trc20_transfer_tx();
    let mut data = path_bytes();
    data.extend_from_slice(&raw);

    let (review_id, document) = expect_review(submit(&mut fixture, apdu(0x04, 0x10, &data)));
    assert_eq!(
        field_value(&document, "review.field.contract_type").as_deref(),
        Some("TriggerSmartContract")
    );
    assert_eq!(
        field_value(&document, "review.field.selector").as_deref(),
        Some("a9059cbb")
    );
    assert_eq!(
        field_value(&document, "review.field.amount").as_deref(),
        Some("1000000")
    );
    assert_eq!(document.parse_status, ParseStatus::Complete);

    let payload = resolve(&mut fixture, review_id, ReviewDecision::Approve);
    verify_signature(&fixture, &payload, &open_ledger_crypto::sha256::hash(&raw));
}

#[test]
fn unknown_contract_gets_a_generic_review_instead_of_rejection() {
    let mut fixture = setup();
    let raw = unknown_contract_tx();
    let mut data = path_bytes();
    data.extend_from_slice(&raw);

    let (review_id, document) = expect_review(submit(&mut fixture, apdu(0x04, 0x10, &data)));
    assert_eq!(
        field_value(&document, "review.field.contract_type").as_deref(),
        Some("WitnessCreateContract (#5)")
    );
    assert_eq!(document.parse_status, ParseStatus::Partial);
    assert!(document
        .risks
        .iter()
        .any(|risk| risk.code == "tron.unknown_contract_type"));
    // 通用视图把 21 字节地址渲染成 base58。
    let generic: Vec<String> = document.sections[0]
        .fields
        .iter()
        .filter(|field| field.label_key == "review.field.param")
        .filter_map(|field| match &field.value {
            FieldValue::Text { value } => Some(value.clone()),
            _ => None,
        })
        .collect();
    assert_eq!(generic.len(), 1, "{generic:?}");
    assert!(generic[0].starts_with("field 1: T"), "{generic:?}");

    let payload = resolve(&mut fixture, review_id, ReviewDecision::Approve);
    verify_signature(&fixture, &payload, &open_ledger_crypto::sha256::hash(&raw));
}

#[test]
fn multi_contract_transaction_lists_every_contract() {
    let mut fixture = setup();
    let raw = two_contract_tx();
    let mut data = path_bytes();
    data.extend_from_slice(&raw);

    let (review_id, document) = expect_review(submit(&mut fixture, apdu(0x04, 0x10, &data)));
    let types: Vec<String> = document.sections[0]
        .fields
        .iter()
        .filter(|field| field.label_key == "review.field.contract_type")
        .filter_map(|field| match &field.value {
            FieldValue::Text { value } => Some(value.clone()),
            _ => None,
        })
        .collect();
    assert_eq!(
        types,
        vec![
            "TransferContract".to_string(),
            "WitnessCreateContract (#5)".to_string()
        ]
    );
    assert!(document
        .risks
        .iter()
        .any(|risk| risk.code == "tron.unknown_contract_type"));
    assert_eq!(document.parse_status, ParseStatus::Partial);

    let payload = resolve(&mut fixture, review_id, ReviewDecision::Approve);
    verify_signature(&fixture, &payload, &open_ledger_crypto::sha256::hash(&raw));
}

#[test]
fn critical_contract_type_is_flagged() {
    let mut fixture = setup();
    let raw = critical_contract_tx();
    let mut data = path_bytes();
    data.extend_from_slice(&raw);

    let (review_id, document) = expect_review(submit(&mut fixture, apdu(0x04, 0x10, &data)));
    assert!(document.risks.iter().any(|risk| {
        risk.code == "tron.critical_contract_type" && risk.severity == RiskLevel::Critical
    }));
    assert_eq!(document.parse_status, ParseStatus::Partial);

    let payload = resolve(&mut fixture, review_id, ReviewDecision::Approve);
    verify_signature(&fixture, &payload, &open_ledger_crypto::sha256::hash(&raw));
}

#[test]
fn malformed_protobuf_is_rejected() {
    let mut fixture = setup();
    let mut data = path_bytes();
    data.extend_from_slice(&[0x0a, 0x05, 0x01, 0x02]);
    assert_eq!(
        expect_emit(submit(&mut fixture, apdu(0x04, 0x10, &data))),
        vec![0x6A, 0x80]
    );
}

#[test]
fn a_path_outside_the_tron_subtree_is_rejected() {
    let mut fixture = setup();
    let mut data = vec![5u8];
    for component in [0x8000_002Cu32, 0x8000_003C, 0x8000_0000, 0, 0] {
        data.extend_from_slice(&component.to_be_bytes());
    }
    assert_eq!(
        expect_emit(submit(&mut fixture, apdu(0x02, 0x00, &data))),
        vec![0x6A, 0x80]
    );
}

#[test]
fn rejection_and_unsupported_commands() {
    let mut fixture = setup();
    let digest = [0x11u8; 32];
    let mut data = path_bytes();
    data.extend_from_slice(&digest);
    let (review_id, _) = expect_review(submit(&mut fixture, apdu(0x05, 0x00, &data)));
    assert_eq!(
        resolve(&mut fixture, review_id, ReviewDecision::Reject),
        vec![0x69, 0x85]
    );

    for ins in [0x0bu8, 0x0d] {
        let mut fixture = setup();
        assert_eq!(
            expect_emit(submit(&mut fixture, apdu(ins, 0x00, &[]))),
            vec![0x6D, 0x00],
            "INS 0x{ins:02X}"
        );
    }
}

#[test]
fn local_account_derivation_still_works() {
    let mut fixture = setup();
    let command = chain_app_api::LocalCommand::DeriveAccount {
        account_profile_index: 0,
        address_index: 1,
    };
    let reply = fixture
        .runtime
        .submit_local(fixture.session, 7, command)
        .unwrap();
    let payload = match reply {
        RuntimeReply::LocalReply { payload, .. } => payload,
        other => panic!("expected local reply, got {other:?}"),
    };
    let text = String::from_utf8(payload).unwrap();
    let seed = open_ledger_crypto::bip39::mnemonic_to_seed(MNEMONIC, "").unwrap();
    let expected = open_ledger_biz::tron::derive_address(&seed, "m/44'/195'/0'/0/1").unwrap();
    assert!(text.contains(&expected), "{text}");
}

#[test]
fn address_confirmation_requires_review_then_returns_the_address() {
    let mut fixture = setup();
    let (review_id, document) = expect_review(submit(&mut fixture, apdu(0x02, 0x01, &path_bytes())));
    assert_eq!(document.operation, OperationKind::AddressConfirmation);
    let address = field_value(&document, "review.field.address").unwrap();
    assert!(address.starts_with('T'));
    assert!(document.risks.is_empty());

    let payload = resolve(&mut fixture, review_id, ReviewDecision::Approve);
    assert_eq!(payload[0], 65);
    assert_eq!(payload[1], 0x04);
    assert_eq!(payload[66], address.len() as u8);
    assert_eq!(&payload[67..67 + address.len()], address.as_bytes());
    assert_eq!(&payload[payload.len() - 2..], &[0x90, 0x00]);
    assert_eq!(payload.len(), 1 + 65 + 1 + address.len() + 2);
}

#[test]
fn address_confirmation_can_be_rejected() {
    let mut fixture = setup();
    let (review_id, _) = expect_review(submit(&mut fixture, apdu(0x02, 0x01, &path_bytes())));
    assert_eq!(
        resolve(&mut fixture, review_id, ReviewDecision::Reject),
        vec![0x69, 0x85]
    );
}

#[test]
fn address_response_includes_the_chain_code_when_requested() {
    let mut fixture = setup_with(policy_with_chain_code());
    let payload = expect_emit(submit(
        &mut fixture,
        apdu_p2(0x02, 0x00, 0x01, &path_bytes()),
    ));
    assert_eq!(&payload[payload.len() - 2..], &[0x90, 0x00]);

    let body = &payload[..payload.len() - 2];
    let address_len = body[66] as usize;
    let address = &body[67..67 + address_len];
    let chain_code = &body[67 + address_len..];
    assert_eq!(chain_code.len(), 32);

    let (_, expected) = open_ledger_biz::hdkey::derive_secp256k1_extended(
        &fixture.keys.seed,
        "m/44'/195'/0'/0/0",
    )
    .unwrap();
    assert_eq!(chain_code, expected);

    let seed = open_ledger_crypto::bip39::mnemonic_to_seed(MNEMONIC, "").unwrap();
    let expected_address = open_ledger_biz::tron::derive_address(&seed, TRON_PATH).unwrap();
    assert_eq!(address, expected_address.as_bytes());
}

#[test]
fn ecdh_returns_the_uncompressed_shared_point() {
    let mut fixture = setup();
    let peer_private = [0x07u8; 32];
    let peer_public =
        open_ledger_crypto::secp256k1::public_key_bytes(&peer_private, false).unwrap();
    let mut data = path_bytes();
    data.extend_from_slice(&peer_public);

    let payload = expect_emit(submit(&mut fixture, apdu_p2(0x0A, 0x00, 0x01, &data)));
    assert_eq!(payload.len(), 65 + 2);
    assert_eq!(payload[0], 0x04);
    assert_eq!(&payload[65..], &[0x90, 0x00]);

    // 对称性校验：设备私钥 × 对端公钥 == 对端私钥 × 设备公钥。
    let device_public = open_ledger_crypto::secp256k1::public_key_bytes(
        &fixture.keys.private_key_at(&default_path()),
        false,
    )
    .unwrap();
    let expected =
        open_ledger_crypto::secp256k1::ecdh_shared_point(&peer_private, &device_public).unwrap();
    assert_eq!(&payload[..65], expected.as_slice());
}

#[test]
fn ecdh_rejects_bad_length_and_p1_p2() {
    let peer_private = [0x07u8; 32];
    let peer_public =
        open_ledger_crypto::secp256k1::public_key_bytes(&peer_private, false).unwrap();

    let mut fixture = setup();
    let mut short = path_bytes();
    short.extend_from_slice(&peer_public[..64]);
    assert_eq!(
        expect_emit(submit(&mut fixture, apdu_p2(0x0A, 0x00, 0x01, &short))),
        vec![0x6A, 0x80]
    );

    let mut fixture = setup();
    let mut data = path_bytes();
    data.extend_from_slice(&peer_public);
    assert_eq!(
        expect_emit(submit(&mut fixture, apdu_p2(0x0A, 0x00, 0x00, &data))),
        vec![0x6A, 0x86]
    );
}

#[test]
fn tip712_signs_the_domain_and_message_hashes() {
    let mut fixture = setup();
    let domain = [0x11u8; 32];
    let message = [0x22u8; 32];
    let mut data = path_bytes();
    data.extend_from_slice(&domain);
    data.extend_from_slice(&message);

    let (review_id, document) = expect_review(submit(&mut fixture, apdu(0x0C, 0x00, &data)));
    assert_eq!(document.operation, OperationKind::Message);
    assert_eq!(document.parse_status, ParseStatus::Partial);
    assert!(document
        .risks
        .iter()
        .any(|risk| risk.code == "tron.sign_by_hash"));
    assert_eq!(
        field_value(&document, "review.field.domain_hash").as_deref(),
        Some(hex::encode(domain).as_str())
    );
    assert_eq!(
        field_value(&document, "review.field.struct_hash").as_deref(),
        Some(hex::encode(message).as_str())
    );

    let payload = resolve(&mut fixture, review_id, ReviewDecision::Approve);
    let mut preimage = vec![0x19, 0x01];
    preimage.extend_from_slice(&domain);
    preimage.extend_from_slice(&message);
    verify_signature(&fixture, &payload, &open_ledger_crypto::keccak256::hash(&preimage));
}

#[test]
fn tip712_requires_two_hashes() {
    let mut fixture = setup();
    let mut data = path_bytes();
    data.extend_from_slice(&[0u8; 63]);
    assert_eq!(
        expect_emit(submit(&mut fixture, apdu(0x0C, 0x00, &data))),
        vec![0x6A, 0x80]
    );
}

#[test]
fn trc10_asset_transfer_waits_for_the_token_name_chunk() {
    let mut fixture = setup();
    let raw = transfer_asset_tx("USDT10", 5_000_000, Some(2));
    let split = raw.len() / 2 + 1;

    let mut first = path_bytes();
    first.extend_from_slice(&raw[..split]);
    match submit(&mut fixture, apdu(0x04, 0x00, &first)) {
        RuntimeReply::Emit { payload, state, .. } => {
            assert_eq!(payload, vec![0x90, 0x00]);
            assert_eq!(state, OperationState::Collecting);
        }
        other => panic!("expected collecting emit, got {other:?}"),
    }
    // tx 本体最后一帧是 0x80（不是 0x90），之后才是代币名分片。
    match submit(&mut fixture, apdu(0x04, 0x80, &raw[split..])) {
        RuntimeReply::Emit { payload, state, .. } => {
            assert_eq!(payload, vec![0x90, 0x00]);
            assert_eq!(state, OperationState::Collecting);
        }
        other => panic!("expected collecting emit, got {other:?}"),
    }

    let (review_id, document) = expect_review(submit(&mut fixture, apdu(0x04, 0xA8, b"USDT10")));
    assert_eq!(
        field_value(&document, "review.field.contract_type").as_deref(),
        Some("TransferAssetContract")
    );
    assert_eq!(
        field_value(&document, "review.field.asset").as_deref(),
        Some("USDT10")
    );
    assert_eq!(
        field_value(&document, "review.field.amount").as_deref(),
        Some("5000000")
    );
    assert_eq!(
        field_value(&document, "review.field.permission").as_deref(),
        Some("P2")
    );
    assert!(field_value(&document, "review.field.to")
        .unwrap()
        .starts_with('T'));
    assert_eq!(document.parse_status, ParseStatus::Complete);

    let payload = resolve(&mut fixture, review_id, ReviewDecision::Approve);
    verify_signature(&fixture, &payload, &open_ledger_crypto::sha256::hash(&raw));
}
