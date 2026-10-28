//! 阶段 2 切片 A 验收：`GET_PUBLIC_KEY` 经新 runtime 后与官方 app-ethereum
//! 的响应布局、地址与状态字一致；确认走宿主审批，拒绝不产生密钥访问。

use std::sync::{Arc, Mutex};

use chain_app_api::*;
use chain_app_ethereum::{descriptor, EthereumFactory};
use chain_app_runtime::{ReviewDecision, Runtime, RuntimeReply};

const MNEMONIC: &str =
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
const EXPECTED_ADDRESS: &str = "0x9858EfFD232B4033E47d90003D41EC34EcaEda94";

struct CryptoKeys {
    seed: Vec<u8>,
    public_key_calls: Mutex<usize>,
}

impl CryptoKeys {
    fn new() -> Self {
        let seed = open_ledger_crypto::bip39::mnemonic_to_seed(MNEMONIC, "")
            .unwrap()
            .to_vec();
        Self {
            seed,
            public_key_calls: Mutex::new(0),
        }
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
        *self.public_key_calls.lock().unwrap() += 1;
        let (private_key, chain_code) =
            open_ledger_biz::hdkey::derive_secp256k1_extended(&self.seed, &path_string(&request.path))
                .map_err(|e| HostError::Unavailable(e.to_string()))?;
        let bytes = open_ledger_crypto::secp256k1::public_key_bytes(&private_key, false)
            .map_err(|e| HostError::Unavailable(e.to_string()))?;
        Ok(PublicKey {
            bytes,
            chain_code: if request.include_chain_code {
                Some(chain_code.to_vec())
            } else {
                None
            },
        })
    }

    fn sign(
        &self,
        _auth: &SignAuthorization,
        _operation: &SignOperation,
    ) -> Result<Signature, HostError> {
        Err(HostError::Denied("signing not implemented in slice A".into()))
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
        allow_chain_code: true,
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
    let (session, opened) = runtime.open_app("openledger.ethereum").unwrap();
    assert_eq!(opened.module_id, descriptor().module_id);
    Fixture {
        runtime,
        keys,
        session,
    }
}

fn apdu(ins: u8, p1: u8, p2: u8, data: &[u8]) -> Vec<u8> {
    let mut out = vec![0xE0, ins, p1, p2, data.len() as u8];
    out.extend_from_slice(data);
    out
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

fn assert_public_key_layout(payload: &[u8], expected_address: &str) {
    assert_eq!(payload[0], 0x41);
    assert_eq!(payload[1], 0x04, "uncompressed public key prefix");
    let address_len = payload[66] as usize;
    assert_eq!(address_len, expected_address.len() - 2);
    let address = std::str::from_utf8(&payload[67..67 + address_len]).unwrap();
    assert_eq!(address, expected_address.trim_start_matches("0x"));
    let sw = &payload[payload.len() - 2..];
    assert_eq!(sw, [0x90, 0x00]);
}

#[test]
fn returns_address_without_confirmation() {
    let mut fixture = setup();
    let payload = expect_emit(submit(&mut fixture, apdu(0x02, 0x00, 0x00, &[])));
    assert_public_key_layout(&payload, EXPECTED_ADDRESS);
    assert_eq!(payload.len(), 1 + 65 + 1 + 40 + 2);
    // P1=0x00 不产生审阅。
    assert_eq!(fixture.runtime.pending_reviews(), 0);
}

#[test]
fn explicit_path_is_used() {
    let mut fixture = setup();
    let mut data = vec![5u8];
    for component in [0x8000_002cu32, 0x8000_003c, 0x8000_0000, 0, 0] {
        data.extend_from_slice(&component.to_be_bytes());
    }
    let payload = expect_emit(submit(&mut fixture, apdu(0x02, 0x00, 0x00, &data)));
    assert_public_key_layout(&payload, EXPECTED_ADDRESS);
}

#[test]
fn chain_code_is_appended_only_when_requested() {
    let mut fixture = setup();
    let payload = expect_emit(submit(&mut fixture, apdu(0x02, 0x00, 0x01, &[])));
    assert_public_key_layout(&payload, EXPECTED_ADDRESS);
    // 1 + 65 + 1 + 40 + 32 + 2
    assert_eq!(payload.len(), 141);
}

#[test]
fn confirmation_goes_through_review_then_returns_the_address() {
    let mut fixture = setup();
    let review_id = match submit(&mut fixture, apdu(0x02, 0x01, 0x00, &[])) {
        RuntimeReply::Review {
            review_id,
            document,
            action,
        } => {
            assert_eq!(document.operation, OperationKind::AddressConfirmation);
            assert!(!action.requires_signature());
            review_id
        }
        other => panic!("expected review, got {other:?}"),
    };
    let payload = expect_emit(
        fixture
            .runtime
            .resolve_review(fixture.session, review_id, ReviewDecision::Approve)
            .unwrap(),
    );
    assert_public_key_layout(&payload, EXPECTED_ADDRESS);
    // 地址确认不触发密钥服务。
    assert_eq!(*fixture.keys.public_key_calls.lock().unwrap(), 1);
}

#[test]
fn rejection_returns_6985() {
    let mut fixture = setup();
    let review_id = match submit(&mut fixture, apdu(0x02, 0x01, 0x00, &[])) {
        RuntimeReply::Review { review_id, .. } => review_id,
        other => panic!("expected review, got {other:?}"),
    };
    let payload = expect_emit(
        fixture
            .runtime
            .resolve_review(fixture.session, review_id, ReviewDecision::Reject)
            .unwrap(),
    );
    assert_eq!(payload, vec![0x69, 0x85]);
}

#[test]
fn timeout_returns_6985() {
    let mut fixture = setup();
    let review_id = match submit(&mut fixture, apdu(0x02, 0x01, 0x00, &[])) {
        RuntimeReply::Review { review_id, .. } => review_id,
        other => panic!("expected review, got {other:?}"),
    };
    fixture.runtime.expire_review(review_id).unwrap();
    let error = fixture
        .runtime
        .resolve_review(fixture.session, review_id, ReviewDecision::Approve)
        .unwrap_err();
    assert!(matches!(error, chain_app_runtime::RuntimeError::Approval(_)));
}

#[test]
fn bad_p1_is_rejected_before_any_key_access() {
    let mut fixture = setup();
    let payload = expect_emit(submit(&mut fixture, apdu(0x02, 0x02, 0x00, &[])));
    assert_eq!(payload, vec![0x6A, 0x86]);
    assert_eq!(*fixture.keys.public_key_calls.lock().unwrap(), 0);
}

#[test]
fn bad_p2_is_rejected() {
    let mut fixture = setup();
    let payload = expect_emit(submit(&mut fixture, apdu(0x02, 0x00, 0x02, &[])));
    assert_eq!(payload, vec![0x6A, 0x86]);
}

#[test]
fn truncated_path_returns_wrong_data() {
    let mut fixture = setup();
    // 声明 3 段但只给 2 段。
    let mut data = vec![3u8];
    for component in [0x8000_002cu32, 0x8000_003c] {
        data.extend_from_slice(&component.to_be_bytes());
    }
    let payload = expect_emit(submit(&mut fixture, apdu(0x02, 0x00, 0x00, &data)));
    assert_eq!(payload, vec![0x6A, 0x80]);
}

#[test]
fn no_seed_reaches_the_module() {
    // 编译期约束：模块只能拿到 PublicKey，拿不到 seed；这里用行为断言兜底——
    // 未授予的路径不会被请求，密钥服务调用次数为 0。
    let keys = Arc::new(CryptoKeys::new());
    let mut runtime = Runtime::new(
        "vault-a",
        Default::default(),
        keys.clone(),
        Box::new(NoStorage),
    );
    let mut strict = policy();
    strict.derivation_rules[0].max_index = 0;
    runtime
        .register_module(Arc::new(EthereumFactory), &strict)
        .unwrap();
    let (session, _) = runtime.open_app("openledger.ethereum").unwrap();
    let payload = match runtime
        .submit_wire(session, Wire::LedgerApdu, apdu(0x02, 0x00, 0x00, &[]))
        .unwrap()
    {
        RuntimeReply::Emit { payload, .. } => payload,
        other => panic!("expected emit, got {other:?}"),
    };
    assert_eq!(payload, vec![0x6F, 0x00]);
    assert_eq!(*keys.public_key_calls.lock().unwrap(), 0);
}
