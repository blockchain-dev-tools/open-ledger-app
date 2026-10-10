//! Tron 地址推导业务逻辑。

use crate::errors::Result;
use open_ledger_crypto::{keccak256, base58, secp256k1};

pub fn derive_address(seed: &[u8], path: &str) -> Result<String> {
    let privkey = crate::hdkey::derive_secp256k1_private_key(seed, path)?;
    let uncompressed_pubkey = secp256k1::public_key_bytes(&privkey, false)?;
    Ok(tron_address_from_pubkey(&uncompressed_pubkey))
}

pub fn tron_address_from_pubkey(uncompressed_pubkey: &[u8]) -> String {
    let pubkey_hash = keccak256::hash(&uncompressed_pubkey[1..]);
    let last20 = &pubkey_hash[12..];
    let mut addr_raw = Vec::with_capacity(21);
    addr_raw.push(0x41);
    addr_raw.extend_from_slice(last20);
    base58::encode_check(&addr_raw)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_seed() -> Vec<u8> {
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        let mnemonic = bip39::Mnemonic::parse(phrase).unwrap();
        mnemonic.to_seed("").to_vec()
    }

    fn test_uncompressed_pubkey() -> Vec<u8> {
        let seed = test_seed();
        let privkey = crate::hdkey::derive_secp256k1_private_key(&seed, "m/44'/195'/0'/0/0").unwrap();
        open_ledger_crypto::secp256k1::public_key_bytes(&privkey, false).unwrap()
    }

    #[test]
    fn derive_address_starts_with_t() {
        let seed = test_seed();
        let addr = derive_address(&seed, "m/44'/195'/0'/0/0").unwrap();
        assert!(addr.starts_with('T'));
        assert_eq!(addr.len(), 34);
    }

    #[test]
    fn tron_address_from_pubkey_deterministic() {
        let pk = test_uncompressed_pubkey();
        let addr1 = tron_address_from_pubkey(&pk);
        let addr2 = tron_address_from_pubkey(&pk);
        assert_eq!(addr1, addr2);
        assert!(addr1.starts_with('T'));
        assert_eq!(addr1.len(), 34);
    }

    #[test]
    fn tron_address_from_pubkey_starts_with_t() {
        let pk = test_uncompressed_pubkey();
        let addr = tron_address_from_pubkey(&pk);
        assert!(addr.starts_with('T'));
        assert_eq!(addr.len(), 34);
    }

    #[test]
    fn derive_address_deterministic() {
        let seed = test_seed();
        let a = derive_address(&seed, "m/44'/195'/0'/0/0").unwrap();
        let b = derive_address(&seed, "m/44'/195'/0'/0/0").unwrap();
        assert_eq!(a, b);
    }

    #[test]
    fn derive_address_different_paths() {
        let seed = test_seed();
        let a = derive_address(&seed, "m/44'/195'/0'/0/0").unwrap();
        let b = derive_address(&seed, "m/44'/195'/0'/0/1").unwrap();
        assert_ne!(a, b);
    }
}
