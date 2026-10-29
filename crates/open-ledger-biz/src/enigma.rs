//! Enigma 确定性助记词。
//!
//! 谜语 + 密钥 → keccak256 → 24 词 BIP-39 mnemonic。
//!
//! # 算法概述
//!
//! 谜语文本按词表语言切分后，逐 token 查 BIP-39 词表索引，每个索引以固定
//! 2 字节大端（u16）编码，最多 [`MAX_INDICES`] 个词按顺序拼接为字节序列，
//! 再经 keccak256 与密钥盐哈希混合，得到最终 32 字节熵，
//! 最后编码为 24 词助记词（[`generate`] 固定英文输出）。
//!
//! 确定性：相同 (谜语, 密钥, 语言) 永远得到相同结果。
//!
//! 注意：这是输入→助记词的派生算法，任何字节级改动都会使既有 Enigma 钱包
//! 无法用原输入恢复。重构时必须保持输出字节流完全等价，详见 [`derive_entropy`]。

use crate::errors::{ChainError, Result};
use bip39::{Language, Mnemonic};
use sha3::{Digest, Keccak256};
use crate::mnemonic::Bip39Language;

/// 最终熵长度：32 字节 = 256 bit，恰对应 BIP-39 24 词所需的熵长度。
const ENTROPY_BYTES: usize = 32;

/// 每个词表索引编码的字节数（u16 大端；BIP-39 索引 0–2047 天然装入）。
const BYTES_PER_WORD: usize = 2;

/// 最多参与熵的索引数（安全上限，防止超长谜语耗尽输入）。
const MAX_INDICES: usize = 1024;

/// 谜语文本长度上限（字符数），超出部分被截断忽略。
const MAX_ENIGMA_CAP: usize = 1024;

/// 判断词表语言是否属于 CJK（简体中文 / 繁体中文 / 日文）。
/// CJK 语言按「字」切分谜语，其他语言按「词」切分。
fn is_cjk(lang: Language) -> bool {
    matches!(lang, Language::SimplifiedChinese | Language::TraditionalChinese | Language::Japanese)
}

/// 按词表语言把谜语文本切分成一个 token 列表。
///
/// - CJK：逐个非空白字符切分（每个汉字/假名是一个独立 token）；
/// - 其他：按空白切分并统一转小写（英文等大小写不敏感）。
fn tokenize(text: &str, lang: Language) -> Vec<String> {
    if is_cjk(lang) {
        text.chars().filter(|c| !c.is_whitespace()).map(|c| c.to_string()).collect()
    } else {
        text.split_whitespace().map(|w| w.to_lowercase()).collect()
    }
}

/// 步骤 1：谜语文本 → 命中的词数组。
///
/// 谜语截断到 [`MAX_ENIGMA_CAP`] 字符后按语言切分，只保留 BIP-39 词表中
/// 命中的 token（查不到的被跳过、不贡献熵），最多 [`MAX_INDICES`] 个。
fn match_tokens(riddle: &str, lang: Language) -> Vec<String> {
    let riddle: String = riddle.chars().take(MAX_ENIGMA_CAP).collect();
    let tokens = tokenize(&riddle, lang);
    let mut matched = Vec::with_capacity(MAX_INDICES);
    for token in tokens {
        if matched.len() >= MAX_INDICES { break; }
        if lang.find_word(&token).is_some() { matched.push(token); }
    }
    matched
}

/// 统计谜语在给定词表中命中的 token 数（仅用于 UI 提示，不参与派生）。
///
/// 计数规则与 [`match_tokens`] 完全一致：谜语先截断到 [`MAX_ENIGMA_CAP`]
/// 字符，CJK 逐字切分、其他语言按空白切分，最多 [`MAX_INDICES`] 个命中。
pub fn match_count(riddle: &str, language: Bip39Language) -> usize {
    match_tokens(riddle, language.to_bip39_language()).len()
}

/// 步骤 2：词数组 → u16 索引数组（查词表，未命中的 token 跳过）。
fn tokens_to_indices(tokens: &[String], lang: Language) -> Vec<u16> {
    let mut indices = Vec::with_capacity(MAX_INDICES);
    for token in tokens {
        if indices.len() >= MAX_INDICES { break; }
        if let Some(index) = lang.find_word(token) { indices.push(index); }
    }
    indices
}

/// 步骤 3：u16 索引数组 → 字节序列。
///
/// 每个索引编码为固定 [`BYTES_PER_WORD`] 字节大端，按谜语顺序直接拼接，
/// 长度随命中词数变化，不再填充到固定宽度。
fn indices_to_bytes(indices: &[u16]) -> Vec<u8> {
    let mut bytes = Vec::with_capacity(indices.len().min(MAX_INDICES) * BYTES_PER_WORD);
    for idx in indices.iter().take(MAX_INDICES) {
        bytes.extend_from_slice(&idx.to_be_bytes());
    }
    bytes
}

/// 步骤 4：字节序列 + 密钥 → 最终 32 字节熵。
///
/// `entropy_hash = keccak256(熵字节)`（keccak 接受任意长度输入）；非空盐时再拼
/// `keccak256(密钥 UTF-8 字节)` 一并 keccak256，空盐则仅熵哈希。
fn finalize_entropy(entropy_bytes: &[u8], secret: &str) -> [u8; ENTROPY_BYTES] {
    let mut hasher = Keccak256::new();
    hasher.update(Keccak256::digest(entropy_bytes));
    if !secret.is_empty() {
        hasher.update(Keccak256::digest(secret.as_bytes()));
    }
    hasher.finalize().into()
}

/// 由 (谜语, 密钥, 词表语言) 计算出最终 32 字节熵。
///
/// [`match_tokens`] → [`tokens_to_indices`] → [`indices_to_bytes`] →
/// [`finalize_entropy`]，各步骤均可独立单测。
fn derive_entropy(riddle: &str, secret: &str, lang: Language) -> [u8; 32] {
    let tokens = match_tokens(riddle, lang);
    let indices = tokens_to_indices(&tokens, lang);
    let bytes = indices_to_bytes(&indices);
    finalize_entropy(&bytes, secret)
}

/// 由 (谜语, 密钥, 词表语言) 生成 24 词助记词。
///
/// 注意：`language` 仅决定谜语的切分方式与查词表所用的 BIP-39 语言，
/// 输出助记词**始终为英文**（`Language::English`），与输入语言无关——
/// 这是为了保持种子推导与多语言展示的一致性，由 [`mnemonic_from_entropy`]
/// 负责把同一熵以其他词表「展示」。
pub fn generate(riddle: &str, secret: &str, language: Bip39Language) -> Result<String> {
    let bip39_lang = language.to_bip39_language();
    let entropy = derive_entropy(riddle, secret, bip39_lang);
    let mnemonic = Mnemonic::from_entropy_in(Language::English, &entropy)
        .map_err(|e| ChainError::EnigmaError(e.to_string()))?;
    Ok(mnemonic.to_string())
}

/// 只返回最终熵的 hex（64 字符 = 32 字节），不生成助记词。
///
/// 供 UI 侧在「以不同语言展示助记词」时复用同一熵，配合 [`mnemonic_from_entropy`]
/// 使用，避免重复派生。熵是钱包的真实确定性来源。
pub fn entropy_hex(riddle: &str, secret: &str, language: Bip39Language) -> String {
    let bip39_lang = language.to_bip39_language();
    let entropy = derive_entropy(riddle, secret, bip39_lang);
    hex::encode(entropy)
}

/// 由 32 字节熵 hex（64 字符）重新编码为指定语言的 24 词助记词。
///
/// 用于把同一个 Enigma 钱包以不同 BIP-39 词表「展示」，熵本身不变。
/// 仅用于展示——钱包初始化时种子始终由英文助记词推导。
pub fn mnemonic_from_entropy(entropy_hex: &str, language: Bip39Language) -> Result<String> {
    let bytes = hex::decode(entropy_hex)
        .map_err(|e| ChainError::EnigmaError(format!("invalid entropy hex: {e}")))?;
    if bytes.len() != 32 {
        return Err(ChainError::EnigmaError("entropy must be 32 bytes".into()));
    }
    let mnemonic = Mnemonic::from_entropy_in(language.to_bip39_language(), &bytes)
        .map_err(|e| ChainError::EnigmaError(e.to_string()))?;
    Ok(mnemonic.to_string())
}

#[cfg(test)]
#[path = "enigma_test.rs"]
mod enigma_test;
