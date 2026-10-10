//! BIP-39 seed derivation（PBKDF2-HMAC-SHA512）。
//!
//! 仅包含纯数学的种子派生函数，不包含 mnemonic 生成/验证等业务逻辑。
//! generate/validate/Bip39Language 等放在 open-ledger-biz/crate。

use crate::errors::{CryptoError, Result};
use hmac::Hmac;
use pbkdf2::pbkdf2;
use sha2::Sha512;

/// 从 BIP-39 mnemonic + 可选 passphrase 派生 64-byte seed。
pub fn mnemonic_to_seed(phrase: &str, passphrase: &str) -> Result<[u8; 64]> {
    if let Ok(mnemonic) = bip39::Mnemonic::parse(phrase) {
        return Ok(mnemonic.to_seed(passphrase));
    }
    let normalized: String = phrase
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase();
    let salt = format!("mnemonic{}", passphrase);
    let mut seed = [0u8; 64];
    pbkdf2::<Hmac<Sha512>>(normalized.as_bytes(), salt.as_bytes(), 2048, &mut seed)
        .map_err(|e| CryptoError::SeedDerivationFailed(e.to_string()))?;
    Ok(seed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn standard_mnemonic_produces_seed() {
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        let seed = mnemonic_to_seed(phrase, "").expect("standard mnemonic must produce seed");
        assert_eq!(seed.len(), 64);
    }

    #[test]
    fn seed_is_deterministic() {
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        let seed1 = mnemonic_to_seed(phrase, "").unwrap();
        let seed2 = mnemonic_to_seed(phrase, "").unwrap();
        assert_eq!(seed1, seed2);
    }

    #[test]
    fn seed_with_passphrase() {
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        let seed1 = mnemonic_to_seed(phrase, "TREZOR").unwrap();
        let seed2 = mnemonic_to_seed(phrase, "TREZOR").unwrap();
        assert_eq!(seed1, seed2);
    }

    #[test]
    fn different_passphrases_different_seeds() {
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        let seed_a = mnemonic_to_seed(phrase, "").unwrap();
        let seed_b = mnemonic_to_seed(phrase, "TREZOR").unwrap();
        assert_ne!(seed_a, seed_b);
    }

    #[test]
    fn enigma_style_no_checksum() {
        let phrase = "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo vote";
        let seed = mnemonic_to_seed(phrase, "").expect("Enigma mnemonic must produce seed");
        assert_ne!(seed, [0u8; 64]);
    }

    #[test]
    fn whitespace_normalized() {
        let seed1 = mnemonic_to_seed(
            "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
            "",
        ).unwrap();
        let seed2 = mnemonic_to_seed(
            "  abandon  abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about  ",
            "",
        ).unwrap();
        assert_eq!(seed1, seed2);
    }
}
