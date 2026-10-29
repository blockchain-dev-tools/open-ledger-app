//! 宿主审核策略与模块实现之间的错误类型。

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error, serde::Serialize, serde::Deserialize)]
pub enum AppError {
    /// 事件与当前状态不匹配（例如错误的 service_id）。
    #[error("event rejected: {0}")]
    InvalidEvent(String),
    /// 模块无法处理该输入。
    #[error("bad request: {0}")]
    BadRequest(String),
    #[error("module failure: {0}")]
    Internal(String),
}

/// 宿主服务（密钥、存储）的失败。模块只看到原因文本，不看到宿主内部状态。
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum HostError {
    #[error("denied: {0}")]
    Denied(String),
    #[error("unavailable: {0}")]
    Unavailable(String),
    #[error("storage: {0}")]
    Storage(String),
}
