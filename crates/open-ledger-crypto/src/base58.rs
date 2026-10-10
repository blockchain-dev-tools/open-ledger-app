//! base58 编码（带 checksum）。
//!
//! 用于 SOL 地址（裸 base58）和 Tron 地址（base58check）。

/// 裸 base58 编码。
pub fn encode(data: &[u8]) -> String {
    bs58::encode(data).into_string()
}

/// base58check 编码：data || SHA256d(data)[:4]。
pub fn encode_check(data: &[u8]) -> String {
    let checksum_full = crate::sha256d::hash(data);
    let checksum = &checksum_full[..4];
    let mut full = Vec::with_capacity(data.len() + 4);
    full.extend_from_slice(data);
    full.extend_from_slice(checksum);
    bs58::encode(&full).into_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encode_empty_produces_empty_string() {
        let result = encode(b"");
        assert_eq!(result, "");
    }

    #[test]
    fn encode_deterministic() {
        let a = encode(b"hello");
        let b = encode(b"hello");
        assert_eq!(a, b);
    }

    #[test]
    fn encode_check_25_bytes() {
        // Tron 地址: 0x41 prefix + 20 bytes = 21, + 4 checksum = 25
        let data = [0x41u8; 21];
        let result = encode_check(&data);
        assert_eq!(result.len(), 34); // base58 25 bytes → 34 chars
    }
}
