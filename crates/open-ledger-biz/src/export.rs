//! 导出载荷：公钥与私钥的链特定编码。
//!
//! 「导出」的唯一意义是**可被目标钱包导入**，所以私钥不能一律出 raw hex：
//! BTC 需要 WIF、Solana 需要 base58(64B keypair)、Sui 需要 bech32 `suiprivkey`。
//! 决策见 ADR-011 §3；编码规则留在 Rust（与 crypto 同源），Dart 侧只做转发。

use crate::errors::{ChainError, Result};
use open_ledger_crypto::{base58, bech32, ed25519, secp256k1};

/// 该链的**真公钥**字节。
///
/// 用于替代历史上误存私钥的 `ChainAccount.publicKey` 字段（ADR-011 §4）：
/// 此前 ETH/BTC/Tron/Sui 存的是 `hex(privkey)`，随金库 JSON 明文落盘。
pub fn public_key_for_chain(chain: &str, private_key: &[u8]) -> Result<Vec<u8>> {
    match chain {
        // 非压缩 65B：ETH 地址与 Tron 地址都由它派生
        "ethereum" | "tron" => Ok(secp256k1::public_key_bytes(private_key, false)?),
        // 压缩 33B：P2WPKH 的标准形式
        "bitcoin" => Ok(secp256k1::public_key_bytes(private_key, true)?),
        // Ed25519 32B
        "solana" | "sui" => Ok(ed25519::public_key_bytes(private_key)?),
        other => Err(unknown_chain(other)),
    }
}

/// 该链**可导入**的私钥字符串（ADR-011 §3 编码表）。
pub fn encode_private_key(chain: &str, private_key: &[u8]) -> Result<String> {
    match chain {
        "ethereum" => Ok(format!("0x{}", hex::encode(private_key))),
        "tron" => Ok(hex::encode(private_key)),
        "bitcoin" => Ok(wif_compressed_mainnet(private_key)?),
        "solana" => {
            // 标准 Solana keypair = base58(seed(32) ‖ pubkey(32))
            let pubkey = ed25519::public_key_bytes(private_key)?;
            let mut keypair = Vec::with_capacity(64);
            keypair.extend_from_slice(private_key);
            keypair.extend_from_slice(&pubkey);
            Ok(base58::encode(&keypair))
        }
        "sui" => {
            // 裸 bech32，HRP=suiprivkey，载荷 = 0x00(签名方案标志) ‖ key32
            let mut payload = Vec::with_capacity(33);
            payload.push(0x00);
            payload.extend_from_slice(private_key);
            Ok(bech32::encode_plain("suiprivkey", &payload))
        }
        other => Err(unknown_chain(other)),
    }
}

/// Bitcoin mainnet WIF（compressed）= base58check(`0x80` ‖ key32 ‖ `0x01`)。
fn wif_compressed_mainnet(private_key: &[u8]) -> Result<String> {
    if private_key.len() != 32 {
        return Err(ChainError::InvalidPrivateKey(format!(
            "secp256k1 private key must be 32 bytes, got {}",
            private_key.len()
        )));
    }
    let mut payload = Vec::with_capacity(34);
    payload.push(0x80);
    payload.extend_from_slice(private_key);
    payload.push(0x01);
    Ok(base58::encode_check(&payload))
}

fn unknown_chain(chain: &str) -> ChainError {
    ChainError::InvalidPrivateKey(format!("unknown chain '{chain}'"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn seed() -> Vec<u8> {
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        bip39::Mnemonic::parse(phrase).unwrap().to_seed("").to_vec()
    }

    fn secp_key(path: &str) -> Vec<u8> {
        crate::hdkey::derive_secp256k1_private_key(&seed(), path).unwrap()
    }

    fn ed_key(path: &str) -> Vec<u8> {
        crate::hdkey::derive_ed25519_private_key(&seed(), path).unwrap()
    }

    // ── public_key_for_chain ────────────────────────────────────────

    #[test]
    fn pubkey_lengths_per_chain() {
        assert_eq!(public_key_for_chain("ethereum", &secp_key("m/44'/60'/0'/0/0")).unwrap().len(), 65);
        assert_eq!(public_key_for_chain("tron", &secp_key("m/44'/195'/0'/0/0")).unwrap().len(), 65);
        assert_eq!(public_key_for_chain("bitcoin", &secp_key("m/84'/0'/0'/0/0")).unwrap().len(), 33);
        assert_eq!(public_key_for_chain("solana", &ed_key("m/44'/501'/0'/0'")).unwrap().len(), 32);
        assert_eq!(public_key_for_chain("sui", &ed_key("m/44'/784'/0'/0'/0'")).unwrap().len(), 32);
    }

    #[test]
    fn secp_pubkeys_carry_correct_prefix() {
        let uncompressed = public_key_for_chain("ethereum", &secp_key("m/44'/60'/0'/0/0")).unwrap();
        let compressed = public_key_for_chain("bitcoin", &secp_key("m/84'/0'/0'/0/0")).unwrap();
        assert_eq!(uncompressed[0], 0x04);
        assert!(compressed[0] == 0x02 || compressed[0] == 0x03);
    }

    #[test]
    fn pubkey_is_not_the_private_key() {
        // 回归保护：修复前该字段直接是 privkey 的 hex（ADR-011 §4）。
        let privkey = secp_key("m/44'/60'/0'/0/0");
        let pubkey = public_key_for_chain("ethereum", &privkey).unwrap();
        assert_ne!(pubkey.as_slice(), privkey.as_slice());
        assert_ne!(pubkey.len(), privkey.len()); // 65B 非压缩 vs 32B 私钥
    }

    #[test]
    fn btc_pubkey_matches_address_derivation() {
        // 压缩公钥必须与地址推导用的是同一份，否则「展示的公钥」与「地址」会脱节。
        let privkey = secp_key("m/84'/0'/0'/0/0");
        let pubkey = public_key_for_chain("bitcoin", &privkey).unwrap();
        let from_pubkey = crate::btc::p2wpkh_address(&pubkey);
        let from_seed = crate::btc::derive_address(&seed(), "m/84'/0'/0'/0/0").unwrap();
        assert_eq!(from_pubkey, from_seed);
    }

    #[test]
    fn tron_pubkey_matches_address_derivation() {
        let privkey = secp_key("m/44'/195'/0'/0/0");
        let pubkey = public_key_for_chain("tron", &privkey).unwrap();
        let from_pubkey = crate::tron::tron_address_from_pubkey(&pubkey);
        let from_seed = crate::tron::derive_address(&seed(), "m/44'/195'/0'/0/0").unwrap();
        assert_eq!(from_pubkey, from_seed);
    }

    #[test]
    fn sui_pubkey_matches_address_derivation() {
        let privkey = ed_key("m/44'/784'/0'/0'/0'");
        let pubkey = public_key_for_chain("sui", &privkey).unwrap();
        let from_pubkey = crate::sui::sui_address(&pubkey);
        let from_seed = crate::sui::derive_address(&seed(), "m/44'/784'/0'/0'/0'").unwrap();
        assert_eq!(from_pubkey, from_seed);
    }

    #[test]
    fn unknown_chain_rejected() {
        assert!(public_key_for_chain("dogecoin", &[0u8; 32]).is_err());
        assert!(encode_private_key("dogecoin", &[0u8; 32]).is_err());
    }

    // ── encode_private_key ──────────────────────────────────────────

    #[test]
    fn ethereum_is_0x_prefixed_hex() {
        let encoded = encode_private_key("ethereum", &secp_key("m/44'/60'/0'/0/0")).unwrap();
        assert!(encoded.starts_with("0x"));
        assert_eq!(encoded.len(), 66);
    }

    #[test]
    fn tron_is_bare_hex() {
        let encoded = encode_private_key("tron", &secp_key("m/44'/195'/0'/0/0")).unwrap();
        assert!(!encoded.starts_with("0x"));
        assert_eq!(encoded.len(), 64);
        assert!(encoded.chars().all(|c| c.is_ascii_hexdigit()));
    }

    #[test]
    fn bitcoin_wif_is_compressed_mainnet() {
        let encoded = encode_private_key("bitcoin", &secp_key("m/84'/0'/0'/0/0")).unwrap();
        // 压缩 mainnet WIF: 51 或 52 字符，以 K / L 开头
        assert!(encoded.len() == 51 || encoded.len() == 52, "len={}", encoded.len());
        assert!(encoded.starts_with('K') || encoded.starts_with('L'), "{encoded}");
        let decoded = bs58::decode(&encoded).into_vec().unwrap();
        assert_eq!(decoded.len(), 38); // 34 payload + 4 checksum
        assert_eq!(decoded[0], 0x80);
        assert_eq!(decoded[33], 0x01);
    }

    #[test]
    fn solana_is_base58_keypair() {
        let privkey = ed_key("m/44'/501'/0'/0'");
        let encoded = encode_private_key("solana", &privkey).unwrap();
        let decoded = bs58::decode(&encoded).into_vec().unwrap();
        assert_eq!(decoded.len(), 64);
        assert_eq!(&decoded[..32], &privkey[..]);
        // 后 32 字节必须是真公钥，且与 derive_address 用的那份一致
        let expected_pubkey = ed25519::public_key_bytes(&privkey).unwrap();
        assert_eq!(&decoded[32..], &expected_pubkey[..]);
        assert_eq!(crate::solana::derive_address(&seed(), "m/44'/501'/0'/0'").unwrap(),
                   base58::encode(&expected_pubkey));
    }

    #[test]
    fn sui_is_bech32_suiprivkey() {
        let privkey = ed_key("m/44'/784'/0'/0'/0'");
        let encoded = encode_private_key("sui", &privkey).unwrap();
        assert!(encoded.starts_with("suiprivkey1"), "{encoded}");
        // 解码后应还原 0x00(签名方案标志) ‖ key32
        // `::bech32` = 外部 crate（dev-dependency）；裸 `bech32` 是本模块顶部导入的
        // `open_ledger_crypto::bech32` 模块。
        let (hrp, data) = ::bech32::decode(&encoded).unwrap();
        assert_eq!(hrp.as_str(), "suiprivkey");
        assert_eq!(data.len(), 33);
        assert_eq!(data[0], 0x00);
        assert_eq!(&data[1..], &privkey[..]);
    }

    #[test]
    fn encoding_is_deterministic() {
        let privkey = secp_key("m/44'/60'/0'/0/0");
        assert_eq!(
            encode_private_key("ethereum", &privkey).unwrap(),
            encode_private_key("ethereum", &privkey).unwrap()
        );
    }
}
