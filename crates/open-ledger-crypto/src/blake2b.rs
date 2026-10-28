//! BLAKE2b 哈希函数。
//!
//! 用于 Sui 地址生成：Sui 规定 `blake2b-256(0x00 || ed25519_pubkey)`。
//! 这里使用 BLAKE2b 的 32 字节输出（`Blake2b<U32>`），不是 BLAKE2b-512
//! 再截断 —— 两者是不同的算法参数，截断 512 位摘要会得到不可互操作的地址。

use blake2::digest::consts::U32;
use blake2::digest::Digest;
use blake2::Blake2b;

/// 计算 BLAKE2b-256（32 字节输出）。
pub fn hash(data: &[u8]) -> [u8; 32] {
    let mut hasher = Blake2b::<U32>::new();
    hasher.update(data);
    hasher.finalize().into()
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

    #[test]
    fn matches_blake2b_256_vector() {
        // `blake2b-256("abc")`，与 Python `hashlib.blake2b(b"abc", digest_size=32)`
        // 以及 `b2sum -l 256` 一致。
        assert_eq!(
            hex::encode(hash(b"abc")),
            "bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319"
        );
    }
}
