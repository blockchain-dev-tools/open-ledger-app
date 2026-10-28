//! 审批协调：冻结、绑定、一次性消费。

use std::collections::BTreeMap;

use chain_app_api::manifest::Wire;
use chain_app_api::review::ReviewRequest;
use chain_app_api::ReviewId;

use crate::digest::{binding_digest, BindingInputs, Digest};

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum ApprovalError {
    #[error("unknown review {0}")]
    Unknown(ReviewId),
    #[error("review {0} already consumed")]
    Replay(ReviewId),
    #[error("review {0} expired")]
    Expired(ReviewId),
    #[error("review {0} bound to a different epoch/vault/module")]
    Stale(ReviewId),
    #[error("too many pending approvals")]
    TooManyPending,
}

/// 冻结后的审批。数据一旦写入不可修改；模块只持有 `review_id`。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FrozenApproval {
    pub review_id: ReviewId,
    pub epoch: u64,
    pub vault: String,
    pub module_id: String,
    pub module_version: String,
    pub wire: Wire,
    pub request: ReviewRequest,
    pub binding: Digest,
    consumed: bool,
    expired: bool,
}

pub struct ApprovalCoordinator {
    next_id: ReviewId,
    /// 当前有效 epoch；锁定/切金库时递增，使旧审批整体失效。
    epoch: u64,
    entries: BTreeMap<ReviewId, FrozenApproval>,
    max_pending: usize,
}

impl ApprovalCoordinator {
    pub fn new(epoch: u64, max_pending: usize) -> Self {
        Self {
            next_id: 1,
            epoch,
            entries: BTreeMap::new(),
            max_pending,
        }
    }

    pub fn epoch(&self) -> u64 {
        self.epoch
    }

    pub fn pending_count(&self) -> usize {
        self.entries
            .values()
            .filter(|entry| !entry.consumed && !entry.expired)
            .count()
    }

    /// 复制并冻结请求，计算绑定摘要。
    pub fn freeze(
        &mut self,
        module_id: &str,
        module_version: &str,
        vault: &str,
        wire: Wire,
        request: ReviewRequest,
    ) -> Result<ReviewId, ApprovalError> {
        if self.pending_count() >= self.max_pending {
            return Err(ApprovalError::TooManyPending);
        }
        let binding = binding_digest(&BindingInputs {
            module_id,
            module_version,
            epoch: self.epoch,
            vault,
            wire,
            request: &request,
        });
        let review_id = self.next_id;
        self.next_id += 1;
        self.entries.insert(
            review_id,
            FrozenApproval {
                review_id,
                epoch: self.epoch,
                vault: vault.to_string(),
                module_id: module_id.to_string(),
                module_version: module_version.to_string(),
                wire,
                request,
                binding,
                consumed: false,
                expired: false,
            },
        );
        Ok(review_id)
    }

    /// 原子消费。任何一项不匹配都返回错误，且不改变状态（`Replay` 除外，它就是已消费）。
    pub fn consume(
        &mut self,
        review_id: ReviewId,
        epoch: u64,
        vault: &str,
        module_id: &str,
        module_version: &str,
    ) -> Result<FrozenApproval, ApprovalError> {
        let entry = self
            .entries
            .get_mut(&review_id)
            .ok_or(ApprovalError::Unknown(review_id))?;
        if entry.consumed {
            return Err(ApprovalError::Replay(review_id));
        }
        if entry.expired {
            return Err(ApprovalError::Expired(review_id));
        }
        if entry.epoch != epoch
            || entry.epoch != self.epoch
            || entry.vault != vault
            || entry.module_id != module_id
            || entry.module_version != module_version
        {
            return Err(ApprovalError::Stale(review_id));
        }
        entry.consumed = true;
        Ok(entry.clone())
    }

    pub fn expire(&mut self, review_id: ReviewId) -> Result<(), ApprovalError> {
        let entry = self
            .entries
            .get_mut(&review_id)
            .ok_or(ApprovalError::Unknown(review_id))?;
        entry.expired = true;
        Ok(())
    }

    /// 锁定、切金库、切 App、停用模块时调用：旧 epoch 的全部待批准请求作废。
    pub fn invalidate_all(&mut self) {
        self.epoch += 1;
        for entry in self.entries.values_mut() {
            entry.expired = true;
        }
    }
}
