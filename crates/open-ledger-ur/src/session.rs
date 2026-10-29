//! 一次扫码会话：收帧、去重、完成判定与超时。

use std::collections::HashSet;
use std::time::{Duration, Instant};

use bc_ur::prelude::*;
use open_ledger_biz::errors::{ChainError, Result};

/// 会话存活窗口。Keystone 主机通常每 2~3 秒重播一轮，60 秒足够扫完，
/// 超过则作废，避免旧请求被重放（contract I15）。
pub const SESSION_TIMEOUT: Duration = Duration::from_secs(60);
/// 帧数上限：正常请求远小于此值，超过即视为恶意或损坏。
pub const MAX_FRAMES: usize = 256;
/// 解出的 CBOR 上限。一期只收 ETH 交易请求，16 KiB 绰绰有余。
pub const MAX_BYTES: usize = 16 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PartStatus {
    /// 已收下，还缺帧。
    Pending,
    /// 本帧此前已收到过，未计入进度。
    Duplicate,
    /// 会话完成，可以取结果。
    Complete,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ReceiveState {
    pub status: PartStatus,
    /// 已收到的**不重复**帧数。
    pub received: usize,
    /// 主机声明的总帧数（fountain 编码可能提前完成，故仅用于展示）。
    pub total: usize,
}

pub struct UrSession {
    decoder: MultipartDecoder,
    seen: HashSet<String>,
    received: usize,
    total: usize,
    complete: Option<(String, Vec<u8>)>,
    deadline: Instant,
}

impl UrSession {
    pub fn new() -> Self {
        Self::with_timeout(SESSION_TIMEOUT)
    }

    pub fn with_timeout(timeout: Duration) -> Self {
        Self {
            decoder: MultipartDecoder::new(),
            seen: HashSet::new(),
            received: 0,
            total: 0,
            complete: None,
            deadline: Instant::now() + timeout,
        }
    }

    /// 收一帧；大小写不敏感，重复帧只报 `Duplicate` 不报错。
    pub fn receive(&mut self, part: &str) -> Result<ReceiveState> {
        self.check_deadline()?;
        let normalized = part.trim().to_lowercase();
        if !normalized.starts_with("ur:") {
            return Err(ChainError::ParseError("not a ur: string".into()));
        }

        if self.complete.is_some() {
            return Ok(ReceiveState {
                status: PartStatus::Duplicate,
                received: self.received,
                total: self.total,
            });
        }

        if !self.seen.insert(normalized.clone()) {
            return Ok(ReceiveState {
                status: PartStatus::Duplicate,
                received: self.received,
                total: self.total,
            });
        }
        if self.seen.len() > MAX_FRAMES {
            return Err(ChainError::ParseError(format!(
                "too many frames (>{MAX_FRAMES})"
            )));
        }

        match multipart_total(&normalized) {
            Some(total) => {
                if total == 0 || total as usize > MAX_FRAMES {
                    return Err(ChainError::ParseError(format!(
                        "invalid frame count {total}"
                    )));
                }
                self.total = total as usize;
                self.decoder
                    .receive(&normalized)
                    .map_err(|e| ChainError::ParseError(format!("UR frame: {e}")))?;
                self.received += 1;
                if self.decoder.is_complete() {
                    let message = self
                        .decoder
                        .message()
                        .map_err(|e| ChainError::ParseError(format!("UR message: {e}")))?
                        .ok_or_else(|| {
                            ChainError::ParseError("complete session without message".into())
                        })?;
                    self.finish(message.ur_type_str(), message.cbor().to_cbor_data())?;
                    return Ok(self.state(PartStatus::Complete));
                }
                Ok(self.state(PartStatus::Pending))
            }
            None => {
                let ur = UR::from_ur_string(normalized)
                    .map_err(|e| ChainError::ParseError(format!("UR string: {e}")))?;
                self.received = 1;
                self.total = 1;
                self.finish(ur.ur_type_str(), ur.cbor().to_cbor_data())?;
                Ok(self.state(PartStatus::Complete))
            }
        }
    }

    /// 完成后的 `(ur_type, cbor)`；未完成或超时为 `None`。
    pub fn result(&self) -> Option<(&str, &[u8])> {
        self.complete
            .as_ref()
            .map(|(ur_type, cbor)| (ur_type.as_str(), cbor.as_slice()))
    }

    pub fn is_expired(&self) -> bool {
        Instant::now() >= self.deadline
    }

    fn check_deadline(&self) -> Result<()> {
        if self.is_expired() {
            return Err(ChainError::ParseError("ur session expired".into()));
        }
        Ok(())
    }

    fn finish(&mut self, ur_type: &str, cbor: Vec<u8>) -> Result<()> {
        if cbor.len() > MAX_BYTES {
            return Err(ChainError::ParseError(format!(
                "payload too large ({} bytes)",
                cbor.len()
            )));
        }
        self.complete = Some((ur_type.to_string(), cbor));
        Ok(())
    }

    fn state(&self, status: PartStatus) -> ReceiveState {
        ReceiveState {
            status,
            received: self.received,
            total: self.total,
        }
    }
}

impl Default for UrSession {
    fn default() -> Self {
        Self::new()
    }
}

/// `ur:<type>/<seq>-<total>/<payload>` → `Some(total)`；单帧返回 `None`。
fn multipart_total(part: &str) -> Option<u16> {
    let rest = part.strip_prefix("ur:")?;
    let (_, tail) = rest.split_once('/')?;
    let (indices, _) = tail.rsplit_once('/')?;
    let (seq, total) = indices.split_once('-')?;
    seq.parse::<u16>().ok()?;
    total.parse::<u16>().ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ur::encode_frames;

    fn frames(fragment_len: usize) -> Vec<String> {
        // {1: 42, 2: "hello"} — enough bytes to force more than one frame.
        let cbor = [
            0xa2, 0x01, 0x18, 0x2a, 0x02, 0x45, b'h', b'e', b'l', b'l', b'o',
        ];
        encode_frames("eth-sign-request", &cbor, fragment_len).unwrap()
    }

    #[test]
    fn single_frame_completes_immediately() {
        let single = frames(0);
        let mut session = UrSession::new();
        let state = session.receive(&single[0]).unwrap();
        assert_eq!(state.status, PartStatus::Complete);
        let (ur_type, cbor) = session.result().unwrap();
        assert_eq!(ur_type, "eth-sign-request");
        assert_eq!(cbor.len(), 11);
    }

    #[test]
    fn multipart_out_of_order_and_duplicates() {
        let parts = frames(4);
        assert!(parts.len() > 1);
        let mut session = UrSession::new();
        let mut last = ReceiveState {
            status: PartStatus::Pending,
            received: 0,
            total: 0,
        };
        let mut order: Vec<&String> = parts.iter().rev().collect();
        order.extend(parts.iter()); // 第二轮全是重复帧
        for part in order {
            last = session.receive(part).unwrap();
            if last.status == PartStatus::Complete {
                break;
            }
        }
        assert_eq!(last.status, PartStatus::Complete);
        assert!(session.result().is_some());
    }

    #[test]
    fn duplicate_before_complete_is_reported() {
        let parts = frames(4);
        let mut session = UrSession::new();
        session.receive(&parts[0]).unwrap();
        let state = session.receive(&parts[0].to_uppercase()).unwrap();
        assert_eq!(state.status, PartStatus::Duplicate);
        assert_eq!(state.received, 1);
    }

    #[test]
    fn rejects_garbage_and_oversized_frame_count() {
        let mut session = UrSession::new();
        assert!(session.receive("hello").is_err());
        assert!(session.receive("ur:eth-sign-request/1-9999/aeaeaeae").is_err());
    }

    #[test]
    fn expires_after_timeout() {
        let parts = frames(0);
        let mut session = UrSession::with_timeout(Duration::ZERO);
        assert!(session.is_expired());
        assert!(session.receive(&parts[0]).is_err());
    }
}
