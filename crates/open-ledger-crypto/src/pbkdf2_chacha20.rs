//! PIN-based cryptographic operations: PBKDF2 key derivation and
//! ChaCha20-Poly1305 authenticated encryption for mnemonic protection.

use crate::errors::{CryptoError, Result};
use chacha20poly1305::{aead::Aead, ChaCha20Poly1305, KeyInit, Nonce};
use hmac::{Hmac, Mac};
use pbkdf2::pbkdf2;
use sha2::Sha256;
use zeroize::Zeroize;

const PBKDF2_ITERATIONS: u32 = 100_000;

/// Domain-separation salt for the signing-history key (versioned to avoid
/// colliding with other seed-derived keys).
const HISTORY_KEY_SALT: &[u8] = b"openledger.history.v1";

pub fn pbkdf2_derive(pin: &str, salt: &[u8], key_len: usize) -> Vec<u8> {
    let mut key = vec![0u8; key_len];
    pbkdf2::<Hmac<Sha256>>(pin.as_bytes(), salt, PBKDF2_ITERATIONS, &mut key)
        .expect("PBKDF2-HMAC-SHA256 should not fail");
    key
}

/// HKDF-Expand (RFC 5869 §2.3) producing one 32-byte block:
/// `T(1) = HMAC-SHA256(PRK, info ‖ 0x01)`.
///
/// Used for **domain separation**: a single PBKDF2 master key derives
/// independent subkeys per context (e.g. the tier verifier vs the vault
/// payload), so one master key never encrypts two kinds of data directly.
///
/// Extract is deliberately skipped — the PRK here is already a PBKDF2 output
/// (pseudorandom), which RFC 5869 §3.3 explicitly allows.
///
/// Cost is one HMAC, i.e. negligible next to [pbkdf2_derive].
pub fn hkdf_expand_32(prk: &[u8], info: &[u8]) -> [u8; 32] {
    // Fully qualified: `KeyInit` and `Mac` both define `new_from_slice`.
    let mut mac = <Hmac<Sha256> as Mac>::new_from_slice(prk)
        .expect("HMAC-SHA256 accepts a key of any length");
    mac.update(info);
    mac.update(&[0x01]);
    let block = mac.finalize().into_bytes();
    let mut okm = [0u8; 32];
    okm.copy_from_slice(&block);
    okm
}

pub fn chacha20_encrypt(plaintext: &[u8], key: &[u8; 32]) -> Result<Vec<u8>> {
    let cipher = ChaCha20Poly1305::new_from_slice(key)
        .map_err(|e| CryptoError::InvalidKey(e.to_string()))?;
    let nonce_bytes: [u8; 12] = {
        use rand::RngCore;
        let mut rng = rand::thread_rng();
        let mut buf = [0u8; 12];
        rng.fill_bytes(&mut buf);
        buf
    };
    let nonce = Nonce::from_slice(&nonce_bytes);
    let ciphertext = cipher
        .encrypt(nonce, plaintext)
        .map_err(|e| CryptoError::EncryptionFailed(e.to_string()))?;
    let mut out = Vec::with_capacity(12 + ciphertext.len());
    out.extend_from_slice(&nonce_bytes);
    out.extend_from_slice(&ciphertext);
    Ok(out)
}

pub fn chacha20_decrypt(data: &[u8], key: &[u8; 32]) -> Result<Vec<u8>> {
    if data.len() < 12 {
        return Err(CryptoError::DecryptionFailed("Ciphertext too short (missing nonce)".into()));
    }
    let cipher = ChaCha20Poly1305::new_from_slice(key)
        .map_err(|e| CryptoError::InvalidKey(e.to_string()))?;
    let nonce = Nonce::from_slice(&data[..12]);
    cipher
        .decrypt(nonce, &data[12..])
        .map_err(|e| CryptoError::DecryptionFailed(e.to_string()))
}

/// Derive the 32-byte signing-history key from a BIP-39 seed (hex string).
///
/// The seed is high-entropy, so the PBKDF2 work factor is not a security
/// factor here — it is reused purely for domain separation via
/// [`HISTORY_KEY_SALT`].
pub fn derive_history_key(seed_hex: &str) -> [u8; 32] {
    let derived = pbkdf2_derive(seed_hex, HISTORY_KEY_SALT, 32);
    let mut key = [0u8; 32];
    key.copy_from_slice(&derived);
    key
}

/// Encrypt signing-history JSON with a seed-derived key (ChaCha20-Poly1305).
pub fn history_encrypt(plaintext: &[u8], seed_hex: &str) -> Result<Vec<u8>> {
    let mut key = derive_history_key(seed_hex);
    let result = chacha20_encrypt(plaintext, &key);
    key.zeroize();
    result
}

/// Decrypt signing-history ciphertext with a seed-derived key.
pub fn history_decrypt(data: &[u8], seed_hex: &str) -> Result<Vec<u8>> {
    let mut key = derive_history_key(seed_hex);
    let result = chacha20_decrypt(data, &key);
    key.zeroize();
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pbkdf2_derive_known_length() {
        let key = pbkdf2_derive("123456", b"salt", 32);
        assert_eq!(key.len(), 32);
    }

    #[test]
    fn pbkdf2_derive_deterministic() {
        let a = pbkdf2_derive("test", b"fixed_salt", 16);
        let b = pbkdf2_derive("test", b"fixed_salt", 16);
        assert_eq!(a, b);
    }

    /// RFC 5869 Test Case 1 (SHA-256): T(1) is the first 32 bytes of the
    /// published 42-byte OKM.
    #[test]
    fn hkdf_expand_32_matches_rfc5869_test_case_1() {
        let prk = hex::decode("077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5")
            .unwrap();
        let info = hex::decode("f0f1f2f3f4f5f6f7f8f9").unwrap();

        let okm = hkdf_expand_32(&prk, &info);

        assert_eq!(
            hex::encode(okm),
            "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf"
        );
    }

    #[test]
    fn hkdf_expand_32_separates_contexts() {
        let prk = [0x42u8; 32];
        assert_ne!(
            hkdf_expand_32(&prk, b"openledger.verify.v1"),
            hkdf_expand_32(&prk, b"openledger.vault.v1")
        );
    }

    #[test]
    fn chacha20_roundtrip() {
        let key = [0xabu8; 32];
        let plaintext = b"hello world";
        let encrypted = chacha20_encrypt(plaintext, &key).unwrap();
        assert!(encrypted.len() > 12, "should have nonce + ciphertext");
        let decrypted = chacha20_decrypt(&encrypted, &key).unwrap();
        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn chacha20_wrong_key_fails() {
        let key = [0xabu8; 32];
        let wrong_key = [0xcdu8; 32];
        let encrypted = chacha20_encrypt(b"secret", &key).unwrap();
        assert!(chacha20_decrypt(&encrypted, &wrong_key).is_err());
    }

    #[test]
    fn derive_history_key_is_deterministic_and_seed_dependent() {
        let a = derive_history_key("deadbeef");
        let b = derive_history_key("deadbeef");
        assert_eq!(a, b);
        assert_ne!(a, derive_history_key("deadbeee"));
    }

    #[test]
    fn history_roundtrip() {
        let seed = "0102030405060708090a0b0c0d0e0f10";
        let plaintext = br#"[{"chain":"ethereum"}]"#;
        let encrypted = history_encrypt(plaintext, seed).unwrap();
        assert!(encrypted.len() > 12, "should include nonce + ciphertext");
        assert_eq!(history_decrypt(&encrypted, seed).unwrap(), plaintext);
    }

    #[test]
    fn history_wrong_seed_fails() {
        let encrypted = history_encrypt(b"secret", "aaaa").unwrap();
        assert!(history_decrypt(&encrypted, "bbbb").is_err());
    }
}
