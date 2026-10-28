//! 统一审阅模型：模块产出结构化内容，宿主负责渲染与批准控件。

use crate::sign::{Curve, DerivationScheme};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ParseStatus {
    /// 全部字段可解释。
    Complete,
    /// 有字段无法解释，但主视图仍可用。
    Partial,
    /// 无法解析；宿主不得回退成「普通转账」。
    Opaque,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RiskLevel {
    Info,
    Warning,
    Critical,
}

/// 风险来源必须显式：外部服务给出的结论不能伪装成本机验证事实。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RiskSource {
    Module,
    Host,
    External { provider: String, verified: bool },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Risk {
    /// 稳定 code；宿主据此选固定样式与最低确认要求。
    pub code: String,
    pub severity: RiskLevel,
    pub parameters: Vec<(String, String)>,
    pub source: RiskSource,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FeeKind {
    Known,
    UpperBound,
    Estimated,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FieldValue {
    Address {
        value: String,
        network: String,
        role: String,
    },
    /// 整数原始值 + decimals，禁止浮点。
    Amount {
        raw: String,
        decimals: u8,
        asset: String,
        ticker: Option<String>,
    },
    Fee {
        kind: FeeKind,
        raw: Option<String>,
        decimals: u8,
        asset: String,
    },
    Text {
        value: String,
    },
    Bytes {
        value: Vec<u8>,
    },
    Structured {
        entries: Vec<Field>,
    },
    Boolean(bool),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Field {
    /// 本地化 key，模块不自带文案。
    pub label_key: String,
    pub value: FieldValue,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReviewSection {
    pub title_key: String,
    pub fields: Vec<Field>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OperationKind {
    Transaction,
    Message,
    AddressConfirmation,
    SettingsChange,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NetworkId {
    pub name: String,
    pub chain_id: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReviewDocument {
    pub operation: OperationKind,
    pub network: NetworkId,
    /// 签名账户的展示标识（地址或账户名）。
    pub account: Option<String>,
    pub sections: Vec<ReviewSection>,
    pub risks: Vec<Risk>,
    pub parse_status: ParseStatus,
}

impl ReviewDocument {
    pub fn field_count(&self) -> usize {
        fn count(fields: &[Field]) -> usize {
            fields
                .iter()
                .map(|f| match &f.value {
                    FieldValue::Structured { entries } => 1 + count(entries),
                    _ => 1,
                })
                .sum()
        }
        self.sections.iter().map(|s| count(&s.fields)).sum()
    }

    pub fn depth(&self) -> usize {
        fn walk(fields: &[Field]) -> usize {
            fields
                .iter()
                .map(|f| match &f.value {
                    FieldValue::Structured { entries } => 1 + walk(entries),
                    _ => 1,
                })
                .max()
                .unwrap_or(0)
        }
        self.sections.iter().map(|s| walk(&s.fields)).max().unwrap_or(0)
    }
}

/// 模块请求宿主执行的动作。三类动作的确认要求不同：
/// 地址确认按协议可跳过，签名必须确认，改变风险的设置必须是本机用户操作。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ReviewAction {
    DisplayAddress {
        derivation_scheme: DerivationScheme,
        curve: Curve,
        path: Vec<u32>,
    },
    ChangeSetting {
        key: String,
        value: Vec<u8>,
    },
    Sign(crate::sign::SignPlan),
}

impl ReviewAction {
    pub fn requires_signature(&self) -> bool {
        matches!(self, ReviewAction::Sign(_))
    }
}

/// 附在审批请求上的完整载荷；宿主复制并冻结，模块之后拿不到可修改引用。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReviewRequest {
    pub document: ReviewDocument,
    pub action: ReviewAction,
}
