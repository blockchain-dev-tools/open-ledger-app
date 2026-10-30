//! 宿主 Runtime：注册、会话、审批、密钥门控与效果分发。

use std::collections::HashMap;
use std::sync::Arc;

use chain_app_api::manifest::{AppDescriptor, CapabilitySet, Wire};
use chain_app_api::{
    AppError, CancelReason, ChainApp, DeliveryAck, EcdhRequest, Effect, Event, ExchangeId,
    FinishStatus, KeyService, LocalCommand, ModuleFactory, OperationState, PublicKey,
    PublicKeyRequest, ReviewAction, ReviewDocument, ReviewId, ReviewOutcome, ReviewRequest,
    ServiceResult, SessionConfig, SessionId, SignAuthorization, SignOperation, StorageOp,
    StorageScope, StorageService,
};

use crate::approvals::{ApprovalCoordinator, ApprovalError, FrozenApproval};
use crate::budget::Budget;
use crate::registry::{ModuleRegistry, RegistryError};

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum RuntimeError {
    #[error(transparent)]
    Registry(#[from] RegistryError),
    #[error(transparent)]
    Approval(#[from] ApprovalError),
    #[error(transparent)]
    App(#[from] AppError),
    #[error("unknown module {0}")]
    UnknownModule(String),
    #[error("unknown session")]
    UnknownSession,
    #[error("session busy: a review or delivery is pending")]
    Busy,
    #[error("budget exceeded: {0}")]
    BudgetExceeded(&'static str),
    #[error("capability denied: {0}")]
    CapabilityDenied(String),
    #[error("no pending review for this session")]
    NoPendingReview,
    #[error("unexpected delivery result")]
    UnexpectedDelivery,
    #[error("session already finished")]
    Finished,
}

/// 宿主 UI 只能回传「批准/拒绝」，不能回传签名参数。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReviewDecision {
    Approve,
    Reject,
}

/// Runtime 对宿主的输出。审批请求带上了宿主分配的 `review_id`。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RuntimeReply {
    Emit {
        wire: Wire,
        exchange_id: ExchangeId,
        payload: Vec<u8>,
        state: OperationState,
    },
    LocalReply {
        request_id: u64,
        payload: Vec<u8>,
    },
    Review {
        review_id: ReviewId,
        document: ReviewDocument,
        action: ReviewAction,
    },
    Finished {
        status: FinishStatus,
    },
    AwaitInput,
}

struct Session {
    epoch: u64,
    module_id: String,
    module_version: String,
    storage_schema: u32,
    granted: CapabilitySet,
    app: Box<dyn ChainApp>,
    wire: Wire,
    next_exchange: ExchangeId,
    accumulated_input: usize,
    pending_review: Option<ReviewId>,
    /// 最近一次被消费的审批，用于把重复回调识别为 replay 而不是「无待批准」。
    last_consumed_review: Option<ReviewId>,
    awaiting_delivery: Option<ExchangeId>,
    finished: bool,
}

pub struct Runtime {
    vault: String,
    epoch: u64,
    budget: Budget,
    registry: ModuleRegistry,
    approvals: ApprovalCoordinator,
    sessions: HashMap<SessionId, Session>,
    next_session: SessionId,
    keys: Arc<dyn KeyService>,
    storage: Box<dyn StorageService>,
}

impl Runtime {
    pub fn new(
        vault: impl Into<String>,
        budget: Budget,
        keys: Arc<dyn KeyService>,
        storage: Box<dyn StorageService>,
    ) -> Self {
        Self {
            vault: vault.into(),
            epoch: 1,
            approvals: ApprovalCoordinator::new(1, budget.max_pending_approvals),
            budget,
            registry: ModuleRegistry::default(),
            sessions: HashMap::new(),
            next_session: 1,
            keys,
            storage,
        }
    }

    /// 注册模块。授予能力 = 描述符请求 ∩ 宿主策略。
    pub fn register_module(
        &mut self,
        factory: Arc<dyn ModuleFactory>,
        policy: &CapabilitySet,
    ) -> Result<(), RuntimeError> {
        self.registry.register(factory, policy)?;
        Ok(())
    }

    pub fn list_apps(&self) -> Vec<AppDescriptor> {
        self.registry.list()
    }

    pub fn epoch(&self) -> u64 {
        self.epoch
    }

    pub fn vault(&self) -> &str {
        &self.vault
    }

    pub fn pending_reviews(&self) -> usize {
        self.approvals.pending_count()
    }

    pub fn open_app(&mut self, module_id: &str) -> Result<(SessionId, AppDescriptor), RuntimeError> {
        let entry = self
            .registry
            .get(module_id)
            .ok_or_else(|| RuntimeError::UnknownModule(module_id.to_string()))?;
        let descriptor = entry.descriptor.clone();
        let granted = entry.granted.clone();
        let mut app = entry.create_app();
        let session_id = self.next_session;
        self.next_session += 1;
        app.open(SessionConfig {
            session_id,
            epoch: self.epoch,
            granted: granted.clone(),
            public_config: Vec::new(),
        })?;
        self.sessions.insert(
            session_id,
            Session {
                epoch: self.epoch,
                module_id: descriptor.module_id.clone(),
                module_version: descriptor.module_version.clone(),
                storage_schema: descriptor.storage_schema_version,
                granted,
                app,
                wire: descriptor
                    .protocol_profiles
                    .first()
                    .map(|p| p.wire)
                    .unwrap_or(Wire::LedgerApdu),
                next_exchange: 1,
                accumulated_input: 0,
                pending_review: None,
                last_consumed_review: None,
                awaiting_delivery: None,
                finished: false,
            },
        );
        Ok((session_id, descriptor))
    }

    pub fn submit_wire(
        &mut self,
        session_id: SessionId,
        wire: Wire,
        payload: Vec<u8>,
    ) -> Result<RuntimeReply, RuntimeError> {
        let (max_wire_payload, max_accumulated_input) = (
            self.budget.max_wire_payload,
            self.budget.max_accumulated_input,
        );
        let exchange_id = {
            let session = self.session_mut(session_id)?;
            if session.finished {
                return Err(RuntimeError::Finished);
            }
            if session.pending_review.is_some() || session.awaiting_delivery.is_some() {
                return Err(RuntimeError::Busy);
            }
            if payload.len() > max_wire_payload {
                return Err(RuntimeError::BudgetExceeded("wire payload"));
            }
            if session.accumulated_input + payload.len() > max_accumulated_input {
                return Err(RuntimeError::BudgetExceeded("accumulated input"));
            }
            session.accumulated_input += payload.len();
            session.wire = wire;
            let id = session.next_exchange;
            session.next_exchange += 1;
            id
        };
        self.pump(
            session_id,
            Event::Wire {
                exchange_id,
                wire,
                payload,
            },
        )
    }

    pub fn submit_local(
        &mut self,
        session_id: SessionId,
        request_id: u64,
        command: LocalCommand,
    ) -> Result<RuntimeReply, RuntimeError> {
        {
            let session = self.session_mut(session_id)?;
            if session.finished {
                return Err(RuntimeError::Finished);
            }
            if session.pending_review.is_some() || session.awaiting_delivery.is_some() {
                return Err(RuntimeError::Busy);
            }
        }
        self.pump(session_id, Event::Local { request_id, command })
    }

    /// 批准/拒绝后，签名在宿主内一次跑完；返回的效果就是回给外部钱包的字节。
    pub fn resolve_review(
        &mut self,
        session_id: SessionId,
        review_id: ReviewId,
        decision: ReviewDecision,
    ) -> Result<RuntimeReply, RuntimeError> {
        let (module_id, module_version, session_epoch, granted) = {
            let session = self.session_mut(session_id)?;
            if session.pending_review != Some(review_id) {
                if session.last_consumed_review == Some(review_id) {
                    return Err(RuntimeError::Approval(ApprovalError::Replay(review_id)));
                }
                return Err(RuntimeError::NoPendingReview);
            }
            (
                session.module_id.clone(),
                session.module_version.clone(),
                session.epoch,
                session.granted.clone(),
            )
        };
        let vault = self.vault.clone();
        let approval = self.approvals.consume(
            review_id,
            session_epoch,
            &vault,
            &module_id,
            &module_version,
        )?;
        {
            let session = self.session_mut(session_id)?;
            session.pending_review = None;
            session.last_consumed_review = Some(review_id);
        }
        let outcome = match decision {
            ReviewDecision::Reject => ReviewOutcome::Rejected,
            ReviewDecision::Approve => self.execute_approved(&approval, &granted),
        };
        self.pump(session_id, Event::ReviewResult { review_id, outcome })
    }

    pub fn delivery_result(
        &mut self,
        session_id: SessionId,
        exchange_id: ExchangeId,
        ack: DeliveryAck,
    ) -> Result<RuntimeReply, RuntimeError> {
        {
            let session = self.session_mut(session_id)?;
            if session.awaiting_delivery != Some(exchange_id) {
                return Err(RuntimeError::UnexpectedDelivery);
            }
            session.awaiting_delivery = None;
        }
        if let DeliveryAck::Failed(reason) = ack {
            let session = self.session_mut(session_id)?;
            session.app.close(CancelReason::Disconnected);
            session.finished = true;
            return Err(RuntimeError::App(AppError::BadRequest(format!(
                "delivery failed: {reason}"
            ))));
        }
        self.pump(session_id, Event::Delivered { exchange_id, ack })
    }

    /// 宿主侧超时：作废该审批，模块之后只能编码协议终态。
    pub fn expire_review(&mut self, review_id: ReviewId) -> Result<(), RuntimeError> {
        self.approvals.expire(review_id)?;
        Ok(())
    }

    pub fn cancel(
        &mut self,
        session_id: SessionId,
        reason: CancelReason,
    ) -> Result<RuntimeReply, RuntimeError> {
        {
            let session = self.session_mut(session_id)?;
            session.pending_review = None;
            session.awaiting_delivery = None;
        }
        self.pump(session_id, Event::Cancel { reason })
    }

    /// 锁定：旧 epoch 的所有待批准请求作废，会话关闭，但保留对象以便返回明确错误。
    pub fn lock(&mut self) {
        self.epoch += 1;
        self.approvals.invalidate_all();
        for session in self.sessions.values_mut() {
            session.app.close(CancelReason::Locked);
            session.awaiting_delivery = None;
        }
    }

    /// 切换金库：与锁定同样作废旧授权，并解除当前会话绑定。
    pub fn switch_vault(&mut self, vault: impl Into<String>) {
        self.vault = vault.into();
        self.lock();
        self.sessions.clear();
    }

    pub fn close(&mut self, session_id: SessionId, reason: CancelReason) {
        if let Some(mut session) = self.sessions.remove(&session_id) {
            session.app.close(reason);
        }
    }

    fn session_mut(&mut self, session_id: SessionId) -> Result<&mut Session, RuntimeError> {
        self.sessions
            .get_mut(&session_id)
            .ok_or(RuntimeError::UnknownSession)
    }

    fn session(&self, session_id: SessionId) -> Result<&Session, RuntimeError> {
        self.sessions
            .get(&session_id)
            .ok_or(RuntimeError::UnknownSession)
    }

    /// 每步只产出一个效果；宿主执行内部服务后以匹配 ID 的事件恢复。
    fn pump(&mut self, session_id: SessionId, first: Event) -> Result<RuntimeReply, RuntimeError> {
        let mut event = first;
        for _ in 0..self.budget.max_steps_per_call {
            let effect = self.session_mut(session_id)?.app.step(event)?;
            match effect {
                Effect::NeedPublicKey {
                    service_id,
                    request,
                } => {
                    let result = {
                        let session = self.session(session_id)?;
                        self.execute_public_key(&session.granted, &request)
                    };
                    event = Event::ServiceResult {
                        service_id,
                        result,
                    };
                }
                Effect::NeedEcdh {
                    service_id,
                    request,
                } => {
                    let result = {
                        let session = self.session(session_id)?;
                        self.execute_ecdh(&session.granted, &request)
                    };
                    event = Event::ServiceResult {
                        service_id,
                        result,
                    };
                }
                Effect::NeedStore {
                    service_id,
                    operation,
                } => {
                    let (granted, scope) = {
                        let session = self.session(session_id)?;
                        (
                            session.granted.clone(),
                            StorageScope {
                                vault: self.vault.clone(),
                                module_id: session.module_id.clone(),
                                schema: session.storage_schema,
                            },
                        )
                    };
                    let result = self.execute_storage(&granted, &scope, &operation);
                    event = Event::ServiceResult {
                        service_id,
                        result,
                    };
                }
                Effect::NeedReview { request, .. } => {
                    return self.freeze_and_ask(session_id, *request);
                }
                Effect::Emit {
                    wire,
                    exchange_id,
                    payload,
                    state,
                } => {
                    let session = self.session_mut(session_id)?;
                    session.awaiting_delivery = Some(exchange_id);
                    return Ok(RuntimeReply::Emit {
                        wire,
                        exchange_id,
                        payload,
                        state,
                    });
                }
                Effect::LocalReply {
                    request_id,
                    payload,
                } => return Ok(RuntimeReply::LocalReply { request_id, payload }),
                Effect::Finished { status } => {
                    self.session_mut(session_id)?.finished = true;
                    return Ok(RuntimeReply::Finished { status });
                }
                Effect::AwaitInput => return Ok(RuntimeReply::AwaitInput),
            }
        }
        Err(RuntimeError::BudgetExceeded("step budget"))
    }

    fn freeze_and_ask(
        &mut self,
        session_id: SessionId,
        request: ReviewRequest,
    ) -> Result<RuntimeReply, RuntimeError> {
        let (module_id, module_version, wire, granted) = {
            let session = self.session(session_id)?;
            (
                session.module_id.clone(),
                session.module_version.clone(),
                session.wire,
                session.granted.clone(),
            )
        };
        if request.document.field_count() > self.budget.max_review_fields {
            return Err(RuntimeError::BudgetExceeded("review fields"));
        }
        if request.document.depth() > self.budget.max_review_depth {
            return Err(RuntimeError::BudgetExceeded("review depth"));
        }
        if let ReviewAction::Sign(plan) = &request.action {
            if plan.operations.len() > self.budget.max_plan_operations {
                return Err(RuntimeError::BudgetExceeded("plan operations"));
            }
            if !granted.allow_signing {
                return Err(RuntimeError::CapabilityDenied("signing".into()));
            }
        }
        if request.document.parse_status == chain_app_api::ParseStatus::Opaque
            && matches!(request.action, ReviewAction::Sign(_))
        {
            // 盲签必须走统一风险策略；骨架阶段直接拒绝，不允许模块以普通提示绕过。
            return Err(RuntimeError::CapabilityDenied("opaque signing".into()));
        }
        let review_id = self.approvals.freeze(
            &module_id,
            &module_version,
            &self.vault,
            wire,
            request.clone(),
        )?;
        self.session_mut(session_id)?.pending_review = Some(review_id);
        Ok(RuntimeReply::Review {
            review_id,
            document: request.document,
            action: request.action,
        })
    }

    fn execute_public_key(
        &self,
        granted: &CapabilitySet,
        request: &PublicKeyRequest,
    ) -> ServiceResult {
        if !granted.allows_path(request.derivation_scheme, request.curve, &request.path) {
            return ServiceResult::Failed("derivation path not granted".into());
        }
        if request.include_chain_code && !granted.allow_chain_code {
            return ServiceResult::Failed("chain code not granted".into());
        }
        match self.keys.public_key(request) {
            Ok(key) => ServiceResult::PublicKey(PublicKey {
                bytes: key.bytes,
                chain_code: key.chain_code,
            }),
            Err(error) => ServiceResult::Failed(error.to_string()),
        }
    }

    fn execute_ecdh(
        &self,
        granted: &CapabilitySet,
        request: &EcdhRequest,
    ) -> ServiceResult {
        if !granted.allows_path(request.derivation_scheme, request.curve, &request.path) {
            return ServiceResult::Failed("derivation path not granted".into());
        }
        // ECDH 与签名同属私钥运算：复用 allow_signing 作为能力门。
        if !granted.allow_signing {
            return ServiceResult::Failed("ecdh not granted".into());
        }
        match self.keys.ecdh(request) {
            Ok(secret) => ServiceResult::SharedSecret(secret),
            Err(error) => ServiceResult::Failed(error.to_string()),
        }
    }

    fn execute_storage(
        &mut self,
        granted: &CapabilitySet,
        scope: &StorageScope,
        operation: &StorageOp,
    ) -> ServiceResult {
        if !granted.allow_storage {
            return ServiceResult::Failed("storage not granted".into());
        }
        let outcome = match operation {
            StorageOp::Read { key } => self.storage.read(scope, key),
            StorageOp::Write { key, value } => self
                .storage
                .write(scope, key, value.clone())
                .map(|_| None),
            StorageOp::Delete { key } => self.storage.delete(scope, key).map(|_| None),
        };
        match outcome {
            Ok(value) => ServiceResult::Storage(value),
            Err(error) => ServiceResult::Failed(error.to_string()),
        }
    }

    /// 审批已消费：按冻结计划逐条签名。任何一步失败都不自动重跑。
    fn execute_approved(
        &self,
        approval: &FrozenApproval,
        granted: &CapabilitySet,
    ) -> ReviewOutcome {
        let plan = match &approval.request.action {
            ReviewAction::Sign(plan) => plan,
            // 地址确认 / 设置变更不产生签名。
            _ => return ReviewOutcome::Approved { signatures: vec![] },
        };
        if !granted.allow_signing {
            return ReviewOutcome::Failed("signing not granted".into());
        }
        let mut signatures = Vec::with_capacity(plan.operations.len());
        for operation in &plan.operations {
            if let Err(reason) = self.authorize_operation(granted, operation) {
                return ReviewOutcome::Failed(reason);
            }
            let auth = SignAuthorization {
                review_id: approval.review_id,
                epoch: approval.epoch,
                vault: approval.vault.clone(),
                module_id: approval.module_id.clone(),
                module_version: approval.module_version.clone(),
                operation_id: operation.operation_id,
            };
            match self.keys.sign(&auth, operation) {
                Ok(signature) => signatures.push(signature),
                Err(error) => return ReviewOutcome::Failed(error.to_string()),
            }
        }
        ReviewOutcome::Approved { signatures }
    }

    fn authorize_operation(
        &self,
        granted: &CapabilitySet,
        operation: &SignOperation,
    ) -> Result<(), String> {
        if !operation.curve.matches(operation.derivation_scheme) {
            return Err("scheme/curve mismatch".into());
        }
        if !granted.allows_path(
            operation.derivation_scheme,
            operation.curve,
            &operation.path,
        ) {
            return Err("derivation path not granted".into());
        }
        match operation.scheme {
            chain_app_api::SignScheme::EcdsaPrehash { digest_len, .. } => {
                if operation.input.len() != usize::from(digest_len) {
                    return Err("digest length mismatch".into());
                }
                if operation.curve != chain_app_api::Curve::Secp256k1 {
                    return Err("ecdsa requires secp256k1".into());
                }
            }
            chain_app_api::SignScheme::Ed25519Message => {
                if operation.curve != chain_app_api::Curve::Ed25519 {
                    return Err("ed25519 scheme requires ed25519 curve".into());
                }
            }
            chain_app_api::SignScheme::SchnorrTaprootKeyPath { .. } => {
                if operation.curve != chain_app_api::Curve::Secp256k1 {
                    return Err("schnorr requires secp256k1".into());
                }
                if operation.input.len() != 32 {
                    return Err("taproot sighash must be 32 bytes".into());
                }
            }
        }
        Ok(())
    }
}
