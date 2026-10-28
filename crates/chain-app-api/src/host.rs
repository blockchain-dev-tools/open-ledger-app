//! 宿主必须提供的服务。实现位于宿主（KeyService / Vault），不进入链模块。

use crate::error::HostError;
use crate::event::{ReviewId, ServiceId};
use crate::sign::{EcdhRequest, PublicKey, PublicKeyRequest, Signature, SignOperation};

/// 存储命名空间。由宿主按「当前金库 + 模块 + schema」组装，模块不能指定其他金库。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StorageScope {
    pub vault: String,
    pub module_id: String,
    pub schema: u32,
}

impl StorageScope {
    /// 供宿主实现拼接物理键；模块提供的 key 只能是逻辑名。
    pub fn physical_key(&self, key: &str) -> String {
        format!("vault:{}|module:{}|schema:{}|{}", self.vault, self.module_id, self.schema, key)
    }
}

/// 一次已冻结、已消费的授权凭据。密钥服务可据此拒绝任何未绑定的签名请求。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SignAuthorization {
    pub review_id: ReviewId,
    pub epoch: u64,
    pub vault: String,
    pub module_id: String,
    pub module_version: String,
    pub operation_id: u32,
}

/// 私钥运算与派生。seed 只存在于此实现内部。
pub trait KeyService {
    fn public_key(&self, request: &PublicKeyRequest) -> Result<PublicKey, HostError>;

    /// 只有在宿主完成审批消费后才会被调用。实现方可再次核验 `auth`。
    fn sign(&self, auth: &SignAuthorization, operation: &SignOperation) -> Result<Signature, HostError>;

    /// ECDH 共享点。默认拒绝：宿主必须显式实现，避免模块悄悄扩大私钥能力。
    fn ecdh(&self, _request: &EcdhRequest) -> Result<Vec<u8>, HostError> {
        Err(HostError::Denied("ecdh not supported".into()))
    }
}

/// 加密、限额与迁移由宿主实现；模块只见命名空间内的键值。
pub trait StorageService {
    fn read(&mut self, scope: &StorageScope, key: &str) -> Result<Option<Vec<u8>>, HostError>;
    fn write(&mut self, scope: &StorageScope, key: &str, value: Vec<u8>) -> Result<(), HostError>;
    fn delete(&mut self, scope: &StorageScope, key: &str) -> Result<(), HostError>;
}

/// 模块请求的宿主能力标识，用于把 `ServiceResult` 路由回正确的悬挂点。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ServiceKind {
    PublicKey,
    Storage,
}

/// 宿主执行效果的记录，便于测试断言「没有发生签名」。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ServiceCall {
    pub service_id: ServiceId,
    pub kind: ServiceKind,
}
