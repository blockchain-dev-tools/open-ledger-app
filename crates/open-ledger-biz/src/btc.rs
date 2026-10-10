//! BTC 地址推导业务逻辑。

use crate::errors::Result;
use open_ledger_crypto::{hash160, bech32, secp256k1};

pub fn derive_address(seed: &[u8], path: &str) -> Result<String> {
    let privkey = crate::hdkey::derive_secp256k1_private_key(seed, path)?;
    let compressed_pubkey = secp256k1::public_key_bytes(&privkey, true)?;
    Ok(p2wpkh_address(&compressed_pubkey))
}

pub fn p2wpkh_address(compressed_pubkey: &[u8]) -> String {
    let pubkey_hash = hash160::hash(compressed_pubkey);
    bech32::encode("bc", 0, &pubkey_hash)
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
    fn derive_address_valid() {
        let seed = test_seed();
        let addr = derive_address(&seed, "m/84'/0'/0'/0/0").unwrap();
        assert!(addr.starts_with("bc1"));
        assert_eq!(addr.len(), 42);
    }

    #[test]
    fn p2wpkh_valid_bech32() {
        let seed = test_seed();
        let privkey = crate::hdkey::derive_secp256k1_private_key(&seed, "m/84'/0'/0'/0/0").unwrap();
        let pk = secp256k1::public_key_bytes(&privkey, true).unwrap();
        let addr = p2wpkh_address(&pk);
        assert!(addr.starts_with("bc1"));
        assert_eq!(addr.len(), 42);
    }
}
