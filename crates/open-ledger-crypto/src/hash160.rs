//! HASH-160: SHA-256 → RIPEMD-160。
//!
//! 用于 BTC P2WPKH 地址生成。

use ripemd::Ripemd160;
use sha2::{Digest, Sha256};

/// 计算 HASH-160（SHA-256 后接 RIPEMD-160）。
///
/// 返回 20 bytes。
pub fn hash(data: &[u8]) -> [u8; 20] {
    let sha = {
        let mut hasher = Sha256::new();
        hasher.update(data);
        hasher.finalize()
    };
    let mut hasher = Ripemd160::new();
    hasher.update(&sha);
    hasher.finalize().into()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn known_length() {
        let result = hash(b"test data");
        assert_eq!(result.len(), 20);
    }

    #[test]
    fn deterministic() {
        let a = hash(b"hello");
        let b = hash(b"hello");
        assert_eq!(a, b);
    }

    #[test]
    fn not_all_zeros() {
        let result = hash(b"test");
        let zero = [0u8; 20];
        assert_ne!(result, zero);
    }
}
