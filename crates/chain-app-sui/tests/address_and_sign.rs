//! 阶段 4 验收：Sui 地址与 Ed25519 签名。

use std::sync::Arc;

use chain_app_api::*;
use chain_app_runtime::{ReviewDecision, Runtime, RuntimeReply};
use chain_app_sui::SuiFactory;
use ed25519_dalek::{Signature as DalekSignature, VerifyingKey};

const MNEMONIC: &str =
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
const SUI_PATH: &str = "m/44'/784'/0'/0'/0'";

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
    let (session, _) = runtime.open_app("openledger.sui").unwrap();
    Fixture { runtime, session }
}

fn path_bytes() -> Vec<u8> {
    let mut out = vec![5u8];
    for component in [
        0x8000_002Cu32,
        0x8000_0310,
        0x8000_0000,
        0x8000_0000,
        0x8000_0000,
    ] {
        out.extend_from_slice(&component.to_be_bytes());
    }
    out
}

fn apdu(ins: u8, data: &[u8]) -> Vec<u8> {
    let mut out = vec![0x07, ins, 0x00, 0x00, data.len() as u8];
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

fn expected_address() -> String {
    let seed = open_ledger_crypto::bip39::mnemonic_to_seed(MNEMONIC, "").unwrap();
    open_ledger_biz::sui::derive_address(&seed, SUI_PATH).unwrap()
}

#[test]
fn address_matches_the_library_derivation() {
    let mut fixture = setup();
    let payload = expect_emit(submit(&mut fixture, apdu(0x02, &path_bytes())));
    assert_eq!(&payload[payload.len() - 2..], &[0x90, 0x00]);
    let address = String::from_utf8(payload[..payload.len() - 2].to_vec()).unwrap();
    assert_eq!(address, expected_address());
    assert!(address.starts_with("0x"));
}

#[test]
fn sign_review_and_signature_verify_against_the_message() {
    let mut fixture = setup();
    let message = b"sui transaction intent message".to_vec();
    let mut data = path_bytes();
    data.extend_from_slice(&message);

    let (review_id, document) = expect_review(submit(&mut fixture, apdu(0x04, &data)));
    assert_eq!(document.network.name, "Sui");
    assert_eq!(document.sections[0].title_key, "review.section.sui");
    assert_eq!(document.account.as_deref(), Some(expected_address().as_str()));

    let payload = resolve(&mut fixture, review_id, ReviewDecision::Approve);
    assert_eq!(payload.len(), 66);
    assert_eq!(&payload[64..], &[0x90, 0x00]);

    let seed = open_ledger_crypto::bip39::mnemonic_to_seed(MNEMONIC, "").unwrap();
    let private_key = open_ledger_biz::hdkey::derive_ed25519_private_key(&seed, SUI_PATH).unwrap();
    let public_key = open_ledger_crypto::ed25519::public_key_bytes(&private_key).unwrap();
    let verifying = VerifyingKey::from_bytes(&public_key.try_into().unwrap()).unwrap();
    let signature = DalekSignature::from_slice(&payload[..64]).unwrap();
    verifying.verify_strict(&message, &signature).unwrap();
}

#[test]
fn rejecting_a_signature_returns_user_denied() {
    let mut fixture = setup();
    let mut data = path_bytes();
    data.extend_from_slice(b"payload");
    let (review_id, _) = expect_review(submit(&mut fixture, apdu(0x04, &data)));
    assert_eq!(
        resolve(&mut fixture, review_id, ReviewDecision::Reject),
        vec![0x69, 0x85]
    );
}

#[test]
fn empty_payload_is_rejected() {
    let mut fixture = setup();
    assert_eq!(
        expect_emit(submit(&mut fixture, apdu(0x04, &path_bytes()))),
        vec![0x6A, 0x80]
    );
}

#[test]
fn unknown_ins_is_rejected() {
    let mut fixture = setup();
    assert_eq!(
        expect_emit(submit(&mut fixture, apdu(0x09, &[]))),
        vec![0x6D, 0x00]
    );
}
