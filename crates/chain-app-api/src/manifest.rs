//! 模块描述符与宿主授予的能力。
//!
//! 描述符是**请求**；真正生效的是它与宿主随包审核策略的交集（由 runtime 计算）。
//! 描述符不能自行扩大权限。

use crate::sign::{Curve, DerivationScheme};

/// 当前接口版本。模块声明不兼容的 `api_version` 时宿主拒绝启用。
pub const API_VERSION: u32 = 1;

/// 硬化的索引偏移。
pub const HARDENED: u32 = 0x8000_0000;

/// 对外线协议。2.0 的 UR/QR 是新增枚举值，不是新架构。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum Wire {
    LedgerApdu,
    Ur,
}

impl Wire {
    pub fn as_str(self) -> &'static str {
        match self {
            Wire::LedgerApdu => "ledger-apdu",
            Wire::Ur => "ur",
        }
    }
}

/// 一种对外协议的兼容声明。必须写清「不支持什么」，否则无法据此判断回归。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct ProtocolProfile {
    /// 对外模拟的名称，例如 `Ethereum`。
    pub name: String,
    /// 对外模拟的版本，与模块自身版本分开。
    pub version: String,
    pub wire: Wire,
    pub supported: Vec<String>,
    pub unsupported: Vec<String>,
    /// 向量来源（仓库 + commit + 许可证），供差分测试追溯。
    pub vector_sources: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct AccountProfile {
    pub network: String,
    pub account_type: String,
    /// 默认路径模板，例如 `m/44'/60'/0'/0/0`。
    pub default_path: String,
    pub derivation_scheme: DerivationScheme,
    pub curve: Curve,
}

/// 允许的派生范围。不能只用字符串前缀验证路径。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct DerivationRule {
    pub derivation_scheme: DerivationScheme,
    pub curve: Curve,
    pub depth: u8,
    /// 必须硬化的位置下标。
    pub hardened_positions: Vec<u8>,
    /// 可变索引上限（含）。硬化位按去掉偏移后的值比较。
    pub max_index: u32,
}

impl DerivationRule {
    pub fn allows(&self, path: &[u32]) -> bool {
        if path.len() != usize::from(self.depth) || !self.curve.matches(self.derivation_scheme) {
            return false;
        }
        path.iter().enumerate().all(|(i, &component)| {
            let hardened = component >= HARDENED;
            if self.hardened_positions.contains(&(i as u8)) != hardened {
                return false;
            }
            let index = if hardened { component - HARDENED } else { component };
            index <= self.max_index
        })
    }
}

/// 模块请求的能力。宿主与其审核策略求交集后才生效。
#[derive(Debug, Clone, PartialEq, Eq, Default, serde::Serialize, serde::Deserialize)]
pub struct CapabilitySet {
    pub derivation_rules: Vec<DerivationRule>,
    pub allow_chain_code: bool,
    pub allow_signing: bool,
    pub allow_storage: bool,
}

impl CapabilitySet {
    /// 交集：与宿主策略取更严的一方。
    /// 允许集合的交 = 硬化要求取并集、可变索引上限取较小值。
    pub fn intersect(&self, policy: &CapabilitySet) -> CapabilitySet {
        let derivation_rules = self
            .derivation_rules
            .iter()
            .filter_map(|rule| {
                policy
                    .derivation_rules
                    .iter()
                    .find(|allowed| {
                        allowed.derivation_scheme == rule.derivation_scheme
                            && allowed.curve == rule.curve
                            && allowed.depth == rule.depth
                    })
                    .map(|allowed| {
                        let mut hardened_positions = rule.hardened_positions.clone();
                        for position in &allowed.hardened_positions {
                            if !hardened_positions.contains(position) {
                                hardened_positions.push(*position);
                            }
                        }
                        hardened_positions.sort_unstable();
                        DerivationRule {
                            derivation_scheme: rule.derivation_scheme,
                            curve: rule.curve,
                            depth: rule.depth,
                            hardened_positions,
                            max_index: rule.max_index.min(allowed.max_index),
                        }
                    })
            })
            .collect();
        CapabilitySet {
            derivation_rules,
            allow_chain_code: self.allow_chain_code && policy.allow_chain_code,
            allow_signing: self.allow_signing && policy.allow_signing,
            allow_storage: self.allow_storage && policy.allow_storage,
        }
    }

    pub fn allows_path(&self, scheme: DerivationScheme, curve: Curve, path: &[u32]) -> bool {
        self.derivation_rules
            .iter()
            .any(|rule| rule.derivation_scheme == scheme && rule.curve == curve && rule.allows(path))
    }
}

/// 模块清单。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct AppDescriptor {
    /// 稳定内部 ID，例如 `openledger.ethereum`；不用展示名称作存储主键。
    pub module_id: String,
    pub module_version: String,
    pub api_version: u32,
    pub review_schema_version: u32,
    pub storage_schema_version: u32,
    pub protocol_profiles: Vec<ProtocolProfile>,
    pub account_profiles: Vec<AccountProfile>,
    pub requested_capabilities: CapabilitySet,
}

impl AppDescriptor {
    pub fn profile_for(&self, wire: Wire) -> Option<&ProtocolProfile> {
        self.protocol_profiles.iter().find(|p| p.wire == wire)
    }
}
