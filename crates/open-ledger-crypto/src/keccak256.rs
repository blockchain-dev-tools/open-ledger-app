//! Keccak-256 纯哈希函数（SHA-3 标准）。
//!
//! 用于 ETH 地址、Tron 地址、Enigma 熵推导。

use sha3::{Digest, Keccak256};

/// 计算 keccak256 哈希。
///
/// 输入 bytes，输出 32 bytes。
pub fn hash(data: &[u8]) -> [u8; 32] {
    let mut hasher = Keccak256::new();
    hasher.update(data);
    hasher.finalize().into()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn known_hash() {
        let result = hash(b"hello");
        let hex_str = hex::encode(result);
        assert_eq!(hex_str.len(), 64, "hex output must be 64 chars for 32 bytes");
        assert_eq!(
            hex_str,
            "1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8"
        );
    }

    #[test]
    fn deterministic() {
        let a = hash(b"test");
        let b = hash(b"test");
        assert_eq!(a, b);
    }

    #[test]
    fn different_inputs() {
        let a = hash(b"hello");
        let b = hash(b"world");
        assert_ne!(a, b);
    }

    #[test]
    fn empty_input() {
        let result = hash(b"");
        assert_eq!(
            hex::encode(result),
            "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"
        );
    }
}
