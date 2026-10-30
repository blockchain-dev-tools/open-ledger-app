//! Bitcoin 链 App（阶段 3）。
//!
//! 协议实现状态：**非标准实现，真实主机不可用**。
//!
//! Ledger 官方有两套 Bitcoin APDU 协议，本模块的编号组合与两者都不匹配：
//!
//! - legacy app（`LedgerHQ/app-bitcoin-legacy`）：`CLA 0xE0`，
//!   `0x40 GET_WALLET_PUBLIC_KEY` / `0x44 HASH_INPUT_START` /
//!   `0x48 HASH_INPUT_FINALIZE_FULL` / `0x4A HASH_SIGN`，摘要由设备自己算。
//! - 现行 app（`LedgerHQ/app-bitcoin`，协议 2.1.0+）：`CLA 0xE1`，
//!   `0x00 GET_EXTENDED_PUBKEY` / `0x03 GET_WALLET_ADDRESS` / `0x04 SIGN_PSBT`，
//!   `P1` 必须为 0、`P2` 是协议版本；`SIGN_PSBT` 是 Merkleized 交互协议，
//!   设备会反向请求 `GET_PREIMAGE` / `GET_MERKLE_LEAF_PROOF`。
//!
//! 本模块使用 `CLA 0xE1`（现行 app 的 CLA）+ legacy 编号，且 `0x44` 的负载是
//! 我们自己定义的「主机算好 32 字节摘要，设备直接签」。两套官方协议都不会发出
//! 这个组合，所以真实主机拿到的是 `6D00`，只有本仓的参考主机能用。
//!
//! 由此带来的约束：
//!
//! - 签名是**盲签**：确认页必须显式声明 `blind-signing` 风险，`parse_status`
//!   只能是 `Partial`（见 `handle_sign`）；
//! - 与标准对齐的工作见 T-028（`SIGN_PSBT` 或 legacy `HASH_INPUT` 流程）；
//! - **不得再占用官方编号并赋予不同语义**：扩展必须换编号并在本文档首行标明。
//!
//! 具体命令：
//!
//! - `E1 40`：P1 = 是否在设备上确认地址（0/1），P2 = 地址格式（0 legacy /
//!   1 p2sh / 2 bech32 / 4 bech32m），按路径派生公钥后编码成对应类型。
//! - `E1 44`（自有扩展 `SIGN_DIGEST`）：`[path][input_count][sighash(32)]*count`，
//!   一次审批为多个输入产出签名，按输入顺序拼接返回。P1 是 sighash type：
//!   Taproot（`m/86'`）把它作为 BIP-341 hash_type 传给宿主（非 0 时签名消息
//!   多一个字节），其余类型沿用 65 字节紧凑 ECDSA 输出。
//!
//! 与 ETH 一样，模块不接触 seed：公钥向宿主请求，签名由宿主在批准后执行。

use chain_app_api::{
    AppDescriptor, AppError, ChainApp, Curve, DerivationRule, DerivationScheme, Effect, Event,
    ExchangeId, Field, FieldValue, FinishStatus, KeyOutput, NetworkId, OperationKind,
    ParseStatus, PublicKeyRequest, ReviewAction, ReviewDocument, ReviewOutcome, ReviewRequest,
    ReviewSection, Risk, RiskLevel, RiskSource, ServiceResult, SessionConfig, SignOperation,
    SignPlan, SignScheme, Wire, API_VERSION,
};
use open_ledger_crypto::{base58, bech32, hash160, secp256k1};

pub mod sw {
    pub const OK: u16 = 0x9000;
    pub const DENIED: u16 = 0x6985;
    pub const WRONG_DATA: u16 = 0x6A80;
    pub const WRONG_P1_P2: u16 = 0x6A86;
    pub const UNKNOWN_INS: u16 = 0x6D00;
    pub const CLA_NOT_SUPPORTED: u16 = 0x6E00;
    pub const UNKNOWN: u16 = 0x6F00;
}

pub const MODULE_ID: &str = "openledger.bitcoin";

const CLA_BTC: u8 = 0xE1;
/// `0x40` 沿用 legacy 编号，但在官方现行 app 里 `0x40` 未分配（见模块文档）。
const INS_GET_PUBLIC_KEY: u8 = 0x40;
/// 自有扩展：主机交摘要、设备直接签。官方现行 app 的 `0x04` 是 `SIGN_PSBT`，
/// legacy 的 `0x44` 是 `HASH_INPUT_START` —— 两者语义都不是本命令。
const INS_SIGN_DIGEST: u8 = 0x44;

/// 一笔交易最多接受的输入数；超过即拒，避免一次审批绑过多签名。
const MAX_INPUTS: usize = 16;

/// Bitcoin 网络。只影响地址编码、默认 coin type 与审阅文案，不改变密钥。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Network {
    Mainnet,
    Testnet,
    Regtest,
    Signet,
}

impl Network {
    /// `P2` 高 4 位：0 主网 / 1 testnet / 2 regtest / 3 signet。
    fn from_code(code: u8) -> Option<Self> {
        match code {
            0x00 => Some(Network::Mainnet),
            0x01 => Some(Network::Testnet),
            0x02 => Some(Network::Regtest),
            0x03 => Some(Network::Signet),
            _ => None,
        }
    }

    fn hrp(self) -> &'static str {
        match self {
            Network::Mainnet => "bc",
            Network::Testnet | Network::Signet => "tb",
            Network::Regtest => "bcrt",
        }
    }

    /// BIP-44 coin type：主网 `0'`，其余测试网络 `1'`。
    fn coin_type(self) -> u32 {
        match self {
            Network::Mainnet => 0,
            Network::Testnet | Network::Regtest | Network::Signet => 1,
        }
    }

    /// P2PKH 版本字节：主网 `0x00`，测试网络 `0x6F`。
    fn p2pkh_version(self) -> u8 {
        match self {
            Network::Mainnet => 0x00,
            _ => 0x6F,
        }
    }

    /// P2SH 版本字节：主网 `0x05`，测试网络 `0xC4`。
    fn p2sh_version(self) -> u8 {
        match self {
            Network::Mainnet => 0x05,
            _ => 0xC4,
        }
    }

    /// 审阅页里展示的网络名。
    fn display_name(self) -> &'static str {
        match self {
            Network::Mainnet => "Bitcoin",
            Network::Testnet => "Bitcoin Testnet",
            Network::Regtest => "Bitcoin Regtest",
            Network::Signet => "Bitcoin Signet",
        }
    }
}

/// 解析 `P2`：高 4 位是网络，低 4 位是地址格式。
///
/// 低 4 位沿用官方 app-bitcoin 的 `P2_ADDR_FORMAT_*`，所以真实主机（发 `P2=0`
/// 或 `0x02`）的行为与主网逐字节一致；网络位只有我们自己使用
/// （见 ADR-020 的落地修订）。
fn parse_p2(p2: u8) -> Result<(Network, AddressType), u16> {
    let network = Network::from_code(p2 >> 4).ok_or(sw::WRONG_P1_P2)?;
    let address_type = AddressType::from_p2(p2 & 0x0F).ok_or(sw::WRONG_DATA)?;
    Ok((network, address_type))
}

/// 本机账户页可选的地址类型，按 `account_profile_index` 索引。
///
/// 下标 0 必须保持 P2WPKH：升级前创建的 BTC 账户就是它，换掉等于换地址。
const ACCOUNT_PROFILES: [AddressType; 4] = [
    AddressType::NativeSegwit,
    AddressType::Legacy,
    AddressType::NestedSegwit,
    AddressType::Taproot,
];

/// Bitcoin 的四种单签地址类型。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum AddressType {
    Legacy,
    NestedSegwit,
    NativeSegwit,
    Taproot,
}

impl AddressType {
    /// BIP-43 purpose，决定派生路径。
    fn purpose(self) -> u32 {
        match self {
            AddressType::Legacy => 44,
            AddressType::NestedSegwit => 49,
            AddressType::NativeSegwit => 84,
            AddressType::Taproot => 86,
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            AddressType::Legacy => "p2pkh",
            AddressType::NestedSegwit => "p2sh-p2wpkh",
            AddressType::NativeSegwit => "p2wpkh",
            AddressType::Taproot => "p2tr",
        }
    }

    fn from_purpose(purpose: u32) -> Option<Self> {
        match purpose {
            44 => Some(AddressType::Legacy),
            49 => Some(AddressType::NestedSegwit),
            84 => Some(AddressType::NativeSegwit),
            86 => Some(AddressType::Taproot),
            _ => None,
        }
    }

    /// 官方 app-bitcoin 的 `P2_ADDR_FORMAT_*`：0 legacy / 1 p2sh / 2 bech32 /
    /// 3 cashaddr / 4 bech32m。cashaddr（BCH）不支持，返回 `None`。
    fn from_p2(p2: u8) -> Option<Self> {
        match p2 {
            0x00 => Some(AddressType::Legacy),
            0x01 => Some(AddressType::NestedSegwit),
            0x02 => Some(AddressType::NativeSegwit),
            0x04 => Some(AddressType::Taproot),
            _ => None,
        }
    }

    /// 路径 purpose；认不出时返回 `None`（不能默认成某种格式，否则会返回错误地址）。
    fn from_path(path: &[u32]) -> Option<Self> {
        let purpose = path.first()?;
        if *purpose < 0x8000_0000 {
            return None;
        }
        Self::from_purpose(purpose - 0x8000_0000)
    }

    /// 33 字节压缩公钥 → 地址。网络只换前缀，不换密钥。
    fn encode(self, compressed_pubkey: &[u8], network: Network) -> Option<String> {
        if compressed_pubkey.len() != 33 {
            return None;
        }
        Some(match self {
            AddressType::Legacy => {
                let mut payload = Vec::with_capacity(21);
                payload.push(network.p2pkh_version());
                payload.extend_from_slice(&hash160::hash(compressed_pubkey));
                base58::encode_check(&payload)
            }
            AddressType::NestedSegwit => {
                let mut script = Vec::with_capacity(22);
                script.push(0x00);
                script.push(0x14);
                script.extend_from_slice(&hash160::hash(compressed_pubkey));
                let mut payload = Vec::with_capacity(21);
                payload.push(network.p2sh_version());
                payload.extend_from_slice(&hash160::hash(&script));
                base58::encode_check(&payload)
            }
            AddressType::NativeSegwit => bech32::encode(network.hrp(), 0, &hash160::hash(compressed_pubkey)),
            AddressType::Taproot => {
                let output_key = secp256k1::taproot_output_key(&compressed_pubkey[1..]).ok()?;
                bech32::encode_segwit(network.hrp(), 1, &output_key)
            }
        })
    }
}

struct Apdu {
    cla: u8,
    ins: u8,
    p1: u8,
    p2: u8,
    data: Vec<u8>,
}

impl Apdu {
    fn parse(bytes: &[u8]) -> Option<Self> {
        if bytes.len() < 4 {
            return None;
        }
        let lc = *bytes.get(4)? as usize;
        let end = 5 + lc;
        if bytes.len() < end {
            return None;
        }
        Some(Self {
            cla: bytes[0],
            ins: bytes[1],
            p1: bytes[2],
            p2: bytes[3],
            data: bytes[5..end].to_vec(),
        })
    }
}

fn status(code: u16) -> Vec<u8> {
    code.to_be_bytes().to_vec()
}

enum Stage {
    Idle,
    AwaitKey,
    AwaitReview,
}

struct Pending {
    exchange_id: ExchangeId,
    path: Vec<u32>,
    address: String,
    address_type: AddressType,
    network: Network,
    /// 待签摘要；`None` 表示这是地址查询。
    sighashes: Option<Vec<[u8; 32]>>,
    /// 地址查询时是否要用户确认（P1 = 1）。
    display: bool,
    /// Taproot 的 BIP-341 hash_type；由 P1 携带。
    hash_type: u8,
}

pub struct BitcoinModule {
    stage: Stage,
    pending: Option<Pending>,
    /// 本机账户请求的 `request_id` 与所选地址类型（`LocalCommand::DeriveAccount`）。
    local: Option<(u64, AddressType)>,
}

impl Default for BitcoinModule {
    fn default() -> Self {
        Self::new()
    }
}

impl BitcoinModule {
    pub fn new() -> Self {
        Self {
            stage: Stage::Idle,
            pending: None,
            local: None,
        }
    }

    fn emit(&self, exchange_id: ExchangeId, payload: Vec<u8>) -> Effect {
        Effect::Emit {
            wire: Wire::LedgerApdu,
            exchange_id,
            payload,
            state: chain_app_api::OperationState::Final,
        }
    }

    fn handle_apdu(&mut self, exchange_id: ExchangeId, bytes: &[u8]) -> Result<Effect, AppError> {
        let apdu =
            Apdu::parse(bytes).ok_or_else(|| AppError::BadRequest("truncated APDU".into()))?;
        if apdu.cla != CLA_BTC {
            return Ok(self.emit(exchange_id, status(sw::CLA_NOT_SUPPORTED)));
        }
        match apdu.ins {
            INS_GET_PUBLIC_KEY => self.handle_get_public_key(
                exchange_id,
                apdu.p1,
                apdu.p2,
                &apdu.data,
            ),
            INS_SIGN_DIGEST => self.handle_sign(exchange_id, apdu.p1, apdu.p2, &apdu.data),
            _ => Ok(self.emit(exchange_id, status(sw::UNKNOWN_INS))),
        }
    }

    /// `P1` = 是否在设备上确认地址，`P2` = 网络（高 4 位）+ 地址格式（低 4 位）。
    fn handle_get_public_key(
        &mut self,
        exchange_id: ExchangeId,
        p1: u8,
        p2: u8,
        data: &[u8],
    ) -> Result<Effect, AppError> {
        if p1 > 1 {
            return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2)));
        }
        let (network, address_type) = match parse_p2(p2) {
            Ok(parsed) => parsed,
            Err(code) => return Ok(self.emit(exchange_id, status(code))),
        };
        let (path, rest) = match split_path(data, network) {
            Some(split) => split,
            None => return Ok(self.emit(exchange_id, status(sw::WRONG_DATA))),
        };
        if !rest.is_empty() {
            return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
        }
        self.pending = Some(Pending {
            exchange_id,
            path: path.clone(),
            address: String::new(),
            address_type,
            network,
            sighashes: None,
            display: p1 == 1,
            hash_type: 0,
        });
        self.stage = Stage::AwaitKey;
        Ok(Effect::NeedPublicKey {
            service_id: 1,
            request: PublicKeyRequest {
                derivation_scheme: DerivationScheme::Bip32Secp256k1,
                curve: Curve::Secp256k1,
                path,
                output: KeyOutput::CompressedSecp256k1,
                include_chain_code: false,
            },
        })
    }

    /// `P1` = sighash type（Taproot 用），`P2` 只允许携带网络位（低 4 位必须为 0）。
    fn handle_sign(
        &mut self,
        exchange_id: ExchangeId,
        p1: u8,
        p2: u8,
        data: &[u8],
    ) -> Result<Effect, AppError> {
        let Some(network) = Network::from_code(p2 >> 4) else {
            return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2)));
        };
        if p2 & 0x0F != 0 {
            return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2)));
        }
        let (path, rest) = match split_path(data, network) {
            Some(split) => split,
            None => return Ok(self.emit(exchange_id, status(sw::WRONG_DATA))),
        };
        if rest.is_empty() {
            return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
        }
        let count = rest[0] as usize;
        let digests = &rest[1..];
        if count == 0 || count > MAX_INPUTS || digests.len() != count * 32 {
            return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
        }
        // 签名类型只能由路径 purpose 决定：拿 m/84 的密钥做 Schnorr 签不出有效签名。
        let Some(address_type) = AddressType::from_path(&path) else {
            return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
        };
        let mut sighashes = Vec::with_capacity(count);
        for chunk in digests.as_chunks::<32>().0 {
            sighashes.push(*chunk);
        }

        self.pending = Some(Pending {
            exchange_id,
            path: path.clone(),
            address: String::new(),
            address_type,
            network,
            sighashes: Some(sighashes),
            display: false,
            hash_type: p1,
        });
        self.stage = Stage::AwaitKey;
        Ok(Effect::NeedPublicKey {
            service_id: 2,
            request: PublicKeyRequest {
                derivation_scheme: DerivationScheme::Bip32Secp256k1,
                curve: Curve::Secp256k1,
                path,
                output: KeyOutput::CompressedSecp256k1,
                include_chain_code: false,
            },
        })
    }

    fn handle_local(
        &mut self,
        request_id: u64,
        command: chain_app_api::LocalCommand,
    ) -> Result<Effect, AppError> {
        match command {
            chain_app_api::LocalCommand::DeriveAccount {
                account_profile_index,
                address_index,
            } if address_index <= 1000 => {
                let Some(address_type) =
                    ACCOUNT_PROFILES.get(usize::from(account_profile_index)).copied()
                else {
                    return Ok(Effect::LocalReply {
                        request_id,
                        payload: Vec::new(),
                    });
                };
                self.local = Some((request_id, address_type));
                self.stage = Stage::AwaitKey;
                Ok(Effect::NeedPublicKey {
                    service_id: 9,
                    request: PublicKeyRequest {
                        derivation_scheme: DerivationScheme::Bip32Secp256k1,
                        curve: Curve::Secp256k1,
                        path: account_path(address_type, address_index),
                        output: KeyOutput::CompressedSecp256k1,
                        include_chain_code: false,
                    },
                })
            }
            _ => Ok(Effect::LocalReply {
                request_id,
                payload: Vec::new(),
            }),
        }
    }

    fn handle_service_result(&mut self, result: ServiceResult) -> Result<Effect, AppError> {
        // 本机账户派生：结果直接回给 UI，不涉及 APDU。账户页固定主网。
        if let Some((request_id, address_type)) = self.local.take() {
            self.stage = Stage::Idle;
            let payload = match result {
                ServiceResult::PublicKey(key) => {
                    match address_type.encode(&key.bytes, Network::Mainnet) {
                        Some(address) => format!(
                            "{{\"address\":\"{address}\",\"public_key\":\"{}\",\"address_type\":\"{}\"}}",
                            hex::encode(&key.bytes),
                            address_type.as_str()
                        )
                        .into_bytes(),
                        None => Vec::new(),
                    }
                }
                _ => Vec::new(),
            };
            return Ok(Effect::LocalReply {
                request_id,
                payload,
            });
        }
        let key = match result {
            ServiceResult::PublicKey(key) => key,
            ServiceResult::Failed(_) => {
                let exchange_id = self.pending.take().map(|p| p.exchange_id).unwrap_or(1);
                self.stage = Stage::Idle;
                return Ok(self.emit(exchange_id, status(sw::UNKNOWN)));
            }
            ServiceResult::Storage(_) | ServiceResult::SharedSecret(_) => {
                return Err(AppError::InvalidEvent("unexpected storage result".into()))
            }
        };
        let address = match self.pending.as_ref().and_then(|pending| {
            pending.address_type.encode(&key.bytes, pending.network)
        }) {
            Some(address) => address,
            None => {
                let exchange_id = self.pending.take().map(|p| p.exchange_id).unwrap_or(1);
                self.stage = Stage::Idle;
                return Ok(self.emit(exchange_id, status(sw::UNKNOWN)));
            }
        };

        let (exchange_id, path, sighashes, display, hash_type, network_name) = {
            let pending = self
                .pending
                .as_mut()
                .ok_or_else(|| AppError::InvalidEvent("no pending request".into()))?;
            pending.address = address.clone();
            (
                pending.exchange_id,
                pending.path.clone(),
                pending.sighashes.clone(),
                pending.display,
                pending.hash_type,
                pending.network.display_name(),
            )
        };

        let Some(sighashes) = sighashes else {
            if !display {
                // 地址查询：ASCII 地址 + 9000（与迁移前的线格式一致）。
                let mut payload = address.into_bytes();
                payload.extend_from_slice(&status(sw::OK));
                self.pending = None;
                self.stage = Stage::Idle;
                return Ok(self.emit(exchange_id, payload));
            }
            // P1 = 1：与官方 app 一样，先在设备上显示地址让用户核对。
            self.stage = Stage::AwaitReview;
            return Ok(Effect::NeedReview {
                service_id: 4,
                request: Box::new(ReviewRequest {
                    document: ReviewDocument {
                        operation: OperationKind::AddressConfirmation,
                        network: NetworkId {
                            name: network_name.into(),
                            chain_id: None,
                        },
                        account: Some(address.clone()),
                        sections: vec![ReviewSection {
                            title_key: "review.section.bitcoin".into(),
                            fields: vec![Field {
                                label_key: "review.field.address".into(),
                                value: FieldValue::Address {
                                    value: address,
                                    network: network_name.into(),
                                    role: "account".into(),
                                },
                            }],
                        }],
                        risks: vec![],
                        parse_status: ParseStatus::Complete,
                    },
                    action: ReviewAction::DisplayAddress {
                        derivation_scheme: DerivationScheme::Bip32Secp256k1,
                        curve: Curve::Secp256k1,
                        path,
                    },
                }),
            });
        };

        let operations: Vec<SignOperation> = sighashes
            .iter()
            .enumerate()
            .map(|(index, digest)| SignOperation {
                operation_id: index as u32 + 1,
                derivation_scheme: DerivationScheme::Bip32Secp256k1,
                curve: Curve::Secp256k1,
                path: path.clone(),
                scheme: if path_is_taproot(&path) {
                    SignScheme::SchnorrTaprootKeyPath { hash_type }
                } else {
                    SignScheme::EcdsaPrehash {
                        digest_len: 32,
                        low_s: true,
                    }
                },
                input: digest.to_vec(),
                public_parameters: Vec::new(),
            })
            .collect();

        self.stage = Stage::AwaitReview;
        Ok(Effect::NeedReview {
            service_id: 3,
            request: Box::new(ReviewRequest {
                document: ReviewDocument {
                    operation: OperationKind::Transaction,
                    network: NetworkId {
                        name: network_name.into(),
                        chain_id: None,
                    },
                    account: Some(address.clone()),
                    sections: vec![ReviewSection {
                        title_key: "review.section.bitcoin".into(),
                        fields: vec![
                            Field {
                                label_key: "review.field.address".into(),
                                value: FieldValue::Address {
                                    value: address,
                                    network: network_name.into(),
                                    role: "account".into(),
                                },
                            },
                            Field {
                                label_key: "review.field.inputs".into(),
                                value: FieldValue::Text {
                                    value: sighashes.len().to_string(),
                                },
                            },
                            Field {
                                label_key: "review.field.first_sighash".into(),
                                value: FieldValue::Bytes {
                                    value: sighashes[0].to_vec(),
                                },
                            },
                        ],
                    }],
                    // 设备只拿到摘要，没有任何可解析的交易内容：这是盲签，
                    // 必须显式声明，不能伪装成「已审阅的交易」。
                    risks: vec![Risk {
                        code: "blind-signing".into(),
                        severity: RiskLevel::Critical,
                        parameters: vec![(
                            "reason".into(),
                            "host supplied digests; transaction not parsed".into(),
                        )],
                        source: RiskSource::Module,
                    }],
                    parse_status: ParseStatus::Partial,
                },
                action: ReviewAction::Sign(SignPlan { operations }),
            }),
        })
    }

    fn handle_review(&mut self, outcome: ReviewOutcome) -> Result<Effect, AppError> {
        let pending = self
            .pending
            .take()
            .ok_or_else(|| AppError::InvalidEvent("no pending review".into()))?;
        self.stage = Stage::Idle;

        // 地址确认：批准后把地址回给主机，拒绝/超时回 6985。
        let Some(sighashes) = pending.sighashes.as_ref() else {
            let payload = match outcome {
                ReviewOutcome::Approved { .. } => {
                    let mut out = pending.address.into_bytes();
                    out.extend_from_slice(&status(sw::OK));
                    out
                }
                ReviewOutcome::Rejected | ReviewOutcome::TimedOut => status(sw::DENIED),
                ReviewOutcome::Failed(_) => status(sw::UNKNOWN),
            };
            return Ok(self.emit(pending.exchange_id, payload));
        };

        let expected = sighashes.len();
        let signature_len = if path_is_taproot(&pending.path) { 64 } else { 65 };

        let payload = match outcome {
            ReviewOutcome::Approved { signatures } => {
                if signatures.len() != expected {
                    status(sw::UNKNOWN)
                } else {
                    let mut out = Vec::with_capacity(expected * signature_len + 2);
                    let mut complete = true;
                    for signature in &signatures {
                        if path_is_taproot(&pending.path) {
                            if signature.bytes.len() != 64 {
                                complete = false;
                                break;
                            }
                            out.extend_from_slice(&signature.bytes);
                            continue;
                        }
                        match (&signature.bytes[..], signature.recovery_id) {
                            (bytes, Some(recovery)) if bytes.len() == 64 => {
                                out.push(27 + recovery);
                                out.extend_from_slice(bytes);
                            }
                            _ => {
                                complete = false;
                                break;
                            }
                        }
                    }
                    if complete {
                        out.extend_from_slice(&status(sw::OK));
                        out
                    } else {
                        status(sw::UNKNOWN)
                    }
                }
            }
            ReviewOutcome::Rejected | ReviewOutcome::TimedOut => status(sw::DENIED),
            ReviewOutcome::Failed(_) => status(sw::UNKNOWN),
        };
        Ok(self.emit(pending.exchange_id, payload))
    }
}

impl ChainApp for BitcoinModule {
    fn open(&mut self, _config: SessionConfig) -> Result<(), AppError> {
        Ok(())
    }

    fn step(&mut self, event: Event) -> Result<Effect, AppError> {
        match event {
            Event::Wire {
                exchange_id,
                payload,
                ..
            } => match self.stage {
                Stage::Idle => self.handle_apdu(exchange_id, &payload),
                _ => Err(AppError::InvalidEvent("busy".into())),
            },
            Event::ServiceResult { result, .. } => self.handle_service_result(result),
            Event::ReviewResult { outcome, .. } => self.handle_review(outcome),
            Event::Delivered { .. } => Ok(Effect::Finished {
                status: FinishStatus::Delivered,
            }),
            Event::Cancel { .. } => {
                self.pending = None;
                self.local = None;
                self.stage = Stage::Idle;
                Ok(Effect::Finished {
                    status: FinishStatus::Cancelled,
                })
            }
            Event::Local {
                request_id,
                command,
            } => self.handle_local(request_id, command),
        }
    }

    fn close(&mut self, _reason: chain_app_api::CancelReason) {
        self.pending = None;
        self.local = None;
        self.stage = Stage::Idle;
    }
}

/// 账户路径：`m/{44|49|84|86}'/0'/0'/0/{address_index}`。
fn account_path(address_type: AddressType, index: u32) -> Vec<u32> {
    vec![
        0x8000_0000 + address_type.purpose(),
        0x8000_0000,
        0x8000_0000,
        0,
        index,
    ]
}

/// 路径是否派生出 Taproot 账户（`m/86'/…`）。
fn path_is_taproot(path: &[u32]) -> bool {
    matches!(AddressType::from_path(path), Some(AddressType::Taproot))
}

/// 默认路径 `m/84'/{coin}'/0'/0/0`：主网 `0'`，testnet/regtest/signet `1'`。
fn default_path(network: Network) -> Vec<u32> {
    vec![
        0x8000_0000 + 84,
        0x8000_0000 + network.coin_type(),
        0x8000_0000,
        0,
        0,
    ]
}

/// `[count][u32 BE]*` → 路径；空数据用该网络的默认 BIP-84 路径。
fn split_path(data: &[u8], network: Network) -> Option<(Vec<u32>, &[u8])> {
    if data.is_empty() {
        return Some((default_path(network), &[]));
    }
    let count = data[0] as usize;
    let end = 1 + count.checked_mul(4)?;
    if count == 0 || data.len() < end {
        return None;
    }
    let mut path = Vec::with_capacity(count);
    for chunk in data[1..end].as_chunks::<4>().0 {
        path.push(u32::from_be_bytes(*chunk));
    }
    Some((path, &data[end..]))
}

pub fn descriptor() -> AppDescriptor {
    AppDescriptor {
        module_id: MODULE_ID.into(),
        module_version: "0.2.0".into(),
        api_version: API_VERSION,
        review_schema_version: 1,
        storage_schema_version: 1,
        protocol_profiles: vec![chain_app_api::ProtocolProfile {
            name: "Bitcoin".into(),
            version: "2.4.0".into(),
            wire: Wire::LedgerApdu,
            supported: vec![
                "E1 40 GET_WALLET_PUBLIC_KEY (legacy numbering on the current app's CLA; non-standard)".into(),
                "E1 44 SIGN_DIGEST (own extension: host supplies digests; blind signing)".into(),
            ],
            unsupported: vec![
                "cashaddr (BCH)".into(),
                "E1 03 GET_WALLET_ADDRESS / E1 04 SIGN_PSBT (official 2.1.0+ protocol)".into(),
                "legacy HASH_INPUT_START / HASH_INPUT_FINALIZE_FULL / HASH_SIGN flow".into(),
            ],
            vector_sources: vec![
                "tool/e2e/tests/btc_sign.py".into(),
                "BIP-44/49/84/86 test vectors".into(),
            ],
        }],
        account_profiles: ACCOUNT_PROFILES
            .iter()
            .map(|address_type| chain_app_api::AccountProfile {
                network: "Bitcoin".into(),
                account_type: address_type.as_str().into(),
                default_path: format!("m/{}'/0'/0'/0/0", address_type.purpose()),
                derivation_scheme: DerivationScheme::Bip32Secp256k1,
                curve: Curve::Secp256k1,
            })
            .collect(),
        requested_capabilities: chain_app_api::CapabilitySet {
            derivation_rules: vec![DerivationRule {
                derivation_scheme: DerivationScheme::Bip32Secp256k1,
                curve: Curve::Secp256k1,
                depth: 5,
                hardened_positions: vec![0, 1, 2],
                max_index: 1000,
            }],
            allow_chain_code: false,
            allow_signing: true,
            allow_storage: false,
        },
    }
}

pub struct BitcoinFactory;

impl chain_app_api::ModuleFactory for BitcoinFactory {
    fn describe(&self) -> AppDescriptor {
        descriptor()
    }

    fn create(&self) -> Box<dyn ChainApp> {
        Box::new(BitcoinModule::new())
    }
}
