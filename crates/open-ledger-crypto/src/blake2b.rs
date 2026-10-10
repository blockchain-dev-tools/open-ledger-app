//! BLAKE2b 哈希函数。
//!
//! 用于 Sui 地址生成。使用 BLAKE2b-512，取前 32 bytes。

use blake2::Blake2b512;
use blake2::digest::{Digest, FixedOutput};

/// 计算 BLAKE2b-512 哈希，取前 32 bytes。
pub fn hash(data: &[u8]) -> [u8; 32] {
    let mut hasher = Blake2b512::new();
    hasher.update(data);
    let result = hasher.finalize_fixed();
    let mut out = [0u8; 32];
    out.copy_from_slice(&result[..32]);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deterministic() {
        let a = hash(b"test");
        let b = hash(b"test");
        assert_eq!(a, b);
    }

    #[test]
    fn known_length() {
        let result = hash(b"data");
        assert_eq!(result.len(), 32);
    }
}
