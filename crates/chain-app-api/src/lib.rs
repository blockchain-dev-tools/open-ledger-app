//! 链 App 与宿主之间的接口层。
//!
//! 设计约束（见 `decisions/D-016-chain-app-boundary.md`）：
//! - 只传拥有所有权的数据、枚举与不透明 ID；
//! - 不传 Dart 对象、原生回调指针或宿主内存引用；
//! - 模块不接收 seed / 私钥，签名必须经过宿主冻结审批。

pub mod app;
pub mod error;
pub mod event;
pub mod host;
pub mod manifest;
pub mod review;
pub mod sign;
pub mod wire;

pub use app::{ChainApp, ModuleFactory, SessionConfig};
pub use error::{AppError, HostError};
pub use event::{
    CancelReason, DeliveryAck, Effect, Event, ExchangeId, FinishStatus, LocalCommand,
    OperationState, RequestId, ReviewId, ReviewOutcome, ServiceId, ServiceResult, SessionId,
    StorageOp,
};
pub use host::{KeyService, ServiceCall, ServiceKind, SignAuthorization, StorageScope, StorageService};
pub use manifest::{
    AccountProfile, AppDescriptor, CapabilitySet, DerivationRule, ProtocolProfile, Wire,
    API_VERSION, HARDENED,
};
pub use review::{
    FeeKind, Field, FieldValue, NetworkId, OperationKind, ParseStatus, ReviewAction,
    ReviewDocument, ReviewRequest, ReviewSection, Risk, RiskLevel, RiskSource,
};
pub use sign::{
    Curve, DerivationScheme, EcdhRequest, KeyOutput, PublicKey, PublicKeyRequest, SignOperation,
    SignPlan, SignScheme, Signature,
};
