//! `crypto-account` 构造：手机显示、主机扫码导入账户。
//!
//! 线上结构（2026-10-28 与官方 JS 逐字节核对）：
//! `311(account) -> 403(pkh script expression) -> 303(hdkey) -> 304(keypath)`。
//! 注意 403 **直接**包住 303，中间没有 308 输出描述符；keypath 的组件是
//! 摊平的 `[index, hardened, ...]`；父指纹写成无符号整数而不是字节串。

use ciborium::value::Value;
use open_ledger_biz::errors::{ChainError, Result};
use open_ledger_biz::hdkey;
use open_ledger_crypto::{hash160, secp256k1};
use zeroize::Zeroize;

use crate::eth::address_from_private_key;
use crate::path::{components_to_cbor, int_value, parse_path, render_path};

const HDKEY_TAG: u64 = 303;
const KEYPATH_TAG: u64 = 304;
const PKH_SCRIPT_TAG: u64 = 403;

/// 一张账户码最多带多少个地址描述符（一页 5 个，给到 20 足够翻页）。
pub const MAX_ACCOUNTS_PER_CODE: usize = 20;

/// OKX 浏览器插件扫码导入 Keystone 时只接受这个类型（`Purpose.SYNC` 的白名单
/// 里虽然有 `crypto-hdkey` / `crypto-account`，但插件实际只传
/// `urTypes:[CryptoMultiAccounts]`，其它类型会被判为 `UNEXPECTED_QRCODE` 并重置扫描）。
pub const MULTI_ACCOUNTS_TYPE: &str = "crypto-multi-accounts";

/// OKX 校验同步码时逐个检查 10 个 ETH 账户（`m/44'/60'/i'/0/0`），少一个就整包拒绝。
pub const MULTI_ACCOUNTS_ETH_COUNT: u32 = 10;

/// OKX 还要求三条 BTC 账户级 xpub（legacy / nested segwit / native segwit）。
const MULTI_ACCOUNTS_BTC_PATHS: [&str; 3] = ["m/44'/0'/0'", "m/49'/0'/0'", "m/84'/0'/0'"];
const MULTI_ACCOUNTS_ETH_PATH: &str = "m/44'/60'/0'";

/// 一张账户码：dCBOR 字节 + 这一页每个账户的地址（给界面展示）。
pub struct CryptoAccountCode {
    pub cbor: Vec<u8>,
    pub addresses: Vec<[u8; 20]>,
}

/// 构造含一个账户的 `crypto-account` dCBOR。
pub fn build_crypto_account(seed: &[u8], path: &str) -> Result<Vec<u8>> {
    build_crypto_accounts(seed, path, 1)
}

/// 构造含 `count` 个连续账户（`path` 起、最后一个索引逐个 +1）的 `crypto-account`。
pub fn build_crypto_accounts(seed: &[u8], path: &str, count: usize) -> Result<Vec<u8>> {
    Ok(build_crypto_account_code(seed, path, count)?.cbor)
}

/// 构造一张账户码（`count` 个连续账户）并回传这一页的地址。
///
/// 主机按「页」取地址：MetaMask 的 QR 导入一次要 5 个（`getAddressesPage(0, 5)`），
/// 账户码里缺 index 1 就报 `Address not found for index 1`。所以一页必须把
/// 5 个地址描述符一起带上，而不是一个账户一张码。
pub fn build_crypto_account_code(
    seed: &[u8],
    path: &str,
    count: usize,
) -> Result<CryptoAccountCode> {
    let components = parse_path(path)?;
    if components.is_empty() {
        return Err(ChainError::InvalidPath(
            "account path must be below m".into(),
        ));
    }
    if count == 0 || count > MAX_ACCOUNTS_PER_CODE {
        return Err(ChainError::InvalidPath(format!(
            "account count must be 1..={MAX_ACCOUNTS_PER_CODE}"
        )));
    }
    let (base_index, hardened) = *components.last().expect("checked non-empty");
    if hardened {
        return Err(ChainError::InvalidPath(
            "account path must end in a non-hardened index".into(),
        ));
    }
    if base_index as usize + count > 0x8000_0000 {
        return Err(ChainError::InvalidPath("account index overflow".into()));
    }

    let master_fingerprint = fingerprint(seed, "m")?;
    let parent_components = &components[..components.len() - 1];
    let parent_fingerprint = fingerprint(seed, &render_path(parent_components))?;

    let mut outputs = Vec::with_capacity(count);
    let mut addresses = Vec::with_capacity(count);
    for offset in 0..count {
        let mut leaf = components.clone();
        *leaf.last_mut().expect("checked non-empty") = (base_index + offset as u32, false);
        let (output, address) = descriptor(seed, &leaf, &master_fingerprint, &parent_fingerprint)?;
        outputs.push(output);
        addresses.push(address);
    }

    let account = Value::Map(vec![
        (int_value(1), Value::Bytes(master_fingerprint.to_vec())),
        (int_value(2), Value::Array(outputs)),
    ]);

    let mut cbor = Vec::new();
    ciborium::ser::into_writer(&account, &mut cbor)
        .map_err(|e| ChainError::ParseError(format!("account CBOR: {e}")))?;
    Ok(CryptoAccountCode { cbor, addresses })
}

/// Keystone（OKX 插件）的「同步码」：`crypto-multi-accounts`。
///
/// OKX 不自己派生：它按路径取 key 再自己往下推。
/// `parseMultiAccounts` + 校验（2026-10-28 读插件源码确认）要求这一组 key：
///
/// - BTC 账户级 xpub：`m/44'/0'/0'`、`m/49'/0'/0'`、`m/84'/0'/0'`
/// - ETH 账户级 xpub：`m/44'/60'/0'`
/// - 10 个 ETH 账户叶公钥：`m/44'/60'/i'/0/0`（i = 0..9）
///
/// `device` 不要写成 `Keystone 3 Pro`：插件会对该型号 + 低版本弹固件升级提示。
/// `deviceId` 用主指纹的十六进制，保证同一钱包重复导入时能被识别为同一设备。
pub fn build_multi_accounts(seed: &[u8], device: &str, version: &str) -> Result<Vec<u8>> {
    let master_fingerprint = fingerprint(seed, "m")?;

    let mut paths: Vec<String> = MULTI_ACCOUNTS_BTC_PATHS
        .iter()
        .chain(std::iter::once(&MULTI_ACCOUNTS_ETH_PATH))
        .map(|path| (*path).to_string())
        .collect();
    for index in 0..MULTI_ACCOUNTS_ETH_COUNT {
        paths.push(format!("m/44'/60'/{index}'/0/0"));
    }

    let mut keys = Vec::with_capacity(paths.len());
    for path in &paths {
        let components = parse_path(path)?;
        let parent_fingerprint = parent_fingerprint(seed, &components)?;
        keys.push(account_key(
            seed,
            &components,
            &master_fingerprint,
            &parent_fingerprint,
        )?);
    }

    let account = Value::Map(vec![
        (
            int_value(1),
            int_value(u32::from_be_bytes(master_fingerprint) as i128),
        ),
        (int_value(2), Value::Array(keys)),
        (int_value(3), Value::Text(device.to_string())),
        (int_value(4), Value::Text(hex::encode(master_fingerprint))),
        (int_value(5), Value::Text(version.to_string())),
    ]);
    let mut cbor = Vec::new();
    ciborium::ser::into_writer(&account, &mut cbor)
        .map_err(|e| ChainError::ParseError(format!("account CBOR: {e}")))?;
    Ok(cbor)
}

/// 一个 `403(pkh) -> 303(hdkey) -> 304(keypath)` 输出描述符，同时给出地址。
fn descriptor(
    seed: &[u8],
    components: &[(u32, bool)],
    master_fingerprint: &[u8; 4],
    parent_fingerprint: &[u8; 4],
) -> Result<(Value, [u8; 20])> {
    let (mut private_key, chain_code) =
        hdkey::derive_secp256k1_extended(seed, &render_path(components))?;
    let public_key = secp256k1::public_key_bytes(&private_key, true)?;
    let address = address_from_private_key(&private_key)?;
    private_key.zeroize();

    let output = Value::Tag(
        PKH_SCRIPT_TAG,
        Box::new(hdkey_item(
            &public_key,
            &chain_code,
            components,
            master_fingerprint,
            parent_fingerprint,
        )),
    );
    Ok((output, address))
}

/// 单个 `303(hdkey)`（同步码里直接放它，不再套 `403`）。
fn account_key(
    seed: &[u8],
    components: &[(u32, bool)],
    master_fingerprint: &[u8; 4],
    parent_fingerprint: &[u8; 4],
) -> Result<Value> {
    let (mut private_key, chain_code) =
        hdkey::derive_secp256k1_extended(seed, &render_path(components))?;
    let public_key = secp256k1::public_key_bytes(&private_key, true)?;
    private_key.zeroize();
    Ok(hdkey_item(
        &public_key,
        &chain_code,
        components,
        master_fingerprint,
        parent_fingerprint,
    ))
}

fn hdkey_item(
    public_key: &[u8],
    chain_code: &[u8],
    components: &[(u32, bool)],
    master_fingerprint: &[u8; 4],
    parent_fingerprint: &[u8; 4],
) -> Value {
    let keypath = Value::Tag(
        KEYPATH_TAG,
        Box::new(Value::Map(vec![
            (int_value(1), components_to_cbor(components)),
            // `source_fingerprint` 必须是整数：OKX 的 `CryptoKeypath.fromDataItem`
            // 会拿它做 `writeUInt32BE(value)`，写成字节串会直接抛异常。
            (
                int_value(2),
                int_value(u32::from_be_bytes(*master_fingerprint) as i128),
            ),
        ])),
    );
    Value::Tag(
        HDKEY_TAG,
        Box::new(Value::Map(vec![
            (int_value(3), Value::Bytes(public_key.to_vec())),
            (int_value(4), Value::Bytes(chain_code.to_vec())),
            (int_value(6), keypath),
            (
                int_value(8),
                int_value(u32::from_be_bytes(*parent_fingerprint) as i128),
            ),
        ])),
    )
}

/// 路径父节点的指纹；账户级路径（如 `m/44'/60'/0'`）取 `m/44'/60'`。
fn parent_fingerprint(seed: &[u8], components: &[(u32, bool)]) -> Result<[u8; 4]> {
    if components.is_empty() {
        return Err(ChainError::InvalidPath(
            "account path must be below m".into(),
        ));
    }
    let parent = &components[..components.len() - 1];
    if parent.is_empty() {
        return Ok([0u8; 4]);
    }
    fingerprint(seed, &render_path(parent))
}

/// 账户地址（原始 20 字节），供界面在导出前展示。
pub fn account_address(seed: &[u8], path: &str) -> Result<[u8; 20]> {
    let mut private_key = hdkey::derive_secp256k1_private_key(seed, path)?;
    let result = address_from_private_key(&private_key);
    private_key.zeroize();
    result
}

/// 路径公钥的 HASH160 前 4 字节。
fn fingerprint(seed: &[u8], path: &str) -> Result<[u8; 4]> {
    let mut private_key = hdkey::derive_secp256k1_private_key(seed, path)?;
    let public_key = secp256k1::public_key_bytes(&private_key, true).map_err(ChainError::from);
    private_key.zeroize();
    let hash = hash160::hash(&public_key?);
    Ok([hash[0], hash[1], hash[2], hash[3]])
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ur::encode_frames;

    fn test_seed() -> Vec<u8> {
        let phrase =
            "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        let mnemonic = bip39::Mnemonic::parse(phrase).unwrap();
        mnemonic.to_seed("").to_vec()
    }

    #[test]
    fn account_wire_shape() {
        let cbor = build_crypto_account(&test_seed(), "m/44'/60'/0'/0/0").unwrap();
        // The UR layer validates dCBOR while wrapping it.
        encode_frames("crypto-account", &cbor, 0).unwrap();

        let value: Value = ciborium::de::from_reader(cbor.as_slice()).unwrap();
        let account = value.as_map().unwrap();
        assert_eq!(account.len(), 2, "master fingerprint + outputs");
        assert_eq!(account[0].1.as_bytes().unwrap().len(), 4);

        let outputs = account[1].1.as_array().unwrap();
        let Value::Tag(script_tag, inner) = &outputs[0] else {
            panic!("output must be tagged");
        };
        assert_eq!(*script_tag, PKH_SCRIPT_TAG);
        let Value::Tag(hd_tag, hd) = inner.as_ref() else {
            panic!("hdkey must be tagged");
        };
        assert_eq!(*hd_tag, HDKEY_TAG);

        let fields = hd.as_map().unwrap();
        let key = fields[0].1.as_bytes().unwrap();
        assert_eq!(key.len(), 33, "compressed public key");
        assert!(key[0] == 0x02 || key[0] == 0x03);
        assert_eq!(fields[1].1.as_bytes().unwrap().len(), 32, "chain code");
        assert!(matches!(fields[3].1, Value::Integer(_)), "parent fingerprint is an integer");
    }

    #[test]
    fn account_address_matches_eth_derivation() {
        let address = account_address(&test_seed(), "m/44'/60'/0'/0/0").unwrap();
        let hex = hex::encode(address);
        assert_eq!(hex, "9858effd232b4033e47d90003d41ec34ecaeda94");
    }

    #[test]
    fn one_code_carries_a_whole_page() {
        let seed = test_seed();
        let code = build_crypto_account_code(&seed, "m/44'/60'/0'/0/0", 5).unwrap();
        // dCBOR 规范化同样要过 UR 层这一关。
        encode_frames("crypto-account", &code.cbor, 0).unwrap();
        assert_eq!(code.addresses.len(), 5);
        assert_eq!(
            hex::encode(code.addresses[0]),
            "9858effd232b4033e47d90003d41ec34ecaeda94"
        );
        for offset in 0..5 {
            let path = format!("m/44'/60'/0'/0/{offset}");
            assert_eq!(code.addresses[offset], account_address(&seed, &path).unwrap());
        }

        let value: Value = ciborium::de::from_reader(code.cbor.as_slice()).unwrap();
        let account = value.as_map().unwrap();
        let outputs = account[1].1.as_array().unwrap();
        assert_eq!(outputs.len(), 5);

        let mut keys = Vec::new();
        for (offset, output) in outputs.iter().enumerate() {
            let Value::Tag(script_tag, inner) = output else {
                panic!("output must be tagged");
            };
            assert_eq!(*script_tag, PKH_SCRIPT_TAG);
            let Value::Tag(_, hd) = inner.as_ref() else {
                panic!("hdkey must be tagged");
            };
            let fields = hd.as_map().unwrap();
            keys.push(fields[0].1.as_bytes().unwrap().to_vec());

            let Value::Tag(_, keypath) = &fields[2].1 else {
                panic!("keypath must be tagged");
            };
            let components = keypath.as_map().unwrap()[0].1.as_array().unwrap();
            // 摊平数组：…, index, hardened
            let index = components[components.len() - 2].as_integer().unwrap();
            assert_eq!(i128::from(index.clone()), offset as i128);
        }
        assert_ne!(keys[0], keys[1], "each address needs its own key");
    }

    #[test]
    fn rejects_hardened_leaf_and_impossible_counts() {
        let seed = test_seed();
        assert!(build_crypto_accounts(&seed, "m/44'/60'/0'/0/0'", 5).is_err());
        assert!(build_crypto_accounts(&seed, "m/44'/60'/0'/0/0", 0).is_err());
        assert!(build_crypto_accounts(&seed, "m/44'/60'/0'/0/0", MAX_ACCOUNTS_PER_CODE + 1).is_err());
    }

    #[test]
    fn rejects_master_path() {
        assert!(build_crypto_account(&test_seed(), "m").is_err());
    }

    #[test]
    fn multi_accounts_carry_the_paths_okx_checks() {
        let seed = test_seed();
        let cbor = build_multi_accounts(&seed, "Open Ledger", "1.0.4").unwrap();
        // dCBOR 规范化同样要过 UR 层这一关。
        encode_frames(MULTI_ACCOUNTS_TYPE, &cbor, 60).unwrap();

        let value: Value = ciborium::de::from_reader(cbor.as_slice()).unwrap();
        let account = value.as_map().unwrap();
        assert_eq!(account.len(), 5, "fingerprint + keys + device + id + version");
        assert!(matches!(account[0].1, Value::Integer(_)), "fingerprint is an integer");

        let keys = account[1].1.as_array().unwrap();
        assert_eq!(keys.len() as u32, 3 + 1 + MULTI_ACCOUNTS_ETH_COUNT);

        let mut paths = Vec::new();
        for key in keys {
            let Value::Tag(tag, inner) = key else {
                panic!("key must be tagged for OKX");
            };
            assert_eq!(*tag, HDKEY_TAG);
            let fields = inner.as_map().unwrap();
            assert_eq!(fields[0].1.as_bytes().unwrap().len(), 33);
            assert_eq!(fields[1].1.as_bytes().unwrap().len(), 32);
            let Value::Tag(_, keypath) = &fields[2].1 else {
                panic!("keypath must be tagged");
            };
            let keypath_fields = keypath.as_map().unwrap();
            // OKX 会对 source fingerprint 调 `writeUInt32BE`，只认整数。
            assert!(
                matches!(keypath_fields[1].1, Value::Integer(_)),
                "source fingerprint must be an integer"
            );
            assert_eq!(keypath_fields[1].1, account[0].1);
            let components = crate::path::components_from_cbor(&keypath_fields[0].1)
                .expect("flat keypath components");
            paths.push(render_path(&components));
        }

        let mut expected = vec![
            "m/44'/0'/0'".to_string(),
            "m/49'/0'/0'".to_string(),
            "m/84'/0'/0'".to_string(),
            "m/44'/60'/0'".to_string(),
        ];
        for index in 0..MULTI_ACCOUNTS_ETH_COUNT {
            expected.push(format!("m/44'/60'/{index}'/0/0"));
        }
        assert_eq!(paths, expected);
    }
}
