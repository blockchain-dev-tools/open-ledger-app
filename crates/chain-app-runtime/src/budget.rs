//! 资源预算。
//!
//! 模块同进程运行，这些上限是**工程边界**，不是恶意插件隔离保证。

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Budget {
    /// 单帧输入上限。
    pub max_wire_payload: usize,
    /// 一个会话累计输入上限。
    pub max_accumulated_input: usize,
    /// 审阅文档字段数上限。
    pub max_review_fields: usize,
    /// 审阅嵌套深度上限。
    pub max_review_depth: usize,
    /// 一次批准覆盖的签名操作数上限。
    pub max_plan_operations: usize,
    /// 单次调用内允许的模块步数（防止内部死循环把调用卡死）。
    pub max_steps_per_call: usize,
    /// 同时悬挂的待批准请求上限。
    pub max_pending_approvals: usize,
}

impl Default for Budget {
    fn default() -> Self {
        Self {
            max_wire_payload: 4096,
            max_accumulated_input: 262_144,
            max_review_fields: 64,
            max_review_depth: 4,
            max_plan_operations: 8,
            max_steps_per_call: 32,
            max_pending_approvals: 8,
        }
    }
}
