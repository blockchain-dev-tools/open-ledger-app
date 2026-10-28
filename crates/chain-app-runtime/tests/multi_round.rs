//! 阶段 3 的多轮协议压力测试（离线）。
//!
//! 用一个虚拟模块模拟 Bitcoin 式交互：中断响应 → 客户端 CONTINUE →
//! 一次审批 → 逐个 yield 签名 → 每轮等 `Delivered` 才继续。
//! 重点验证 `OperationState::Collecting`、`Effect::AwaitInput` 与
//! 投递失败终止会话（不重新签名）这三条运行时契约。

use std::sync::{Arc, Mutex};

use chain_app_api::*;
use chain_app_runtime::{Budget, ReviewDecision, Runtime, RuntimeError, RuntimeReply};

const MODULE: &str = "test.multiround";

// ── 宿主服务 ──────────────────────────────────────────────────────────

struct CountingKeys {
    calls: Mutex<usize>,
}

impl CountingKeys {
    fn new() -> Self {
        Self {
            calls: Mutex::new(0),
        }
    }
}

impl KeyService for CountingKeys {
    fn public_key(&self, _request: &PublicKeyRequest) -> Result<PublicKey, HostError> {
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
        *self.calls.lock().unwrap() += 1;
        Ok(Signature {
            operation_id: operation.operation_id,
            bytes: vec![operation.operation_id as u8; 64],
            recovery_id: Some(0),
        })
    }
}

struct NoStorage;

impl StorageService for NoStorage {
    fn read(&mut self, _: &StorageScope, _: &str) -> Result<Option<Vec<u8>>, HostError> {
        Ok(None)
    }
    fn write(&mut self, _: &StorageScope, _: &str, _: Vec<u8>) -> Result<(), HostError> {
        Ok(())
    }
    fn delete(&mut self, _: &StorageScope, _: &str) -> Result<(), HostError> {
        Ok(())
    }
}

// ── 虚拟多轮模块 ──────────────────────────────────────────────────────

#[derive(PartialEq)]
enum Stage {
    Idle,
    /// 已发出中断响应，等客户端 CONTINUE。
    Interrupted,
    AwaitReview,
    /// 已批准，正逐个 yield 签名。
    Yielding,
}

struct MultiRoundModule {
    stage: Stage,
    exchange: ExchangeId,
    signatures: Vec<Signature>,
    next: usize,
}

impl MultiRoundModule {
    fn new() -> Self {
        Self {
            stage: Stage::Idle,
            exchange: 0,
            signatures: Vec::new(),
            next: 0,
        }
    }

    fn emit(&self, payload: Vec<u8>, state: OperationState) -> Effect {
        Effect::Emit {
            wire: Wire::LedgerApdu,
            exchange_id: self.exchange,
            payload,
            state,
        }
    }
}

impl ChainApp for MultiRoundModule {
    fn open(&mut self, _config: SessionConfig) -> Result<(), AppError> {
        Ok(())
    }

    fn step(&mut self, event: Event) -> Result<Effect, AppError> {
        match event {
            Event::Wire {
                exchange_id,
                ..
            } => {
                self.exchange = exchange_id;
                match self.stage {
                    Stage::Idle => {
                        self.stage = Stage::Interrupted;
                        // 中断响应：告诉客户端「继续发」。
                        Ok(self.emit(b"CONTINUE".to_vec(), OperationState::Collecting))
                    }
                    Stage::Interrupted => {
                        self.stage = Stage::AwaitReview;
                        let operations = (1..=3)
                            .map(|id| SignOperation {
                                operation_id: id,
                                derivation_scheme: DerivationScheme::Bip32Secp256k1,
                                curve: Curve::Secp256k1,
                                path: vec![0x8000_0000, 0x8000_0000, 0x8000_0000, 0, 0],
                                scheme: SignScheme::EcdsaPrehash {
                                    digest_len: 32,
                                    low_s: true,
                                },
                                input: vec![id as u8; 32],
                                public_parameters: Vec::new(),
                            })
                            .collect();
                        Ok(Effect::NeedReview {
                            service_id: 1,
                            request: Box::new(ReviewRequest {
                                document: ReviewDocument {
                                    operation: OperationKind::Transaction,
                                    network: NetworkId {
                                        name: "Test".into(),
                                        chain_id: None,
                                    },
                                    account: None,
                                    sections: vec![ReviewSection {
                                        title_key: "review.section.test".into(),
                                        fields: vec![Field {
                                            label_key: "review.field.inputs".into(),
                                            value: FieldValue::Text {
                                                value: "3".into(),
                                            },
                                        }],
                                    }],
                                    risks: vec![],
                                    parse_status: ParseStatus::Complete,
                                },
                                action: ReviewAction::Sign(SignPlan { operations }),
                            }),
                        })
                    }
                    _ => Err(AppError::InvalidEvent("busy".into())),
                }
            }
            Event::ReviewResult { outcome, .. } => match outcome {
                ReviewOutcome::Approved { signatures } => {
                    self.signatures = signatures;
                    self.next = 0;
                    self.stage = Stage::Yielding;
                    let first = self.signatures[0].bytes.clone();
                    Ok(self.emit(first, OperationState::Collecting))
                }
                ReviewOutcome::Rejected | ReviewOutcome::TimedOut | ReviewOutcome::Failed(_) => {
                    self.stage = Stage::Idle;
                    let mut payload = vec![0x69, 0x85];
                    payload.extend_from_slice(&[0x90, 0x00]);
                    Ok(self.emit(payload, OperationState::Final))
                }
            },
            Event::Delivered { .. } => {
                if self.stage == Stage::Interrupted {
                    // 中断帧已写出，但整笔操作还没结束。
                    return Ok(Effect::AwaitInput);
                }
                if self.stage == Stage::Yielding {
                    self.next += 1;
                    if self.next < self.signatures.len() {
                        let payload = self.signatures[self.next].bytes.clone();
                        return Ok(self.emit(payload, OperationState::Collecting));
                    }
                    self.stage = Stage::Idle;
                }
                Ok(Effect::Finished {
                    status: FinishStatus::Delivered,
                })
            }
            Event::Cancel { .. } => {
                self.stage = Stage::Idle;
                Ok(Effect::Finished {
                    status: FinishStatus::Cancelled,
                })
            }
            Event::ServiceResult { .. } => Err(AppError::InvalidEvent("unexpected".into())),
            Event::Local { request_id, .. } => Ok(Effect::LocalReply {
                request_id,
                payload: Vec::new(),
            }),
        }
    }

    fn close(&mut self, _reason: CancelReason) {
        self.stage = Stage::Idle;
        self.signatures.clear();
    }
}

struct MultiRoundFactory;

impl ModuleFactory for MultiRoundFactory {
    fn describe(&self) -> AppDescriptor {
        AppDescriptor {
            module_id: MODULE.into(),
            module_version: "0.1.0".into(),
            api_version: API_VERSION,
            review_schema_version: 1,
            storage_schema_version: 1,
            protocol_profiles: vec![ProtocolProfile {
                name: "test".into(),
                version: "1".into(),
                wire: Wire::LedgerApdu,
                supported: vec!["00 00 TEST".into()],
                unsupported: vec![],
                vector_sources: vec![],
            }],
            account_profiles: vec![AccountProfile {
                network: "Test".into(),
                account_type: "default".into(),
                default_path: "m/0'/0'/0'/0/0".into(),
                derivation_scheme: DerivationScheme::Bip32Secp256k1,
                curve: Curve::Secp256k1,
            }],
            requested_capabilities: CapabilitySet {
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
            },
        }
    }

    fn create(&self) -> Box<dyn ChainApp> {
        Box::new(MultiRoundModule::new())
    }
}

// ── fixture ───────────────────────────────────────────────────────────

struct Fixture {
    runtime: Runtime,
    keys: Arc<CountingKeys>,
    session: SessionId,
}

fn setup() -> Fixture {
    let keys = Arc::new(CountingKeys::new());
    let mut runtime = Runtime::new("vault", Budget::default(), keys.clone(), Box::new(NoStorage));
    runtime
        .register_module(
            Arc::new(MultiRoundFactory),
            &CapabilitySet {
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
            },
        )
        .unwrap();
    let (session, _) = runtime.open_app(MODULE).unwrap();
    Fixture {
        runtime,
        keys,
        session,
    }
}

fn wire(fixture: &mut Fixture) -> RuntimeReply {
    fixture
        .runtime
        .submit_wire(fixture.session, Wire::LedgerApdu, vec![0x00, 0x00, 0x00, 0x00])
        .unwrap()
}

fn ack(fixture: &mut Fixture, reply: &RuntimeReply) -> RuntimeReply {
    match reply {
        RuntimeReply::Emit { exchange_id, .. } => fixture
            .runtime
            .delivery_result(fixture.session, *exchange_id, DeliveryAck::Acknowledged)
            .unwrap(),
        other => panic!("expected emit, got {other:?}"),
    }
}

// ── 用例 ──────────────────────────────────────────────────────────────

#[test]
fn interrupt_then_continue_reaches_a_review() {
    let mut fixture = setup();

    let interrupted = wire(&mut fixture);
    match &interrupted {
        RuntimeReply::Emit {
            payload, state, ..
        } => {
            assert_eq!(payload, b"CONTINUE");
            assert_eq!(*state, OperationState::Collecting);
        }
        other => panic!("expected interrupt emit, got {other:?}"),
    }
    // 中断帧投递后模块回到 AwaitInput，会话不能结束。
    assert!(matches!(ack(&mut fixture, &interrupted), RuntimeReply::AwaitInput));

    let review = wire(&mut fixture);
    match review {
        RuntimeReply::Review { action, .. } => {
            assert!(matches!(action, ReviewAction::Sign(ref plan) if plan.operations.len() == 3));
        }
        other => panic!("expected review, got {other:?}"),
    }
    assert_eq!(*fixture.keys.calls.lock().unwrap(), 0, "审阅阶段不签名");
}

#[test]
fn approval_yields_one_signature_per_round() {
    let mut fixture = setup();
    let interrupted = wire(&mut fixture);
    ack(&mut fixture, &interrupted);
    let review_id = match wire(&mut fixture) {
        RuntimeReply::Review { review_id, .. } => review_id,
        other => panic!("expected review, got {other:?}"),
    };

    let mut reply = fixture
        .runtime
        .resolve_review(fixture.session, review_id, ReviewDecision::Approve)
        .unwrap();
    assert_eq!(*fixture.keys.calls.lock().unwrap(), 3, "批准时一次签完全部输入");

    let mut yielded = 0;
    loop {
        match &reply {
            RuntimeReply::Emit {
                payload, state, ..
            } => {
                assert_eq!(*state, OperationState::Collecting);
                assert_eq!(payload.len(), 64);
                yielded += 1;
            }
            RuntimeReply::Finished { .. } => break,
            other => panic!("unexpected reply {other:?}"),
        }
        reply = ack(&mut fixture, &reply);
    }
    assert_eq!(yielded, 3);
    assert_eq!(*fixture.keys.calls.lock().unwrap(), 3, "yield 不重复签名");
}

#[test]
fn delivery_failure_mid_round_stops_without_resigning() {
    let mut fixture = setup();
    let interrupted = wire(&mut fixture);
    ack(&mut fixture, &interrupted);
    let review_id = match wire(&mut fixture) {
        RuntimeReply::Review { review_id, .. } => review_id,
        other => panic!("expected review, got {other:?}"),
    };
    let first = fixture
        .runtime
        .resolve_review(fixture.session, review_id, ReviewDecision::Approve)
        .unwrap();
    let exchange = match first {
        RuntimeReply::Emit { exchange_id, .. } => exchange_id,
        other => panic!("expected emit, got {other:?}"),
    };

    let failed = fixture.runtime.delivery_result(
        fixture.session,
        exchange,
        DeliveryAck::Failed("ble link lost".into()),
    );
    assert!(failed.is_err(), "投递失败必须终止会话");

    // 会话已结束：既不能继续，也不会再签名。
    assert!(matches!(
        fixture.runtime.submit_wire(fixture.session, Wire::LedgerApdu, vec![0, 0, 0, 0]),
        Err(RuntimeError::Finished)
    ));
    assert_eq!(*fixture.keys.calls.lock().unwrap(), 3);
}

#[test]
fn review_state_rejects_new_wire_frames() {
    let mut fixture = setup();
    let interrupted = wire(&mut fixture);
    ack(&mut fixture, &interrupted);
    let _review = wire(&mut fixture);

    // 审阅未决时再来一帧：会话 busy，而不是覆盖待批准内容。
    assert!(matches!(
        fixture.runtime.submit_wire(fixture.session, Wire::LedgerApdu, vec![0, 0, 0, 0]),
        Err(RuntimeError::Busy)
    ));
}

#[test]
fn rejection_terminates_without_signing() {
    let mut fixture = setup();
    let interrupted = wire(&mut fixture);
    ack(&mut fixture, &interrupted);
    let review_id = match wire(&mut fixture) {
        RuntimeReply::Review { review_id, .. } => review_id,
        other => panic!("expected review, got {other:?}"),
    };

    let reply = fixture
        .runtime
        .resolve_review(fixture.session, review_id, ReviewDecision::Reject)
        .unwrap();
    match reply {
        RuntimeReply::Emit { payload, .. } => {
            assert_eq!(&payload[..2], &[0x69, 0x85]);
        }
        other => panic!("expected emit, got {other:?}"),
    }
    assert_eq!(*fixture.keys.calls.lock().unwrap(), 0);
}
