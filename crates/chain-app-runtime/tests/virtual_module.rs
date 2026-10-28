//! 虚拟模块端到端测试：越权、重放、锁定、过期、篡改、存储隔离、单活动操作、投递失败。
//!
//! 这些用例不依赖真实链、不依赖设备，跑在 `cargo test` 里；
//! 它们断言的是**宿主边界**，而不是某个链的解析正确性。

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use chain_app_api::*;
use chain_app_runtime::{ReviewDecision, Runtime, RuntimeError, RuntimeReply};

const PATH_ETH: [u32; 5] = [
    0x8000_002c, // 44'
    0x8000_003c, // 60'
    0x8000_0000, // 0'
    0,
    0,
];

const DIGEST: [u8; 32] = [0x11; 32];

// ── 宿主服务桩 ────────────────────────────────────────────────────────

#[derive(Default)]
struct RecordingKeys {
    public_key_calls: Mutex<Vec<PublicKeyRequest>>,
    sign_calls: Mutex<Vec<SignOperation>>,
}

impl KeyService for RecordingKeys {
    fn public_key(&self, request: &PublicKeyRequest) -> Result<PublicKey, HostError> {
        self.public_key_calls.lock().unwrap().push(request.clone());
        Ok(PublicKey {
            bytes: vec![0x02; 33],
            chain_code: None,
        })
    }

    fn sign(
        &self,
        _auth: &SignAuthorization,
        operation: &SignOperation,
    ) -> Result<Signature, HostError> {
        self.sign_calls.lock().unwrap().push(operation.clone());
        Ok(Signature {
            operation_id: operation.operation_id,
            bytes: vec![0xAA; 64],
            recovery_id: None,
        })
    }
}

#[derive(Default)]
struct MemoryStorage {
    entries: HashMap<String, Vec<u8>>,
}

impl StorageService for MemoryStorage {
    fn read(&mut self, scope: &StorageScope, key: &str) -> Result<Option<Vec<u8>>, HostError> {
        Ok(self.entries.get(&scope.physical_key(key)).cloned())
    }

    fn write(&mut self, scope: &StorageScope, key: &str, value: Vec<u8>) -> Result<(), HostError> {
        self.entries.insert(scope.physical_key(key), value);
        Ok(())
    }

    fn delete(&mut self, scope: &StorageScope, key: &str) -> Result<(), HostError> {
        self.entries.remove(&scope.physical_key(key));
        Ok(())
    }
}

// ── 虚拟模块 ──────────────────────────────────────────────────────────

struct VirtualModule {
    module_id: String,
    exchange: u64,
    stage: Stage,
}

enum Stage {
    Idle,
    Key,
    Sign,
    StoreWrite,
    StoreRead,
}

impl VirtualModule {
    fn new(module_id: &str) -> Self {
        Self {
            module_id: module_id.to_string(),
            exchange: 0,
            stage: Stage::Idle,
        }
    }

    fn descriptor_for(module_id: &str) -> AppDescriptor {
        AppDescriptor {
            module_id: module_id.to_string(),
            module_version: "0.0.1".into(),
            api_version: API_VERSION,
            review_schema_version: 1,
            storage_schema_version: 1,
            protocol_profiles: vec![ProtocolProfile {
                name: "Virtual".into(),
                version: "1.0".into(),
                wire: Wire::LedgerApdu,
                supported: vec!["VIRTUAL_TEST_CMD".into()],
                unsupported: vec!["everything-else".into()],
                vector_sources: vec!["tests/virtual_module.rs".into()],
            }],
            account_profiles: vec![AccountProfile {
                network: "virtual".into(),
                account_type: "default".into(),
                default_path: "m/44'/60'/0'/0/0".into(),
                derivation_scheme: DerivationScheme::Bip32Secp256k1,
                curve: Curve::Secp256k1,
            }],
            requested_capabilities: CapabilitySet {
                derivation_rules: vec![DerivationRule {
                    derivation_scheme: DerivationScheme::Bip32Secp256k1,
                    curve: Curve::Secp256k1,
                    depth: 5,
                    hardened_positions: vec![0, 1, 2],
                    max_index: 1000,
                }],
                allow_chain_code: false,
                allow_signing: true,
                allow_storage: true,
            },
        }
    }

    fn transaction_document(status: ParseStatus) -> ReviewDocument {
        ReviewDocument {
            operation: OperationKind::Transaction,
            network: NetworkId {
                name: "virtual".into(),
                chain_id: Some(1),
            },
            account: Some("0xabc".into()),
            sections: vec![ReviewSection {
                title_key: "review.section.transfer".into(),
                fields: vec![
                    Field {
                        label_key: "review.field.amount".into(),
                        value: FieldValue::Amount {
                            raw: "1000".into(),
                            decimals: 18,
                            asset: "ETH".into(),
                            ticker: Some("ETH".into()),
                        },
                    },
                    Field {
                        label_key: "review.field.to".into(),
                        value: FieldValue::Address {
                            value: "0xdef".into(),
                            network: "virtual".into(),
                            role: "recipient".into(),
                        },
                    },
                ],
            }],
            risks: vec![],
            parse_status: status,
        }
    }

    fn sign_plan(operations: Vec<SignOperation>) -> SignPlan {
        SignPlan { operations }
    }

    fn op(id: u32) -> SignOperation {
        SignOperation {
            operation_id: id,
            derivation_scheme: DerivationScheme::Bip32Secp256k1,
            curve: Curve::Secp256k1,
            path: PATH_ETH.to_vec(),
            scheme: SignScheme::EcdsaPrehash {
                digest_len: 32,
                low_s: true,
            },
            input: DIGEST.to_vec(),
            public_parameters: vec![],
        }
    }
}

impl ChainApp for VirtualModule {
    fn open(&mut self, _config: SessionConfig) -> Result<(), AppError> {
        Ok(())
    }

    fn step(&mut self, event: Event) -> Result<Effect, AppError> {
        match event {
            Event::Wire {
                exchange_id,
                payload,
                ..
            } => {
                self.exchange = exchange_id;
                match payload.first().copied() {
                    Some(0x01) => {
                        self.stage = Stage::Key;
                        Ok(Effect::NeedPublicKey {
                            service_id: 1,
                            request: PublicKeyRequest {
                                derivation_scheme: DerivationScheme::Bip32Secp256k1,
                                curve: Curve::Secp256k1,
                                path: PATH_ETH.to_vec(),
                                output: KeyOutput::CompressedSecp256k1,
                                include_chain_code: false,
                            },
                        })
                    }
                    Some(0x02) => {
                        let plan = Self::sign_plan(vec![Self::op(1)]);
                        self.stage = Stage::Sign;
                        Ok(Effect::NeedReview {
                            service_id: 2,
                            request: Box::new(ReviewRequest {
                                document: Self::transaction_document(ParseStatus::Complete),
                                action: ReviewAction::Sign(plan),
                            }),
                        })
                    }
                    Some(0x03) => {
                        self.stage = Stage::Key;
                        let mut path = PATH_ETH.to_vec();
                        path[4] = 900; // 超出授予的索引上限
                        Ok(Effect::NeedPublicKey {
                            service_id: 1,
                            request: PublicKeyRequest {
                                derivation_scheme: DerivationScheme::Bip32Secp256k1,
                                curve: Curve::Secp256k1,
                                path,
                                output: KeyOutput::CompressedSecp256k1,
                                include_chain_code: false,
                            },
                        })
                    }
                    Some(0x04) => {
                        self.stage = Stage::StoreWrite;
                        Ok(Effect::NeedStore {
                            service_id: 3,
                            operation: StorageOp::Write {
                                key: "cfg".into(),
                                value: b"v1".to_vec(),
                            },
                        })
                    }
                    Some(0x05) => {
                        self.stage = Stage::StoreRead;
                        Ok(Effect::NeedStore {
                            service_id: 3,
                            operation: StorageOp::Read { key: "cfg".into() },
                        })
                    }
                    Some(0x06) => {
                        let plan = Self::sign_plan(vec![Self::op(1)]);
                        Ok(Effect::NeedReview {
                            service_id: 2,
                            request: Box::new(ReviewRequest {
                                document: Self::transaction_document(ParseStatus::Opaque),
                                action: ReviewAction::Sign(plan),
                            }),
                        })
                    }
                    Some(0x07) => {
                        let plan = Self::sign_plan(vec![Self::op(1), Self::op(2)]);
                        self.stage = Stage::Sign;
                        Ok(Effect::NeedReview {
                            service_id: 2,
                            request: Box::new(ReviewRequest {
                                document: Self::transaction_document(ParseStatus::Complete),
                                action: ReviewAction::Sign(plan),
                            }),
                        })
                    }
                    Some(0x08) => {
                        let action = ReviewAction::DisplayAddress {
                            derivation_scheme: DerivationScheme::Bip32Secp256k1,
                            curve: Curve::Secp256k1,
                            path: PATH_ETH.to_vec(),
                        };
                        Ok(Effect::NeedReview {
                            service_id: 2,
                            request: Box::new(ReviewRequest {
                                document: ReviewDocument {
                                    operation: OperationKind::AddressConfirmation,
                                    network: NetworkId {
                                        name: "virtual".into(),
                                        chain_id: Some(1),
                                    },
                                    account: None,
                                    sections: vec![],
                                    risks: vec![],
                                    parse_status: ParseStatus::Complete,
                                },
                                action,
                            }),
                        })
                    }
                    _ => Err(AppError::BadRequest("unknown command".into())),
                }
            }
            Event::ServiceResult { result, .. } => match &self.stage {
                Stage::Key => match result {
                    ServiceResult::PublicKey(key) => Ok(Effect::Emit {
                        wire: Wire::LedgerApdu,
                        exchange_id: self.exchange,
                        payload: key.bytes,
                        state: OperationState::Final,
                    }),
                    ServiceResult::Failed(_) => Ok(Effect::Emit {
                        wire: Wire::LedgerApdu,
                        exchange_id: self.exchange,
                        payload: b"denied".to_vec(),
                        state: OperationState::Final,
                    }),
                    ServiceResult::Storage(_) | ServiceResult::SharedSecret(_) => {
                        Err(AppError::InvalidEvent("wrong result".into()))
                    }
                },
                Stage::StoreWrite => {
                    self.stage = Stage::StoreRead;
                    Ok(Effect::NeedStore {
                        service_id: 4,
                        operation: StorageOp::Read { key: "cfg".into() },
                    })
                }
                Stage::StoreRead => match result {
                    ServiceResult::Storage(value) => Ok(Effect::Emit {
                        wire: Wire::LedgerApdu,
                        exchange_id: self.exchange,
                        payload: value.unwrap_or_default(),
                        state: OperationState::Final,
                    }),
                    _ => Err(AppError::InvalidEvent("wrong result".into())),
                },
                Stage::Sign | Stage::Idle => {
                    Err(AppError::InvalidEvent("unexpected service result".into()))
                }
            },
            Event::ReviewResult { outcome, .. } => match outcome {
                ReviewOutcome::Approved { signatures } => {
                    let payload: Vec<u8> = signatures.into_iter().flat_map(|s| s.bytes).collect();
                    Ok(Effect::Emit {
                        wire: Wire::LedgerApdu,
                        exchange_id: self.exchange,
                        payload,
                        state: OperationState::Final,
                    })
                }
                ReviewOutcome::Rejected => Ok(Effect::Emit {
                    wire: Wire::LedgerApdu,
                    exchange_id: self.exchange,
                    payload: vec![0x69, 0x85],
                    state: OperationState::Final,
                }),
                ReviewOutcome::TimedOut => Ok(Effect::Emit {
                    wire: Wire::LedgerApdu,
                    exchange_id: self.exchange,
                    payload: vec![0x64, 0x00],
                    state: OperationState::Final,
                }),
                ReviewOutcome::Failed(_) => Ok(Effect::Emit {
                    wire: Wire::LedgerApdu,
                    exchange_id: self.exchange,
                    payload: vec![0x6f, 0x00],
                    state: OperationState::Final,
                }),
            },
            Event::Delivered { .. } => Ok(Effect::Finished {
                status: FinishStatus::Delivered,
            }),
            Event::Cancel { .. } => Ok(Effect::Finished {
                status: FinishStatus::Cancelled,
            }),
            Event::Local { request_id, .. } => Ok(Effect::LocalReply {
                request_id,
                payload: b"local".to_vec(),
            }),
        }
    }

    fn close(&mut self, _reason: CancelReason) {
        let _ = &self.module_id;
    }
}

struct VirtualFactory {
    module_id: String,
}

impl ModuleFactory for VirtualFactory {
    fn describe(&self) -> AppDescriptor {
        VirtualModule::descriptor_for(&self.module_id)
    }

    fn create(&self) -> Box<dyn ChainApp> {
        Box::new(VirtualModule::new(&self.module_id))
    }
}

// ── 夹具 ──────────────────────────────────────────────────────────────

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
        allow_storage: true,
    }
}

fn setup() -> (Runtime, Arc<RecordingKeys>, SessionId) {
    let keys = Arc::new(RecordingKeys::default());
    let mut runtime = Runtime::new(
        "vault-a",
        Default::default(),
        keys.clone(),
        Box::new(MemoryStorage::default()),
    );
    runtime
        .register_module(
            Arc::new(VirtualFactory {
                module_id: "openledger.virtual".into(),
            }),
            &policy(),
        )
        .unwrap();
    let (session, _) = runtime.open_app("openledger.virtual").unwrap();
    (runtime, keys, session)
}

fn submit_sign(runtime: &mut Runtime, session: SessionId) -> ReviewId {
    match runtime
        .submit_wire(session, Wire::LedgerApdu, vec![0x02])
        .unwrap()
    {
        RuntimeReply::Review { review_id, .. } => review_id,
        other => panic!("expected review, got {other:?}"),
    }
}

// ── 用例 ──────────────────────────────────────────────────────────────

#[test]
fn approve_signs_once_then_delivers() {
    let (mut runtime, keys, session) = setup();
    let review_id = submit_sign(&mut runtime, session);

    let reply = runtime
        .resolve_review(session, review_id, ReviewDecision::Approve)
        .unwrap();
    match reply {
        RuntimeReply::Emit {
            payload, state, ..
        } => {
            assert_eq!(state, OperationState::Final);
            assert_eq!(payload, vec![0xAA; 64]);
        }
        other => panic!("expected emit, got {other:?}"),
    }
    assert_eq!(keys.sign_calls.lock().unwrap().len(), 1);
    // 冻结计划里的输入必须原样到达密钥服务。
    assert_eq!(keys.sign_calls.lock().unwrap()[0].input, DIGEST);
}

#[test]
fn replayed_approval_cannot_sign_twice() {
    let (mut runtime, keys, session) = setup();
    let review_id = submit_sign(&mut runtime, session);
    runtime
        .resolve_review(session, review_id, ReviewDecision::Approve)
        .unwrap();

    let error = runtime
        .resolve_review(session, review_id, ReviewDecision::Approve)
        .unwrap_err();
    assert!(
        matches!(error, RuntimeError::Approval(_)),
        "unexpected error: {error}"
    );
    assert_eq!(keys.sign_calls.lock().unwrap().len(), 1);
}

#[test]
fn lock_invalidates_pending_approval() {
    let (mut runtime, keys, session) = setup();
    let review_id = submit_sign(&mut runtime, session);

    runtime.lock();
    let error = runtime
        .resolve_review(session, review_id, ReviewDecision::Approve)
        .unwrap_err();
    assert!(
        matches!(error, RuntimeError::Approval(_)),
        "unexpected error: {error}"
    );
    assert_eq!(keys.sign_calls.lock().unwrap().len(), 0);
}

#[test]
fn expired_review_cannot_sign() {
    let (mut runtime, keys, session) = setup();
    let review_id = submit_sign(&mut runtime, session);

    runtime.expire_review(review_id).unwrap();
    let error = runtime
        .resolve_review(session, review_id, ReviewDecision::Approve)
        .unwrap_err();
    assert!(
        matches!(error, RuntimeError::Approval(_)),
        "unexpected error: {error}"
    );
    assert_eq!(keys.sign_calls.lock().unwrap().len(), 0);
}

#[test]
fn pending_review_blocks_a_second_request() {
    let (mut runtime, _keys, session) = setup();
    let _review_id = submit_sign(&mut runtime, session);

    let error = runtime
        .submit_wire(session, Wire::LedgerApdu, vec![0x02])
        .unwrap_err();
    assert!(matches!(error, RuntimeError::Busy), "unexpected: {error}");
}

#[test]
fn overreaching_derivation_path_is_denied_without_key_access() {
    let (mut runtime, keys, session) = setup();
    let reply = runtime
        .submit_wire(session, Wire::LedgerApdu, vec![0x03])
        .unwrap();
    match reply {
        RuntimeReply::Emit { payload, .. } => assert_eq!(payload, b"denied".to_vec()),
        other => panic!("expected emit, got {other:?}"),
    }
    // 门控发生在密钥服务之前。
    assert!(keys.public_key_calls.lock().unwrap().is_empty());
}

#[test]
fn opaque_review_cannot_be_signed() {
    let (mut runtime, keys, session) = setup();
    let error = runtime
        .submit_wire(session, Wire::LedgerApdu, vec![0x06])
        .unwrap_err();
    assert!(
        matches!(error, RuntimeError::CapabilityDenied(_)),
        "unexpected: {error}"
    );
    assert_eq!(keys.sign_calls.lock().unwrap().len(), 0);
}

#[test]
fn address_confirmation_approves_without_signature() {
    let (mut runtime, keys, session) = setup();
    let review_id = match runtime
        .submit_wire(session, Wire::LedgerApdu, vec![0x08])
        .unwrap()
    {
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
    runtime
        .resolve_review(session, review_id, ReviewDecision::Approve)
        .unwrap();
    assert_eq!(keys.sign_calls.lock().unwrap().len(), 0);
}

#[test]
fn multi_operation_plan_runs_in_frozen_order() {
    let (mut runtime, keys, session) = setup();
    let review_id = match runtime
        .submit_wire(session, Wire::LedgerApdu, vec![0x07])
        .unwrap()
    {
        RuntimeReply::Review { review_id, .. } => review_id,
        other => panic!("expected review, got {other:?}"),
    };
    runtime
        .resolve_review(session, review_id, ReviewDecision::Approve)
        .unwrap();
    let calls = keys.sign_calls.lock().unwrap();
    assert_eq!(
        calls.iter().map(|op| op.operation_id).collect::<Vec<_>>(),
        vec![1, 2]
    );
}

#[test]
fn storage_is_namespaced_per_module_and_vault() {
    let keys = Arc::new(RecordingKeys::default());
    let mut runtime = Runtime::new(
        "vault-a",
        Default::default(),
        keys,
        Box::new(MemoryStorage::default()),
    );
    for id in ["openledger.alpha", "openledger.beta"] {
        runtime
            .register_module(Arc::new(VirtualFactory { module_id: id.into() }), &policy())
            .unwrap();
    }
    let (alpha, _) = runtime.open_app("openledger.alpha").unwrap();
    let (beta, _) = runtime.open_app("openledger.beta").unwrap();

    // alpha 写入并读回。
    match runtime
        .submit_wire(alpha, Wire::LedgerApdu, vec![0x04])
        .unwrap()
    {
        RuntimeReply::Emit { payload, .. } => assert_eq!(payload, b"v1".to_vec()),
        other => panic!("expected emit, got {other:?}"),
    }
    runtime
        .delivery_result(alpha, 1, DeliveryAck::Acknowledged)
        .unwrap();

    // beta 读同一个逻辑键：必须为空。
    match runtime
        .submit_wire(beta, Wire::LedgerApdu, vec![0x05])
        .unwrap()
    {
        RuntimeReply::Emit { payload, .. } => assert!(payload.is_empty()),
        other => panic!("expected emit, got {other:?}"),
    }
    runtime
        .delivery_result(beta, 1, DeliveryAck::Acknowledged)
        .unwrap();

    // 换金库后，同一个模块也读不到旧金库的数据。
    runtime.switch_vault("vault-b");
    let (alpha_b, _) = runtime.open_app("openledger.alpha").unwrap();
    match runtime
        .submit_wire(alpha_b, Wire::LedgerApdu, vec![0x05])
        .unwrap()
    {
        RuntimeReply::Emit { payload, .. } => assert!(payload.is_empty()),
        other => panic!("expected emit, got {other:?}"),
    }
}

#[test]
fn delivery_failure_does_not_re_sign() {
    let (mut runtime, keys, session) = setup();
    let review_id = submit_sign(&mut runtime, session);
    let exchange = match runtime
        .resolve_review(session, review_id, ReviewDecision::Approve)
        .unwrap()
    {
        RuntimeReply::Emit { exchange_id, .. } => exchange_id,
        other => panic!("expected emit, got {other:?}"),
    };
    assert_eq!(keys.sign_calls.lock().unwrap().len(), 1);

    let error = runtime
        .delivery_result(session, exchange, DeliveryAck::Failed("ble write".into()))
        .unwrap_err();
    assert!(matches!(error, RuntimeError::App(_)), "unexpected: {error}");
    // 失败不重签。
    assert_eq!(keys.sign_calls.lock().unwrap().len(), 1);
}

#[test]
fn oversized_wire_is_rejected_before_the_module_sees_it() {
    let (mut runtime, _keys, session) = setup();
    let error = runtime
        .submit_wire(session, Wire::LedgerApdu, vec![0x02; 8192])
        .unwrap_err();
    assert!(
        matches!(error, RuntimeError::BudgetExceeded("wire payload")),
        "unexpected: {error}"
    );
}

#[test]
fn derivation_rule_rejects_wrong_shape() {
    let rule = DerivationRule {
        derivation_scheme: DerivationScheme::Bip32Secp256k1,
        curve: Curve::Secp256k1,
        depth: 5,
        hardened_positions: vec![0, 1, 2],
        max_index: 100,
    };
    assert!(rule.allows(&PATH_ETH));
    // 少了硬化位。
    assert!(!rule.allows(&[44, 60, 0, 0, 0]));
    // 索引超限。
    assert!(!rule.allows(&[0x8000_002c, 0x8000_003c, 0x8000_0000, 0, 101]));
    // 深度不符。
    assert!(!rule.allows(&[0x8000_002c, 0x8000_003c, 0x8000_0000]));
}

#[test]
fn binding_digest_covers_review_content() {
    use chain_app_runtime::{binding_digest, BindingInputs};

    let base = VirtualModule::transaction_document(ParseStatus::Complete);
    let mut changed = base.clone();
    changed.sections[0].fields[0].value = FieldValue::Amount {
        raw: "2000".into(),
        decimals: 18,
        asset: "ETH".into(),
        ticker: Some("ETH".into()),
    };
    let plan = VirtualModule::sign_plan(vec![VirtualModule::op(1)]);
    let request = ReviewRequest {
        document: base,
        action: ReviewAction::Sign(plan.clone()),
    };
    let changed_request = ReviewRequest {
        document: changed,
        action: ReviewAction::Sign(plan),
    };
    let digest_a = binding_digest(&BindingInputs {
        module_id: "openledger.virtual",
        module_version: "0.0.1",
        epoch: 1,
        vault: "vault-a",
        wire: Wire::LedgerApdu,
        request: &request,
    });
    let digest_b = binding_digest(&BindingInputs {
        module_id: "openledger.virtual",
        module_version: "0.0.1",
        epoch: 1,
        vault: "vault-a",
        wire: Wire::LedgerApdu,
        request: &changed_request,
    });
    assert_ne!(digest_a, digest_b);
}

#[test]
fn switch_vault_drops_sessions_and_approvals() {
    let keys = Arc::new(RecordingKeys::default());
    let mut runtime = Runtime::new(
        "vault-a",
        Default::default(),
        keys.clone(),
        Box::new(MemoryStorage::default()),
    );
    runtime
        .register_module(
            Arc::new(VirtualFactory {
                module_id: "openledger.virtual".into(),
            }),
            &policy(),
        )
        .unwrap();
    let (session, _) = runtime.open_app("openledger.virtual").unwrap();
    let review_id = submit_sign(&mut runtime, session);
    runtime.switch_vault("vault-b");
    let error = runtime
        .resolve_review(session, review_id, ReviewDecision::Approve)
        .unwrap_err();
    assert!(
        matches!(error, RuntimeError::UnknownSession),
        "unexpected: {error}"
    );
    assert_eq!(keys.sign_calls.lock().unwrap().len(), 0);
    // 旧金库的待批准请求不再计数。
    assert_eq!(runtime.pending_reviews(), 0);
}
