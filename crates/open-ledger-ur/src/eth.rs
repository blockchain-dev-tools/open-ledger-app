//! `eth-sign-request` / `eth-signature` 的 dCBOR 结构与签名。
//!
//! 字段编号来自 Keystone 的 `bc-ur-registry-eth`（2026-10-28 用官方 JS
//! 逐字节核对）：1 请求 ID（tag 37 UUID）、2 待签数据、3 数据类型、
//! 4 chain id、5 派生路径（tag 304）、6 地址、7 来源。

use ciborium::value::Value;
use open_ledger_biz::errors::{ChainError, Result};
use open_ledger_biz::hdkey;
use open_ledger_crypto::{keccak256, secp256k1};
use zeroize::Zeroize;

use crate::path::{as_i128, components_from_cbor, int_value, render_path};

pub const ETH_SIGN_REQUEST_TYPE: &str = "eth-sign-request";
pub const ETH_SIGNATURE_TYPE: &str = "eth-signature";

const UUID_TAG: u64 = 37;
const KEYPATH_TAG: u64 = 304;

const MAX_SIGN_DATA: usize = 32 * 1024;
const MAX_ORIGIN_LEN: usize = 64;

/// 签名原文是一笔已编码交易（legacy 或 EIP-1559）；哈希就是 `keccak256(sign_data)`。
pub const DATA_TYPE_TRANSACTION: u32 = 1;
/// `eth_signTypedData` —— 一期不做（需要 JSON 解析与结构哈希）。
pub const DATA_TYPE_TYPED_DATA: u32 = 2;
/// 个人消息：`"\x19Ethereum Signed Message:\n" + len + message`。
pub const DATA_TYPE_PERSONAL_MESSAGE: u32 = 3;
/// 已编码的 typed transaction，哈希规则与 1 相同。
pub const DATA_TYPE_TYPED_TRANSACTION: u32 = 4;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EthSignRequest {
    pub request_id: Option<[u8; 16]>,
    pub sign_data: Vec<u8>,
    pub data_type: u32,
    pub chain_id: Option<u32>,
    /// 规范化后的 BIP-32 路径，例如 `m/44'/60'/0'/0/0`。
    pub path: String,
    pub address: Option<[u8; 20]>,
    pub origin: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EthSignatureOut {
    /// `r || s || v`。末字节 `v` 按宿主约定取值：typed transaction 是 `yParity`（0/1），
    /// legacy 交易是 EIP-155 的 `chainId * 2 + 35 + recid`（装不进一个字节时退回 27/28），
    /// 个人消息是 27/28。
    pub signature: [u8; 65],
    /// 本机按请求路径派生的地址（20 字节）。
    pub address: [u8; 20],
    /// 请求若带地址，是否与本机派生结果一致（不一致时不会走到签名）。
    pub address_matches: bool,
}

impl EthSignRequest {
    pub fn from_cbor(cbor: &[u8]) -> Result<Self> {
        let value: Value = ciborium::de::from_reader(cbor)
            .map_err(|e| ChainError::ParseError(format!("request CBOR: {e}")))?;
        let map = value
            .as_map()
            .ok_or_else(|| ChainError::ParseError("request must be a map".into()))?;

        let sign_data = field_bytes(map, 2, "sign-data")?.to_vec();
        if sign_data.is_empty() {
            return Err(ChainError::ParseError("sign-data is empty".into()));
        }
        if sign_data.len() > MAX_SIGN_DATA {
            return Err(ChainError::ParseError(format!(
                "sign-data too large ({} bytes)",
                sign_data.len()
            )));
        }

        let data_type = as_i128(field(map, 3, "data-type")?)? as u32;
        match data_type {
            DATA_TYPE_TRANSACTION | DATA_TYPE_PERSONAL_MESSAGE | DATA_TYPE_TYPED_TRANSACTION => {}
            DATA_TYPE_TYPED_DATA => {
                return Err(ChainError::ParseError(
                    "typed data (data-type 2) is not supported".into(),
                ))
            }
            other => {
                return Err(ChainError::ParseError(format!(
                    "unknown data-type {other}"
                )))
            }
        }

        let chain_id = optional(map, 4).map(|v| as_i128(v).map(|n| n as u32)).transpose()?;

        let keypath = field_tagged(map, 5, KEYPATH_TAG, "derivation-path")?;
        let keypath_map = keypath
            .as_map()
            .ok_or_else(|| ChainError::ParseError("keypath must be a map".into()))?;
        let components = components_from_cbor(field(keypath_map, 1, "components")?)?;
        if components.is_empty() {
            return Err(ChainError::ParseError("derivation path is empty".into()));
        }

        let address = match optional(map, 6) {
            Some(value) => {
                let bytes = value
                    .as_bytes()
                    .ok_or_else(|| ChainError::ParseError("address must be bytes".into()))?;
                if bytes.len() != 20 {
                    return Err(ChainError::ParseError(format!(
                        "address must be 20 bytes, got {}",
                        bytes.len()
                    )));
                }
                let mut out = [0u8; 20];
                out.copy_from_slice(bytes);
                Some(out)
            }
            None => None,
        };

        let origin = match optional(map, 7) {
            Some(value) => {
                let text = value
                    .as_text()
                    .ok_or_else(|| ChainError::ParseError("origin must be text".into()))?;
                if text.chars().count() > MAX_ORIGIN_LEN {
                    return Err(ChainError::ParseError("origin too long".into()));
                }
                Some(text.to_string())
            }
            None => None,
        };

        let request_id = match optional(map, 1) {
            Some(Value::Tag(tag, inner)) => {
                if *tag != UUID_TAG {
                    return Err(ChainError::ParseError(format!(
                        "request-id tag must be {UUID_TAG}, got {tag}"
                    )));
                }
                let bytes = inner
                    .as_bytes()
                    .ok_or_else(|| ChainError::ParseError("request-id must be bytes".into()))?;
                if bytes.len() != 16 {
                    return Err(ChainError::ParseError(format!(
                        "request-id must be 16 bytes, got {}",
                        bytes.len()
                    )));
                }
                let mut out = [0u8; 16];
                out.copy_from_slice(bytes);
                Some(out)
            }
            Some(_) => {
                return Err(ChainError::ParseError(
                    "request-id must be a tag-37 byte string".into(),
                ))
            }
            None => None,
        };

        Ok(Self {
            request_id,
            sign_data,
            data_type,
            chain_id,
            path: render_path(&components),
            address,
            origin,
        })
    }

    /// 设备要签的 32 字节摘要。
    pub fn signing_hash(&self) -> Result<[u8; 32]> {
        match self.data_type {
            DATA_TYPE_TRANSACTION | DATA_TYPE_TYPED_TRANSACTION => {
                Ok(keccak256::hash(&self.sign_data))
            }
            DATA_TYPE_PERSONAL_MESSAGE => {
                let prefix = format!(
                    "\x19Ethereum Signed Message:\n{}",
                    self.sign_data.len()
                );
                let mut payload = Vec::with_capacity(prefix.len() + self.sign_data.len());
                payload.extend_from_slice(prefix.as_bytes());
                payload.extend_from_slice(&self.sign_data);
                Ok(keccak256::hash(&payload))
            }
            _ => Err(ChainError::ParseError(
                "request data-type is not signable".into(),
            )),
        }
    }

    /// 用 `seed` 在请求路径上签名。
    ///
    /// 请求带地址时先比对，不一致直接拒绝（contract I15），绝不签名。
    pub fn sign(&self, seed: &[u8]) -> Result<EthSignatureOut> {
        let mut private_key = hdkey::derive_secp256k1_private_key(seed, &self.path)?;
        let result = (|| {
            let address = address_from_private_key(&private_key)?;
            let matches = self.address.map(|expected| expected == address);
            if matches == Some(false) {
                return Err(ChainError::AddressError(
                    "request address does not match the derived account".into(),
                ));
            }
            let hash = self.signing_hash()?;
            let raw = secp256k1::sign_prehash_recoverable(&private_key, &hash, |v| v)?;
            // `raw` = v || r || s；Keystone 的 eth-signature 是 r || s || v。
            let mut signature = [0u8; 65];
            signature[..32].copy_from_slice(&raw[1..33]);
            signature[32..64].copy_from_slice(&raw[33..65]);
            signature[64] = self.signature_v(raw[0]);
            Ok(EthSignatureOut {
                signature,
                address,
                address_matches: matches.unwrap_or(true),
            })
        })();
        private_key.zeroize();
        result
    }

    /// 把恢复位换算成宿主期望的 `v`。
    ///
    /// Rabby / `@ethereumjs/tx` 直接把签名末字节交给交易库：typed transaction 里它是
    /// `yParity`（只能 0/1）；legacy 交易则要求 `v = 27/28` 或 EIP-155 的
    /// `chainId * 2 + 35 + recid`，否则报
    /// `Legacy txs need either v = 27/28 or v >= 37 (EIP-155 replay protection)`。
    /// 单字节装不下 EIP-155 形式（`chainId > 110`）时退回 27/28。
    fn signature_v(&self, recovery_id: u8) -> u8 {
        if self.data_type == DATA_TYPE_TYPED_TRANSACTION {
            return recovery_id;
        }
        if self.data_type == DATA_TYPE_TRANSACTION {
            if let Some(chain_id) = self.chain_id {
                let eip155 = u64::from(chain_id) * 2 + 35 + u64::from(recovery_id);
                if let Ok(v) = u8::try_from(eip155) {
                    return v;
                }
            }
        }
        27 + recovery_id
    }
}

/// 地址的原始 20 字节（不做 EIP-55 校验和）。
pub fn address_from_private_key(private_key: &[u8]) -> Result<[u8; 20]> {
    let public_key = secp256k1::public_key_bytes(private_key, false)?;
    let hash = keccak256::hash(&public_key[1..]);
    let mut address = [0u8; 20];
    address.copy_from_slice(&hash[12..]);
    Ok(address)
}

/// 构造 `eth-signature` 的 dCBOR。
pub fn encode_eth_signature(
    request_id: &[u8; 16],
    signature: &[u8],
    origin: Option<&str>,
) -> Result<Vec<u8>> {
    if signature.len() != 65 {
        return Err(ChainError::ParseError(format!(
            "signature must be 65 bytes, got {}",
            signature.len()
        )));
    }
    let mut map = vec![
        (
            int_value(1),
            Value::Tag(UUID_TAG, Box::new(Value::Bytes(request_id.to_vec()))),
        ),
        (int_value(2), Value::Bytes(signature.to_vec())),
    ];
    if let Some(origin) = origin {
        if origin.chars().count() > MAX_ORIGIN_LEN {
            return Err(ChainError::ParseError("origin too long".into()));
        }
        map.push((int_value(3), Value::Text(origin.to_string())));
    }
    let mut out = Vec::new();
    ciborium::ser::into_writer(&Value::Map(map), &mut out)
        .map_err(|e| ChainError::ParseError(format!("signature CBOR: {e}")))?;
    Ok(out)
}

fn field<'a>(map: &'a [(Value, Value)], key: i128, name: &str) -> Result<&'a Value> {
    optional(map, key).ok_or_else(|| ChainError::ParseError(format!("missing {name} ({key})")))
}

fn optional(map: &[(Value, Value)], key: i128) -> Option<&Value> {
    let wanted = int_value(key);
    map.iter()
        .find(|(candidate, _)| *candidate == wanted)
        .map(|(_, value)| value)
}

fn field_bytes<'a>(map: &'a [(Value, Value)], key: i128, name: &str) -> Result<&'a [u8]> {
    field(map, key, name)?
        .as_bytes()
        .map(|bytes| bytes.as_slice())
        .ok_or_else(|| ChainError::ParseError(format!("{name} must be bytes")))
}

fn field_tagged<'a>(
    map: &'a [(Value, Value)],
    key: i128,
    expected_tag: u64,
    name: &str,
) -> Result<&'a Value> {
    match field(map, key, name)? {
        Value::Tag(tag, inner) => {
            if *tag != expected_tag {
                return Err(ChainError::ParseError(format!(
                    "{name} tag must be {expected_tag}, got {tag}"
                )));
            }
            Ok(inner)
        }
        _ => Err(ChainError::ParseError(format!(
            "{name} must be a tag-{expected_tag} item"
        ))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::path::{components_to_cbor, parse_path};

    fn test_seed() -> Vec<u8> {
        let phrase =
            "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        let mnemonic = bip39::Mnemonic::parse(phrase).unwrap();
        mnemonic.to_seed("").to_vec()
    }

    fn request_cbor(address: Option<[u8; 20]>) -> Vec<u8> {
        let path = components_to_cbor(&parse_path("m/44'/60'/0'/0/0").unwrap());
        let keypath = Value::Tag(
            304,
            Box::new(Value::Map(vec![
                (int_value(1), path),
                (int_value(2), Value::Bytes(vec![0x37, 0xb5, 0xee, 0xd4])),
            ])),
        );
        let mut map = vec![
            (
                int_value(1),
                Value::Tag(
                    37,
                    Box::new(Value::Bytes(vec![
                        0x9b, 0x1d, 0xeb, 0x4d, 0x3b, 0x7d, 0x4b, 0xad, 0x9b, 0xdd, 0x2b, 0x0d,
                        0x7b, 0x3d, 0xcb, 0x6d,
                    ])),
                ),
            ),
            (int_value(2), Value::Bytes(vec![0x02, 0xf8, 0x6c])),
            (int_value(3), int_value(DATA_TYPE_TRANSACTION as i128)),
            (int_value(4), int_value(1)),
            (int_value(5), keypath),
        ];
        if let Some(address) = address {
            map.push((int_value(6), Value::Bytes(address.to_vec())));
        }
        map.push((int_value(7), Value::Text("MetaMask".into())));
        let mut out = Vec::new();
        ciborium::ser::into_writer(&Value::Map(map), &mut out).unwrap();
        out
    }

    fn derived_address() -> [u8; 20] {
        // 0x9858EfFD232B4033E47d90003D41EC34EcaEda94 for the public test mnemonic.
        let private_key =
            hdkey::derive_secp256k1_private_key(&test_seed(), "m/44'/60'/0'/0/0").unwrap();
        address_from_private_key(&private_key).unwrap()
    }

    #[test]
    fn parses_request_fields() {
        let request = EthSignRequest::from_cbor(&request_cbor(None)).unwrap();
        assert_eq!(request.request_id.unwrap()[0], 0x9b);
        assert_eq!(request.data_type, DATA_TYPE_TRANSACTION);
        assert_eq!(request.chain_id, Some(1));
        assert_eq!(request.path, "m/44'/60'/0'/0/0");
        assert_eq!(request.origin.as_deref(), Some("MetaMask"));
        assert_eq!(request.signing_hash().unwrap(), keccak256::hash(&[0x02, 0xf8, 0x6c]));
    }

    #[test]
    fn signs_and_matches_address() {
        let expected = derived_address();
        let request = EthSignRequest::from_cbor(&request_cbor(Some(expected))).unwrap();
        let out = request.sign(&test_seed()).unwrap();
        assert!(out.address_matches);
        assert_eq!(out.address, expected);
        // chainId = 1 的 legacy 交易走 EIP-155：v = 1 * 2 + 35 + recid = 37/38。
        assert!(
            matches!(out.signature[64], 37 | 38),
            "v = {}",
            out.signature[64]
        );
    }

    fn request_cbor_with(data_type: u32, chain_id: Option<u32>) -> Vec<u8> {
        let path = components_to_cbor(&parse_path("m/44'/60'/0'/0/0").unwrap());
        let mut map = vec![
            (
                int_value(1),
                Value::Tag(37, Box::new(Value::Bytes(vec![0x9b; 16]))),
            ),
            (int_value(2), Value::Bytes(vec![0x02, 0xf8, 0x6c])),
            (int_value(3), int_value(data_type as i128)),
            (
                int_value(5),
                Value::Tag(304, Box::new(Value::Map(vec![(int_value(1), path)]))),
            ),
        ];
        if let Some(chain_id) = chain_id {
            map.insert(3, (int_value(4), int_value(chain_id as i128)));
        }
        let mut out = Vec::new();
        ciborium::ser::into_writer(&Value::Map(map), &mut out).unwrap();
        out
    }

    #[test]
    fn signature_v_follows_host_rules() {
        // legacy + chainId：EIP-155 形式（BSC chainId 56 → 147/148）。
        let out = EthSignRequest::from_cbor(&request_cbor_with(DATA_TYPE_TRANSACTION, Some(56)))
            .unwrap()
            .sign(&test_seed())
            .unwrap();
        assert!(
            matches!(out.signature[64], 147 | 148),
            "v = {}",
            out.signature[64]
        );

        // legacy 没带 chainId：27/28。
        let out = EthSignRequest::from_cbor(&request_cbor_with(DATA_TYPE_TRANSACTION, None))
            .unwrap()
            .sign(&test_seed())
            .unwrap();
        assert!(
            matches!(out.signature[64], 27 | 28),
            "v = {}",
            out.signature[64]
        );

        // chainId 太大、EIP-155 形式装不进一个字节：退回 27/28。
        let out = EthSignRequest::from_cbor(&request_cbor_with(DATA_TYPE_TRANSACTION, Some(300)))
            .unwrap()
            .sign(&test_seed())
            .unwrap();
        assert!(
            matches!(out.signature[64], 27 | 28),
            "v = {}",
            out.signature[64]
        );

        // typed transaction：末字节是 yParity，只能 0/1。
        let out =
            EthSignRequest::from_cbor(&request_cbor_with(DATA_TYPE_TYPED_TRANSACTION, Some(56)))
                .unwrap()
                .sign(&test_seed())
                .unwrap();
        assert!(out.signature[64] <= 1, "v = {}", out.signature[64]);

        // 个人消息：27/28。
        let out =
            EthSignRequest::from_cbor(&request_cbor_with(DATA_TYPE_PERSONAL_MESSAGE, Some(1)))
                .unwrap()
                .sign(&test_seed())
                .unwrap();
        assert!(
            matches!(out.signature[64], 27 | 28),
            "v = {}",
            out.signature[64]
        );
    }

    #[test]
    fn refuses_mismatched_address() {
        let request = EthSignRequest::from_cbor(&request_cbor(Some([0x22; 20]))).unwrap();
        let error = request.sign(&test_seed()).unwrap_err();
        assert!(matches!(error, ChainError::AddressError(_)));
    }

    #[test]
    fn rejects_typed_data() {
        let path = components_to_cbor(&parse_path("m/44'/60'/0'/0/0").unwrap());
        let map = vec![
            (int_value(2), Value::Bytes(vec![0x01])),
            (int_value(3), int_value(DATA_TYPE_TYPED_DATA as i128)),
            (
                int_value(5),
                Value::Tag(304, Box::new(Value::Map(vec![(int_value(1), path)]))),
            ),
        ];
        let mut out = Vec::new();
        ciborium::ser::into_writer(&Value::Map(map), &mut out).unwrap();
        assert!(EthSignRequest::from_cbor(&out).is_err());
    }

    #[test]
    fn personal_message_hash_matches_eip191() {
        let path = components_to_cbor(&parse_path("m/44'/60'/0'/0/0").unwrap());
        let map = vec![
            (int_value(2), Value::Bytes(b"hello".to_vec())),
            (int_value(3), int_value(DATA_TYPE_PERSONAL_MESSAGE as i128)),
            (
                int_value(5),
                Value::Tag(304, Box::new(Value::Map(vec![(int_value(1), path)]))),
            ),
        ];
        let mut out = Vec::new();
        ciborium::ser::into_writer(&Value::Map(map), &mut out).unwrap();
        let request = EthSignRequest::from_cbor(&out).unwrap();
        let expected = keccak256::hash(b"\x19Ethereum Signed Message:\n5hello");
        assert_eq!(request.signing_hash().unwrap(), expected);
    }

    #[test]
    fn signature_cbor_has_uuid_tag_and_origin() {
        let cbor = encode_eth_signature(&[0x11; 16], &[0x22; 65], Some("MetaMask")).unwrap();
        let value: Value = ciborium::de::from_reader(cbor.as_slice()).unwrap();
        let map = value.as_map().unwrap();
        assert!(matches!(map[0].1, Value::Tag(37, _)));
        assert_eq!(map[1].1.as_bytes().unwrap().len(), 65);
        assert_eq!(map[2].1.as_text(), Some("MetaMask"));
    }

    #[test]
    fn signature_length_is_enforced() {
        assert!(encode_eth_signature(&[0u8; 16], &[0u8; 64], None).is_err());
    }
}
