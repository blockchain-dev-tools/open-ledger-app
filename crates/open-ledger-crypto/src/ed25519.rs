//! Ed25519 签名算法。
//!
//! 封装 ed25519-dalek crate，供 SOL/SUI 共用。

use crate::errors::{CryptoError, Result};
use ed25519_dalek::{Signer, SigningKey};

pub fn sign(private_key: &[u8], message: &[u8]) -> Result<Vec<u8>> {
    let key_bytes: [u8; 32] = private_key
        .try_into()
        .map_err(|_| CryptoError::InvalidKey(format!("ed25519 private key must be 32 bytes, got {}", private_key.len())))?;
    let signing_key = SigningKey::from_bytes(&key_bytes);
    let signature = signing_key.sign(message);
    Ok(signature.to_bytes().to_vec())
}

pub fn public_key_bytes(private_key: &[u8]) -> Result<Vec<u8>> {
    let key_bytes: [u8; 32] = private_key
        .try_into()
        .map_err(|_| CryptoError::InvalidKey(format!("ed25519 private key must be 32 bytes, got {}", private_key.len())))?;
    let signing_key = SigningKey::from_bytes(&key_bytes);
    let verifying_key = signing_key.verifying_key();
    Ok(verifying_key.to_bytes().to_vec())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_privkey() -> Vec<u8> {
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        let mnemonic = bip39::Mnemonic::parse(phrase).unwrap();
        let seed = mnemonic.to_seed("");
        // SLIP-10 Ed25519 derivation
        use hmac::{Hmac, Mac};
        use sha2::Sha512;
        let mut mac = Hmac::<Sha512>::new_from_slice(b"ed25519 seed")
            .expect("HMAC should initialize");
        mac.update(&seed);
        let i = mac.finalize().into_bytes();
        i[..32].to_vec()
    }

    #[test]
    fn sign_returns_64_bytes() {
        let pk = test_privkey();
        let sig = sign(&pk, b"solana message").unwrap();
        assert_eq!(sig.len(), 64);
    }

    #[test]
    fn pubkey_returns_32_bytes() {
        let pk = test_privkey();
        let pubkey = public_key_bytes(&pk).unwrap();
        assert_eq!(pubkey.len(), 32);
    }

    #[test]
    fn sign_deterministic() {
        let pk = test_privkey();
        let sig1 = sign(&pk, b"same message").unwrap();
        let sig2 = sign(&pk, b"same message").unwrap();
        assert_eq!(sig1, sig2);
    }
}
