/// 将 witness program 编码为 bech32 地址字符串。
/// `hrp` — 人类可读部分（如 `"bc"`），`program` — 20 或 32 bytes。
pub fn encode(hrp: &str, witness_version: u8, program: &[u8]) -> String {
    let parsed_hrp = bech32::Hrp::parse(hrp).expect("valid bech32 HRP");
    use bech32::{ByteIterExt, Fe32IterExt};
    let version_fe32 = match witness_version {
        0 => bech32::Fe32::Q,
        v => bech32::Fe32::from_char_unchecked(b'q' - v),
    };
    program
        .iter()
        .copied()
        .bytes_to_fes()
        .with_checksum::<bech32::Bech32>(&parsed_hrp)
        .with_witness_version(version_fe32)
        .chars()
        .collect()
}

/// 普通 bech32（非 segwit）：`hrp1<data>`，`data` 为 8-bit 字节流。
///
/// 与 [`encode`] 的区别是**不带 witness version** —— Sui 的 `suiprivkey` 是
/// 裸 bech32（`bech32::encode(hrp, data, Bech32)`），载荷首字节是签名方案标志。
pub fn encode_plain(hrp: &str, data: &[u8]) -> String {
    let parsed_hrp = bech32::Hrp::parse(hrp).expect("valid bech32 HRP");
    use bech32::{ByteIterExt, Fe32IterExt};
    data.iter()
        .copied()
        .bytes_to_fes()
        .with_checksum::<bech32::Bech32>(&parsed_hrp)
        .chars()
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn p2wpkh_42_chars() {
        let pubkey_hash = [0u8; 20];
        let addr = encode("bc", 0, &pubkey_hash);
        assert!(addr.starts_with("bc1"));
    }

    #[test]
    fn deterministic() {
        let program = [0xabu8; 20];
        let a = encode("bc", 0, &program);
        let b = encode("bc", 0, &program);
        assert_eq!(a, b);
    }
}
