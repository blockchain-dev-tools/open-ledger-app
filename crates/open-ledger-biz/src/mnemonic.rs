//! BIP-39 mnemonic 业务逻辑：生成、验证、重编码、语言支持。
//!
//! 纯种子派生放在 open-ledger-crypto/bip39.rs。

use bip39::{Language, Mnemonic};

/// BIP-39 语言代码（0-9），用于 FFI 传递。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Bip39Language {
    English = 0,
    ChineseSimplified = 1,
    ChineseTraditional = 2,
    Czech = 3,
    French = 4,
    Italian = 5,
    Japanese = 6,
    Korean = 7,
    Portuguese = 8,
    Spanish = 9,
}

impl Bip39Language {
    pub fn to_bip39_language(self) -> Language {
        match self {
            Bip39Language::English => Language::English,
            Bip39Language::ChineseSimplified => Language::SimplifiedChinese,
            Bip39Language::ChineseTraditional => Language::TraditionalChinese,
            Bip39Language::Czech => Language::Czech,
            Bip39Language::French => Language::French,
            Bip39Language::Italian => Language::Italian,
            Bip39Language::Japanese => Language::Japanese,
            Bip39Language::Korean => Language::Korean,
            Bip39Language::Portuguese => Language::Portuguese,
            Bip39Language::Spanish => Language::Spanish,
        }
    }

    pub fn from_u32(code: u32) -> Option<Self> {
        match code {
            0 => Some(Bip39Language::English),
            1 => Some(Bip39Language::ChineseSimplified),
            2 => Some(Bip39Language::ChineseTraditional),
            3 => Some(Bip39Language::Czech),
            4 => Some(Bip39Language::French),
            5 => Some(Bip39Language::Italian),
            6 => Some(Bip39Language::Japanese),
            7 => Some(Bip39Language::Korean),
            8 => Some(Bip39Language::Portuguese),
            9 => Some(Bip39Language::Spanish),
            _ => None,
        }
    }
}

fn strength_to_word_count(strength: u32) -> usize {
    match strength {
        128 => 12,
        256 => 24,
        _ => panic!("invalid BIP-39 strength: {strength}. Must be 128 or 256"),
    }
}

pub fn generate(strength: u32) -> String {
    let word_count = strength_to_word_count(strength);
    Mnemonic::generate(word_count)
        .expect("valid BIP-39 word count")
        .to_string()
}

pub fn validate(phrase: &str) -> bool {
    Mnemonic::parse(phrase).is_ok()
}

pub fn reencode(phrase: &str) -> String {
    Mnemonic::parse(phrase)
        .map(|m| m.to_string())
        .unwrap_or_else(|_| phrase.to_string())
}

pub fn generate_with_language(strength: u32, language: Language) -> String {
    let word_count = strength_to_word_count(strength);
    Mnemonic::generate_in(language, word_count)
        .expect("valid BIP-39 word count")
        .to_string()
}

pub fn validate_with_language(phrase: &str, language: Language) -> bool {
    Mnemonic::parse_in(language, phrase).is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generate_12_words() {
        let phrase = generate(128);
        let words: Vec<&str> = phrase.split_whitespace().collect();
        assert_eq!(words.len(), 12);
        assert!(validate(&phrase));
    }

    #[test]
    fn generate_24_words() {
        let phrase = generate(256);
        let words: Vec<&str> = phrase.split_whitespace().collect();
        assert_eq!(words.len(), 24);
        assert!(validate(&phrase));
    }

    #[test]
    fn validate_valid_mnemonic() {
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        assert!(validate(phrase));
    }

    #[test]
    fn validate_invalid_mnemonic() {
        assert!(!validate("hello world foo bar"));
        assert!(!validate(""));
        assert!(!validate("zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo"));
    }

    #[test]
    fn reencode_preserves_word_count() {
        let phrase = generate(128);
        let normalized = reencode(&phrase);
        assert_eq!(normalized.split_whitespace().count(), phrase.split_whitespace().count());
        assert!(validate(&normalized));
    }

    #[test]
    fn multiple_generations_are_different() {
        let a = generate(128);
        let b = generate(128);
        assert_ne!(a, b);
    }

    #[test]
    fn language_mismatch_fails_validation() {
        let en_phrase = generate(128);
        assert!(validate(&en_phrase));
        let valid_in_spanish = validate_with_language(&en_phrase, Language::Spanish);
        assert!(!valid_in_spanish);
    }
}
