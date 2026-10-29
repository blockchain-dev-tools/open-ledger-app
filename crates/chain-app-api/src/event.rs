//! 事件与效果：模块与宿主之间唯一的两个方向。
//!
//! 每一步只产出一个效果，宿主执行后以匹配 ID 的事件恢复。
//! 不传回调指针、Dart 对象或宿主内存引用。

use crate::manifest::Wire;
use crate::review::ReviewRequest;
use crate::sign::{PublicKey, PublicKeyRequest, Signature};

pub type SessionId = u64;
pub type ExchangeId = u64;
pub type RequestId = u64;
pub type ServiceId = u64;
pub type ReviewId = u64;

/// 本机账户页面发起的请求。与 APDU 共享地址编码、路径校验与密钥请求逻辑。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum LocalCommand {
    AccountProfiles,
    DeriveAccount {
        account_profile_index: u16,
        address_index: u32,
    },
    SettingsRead {
        key: String,
    },
    SettingsChange {
        key: String,
        value: Vec<u8>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum StorageOp {
    Read { key: String },
    Write { key: String, value: Vec<u8> },
    Delete { key: String },
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum ServiceResult {
    PublicKey(PublicKey),
    Storage(Option<Vec<u8>>),
    /// ECDH 共享点（未压缩，65 字节）。
    SharedSecret(Vec<u8>),
    Failed(String),
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum ReviewOutcome {
    Approved { signatures: Vec<Signature> },
    Rejected,
    TimedOut,
    Failed(String),
}

/// 投递结果。UR/QR 只能给到「已显示」，不能记成「已交付」。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum DeliveryAck {
    Acknowledged,
    BestEffort,
    Failed(String),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum CancelReason {
    UserCancelled,
    Locked,
    Disconnected,
    Timeout,
    HostShutdown,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum Event {
    /// 外部钱包来的一帧（完整 APDU 或一条 UR 请求）。
    Wire {
        exchange_id: ExchangeId,
        wire: Wire,
        payload: Vec<u8>,
    },
    Local {
        request_id: RequestId,
        command: LocalCommand,
    },
    ServiceResult {
        service_id: ServiceId,
        result: ServiceResult,
    },
    ReviewResult {
        review_id: ReviewId,
        outcome: ReviewOutcome,
    },
    Delivered {
        exchange_id: ExchangeId,
        ack: DeliveryAck,
    },
    Cancel {
        reason: CancelReason,
    },
}

/// 一轮回复的状态。`Reply` 只结束一轮，不代表整笔操作完成。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum OperationState {
    /// 还要继续收集或等待客户端续传。
    Collecting,
    /// 本次操作的最后一轮响应。
    Final,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum FinishStatus {
    Delivered,
    Rejected,
    Cancelled,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum Effect {
    /// 需要投递到外部钱包的字节或帧。
    Emit {
        wire: Wire,
        exchange_id: ExchangeId,
        payload: Vec<u8>,
        state: OperationState,
    },
    LocalReply {
        request_id: RequestId,
        payload: Vec<u8>,
    },
    NeedPublicKey {
        service_id: ServiceId,
        request: PublicKeyRequest,
    },
    /// 纯私钥运算（ECDH），不产生签名、不需要审批。
    NeedEcdh {
        service_id: ServiceId,
        request: crate::sign::EcdhRequest,
    },
    /// 宿主复制并冻结请求、分配 review_id；模块据此悬挂，等待 `ReviewResult`。
    NeedReview {
        service_id: ServiceId,
        request: Box<ReviewRequest>,
    },
    NeedStore {
        service_id: ServiceId,
        operation: StorageOp,
    },
    AwaitInput,
    Finished {
        status: FinishStatus,
    },
}

impl Effect {
    /// 是否已经交给调用方（而非宿主内部服务）。用于决定 step 循环是否继续。
    pub fn is_outward(&self) -> bool {
        matches!(
            self,
            Effect::Emit { .. } | Effect::LocalReply { .. } | Effect::Finished { .. } | Effect::AwaitInput
        )
    }
}
