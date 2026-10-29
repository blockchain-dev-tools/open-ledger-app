//! TON 地址推导（Wallet v4r2）。
//!
//! TON 的地址不是一个密钥哈希，而是**合约状态哈希**：同一把 ed25519 公钥在
//! v4r2 合约里的地址，等于 `state_init` cell 的哈希。因此这里没法“调一个
//! base58 编码器”就完事，必须按 TL-B 的 cell 表示法自己算：
//!
//! ```text
//! data  = seqno:u32 (0) · subwallet:u32 (698983191) · pubkey:bits256 · plugins:dict (空)
//!         共 321 bit
//! state = cell { 0 bit, refs = [code, data] }
//! addr  = 0x11 · 0x00 (workchain 0) · sha256(state) · crc16le
//! ```
//!
//! `code` 只以哈希形式参与计算（cell 哈希只依赖引用哈希），所以不需要内联
//! 整个合约代码，只钉住 v4r2 的代码哈希即可 —— 该值取自 TON 官方文档
//! "Wallets history" 表格。

use crate::errors::{ChainError, Result};
use open_ledger_crypto::{ed25519, sha256};

/// Wallet v4r2 的代码 cell 哈希（TON 官方文档，Wallets history）。
const V4R2_CODE_HASH: [u8; 32] = [
    0xfe, 0xb5, 0xff, 0x68, 0x20, 0xe2, 0xff, 0x0d, 0x94, 0x83, 0xe7, 0xe0, 0xd6, 0x2c, 0x81, 0x7d,
    0x84, 0x67, 0x89, 0xfb, 0x4a, 0xe5, 0x80, 0xc8, 0x78, 0x86, 0x6d, 0x95, 0x9d, 0xab, 0xd5, 0xc0,
];

/// 主网默认子钱包号。
const SUBWALLET_ID: u32 = 698_983_191;

/// 普通 cell 的表示哈希：`d1 · d2 · data · 引用哈希`。
///
/// `d1` 低 3 位是 level mask（普通 cell 为 0），第 3 位是 exotic 标记，
/// 高 3 位是引用数；`d2` 低 1 位标记最后一字节是否只用了部分 bit。
fn cell_hash(bits: usize, data: &[u8], refs: &[[u8; 32]]) -> [u8; 32] {
    let d1 = (refs.len() as u8) << 4;
    let d2 = ((bits / 8) * 2) as u8 + u8::from(bits % 8 != 0);
    let mut buf = Vec::with_capacity(2 + data.len() + refs.len() * 32);
    buf.push(d1);
    buf.push(d2);
    buf.extend_from_slice(data);
    for r in refs {
        buf.extend_from_slice(r);
    }
    sha256::hash(&buf)
}

/// v4r2 数据 cell：321 bit，最后一 bit 是空插件字典的终止位。
fn data_hash(pubkey: &[u8; 32]) -> [u8; 32] {
    let mut data = Vec::with_capacity(41);
    data.extend_from_slice(&0u32.to_be_bytes()); // seqno
    data.extend_from_slice(&SUBWALLET_ID.to_be_bytes());
    data.extend_from_slice(pubkey);
    data.push(0x00); // plugins: dict 为空 → 一个 0 bit，补齐到字节边界
    cell_hash(321, &data, &[])
}

/// 由公钥算出 `state_init` 哈希，也就是地址主体。
pub fn state_init_hash(pubkey: &[u8; 32]) -> [u8; 32] {
    cell_hash(0, &[], &[V4R2_CODE_HASH, data_hash(pubkey)])
}

/// CRC16-XMODEM（poly 0x1021，初值 0，输入输出均不反转）。
fn crc16(data: &[u8]) -> u16 {
    let mut crc: u16 = 0;
    for byte in data {
        crc ^= u16::from(*byte) << 8;
        for _ in 0..8 {
            crc = if crc & 0x8000 != 0 {
                (crc << 1) ^ 0x1021
            } else {
                crc << 1
            };
        }
    }
    crc
}

/// base64url（无填充）——地址固定 36 字节，正好 48 个字符。
fn base64url(data: &[u8]) -> String {
    const ALPHABET: &[u8; 64] =
        b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    let mut out = String::with_capacity(data.len().div_ceil(3) * 4);
    for chunk in data.chunks(3) {
        let b = [chunk[0], *chunk.get(1).unwrap_or(&0), *chunk.get(2).unwrap_or(&0)];
        let n = (u32::from(b[0]) << 16) | (u32::from(b[1]) << 8) | u32::from(b[2]);
        let chars = chunk.len() + 1;
        for i in 0..chars {
            let idx = ((n >> (18 - i * 6)) & 0x3F) as usize;
            out.push(ALPHABET[idx] as char);
        }
    }
    out
}

/// 把 32 字节地址主体编码成用户可见的 bounceable 地址。
pub fn encode_address(hash: &[u8; 32]) -> String {
    let mut raw = Vec::with_capacity(36);
    raw.push(0x11); // bounceable + workchain 0
    raw.push(0x00); // workchain id
    raw.extend_from_slice(hash);
    let checksum = crc16(&raw);
    // TON 把校验和按大端写入（实测：小端会让官方示例地址校验失败）。
    raw.extend_from_slice(&checksum.to_be_bytes());
    base64url(&raw)
}

/// `m/44'/607'/{account}'`（Ledger 的 TON app 约定）。
pub fn derive_address(seed: &[u8], path: &str) -> Result<String> {
    let privkey = crate::hdkey::derive_ed25519_private_key(seed, path)?;
    let pubkey = ed25519::public_key_bytes(&privkey)?;
    let key: [u8; 32] = pubkey
        .as_slice()
        .try_into()
        .map_err(|_| ChainError::AddressError("ed25519 公钥不是 32 字节".into()))?;
    Ok(encode_address(&state_init_hash(&key)))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn seed() -> Vec<u8> {
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        bip39::Mnemonic::parse(phrase).unwrap().to_seed("").to_vec()
    }

    #[test]
    fn address_shape() {
        let address = derive_address(&seed(), "m/44'/607'/0'/0'/0'/0'").unwrap();
        assert_eq!(address.len(), 48, "36 字节 base64url 无填充");
        assert!(address.starts_with("EQ"), "mainnet bounceable 以 EQ 开头");
        assert!(!address.contains('='), "不补 padding");
    }

    #[test]
    fn crc16_matches_the_ton_test_vector() {
        // TON 文档里的示例地址：解码后重算 CRC 必须与原值一致，
        // 再重编码必须逐字符还原（同时覆盖 base64url 与前缀）。
        let address = "EQCD39VS5jcptHL8vMjEXrzGaRcCVYto7HUn4bpAOg8xqB2N";
        let raw = decode_base64url(address);
        assert_eq!(raw.len(), 36);
        let expected = u16::from_be_bytes([raw[34], raw[35]]);
        assert_eq!(crc16(&raw[..34]), expected);

        let hash: [u8; 32] = raw[2..34].try_into().unwrap();
        assert_eq!(encode_address(&hash), address);
    }

    #[test]
    fn different_paths_give_different_addresses() {
        let a = derive_address(&seed(), "m/44'/607'/0'/0'/0'/0'").unwrap();
        let b = derive_address(&seed(), "m/44'/607'/0'/0'/1'/0'").unwrap();
        assert_ne!(a, b);
    }

    fn decode_base64url(text: &str) -> Vec<u8> {
        const ALPHABET: &[u8; 64] =
            b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
        let mut out = Vec::new();
        for chunk in text.as_bytes().chunks(4) {
            let mut n: u32 = 0;
            for (i, ch) in chunk.iter().enumerate() {
                let v = ALPHABET.iter().position(|c| c == ch).unwrap() as u32;
                n |= v << (18 - i * 6);
            }
            let bytes = chunk.len() - 1;
            for i in 0..bytes {
                out.push(((n >> (16 - i * 8)) & 0xFF) as u8);
            }
        }
        out
    }
}
