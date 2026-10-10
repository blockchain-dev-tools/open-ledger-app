//! Double SHA-256。
//!
//! 用于 BTC/Tron checksum。

use sha2::{Digest, Sha256};

/// 计算 double SHA-256。
///
/// 返回 32 bytes。
pub fn hash(data: &[u8]) -> [u8; 32] {
    let first = {
        let mut hasher = Sha256::new();
        hasher.update(data);
        hasher.finalize()
    };
    let mut hasher = Sha256::new();
    hasher.update(&first);
    hasher.finalize().into()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn known_length() {
        let result = hash(b"test data");
        assert_eq!(result.len(), 32);
    }

    #[test]
    fn deterministic() {
        let a = hash(b"hello");
        let b = hash(b"hello");
        assert_eq!(a, b);
    }

    #[test]
    fn different_inputs() {
        let a = hash(b"hello");
        let b = hash(b"world");
        assert_ne!(a, b);
    }
}
