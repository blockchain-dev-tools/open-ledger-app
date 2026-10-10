//! RLP 解码工具函数。
//!
//! 包含从裸 RLP 数据读取字段的辅助函数。
//! 不包含链特定的语义（如 ERC-20 解码、chainId 提取等）。

/// 将 RLP 整数字段转换为十进制字符串。
pub fn rlp_val_uint(item: &rlp::Rlp) -> String {
    let bytes = match item.data() {
        Ok(b) => b,
        Err(_) => return "0".to_string(),
    };
    bytes_to_decimal(bytes)
}

/// 将 RLP 地址字段转换为 0x-前缀 hex 字符串。
pub fn rlp_addr(item: &rlp::Rlp) -> String {
    let bytes = match item.data() {
        Ok(b) => b,
        Err(_) => return "0x0000000000000000000000000000000000000000".into(),
    };
    if bytes.is_empty() {
        return "0x0000000000000000000000000000000000000000".into();
    }
    format!("0x{}", hex::encode(bytes))
}

/// 大端 bytes → 十进制字符串。
///
/// 用于将 EVM 中的 uint256（32 bytes big-endian）转换为人类可读的数字。
pub fn bytes_to_decimal(bytes: &[u8]) -> String {
    if bytes.is_empty() {
        return "0".to_string();
    }
    let start = bytes.iter().position(|&b| b != 0).unwrap_or(bytes.len());
    if start == bytes.len() {
        return "0".to_string();
    }
    let mut current: Vec<u8> = bytes[start..].to_vec();
    let mut decimal = String::new();
    while !current.is_empty() && !current.iter().all(|&b| b == 0) {
        let mut remainder: u16 = 0;
        let mut next = Vec::new();
        for &b in &current {
            let value = (remainder << 8) | b as u16;
            let q = value / 10;
            remainder = value % 10;
            if !next.is_empty() || q != 0 {
                next.push(q as u8);
            }
        }
        decimal.push(char::from(b'0' + remainder as u8));
        current = next;
    }
    if decimal.is_empty() { "0".to_string() } else { decimal.chars().rev().collect() }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bytes_to_decimal_works() {
        assert_eq!(bytes_to_decimal(&[]), "0");
        assert_eq!(bytes_to_decimal(&[10]), "10");
        assert_eq!(bytes_to_decimal(&[255]), "255");
        assert_eq!(bytes_to_decimal(&hex::decode("0de0b6b3a7640000").unwrap()), "1000000000000000000");
    }

    #[test]
    fn rlp_val_uint_zero() {
        let rlp = rlp::Rlp::new(&[]);
        // empty RLP should return "0"
        let result = rlp_val_uint(&rlp);
        assert_eq!(result, "0");
    }

    #[test]
    fn rlp_addr_default() {
        let rlp = rlp::Rlp::new(&[]);
        let result = rlp_addr(&rlp);
        assert_eq!(result, "0x0000000000000000000000000000000000000000");
    }
}
