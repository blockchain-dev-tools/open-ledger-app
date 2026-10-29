//! NEAR 链 App 验收：地址、分块签名、公钥不匹配拒绝。

use std::sync::Arc;

use chain_app_api::*;
use chain_app_near::NearFactory;
use chain_app_runtime::{ReviewDecision, Runtime, RuntimeReply};
use ed25519_dalek::{Signature as DalekSignature, VerifyingKey};

const MNEMONIC: &str =
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
const NEAR_PATH: &str = "m/44'/397'/0'/0'/1'";
const NEAR_ACCOUNT_PATH: &str = "m/44'/397'/0'/0'/1'";

const PATH: [u32; 5] = [
    0x8000_002C,
    0x8000_018D,
    0x8000_0000,
    0x8000_0000,
    0x8000_0001,
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

/// `[44'|H, 397'|H, 0'|H, 0'|H, 1'|H]` → `m/44'/397'/0'/0'/1'`。
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
        .register_module(Arc::new(NearFactory), &policy())
        .unwrap();
    let (session, _) = runtime.open_app("openledger.near").unwrap();
    Fixture { runtime, session }
}

fn path_bytes() -> Vec<u8> {
    PATH.iter()
        .flat_map(|component| component.to_be_bytes())
        .collect()
}

fn apdu(ins: u8, p1: u8, data: &[u8]) -> Vec<u8> {
    let mut out = vec![0x80, ins, p1, 0x57, data.len() as u8];
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
    let private_key = open_ledger_biz::hdkey::derive_ed25519_private_key(&seed, NEAR_PATH).unwrap();
    open_ledger_crypto::ed25519::public_key_bytes(&private_key).unwrap()
}

fn string(value: &str) -> Vec<u8> {
    let mut out = (value.len() as u32).to_le_bytes().to_vec();
    out.extend_from_slice(value.as_bytes());
    out
}

/// 最小 borsh 交易：alice → bob 转 1 NEAR。
fn transfer_tx(public_key: &[u8]) -> Vec<u8> {
    let mut tx = Vec::new();
    tx.extend_from_slice(&string("alice.near"));
    tx.push(0); // ED25519
    tx.extend_from_slice(public_key);
    tx.extend_from_slice(&7u64.to_le_bytes()); // nonce
    tx.extend_from_slice(&string("bob.near"));
    tx.extend_from_slice(&[0x11; 32]); // block hash
    tx.extend_from_slice(&1u32.to_le_bytes()); // actions
    tx.push(3); // Transfer
    tx.extend_from_slice(&1_000_000_000_000_000_000_000_000u128.to_le_bytes());
    tx
}

#[test]
fn get_public_key_returns_the_implicit_account() {
    let mut fixture = setup();
    let payload = expect_emit(submit(&mut fixture, apdu(0x04, 0x01, &path_bytes())));
    assert_eq!(&payload[payload.len() - 2..], &[0x90, 0x00]);
    assert_eq!(payload[..32].to_vec(), public_key_bytes());
    let seed = open_ledger_crypto::bip39::mnemonic_to_seed(MNEMONIC, "").unwrap();
    assert_eq!(
        hex::encode(&payload[..32]),
        open_ledger_biz::near::derive_address(&seed, NEAR_PATH).unwrap()
    );
}

#[test]
fn display_flag_parks_a_review_before_returning_the_key() {
    let mut fixture = setup();
    let (review_id, document) = expect_review(submit(&mut fixture, apdu(0x04, 0x00, &path_bytes())));
    assert_eq!(document.operation, OperationKind::AddressConfirmation);
    assert_eq!(document.network.name, "NEAR");

    let payload = resolve(&mut fixture, review_id, ReviewDecision::Approve);
    assert_eq!(payload[..32].to_vec(), public_key_bytes());
    assert_eq!(&payload[32..], &[0x90, 0x00]);
}

#[test]
fn chunked_transaction_is_reviewed_then_signed_over_sha256() {
    let mut fixture = setup();
    let tx = transfer_tx(&public_key_bytes());

    // 首块：路径 + 前半段交易，`P1=0x00` 表示还有后续块。
    let mut first = path_bytes();
    first.extend_from_slice(&tx[..10]);
    let collecting = expect_emit(submit(&mut fixture, apdu(0x02, 0x00, &first)));
    assert_eq!(collecting, vec![0x90, 0x00]);

    let (review_id, document) = expect_review(submit(&mut fixture, apdu(0x02, 0x80, &tx[10..])));
    assert_eq!(document.network.name, "NEAR");
    let text = document.sections[0]
        .fields
        .iter()
        .find(|field| field.label_key == "review.field.message")
        .expect("summary field");
    match &text.value {
        FieldValue::Text { value } => {
            assert!(value.contains("alice.near"), "{value}");
            assert!(value.contains("bob.near"), "{value}");
            assert!(value.contains("1000000000000000000000000 yoctoNEAR"), "{value}");
        }
        other => panic!("unexpected summary: {other:?}"),
    }

    let payload = resolve(&mut fixture, review_id, ReviewDecision::Approve);
    assert_eq!(payload.len(), 66);
    assert_eq!(&payload[64..], &[0x90, 0x00]);

    let digest = open_ledger_crypto::sha256::hash(&tx);
    let verifying = VerifyingKey::from_bytes(&public_key_bytes().try_into().unwrap()).unwrap();
    let signature = DalekSignature::from_slice(&payload[..64]).unwrap();
    verifying.verify_strict(&digest, &signature).unwrap();
}

#[test]
fn a_transaction_for_another_key_is_refused() {
    let mut fixture = setup();
    let tx = transfer_tx(&[0x42; 32]);
    let mut data = path_bytes();
    data.extend_from_slice(&tx);
    let payload = expect_emit(submit(&mut fixture, apdu(0x02, 0x80, &data)));
    assert_eq!(payload, vec![0xB0, 0x0D]);
}

#[test]
fn rejected_review_returns_user_denied() {
    let mut fixture = setup();
    let mut data = path_bytes();
    data.extend_from_slice(&transfer_tx(&public_key_bytes()));
    let (review_id, _) = expect_review(submit(&mut fixture, apdu(0x02, 0x80, &data)));
    let payload = resolve(&mut fixture, review_id, ReviewDecision::Reject);
    assert_eq!(payload, vec![0x69, 0x85]);
}

#[test]
fn local_account_derivation_matches_the_library() {
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
    let expected = open_ledger_biz::near::derive_address(
        &open_ledger_crypto::bip39::mnemonic_to_seed(MNEMONIC, "").unwrap(),
        NEAR_ACCOUNT_PATH,
    )
    .unwrap();
    assert!(json.contains(&expected), "{json}");
}
