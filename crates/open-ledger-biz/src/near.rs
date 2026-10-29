//! NEAR 地址推导。
//!
//! NEAR 的隐式账户（implicit account）就是 ed25519 公钥的 64 位十六进制小写
//! 字符串，不带前缀、不需要哈希，也没有校验和。所以这里只做 ed25519 派生。

use crate::errors::Result;
use open_ledger_crypto::ed25519;

/// Ledger 的 NEAR app 使用 5 段全硬化路径 `m/44'/397'/{account}'/0'/1'`。
pub fn derive_address(seed: &[u8], path: &str) -> Result<String> {
    let privkey = crate::hdkey::derive_ed25519_private_key(seed, path)?;
    let pubkey = ed25519::public_key_bytes(&privkey)?;
    Ok(hex::encode(pubkey))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn seed() -> Vec<u8> {
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        bip39::Mnemonic::parse(phrase).unwrap().to_seed("").to_vec()
    }

    #[test]
    fn address_is_the_hex_public_key() {
        let address = derive_address(&seed(), "m/44'/397'/0'/0'/1'").unwrap();
        assert_eq!(address.len(), 64, "隐式账户是 32 字节公钥的 hex");
        assert!(address.chars().all(|c| c.is_ascii_hexdigit()));
        assert_eq!(address, address.to_lowercase());
    }

    #[test]
    fn different_paths_give_different_addresses() {
        let a = derive_address(&seed(), "m/44'/397'/0'/0'/1'").unwrap();
        let b = derive_address(&seed(), "m/44'/397'/1'/0'/1'").unwrap();
        assert_ne!(a, b);
    }
}
