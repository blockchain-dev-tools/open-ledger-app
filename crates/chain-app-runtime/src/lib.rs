//! 宿主 Runtime：模块注册、会话、审批与密钥门控。

pub mod approvals;
pub mod budget;
pub mod digest;
pub mod registry;
pub mod runtime;

pub use approvals::{ApprovalError, FrozenApproval};
pub use budget::Budget;
pub use digest::{binding_digest, descriptor_digest, Digest, BindingInputs};
pub use registry::{ModuleEntry, ModuleRegistry, RegistryError};
pub use runtime::{ReviewDecision, Runtime, RuntimeError, RuntimeReply};
