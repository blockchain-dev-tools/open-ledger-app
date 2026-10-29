//! 模块实现契约。

use crate::error::AppError;
use crate::event::{CancelReason, Event, Effect, SessionId};
use crate::manifest::{AppDescriptor, CapabilitySet};

/// 会话配置。只含宿主绑定的身份、epoch、授予权限与公开配置；
/// 不含 seed、PIN 或任何金库记录。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct SessionConfig {
    pub session_id: SessionId,
    pub epoch: u64,
    pub granted: CapabilitySet,
    /// 公开配置（例如所选网络），由宿主填写并冻结。
    pub public_config: Vec<(String, String)>,
}

/// 一条链的实现。宿主只通过 `step` 推进它，从不跨越 FFI 暴露内部内存。
pub trait ChainApp: Send {
    fn open(&mut self, config: SessionConfig) -> Result<(), AppError>;
    fn step(&mut self, event: Event) -> Result<Effect, AppError>;
    fn close(&mut self, reason: CancelReason);
}

/// 注册表持有的工厂。`describe` 必须是纯函数，不依赖会话状态。
pub trait ModuleFactory: Send + Sync {
    fn describe(&self) -> AppDescriptor;
    fn create(&self) -> Box<dyn ChainApp>;
}
