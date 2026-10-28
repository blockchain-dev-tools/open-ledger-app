//! 模块注册表。注册时把描述符请求的能力与宿主策略求交；描述符不能自行扩权。

use std::sync::Arc;

use chain_app_api::manifest::{AppDescriptor, CapabilitySet, API_VERSION};
use chain_app_api::ModuleFactory;

use crate::digest::Digest;

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum RegistryError {
    #[error("module {0} already registered")]
    Duplicate(String),
    #[error("module {module} requires api {required}, host provides {host}")]
    ApiVersion {
        module: String,
        required: u32,
        host: u32,
    },
    #[error("module {0} declares no protocol profile")]
    NoProtocolProfile(String),
    #[error("module {0} declares no account profile")]
    NoAccountProfile(String),
}

pub struct ModuleEntry {
    pub descriptor: AppDescriptor,
    /// 实际授予的能力 = 请求 ∩ 宿主策略。
    pub granted: CapabilitySet,
    /// 模块的静态指纹，便于审批绑定与版本回退限制。
    pub fingerprint: Digest,
    factory: Arc<dyn ModuleFactory>,
}

impl ModuleEntry {
    pub fn create_app(&self) -> Box<dyn chain_app_api::ChainApp> {
        self.factory.create()
    }
}

#[derive(Default)]
pub struct ModuleRegistry {
    entries: Vec<ModuleEntry>,
}

impl ModuleRegistry {
    pub fn register(
        &mut self,
        factory: Arc<dyn ModuleFactory>,
        policy: &CapabilitySet,
    ) -> Result<(), RegistryError> {
        let descriptor = factory.describe();
        if self
            .entries
            .iter()
            .any(|entry| entry.descriptor.module_id == descriptor.module_id)
        {
            return Err(RegistryError::Duplicate(descriptor.module_id));
        }
        if descriptor.api_version != API_VERSION {
            return Err(RegistryError::ApiVersion {
                module: descriptor.module_id,
                required: descriptor.api_version,
                host: API_VERSION,
            });
        }
        if descriptor.protocol_profiles.is_empty() {
            return Err(RegistryError::NoProtocolProfile(descriptor.module_id));
        }
        if descriptor.account_profiles.is_empty() {
            return Err(RegistryError::NoAccountProfile(descriptor.module_id));
        }
        let granted = descriptor.requested_capabilities.intersect(policy);
        let fingerprint = crate::digest::descriptor_digest(&descriptor);
        self.entries.push(ModuleEntry {
            descriptor,
            granted,
            fingerprint,
            factory,
        });
        Ok(())
    }

    pub fn list(&self) -> Vec<AppDescriptor> {
        self.entries
            .iter()
            .map(|entry| entry.descriptor.clone())
            .collect()
    }

    pub fn get(&self, module_id: &str) -> Option<&ModuleEntry> {
        self.entries
            .iter()
            .find(|entry| entry.descriptor.module_id == module_id)
    }
}
