//! BTC 地址推导业务逻辑。
//!
//! Bitcoin 的「四种地址」不是同一条公钥的四种写法，而是四条不同的 BIP-43
//! purpose 路径（同一颗种子派生四个互不相干的账户）：
//!
//! | 类型 | purpose | 地址前缀 |
//! |---|---|---|
//! | P2PKH legacy | `m/44'/0'/…` | `1…` |
//! | P2SH-P2WPKH | `m/49'/0'/…` | `3…` |
//! | P2WPKH native segwit | `m/84'/0'/…` | `bc1q…` |
//! | P2TR taproot | `m/86'/0'/…` | `bc1p…` |
//!
//! 所以地址类型必须由**路径**决定，不能由调用方随意指定：拿 `m/84'` 的
//! 公钥套 `1…` 编码，得到的是一个谁都无法花费的地址。

use crate::errors::{ChainError, Result};
use open_ledger_crypto::{base58, bech32, hash160, secp256k1};

/// Bitcoin 的四种单签地址类型。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AddressType {
    /// BIP-44 legacy，`1…`。
    Legacy,
    /// BIP-49 嵌套隔离见证，`3…`。
    NestedSegwit,
    /// BIP-84 原生隔离见证，`bc1q…`。
    NativeSegwit,
    /// BIP-86 Taproot（key-path only），`bc1p…`。
    Taproot,
}

impl AddressType {
    /// 该类型对应的 BIP-43 purpose。
    pub fn purpose(self) -> u32 {
        match self {
            AddressType::Legacy => 44,
            AddressType::NestedSegwit => 49,
            AddressType::NativeSegwit => 84,
            AddressType::Taproot => 86,
        }
    }

    /// 稳定标识，用于账户档案与日志（不参与存储主键）。
    pub fn as_str(self) -> &'static str {
        match self {
            AddressType::Legacy => "p2pkh",
            AddressType::NestedSegwit => "p2sh-p2wpkh",
            AddressType::NativeSegwit => "p2wpkh",
            AddressType::Taproot => "p2tr",
        }
    }

    /// 从 purpose 解析；不是四种之一时返回 `None`。
    pub fn from_purpose(purpose: u32) -> Option<Self> {
        match purpose {
            44 => Some(AddressType::Legacy),
            49 => Some(AddressType::NestedSegwit),
            84 => Some(AddressType::NativeSegwit),
            86 => Some(AddressType::Taproot),
            _ => None,
        }
    }

    /// 从路径第一段（purpose）解析地址类型。
    ///
    /// 只接受 Bitcoin 的 coin type 0，避免把 `m/44'/60'…`（ETH）当成 BTC 路径。
    pub fn from_path(path: &str) -> Option<Self> {
        let mut parts = path.split('/');
        let head = parts.next()?;
        if head != "m" {
            return None;
        }
        let purpose = parts.next()?.strip_suffix('\'')?.parse::<u32>().ok()?;
        let coin = parts.next()?.strip_suffix('\'')?.parse::<u32>().ok()?;
        if coin != 0 {
            return None;
        }
        Self::from_purpose(purpose)
    }

    /// 把公钥编码成该类型的地址。`compressed_pubkey` 必须是 33 字节压缩公钥。
    pub fn encode(self, compressed_pubkey: &[u8]) -> Result<String> {
        if compressed_pubkey.len() != 33 {
            return Err(ChainError::InvalidPrivateKey(format!(
                "compressed secp256k1 public key must be 33 bytes, got {}",
                compressed_pubkey.len()
            )));
        }
        match self {
            AddressType::Legacy => Ok(p2pkh_address(compressed_pubkey)),
            AddressType::NestedSegwit => Ok(p2sh_p2wpkh_address(compressed_pubkey)),
            AddressType::NativeSegwit => Ok(p2wpkh_address(compressed_pubkey)),
            AddressType::Taproot => p2tr_address(compressed_pubkey),
        }
    }
}

/// 按路径的 purpose 派生地址。路径本身决定类型，调用方不能另行指定。
pub fn derive_address(seed: &[u8], path: &str) -> Result<String> {
    let address_type = AddressType::from_path(path).ok_or_else(|| {
        ChainError::InvalidPath(format!(
            "'{path}' is not a Bitcoin 44'/49'/84'/86' path"
        ))
    })?;
    let privkey = crate::hdkey::derive_secp256k1_private_key(seed, path)?;
    let compressed_pubkey = secp256k1::public_key_bytes(&privkey, true)?;
    address_type.encode(&compressed_pubkey)
}

/// P2PKH：`base58check(0x00 ‖ hash160(pubkey))`。
pub fn p2pkh_address(compressed_pubkey: &[u8]) -> String {
    let mut payload = Vec::with_capacity(21);
    payload.push(0x00);
    payload.extend_from_slice(&hash160::hash(compressed_pubkey));
    base58::encode_check(&payload)
}

/// P2SH-P2WPKH：`base58check(0x05 ‖ hash160(0x0014 ‖ hash160(pubkey)))`。
pub fn p2sh_p2wpkh_address(compressed_pubkey: &[u8]) -> String {
    let pubkey_hash = hash160::hash(compressed_pubkey);
    let mut script = Vec::with_capacity(22);
    script.push(0x00); // OP_0
    script.push(0x14); // 推入 20 字节
    script.extend_from_slice(&pubkey_hash);
    let mut payload = Vec::with_capacity(21);
    payload.push(0x05);
    payload.extend_from_slice(&hash160::hash(&script));
    base58::encode_check(&payload)
}

/// P2WPKH：`bech32("bc", 0, hash160(pubkey))`。
pub fn p2wpkh_address(compressed_pubkey: &[u8]) -> String {
    let pubkey_hash = hash160::hash(compressed_pubkey);
    bech32::encode("bc", 0, &pubkey_hash)
}

/// P2TR：`bech32m("bc", 1, tweak(lift_x(x(pubkey))))`。
pub fn p2tr_address(compressed_pubkey: &[u8]) -> Result<String> {
    let xonly = &compressed_pubkey[1..];
    let output_key = secp256k1::taproot_output_key(xonly)?;
    Ok(bech32::encode_segwit("bc", 1, &output_key))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_seed() -> Vec<u8> {
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        let mnemonic = bip39::Mnemonic::parse(phrase).unwrap();
        mnemonic.to_seed("").to_vec()
    }

    /// BIP-84 官方向量（`abandon … about`，`m/84'/0'/0'/0/0`）。
    #[test]
    fn bip84_vector() {
        let address = derive_address(&test_seed(), "m/84'/0'/0'/0/0").unwrap();
        assert_eq!(
            address,
            "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
        );
    }

    /// BIP-44 官方向量（同上种子，`m/44'/0'/0'/0/0`）。
    #[test]
    fn bip44_vector() {
        let address = derive_address(&test_seed(), "m/44'/0'/0'/0/0").unwrap();
        assert_eq!(
            address,
            "1LqBGSKuX5yYUonjxT5qGfpUsXKYYWeabA"
        );
    }

    /// BIP-49 官方向量（同上种子，`m/49'/0'/0'/0/0`）。
    #[test]
    fn bip49_vector() {
        let address = derive_address(&test_seed(), "m/49'/0'/0'/0/0").unwrap();
        assert_eq!(
            address,
            "37VucYSaXLCAsxYyAPfbSi9eh4iEcbShgf"
        );
    }

    /// BIP-86 官方向量（同上种子，`m/86'/0'/0'/0/0`）。
    #[test]
    fn bip86_vector() {
        let address = derive_address(&test_seed(), "m/86'/0'/0'/0/0").unwrap();
        assert_eq!(
            address,
            "bc1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcr"
        );
    }

    #[test]
    fn four_types_are_four_distinct_addresses() {
        let seed = test_seed();
        let addresses = [
            derive_address(&seed, "m/44'/0'/0'/0/0").unwrap(),
            derive_address(&seed, "m/49'/0'/0'/0/0").unwrap(),
            derive_address(&seed, "m/84'/0'/0'/0/0").unwrap(),
            derive_address(&seed, "m/86'/0'/0'/0/0").unwrap(),
        ];
        assert!(addresses[0].starts_with('1'));
        assert!(addresses[1].starts_with('3'));
        assert!(addresses[2].starts_with("bc1q"));
        assert!(addresses[3].starts_with("bc1p"));
        for (index, address) in addresses.iter().enumerate() {
            assert!(
                !addresses[..index].contains(address),
                "duplicate address {address}"
            );
        }
    }

    #[test]
    fn non_bitcoin_and_unknown_purposes_are_rejected() {
        let seed = test_seed();
        // ETH 的 coin type 与 BTC 的未知 purpose 都不能被当成 BTC 路径。
        assert!(derive_address(&seed, "m/44'/60'/0'/0/0").is_err());
        assert!(derive_address(&seed, "m/1'/0'/0'/0/0").is_err());
    }

    #[test]
    fn p2wpkh_matches_the_legacy_helper() {
        let seed = test_seed();
        let privkey = crate::hdkey::derive_secp256k1_private_key(&seed, "m/84'/0'/0'/0/0").unwrap();
        let pubkey = secp256k1::public_key_bytes(&privkey, true).unwrap();
        assert_eq!(
            p2wpkh_address(&pubkey),
            derive_address(&seed, "m/84'/0'/0'/0/0").unwrap()
        );
    }

    /// Taproot key-path 签名的跨实现锁定：同一私钥、同一 sighash、aux=0，
    /// 由 @noble/curves（BIP-340 参考实现）算出的签名必须逐字节相同。
    /// 这条覆盖「内部公钥 y 为奇数时先取反再 tweak」这一最容易写错的步骤。
    #[test]
    fn taproot_signature_matches_the_independent_noble_implementation() {
        let seed = test_seed();
        let privkey =
            crate::hdkey::derive_secp256k1_private_key(&seed, "m/86'/0'/0'/0/0").unwrap();
        let signature =
            secp256k1::schnorr_sign_taproot(&privkey, &[0x33u8; 32]).unwrap();
        assert_eq!(
            hex::encode(&signature),
            "65a9117a1c605e99baf156756b099e54d008267c3e26e2863491ca1d49a4790b47800de1bda40ef8f400ab14057f8bd57bbe3e22d6ba6a6bdbd10a98ce496eb1"
        );
    }
}
