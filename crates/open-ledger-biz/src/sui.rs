//! Sui 地址推导业务逻辑。

use crate::errors::Result;
use open_ledger_crypto::{blake2b, ed25519};

pub fn derive_address(seed: &[u8], path: &str) -> Result<String> {
    let privkey = crate::hdkey::derive_ed25519_private_key(seed, path)?;
    let pubkey = ed25519::public_key_bytes(&privkey)?;
    Ok(sui_address(&pubkey))
}

pub fn sui_address(ed25519_pubkey: &[u8]) -> String {
    let mut hasher_input = Vec::with_capacity(1 + ed25519_pubkey.len());
    hasher_input.push(0x00);
    hasher_input.extend_from_slice(ed25519_pubkey);
    let hash = blake2b::hash(&hasher_input);
    format!("0x{}", hex::encode(hash))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_seed() -> Vec<u8> {
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        let mnemonic = bip39::Mnemonic::parse(phrase).unwrap();
        mnemonic.to_seed("").to_vec()
    }

    #[test]
    fn sui_address_format() {
        let pk = [0xabu8; 32];
        let addr = sui_address(&pk);
        assert!(addr.starts_with("0x"));
        assert_eq!(addr.len(), 66);
    }

    #[test]
    fn sui_address_deterministic() {
        let pk = [0xcdu8; 32];
        let a = sui_address(&pk);
        let b = sui_address(&pk);
        assert_eq!(a, b);
    }

    #[test]
    fn derive_address_valid() {
        let seed = test_seed();
        let addr = derive_address(&seed, "m/44'/784'/0'/0'/0'").unwrap();
        assert!(addr.starts_with("0x"));
        assert_eq!(addr.len(), 66);
    }

    #[test]
    fn derive_address_deterministic() {
        let seed = test_seed();
        let a = derive_address(&seed, "m/44'/784'/0'/0'/0'").unwrap();
        let b = derive_address(&seed, "m/44'/784'/0'/0'/0'").unwrap();
        assert_eq!(a, b);
    }

    #[test]
    fn derive_address_different_paths() {
        let seed = test_seed();
        let a = derive_address(&seed, "m/44'/784'/0'/0'/0'").unwrap();
        let b = derive_address(&seed, "m/44'/784'/1'/0'/0'").unwrap();
        assert_ne!(a, b);
    }
}
