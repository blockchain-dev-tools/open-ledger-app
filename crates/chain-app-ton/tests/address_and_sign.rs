//! TON 链 App 验收：公钥、v4r2 交易哈希与签名、未支持形态的拒绝。

use std::sync::Arc;

use chain_app_api::*;
use chain_app_runtime::{ReviewDecision, Runtime, RuntimeReply};
use chain_app_ton::TonFactory;
use ed25519_dalek::{Signature as DalekSignature, VerifyingKey};

const MNEMONIC: &str =
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
const TON_PATH: &str = "m/44'/607'/0'/0'/0'/0'";

const PATH: [u32; 6] = [
    0x8000_002C,
    0x8000_025F,
    0x8000_0000,
    0x8000_0000,
    0x8000_0000,
    0x8000_0000,
];

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

    fn private_key(&self, path: &[u32]) -> Vec<u8> {
        open_ledger_biz::hdkey::derive_ed25519_private_key(&self.seed, &format_path(path)).unwrap()
    }
}

fn format_path(path: &[u32]) -> String {
    let parts: Vec<String> = path
        .iter()
        .map(|component| {
            if *component >= 0x8000_0000 {
                format!("{}'", component - 0x8000_0000)
            } else {
                component.to_string()
            }
        })
        .collect();
    format!("m/{}", parts.join("/"))
}

impl KeyService for EdKeys {
    fn public_key(&self, request: &PublicKeyRequest) -> Result<PublicKey, HostError> {
        let key = open_ledger_crypto::ed25519::public_key_bytes(&self.private_key(&request.path))
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
        let bytes =
            open_ledger_crypto::ed25519::sign(&self.private_key(&operation.path), &operation.input)
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
        derivation_rules: vec![
            DerivationRule {
                derivation_scheme: DerivationScheme::Slip10Ed25519,
                curve: Curve::Ed25519,
                depth: 6,
                hardened_positions: vec![0, 1, 2, 3, 4, 5],
                max_index: 1000,
            },
            DerivationRule {
                derivation_scheme: DerivationScheme::Slip10Ed25519,
                curve: Curve::Ed25519,
                depth: 3,
                hardened_positions: vec![0, 1, 2],
                max_index: 1000,
            },
        ],
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
        .register_module(Arc::new(TonFactory), &policy())
        .unwrap();
    let (session, _) = runtime.open_app("openledger.ton").unwrap();
    Fixture { runtime, session }
}

fn path_bytes() -> Vec<u8> {
    let mut out = vec![PATH.len() as u8];
    for component in PATH {
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

fn public_key_bytes() -> Vec<u8> {
    let seed = open_ledger_crypto::bip39::mnemonic_to_seed(MNEMONIC, "").unwrap();
    let private_key = open_ledger_biz::hdkey::derive_ed25519_private_key(&seed, TON_PATH).unwrap();
    open_ledger_crypto::ed25519::public_key_bytes(&private_key).unwrap()
}

/// 普通转账请求：tag / seqno / timeout / value / dest / bounce / send_mode /
/// 三个 “has_xxx = 0”。
fn transfer_request() -> Vec<u8> {
    let mut out = vec![0x00];
    out.extend_from_slice(&1u32.to_be_bytes()); // seqno
    out.extend_from_slice(&0x6000_0000u32.to_be_bytes()); // timeout
    out.push(8);
    out.extend_from_slice(&1_000_000_000u64.to_be_bytes()); // 1 TON
    out.push(0x00); // workchain
    out.extend_from_slice(&[0xAB; 32]);
    out.push(0x00); // bounce
    out.push(0x03); // send_mode
    out.extend_from_slice(&[0x00, 0x00, 0x00]);
    out
}

#[test]
fn version_and_app_name_identify_the_emulated_app() {
    let mut fixture = setup();
    let version = expect_emit(submit(&mut fixture, apdu(0x03, 0, 0, &[])));
    assert_eq!(version, vec![1, 0, 0, 0x90, 0x00]);
    // 每个 Final 响应都会结束会话；宿主在下一帧前重新打开 App。
    let (session, _) = fixture.runtime.open_app("openledger.ton").unwrap();
    fixture.session = session;
    let name = expect_emit(submit(&mut fixture, apdu(0x04, 0, 0, &[])));
    assert_eq!(&name[..3], b"TON");
    assert_eq!(&name[3..], &[0x90, 0x00]);
}

#[test]
fn get_public_key_matches_the_library_derivation() {
    let mut fixture = setup();
    let payload = expect_emit(submit(&mut fixture, apdu(0x05, 0, 0, &path_bytes())));
    assert_eq!(payload.len(), 34);
    assert_eq!(payload[..32].to_vec(), public_key_bytes());
    assert_eq!(&payload[32..], &[0x90, 0x00]);
}

#[test]
fn display_flag_parks_a_review_before_returning_the_key() {
    let mut fixture = setup();
    let (review_id, document) = expect_review(submit(&mut fixture, apdu(0x05, 1, 0, &path_bytes())));
    assert_eq!(document.operation, OperationKind::AddressConfirmation);
    assert_eq!(document.network.name, "TON");

    let payload = resolve(&mut fixture, review_id, ReviewDecision::Approve);
    assert_eq!(payload[..32].to_vec(), public_key_bytes());
    assert_eq!(&payload[32..], &[0x90, 0x00]);
}

#[test]
fn simple_transfer_is_hashed_and_signed_as_a_v4r2_order() {
    let mut fixture = setup();
    // 首包只带路径（P2=0x03），随后是末包（P2=0x00）。
    let collecting = expect_emit(submit(&mut fixture, apdu(0x06, 0, 0x03, &path_bytes())));
    assert_eq!(collecting, vec![0x90, 0x00]);

    let (review_id, document) = expect_review(submit(
        &mut fixture,
        apdu(0x06, 0, 0x00, &transfer_request()),
    ));
    assert_eq!(document.network.name, "TON");
    let text = document.sections[0]
        .fields
        .iter()
        .find(|field| field.label_key == "review.field.message")
        .expect("summary field");
    match &text.value {
        FieldValue::Text { value } => {
            assert!(value.contains("1000000000 nanoton"), "{value}");
            assert!(value.contains("Seqno: 1"), "{value}");
        }
        other => panic!("unexpected summary: {other:?}"),
    }

    let payload = resolve(&mut fixture, review_id, ReviewDecision::Approve);
    assert_eq!(payload.len(), 100);
    assert_eq!(payload[0], 64);
    assert_eq!(payload[65], 32);
    assert_eq!(&payload[98..], &[0x90, 0x00]);

    let hash: [u8; 32] = payload[66..98].try_into().unwrap();
    let verifying = VerifyingKey::from_bytes(&public_key_bytes().try_into().unwrap()).unwrap();
    let signature = DalekSignature::from_slice(&payload[1..65]).unwrap();
    verifying.verify_strict(&hash, &signature).unwrap();
}

#[test]
fn payload_and_state_init_are_refused_until_implemented() {
    let mut fixture = setup();
    expect_emit(submit(&mut fixture, apdu(0x06, 0, 0x03, &path_bytes())));
    let mut request = transfer_request();
    request[54] = 0x01; // has_payload
    let payload = expect_emit(submit(&mut fixture, apdu(0x06, 0, 0x00, &request)));
    assert_eq!(payload, vec![0xB0, 0x10]);
}

#[test]
fn a_path_without_the_ton_prefix_is_rejected() {
    let mut fixture = setup();
    let mut data = path_bytes();
    data[5] = 0x01; // 破坏 607'
    let payload = expect_emit(submit(&mut fixture, apdu(0x05, 0, 0, &data)));
    assert_eq!(payload, vec![0x6A, 0x87]);
}

#[test]
fn rejected_review_returns_user_denied() {
    let mut fixture = setup();
    expect_emit(submit(&mut fixture, apdu(0x06, 0, 0x03, &path_bytes())));
    let (review_id, _) =
        expect_review(submit(&mut fixture, apdu(0x06, 0, 0x00, &transfer_request())));
    let payload = resolve(&mut fixture, review_id, ReviewDecision::Reject);
    assert_eq!(payload, vec![0x69, 0x85]);
}

#[test]
fn local_account_derivation_builds_a_v4r2_address() {
    let mut fixture = setup();
    let reply = fixture
        .runtime
        .submit_local(
            fixture.session,
            1,
            LocalCommand::DeriveAccount {
                account_profile_index: 0,
                address_index: 0,
            },
        )
        .unwrap();
    let RuntimeReply::LocalReply { payload, .. } = reply else {
        panic!("expected local reply");
    };
    let json = String::from_utf8(payload).unwrap();
    let seed = open_ledger_crypto::bip39::mnemonic_to_seed(MNEMONIC, "").unwrap();
    let expected = open_ledger_biz::ton::derive_address(&seed, TON_PATH).unwrap();
    assert!(json.contains(&expected), "{json}");
}
