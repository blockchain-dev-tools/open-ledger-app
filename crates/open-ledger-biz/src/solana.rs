//! Solana 签名 + 地址推导业务逻辑。

use crate::errors::{ChainError, Result};
use open_ledger_crypto::ed25519;

pub fn sign_message(private_key: &[u8], message: &[u8]) -> Result<Vec<u8>> {
    ed25519::sign(private_key, message).map_err(|e| ChainError::InvalidPrivateKey(e.to_string()))
}

pub fn derive_address(seed: &[u8], path: &str) -> Result<String> {
    let privkey = crate::hdkey::derive_ed25519_private_key(seed, path)?;
    let pubkey = ed25519::public_key_bytes(&privkey)?;
    Ok(bs58::encode(&pubkey).into_string())
}

pub fn public_key_bytes(private_key: &[u8]) -> Result<Vec<u8>> {
    ed25519::public_key_bytes(private_key).map_err(|e| ChainError::InvalidPrivateKey(e.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_privkey() -> Vec<u8> {
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        let mnemonic = bip39::Mnemonic::parse(phrase).unwrap();
        let seed = mnemonic.to_seed("");
        crate::hdkey::derive_ed25519_private_key(&seed, "m/44'/501'/0'/0'").unwrap()
    }

    #[test]
    fn sign_returns_64_bytes() {
        let key = test_privkey();
        let sig = sign_message(&key, b"solana message").unwrap();
        assert_eq!(sig.len(), 64);
    }

    #[test]
    fn pubkey_returns_32_bytes() {
        let key = test_privkey();
        let pubkey = public_key_bytes(&key).unwrap();
        assert_eq!(pubkey.len(), 32);
    }

    #[test]
    fn sign_deterministic() {
        let key = test_privkey();
        let sig1 = sign_message(&key, b"same message").unwrap();
        let sig2 = sign_message(&key, b"same message").unwrap();
        assert_eq!(sig1, sig2);
    }

    #[test]
    fn derive_address_valid() {
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        let mnemonic = bip39::Mnemonic::parse(phrase).unwrap();
        let seed = mnemonic.to_seed("");
        let addr = derive_address(&seed, "m/44'/501'/0'/0'").unwrap();
        assert!(!addr.is_empty());
        assert!(addr.len() >= 32);
    }
}
