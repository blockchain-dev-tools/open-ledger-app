//! Tron 链 App（阶段 4 / T-021）。
//!
//! 线格式对齐官方 `LedgerHQ/app-tron`（CLA 0xE0）：
//!
//! - `E0 02 GET_PUBLIC_KEY` → `[65B 未压缩公钥][len][ASCII base58check]`；
//! - `E0 04 SIGN` → `[path][raw Transaction protobuf]`，设备对原始字节做
//!   **sha256** 后签名；分帧 P1 = `0x00` 首块 / `0x10` 单块 / `0x80` 续块 /
//!   `0x90` 末块，P2 必须为 0；
//! - `E0 05 SIGN_TXN_HASH` → `[path][32B sha256]`，直接签宿主给的摘要；
//! - `E0 08 SIGN_PERSONAL_MESSAGE` → `[path][4B BE 长度][message]`，摘要 =
//!   `keccak256("\x19TRON Signed Message:\n" + 十进制长度 + message)`，P1
//!   `0x00` / `0x80` 分帧；
//! - `E0 06 GET_APP_CONFIGURATION` → `0B 00 05 00`（allowData / allowContract /
//!   signByHash；truncateAddress 关闭）。
//!
//! 签名响应统一为 `r || s || v`，`v` 是恢复位 **0/1**（官方 app-tron
//! `helpers.c:signTransaction` 不转成 27/28）。
//!
//! 0x04 采用「精确解析优先、通用审阅兜底」（T-022）：`TransferContract` 与
//! `TriggerSmartContract` 展示精确字段；其他合约类型不再整笔拒绝，而是展示
//! 类型名 + 通用字段 + `tron.unknown_contract_type` 风险。结构性损坏
//! （无合约、超过 8 个合约、已知类型字段损坏）仍返回 `0x6A80`。
//! 权限变更 / 创建合约 / 自定义合约 / 屏蔽交易额外标 `Critical`。
//! 0x02 支持 P1 确认与 P2 chain code；0x0A ECDH 与 0x0C TIP-712 已实现。

use chain_app_api::{
    AccountProfile, AppDescriptor, AppError, ChainApp, Curve, DerivationRule, DerivationScheme,
    EcdhRequest, Effect, Event, ExchangeId, FeeKind, Field, FieldValue, FinishStatus, KeyOutput,
    NetworkId, OperationKind, ParseStatus, PublicKeyRequest, ReviewAction, ReviewDocument,
    ReviewOutcome, ReviewRequest, ReviewSection, Risk, RiskLevel, RiskSource, ServiceResult,
    SessionConfig, SignOperation, SignPlan, SignScheme, Wire, API_VERSION,
};
use open_ledger_crypto::{base58, keccak256, sha256};

pub mod sw {
    pub const OK: u16 = 0x9000;
    pub const DENIED: u16 = 0x6985;
    pub const WRONG_DATA: u16 = 0x6A80;
    pub const WRONG_P1_P2: u16 = 0x6A86;
    pub const UNKNOWN_INS: u16 = 0x6D00;
    pub const CLA_NOT_SUPPORTED: u16 = 0x6E00;
    pub const UNKNOWN: u16 = 0x6F00;
}

pub const MODULE_ID: &str = "openledger.tron";

const CLA_TRON: u8 = 0xE0;
const INS_GET_ADDRESS: u8 = 0x02;
const INS_SIGN: u8 = 0x04;
const INS_SIGN_HASH: u8 = 0x05;
const INS_CONFIG: u8 = 0x06;
const INS_SIGN_MESSAGE: u8 = 0x08;
const INS_ECDH: u8 = 0x0A;
const INS_TIP712: u8 = 0x0C;

const P1_FIRST: u8 = 0x00;
const P1_SIGN: u8 = 0x10;
const P1_MORE: u8 = 0x80;
const P1_LAST: u8 = 0x90;
/// TRC-10 代币名分片：`0xA0 | index | (last ? 0x08 : 0)`。
const P1_TRC10: u8 = 0xA0;
const P1_TRC10_LAST: u8 = 0x08;

/// `m/44'/195'/0'/0/0`。
const DEFAULT_PATH: [u32; 5] = [0x8000_002C, 0x8000_00C3, 0x8000_0000, 0, 0];

/// 官方 `read_bip32_path` 只接受 Tron 子树：`m/44'/195'/…`。
const TRON_PREFIX: [u32; 2] = [0x8000_002C, 0x8000_00C3];

const MAX_TX_BYTES: usize = 32 * 1024;
const MAX_MESSAGE_BYTES: usize = 32 * 1024;
/// 一笔交易里最多展示的合约数；超过视为异常交易并拒绝。
const MAX_CONTRACTS: usize = 8;

/// Tron 消息签名前缀（官方 `sign_personal_message.c`）。
const SIGN_MAGIC: &[u8] = b"\x19TRON Signed Message:\n";

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
        let mut data = Vec::new();
        let rest = &bytes[4..];
        if !rest.is_empty() {
            let lc = rest[0] as usize;
            if rest.len() < 1 + lc {
                return None;
            }
            data.extend_from_slice(&rest[1..1 + lc]);
        }
        Some(Self {
            cla: bytes[0],
            ins: bytes[1],
            p1: bytes[2],
            p2: bytes[3],
            data,
        })
    }
}

fn status(code: u16) -> Vec<u8> {
    code.to_be_bytes().to_vec()
}

/// 一个合约的审阅视图（T-022：未知类型也走通用视图，不再整笔拒绝）。
#[derive(Debug, Clone, PartialEq, Eq)]
struct ContractView {
    type_id: u64,
    type_name: String,
    to: Option<String>,
    /// TRX / call value，单位 sun。
    amount_sun: Option<u64>,
    /// TRC-20 金额（十进制字符串）。
    trc20_amount: Option<String>,
    contract: Option<String>,
    selector: Option<String>,
    /// TRC-10 代币名（`TransferAssetContract`）。
    asset_name: Option<String>,
    /// `Contract.Permission_id`（0 = owner，>0 = 多签权限）。
    permission: Option<u64>,
    /// 通用视图：未精确解析的字段，按展示行排列（`field N: …`）。
    generic: Vec<String>,
    /// 该合约类型是否有精确解析器。
    known: bool,
    /// 该合约是否被完整解释。
    complete: bool,
    /// 权限变更 / 创建合约 / 屏蔽交易等高风险类型。
    critical: bool,
}

/// 0x04 解析出的审阅信息（最多 `MAX_CONTRACTS` 个合约）。
#[derive(Debug, Clone, PartialEq, Eq)]
struct Summary {
    contracts: Vec<ContractView>,
    fee_limit_sun: Option<u64>,
    /// 所有合约都完整解释。
    complete: bool,
}

enum Kind {
    Address,
    Transaction,
    Hash,
    Message,
    Tip712,
    Ecdh,
}

struct Pending {
    exchange_id: ExchangeId,
    path: Vec<u32>,
    kind: Kind,
    address: String,
    summary: Option<Summary>,
    digest: Option<[u8; 32]>,
    message: Option<Vec<u8>>,
    hash: Option<[u8; 32]>,
    /// 0x02: 地址确认批准后要回的原始公钥。
    public_key: Option<Vec<u8>>,
    /// 0x02: 是否要求本机确认地址。
    confirm: bool,
    /// 0x02: 是否附带 chain code。
    chain_code: Option<Vec<u8>>,
    /// 0x0C: `domainHash` / `messageHash`。
    tip712: Option<([u8; 32], [u8; 32])>,
}

/// 0x04 / 0x08 的分帧缓冲。
struct Collector {
    exchange_id: ExchangeId,
    path: Vec<u32>,
    bytes: Vec<u8>,
    /// 0x08 声明的消息总长；0x04 为 0。
    declared: usize,
}

enum Stage {
    Idle,
    Collecting,
    AwaitKey,
    AwaitReview,
}

pub struct TronModule {
    stage: Stage,
    pending: Option<Pending>,
    collector: Option<Collector>,
    /// 本机账户请求的 `request_id`（`LocalCommand::DeriveAccount`）。
    local: Option<u64>,
}

impl Default for TronModule {
    fn default() -> Self {
        Self::new()
    }
}

impl TronModule {
    pub fn new() -> Self {
        Self {
            stage: Stage::Idle,
            pending: None,
            collector: None,
            local: None,
        }
    }

    fn emit(&self, exchange_id: ExchangeId, payload: Vec<u8>) -> Effect {
        self.emit_state(exchange_id, payload, chain_app_api::OperationState::Final)
    }

    fn emit_state(
        &self,
        exchange_id: ExchangeId,
        payload: Vec<u8>,
        state: chain_app_api::OperationState,
    ) -> Effect {
        Effect::Emit {
            wire: Wire::LedgerApdu,
            exchange_id,
            payload,
            state,
        }
    }

    fn handle_apdu(&mut self, exchange_id: ExchangeId, bytes: &[u8]) -> Result<Effect, AppError> {
        let apdu =
            Apdu::parse(bytes).ok_or_else(|| AppError::BadRequest("truncated APDU".into()))?;
        if apdu.cla != CLA_TRON {
            return Ok(self.emit(exchange_id, status(sw::CLA_NOT_SUPPORTED)));
        }
        match apdu.ins {
            INS_GET_ADDRESS => self.handle_get_address(exchange_id, &apdu),
            INS_SIGN => self.handle_sign(exchange_id, &apdu),
            INS_SIGN_HASH => self.handle_sign_hash(exchange_id, &apdu),
            INS_SIGN_MESSAGE => self.handle_sign_message(exchange_id, &apdu),
            INS_ECDH => self.handle_ecdh(exchange_id, &apdu),
            INS_TIP712 => self.handle_tip712(exchange_id, &apdu),
            // 官方 app-tron 的配置字节：bit0 allowData | bit1 allowContract |
            // bit3 signByHash。truncateAddress (bit2) 为 0。
            INS_CONFIG => Ok(self.emit(
                exchange_id,
                vec![0x0B, 0x00, 0x05, 0x00, 0x90, 0x00],
            )),
            _ => Ok(self.emit(exchange_id, status(sw::UNKNOWN_INS))),
        }
    }

    // ── 0x02 GET_PUBLIC_KEY ──────────────────────────────────────────

    fn handle_get_address(
        &mut self,
        exchange_id: ExchangeId,
        apdu: &Apdu,
    ) -> Result<Effect, AppError> {
        let confirm = match apdu.p1 {
            0x00 => false,
            0x01 => true,
            _ => return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2))),
        };
        if apdu.p2 & !0x01 != 0 {
            return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2)));
        }
        let chaincode = apdu.p2 & 0x01 != 0;
        let data = &apdu.data;
        if data.is_empty() {
            return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
        }
        let (path, rest) = match split_path(data) {
            Some(split) => split,
            None => return Ok(self.emit(exchange_id, status(sw::WRONG_DATA))),
        };
        if !rest.is_empty() || !is_tron_path(&path) {
            return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
        }
        self.pending = Some(Pending {
            exchange_id,
            path: path.clone(),
            kind: Kind::Address,
            address: String::new(),
            summary: None,
            digest: None,
            message: None,
            hash: None,
            public_key: None,
            confirm,
            chain_code: None,
            tip712: None,
        });
        self.stage = Stage::AwaitKey;
        Ok(self.need_key(path, chaincode))
    }

    // ── 0x04 SIGN（raw Transaction protobuf）─────────────────────────

    fn handle_sign(
        &mut self,
        exchange_id: ExchangeId,
        apdu: &Apdu,
    ) -> Result<Effect, AppError> {
        if apdu.p2 != 0x00 {
            return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2)));
        }
        let first = matches!(apdu.p1, P1_FIRST | P1_SIGN);
        let last = matches!(apdu.p1, P1_SIGN | P1_LAST);

        // TRC-10 代币名分片：tx 本体以 0x80 结束，随后 0xA0|index|last 分片携带
        // 代币名；名字本身也内嵌在 tx 里，这里只等最后一帧再签名。
        if apdu.p1 & 0xF0 == P1_TRC10 {
            let Some(collector) = self.collector.as_mut() else {
                return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2)));
            };
            collector.exchange_id = exchange_id;
            if apdu.p1 & P1_TRC10_LAST == 0 {
                return Ok(self.emit_state(
                    exchange_id,
                    status(sw::OK),
                    chain_app_api::OperationState::Collecting,
                ));
            }
            let collector = self.collector.take().expect("collector checked above");
            return self.finish_transaction(collector.exchange_id, collector.path, collector.bytes);
        }

        if !matches!(apdu.p1, P1_FIRST | P1_SIGN | P1_MORE | P1_LAST) {
            return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2)));
        }

        if first {
            let (path, rest) = match split_path(&apdu.data) {
                Some(split) => split,
                None => return Ok(self.emit(exchange_id, status(sw::WRONG_DATA))),
            };
            if !is_tron_path(&path) {
                return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
            }
            if rest.len() > MAX_TX_BYTES {
                return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
            }
            if last {
                return self.finish_transaction(exchange_id, path, rest.to_vec());
            }
            self.collector = Some(Collector {
                exchange_id,
                path,
                bytes: rest.to_vec(),
                declared: 0,
            });
            self.stage = Stage::Collecting;
            return Ok(self.emit_state(
                exchange_id,
                status(sw::OK),
                chain_app_api::OperationState::Collecting,
            ));
        }

        // 续块：0x80 / 0x90，只有原始字节。
        let Some(collector) = self.collector.as_mut() else {
            return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2)));
        };
        if collector.bytes.len() + apdu.data.len() > MAX_TX_BYTES {
            self.collector = None;
            self.stage = Stage::Idle;
            return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
        }
        collector.bytes.extend_from_slice(&apdu.data);
        collector.exchange_id = exchange_id;
        if !last {
            return Ok(self.emit_state(
                exchange_id,
                status(sw::OK),
                chain_app_api::OperationState::Collecting,
            ));
        }
        let collector = self.collector.take().expect("collector checked above");
        self.finish_transaction(collector.exchange_id, collector.path, collector.bytes)
    }

    fn finish_transaction(
        &mut self,
        exchange_id: ExchangeId,
        path: Vec<u32>,
        bytes: Vec<u8>,
    ) -> Result<Effect, AppError> {
        let Some(summary) = parse_transaction(&bytes) else {
            // 结构性损坏（无合约 / 超过 8 个合约 / 已知类型字段损坏）拒绝，
            // 不产生审阅，也不触碰密钥。未知类型已在解析层降级为通用视图。
            self.stage = Stage::Idle;
            return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
        };
        let digest = sha256::hash(&bytes);
        self.pending = Some(Pending {
            exchange_id,
            path: path.clone(),
            kind: Kind::Transaction,
            address: String::new(),
            summary: Some(summary),
            digest: Some(digest),
            message: None,
            hash: None,
            public_key: None,
            confirm: false,
            chain_code: None,
            tip712: None,
        });
        self.stage = Stage::AwaitKey;
        Ok(self.need_key(path, false))
    }

    // ── 0x05 SIGN_TXN_HASH ───────────────────────────────────────────

    fn handle_sign_hash(
        &mut self,
        exchange_id: ExchangeId,
        apdu: &Apdu,
    ) -> Result<Effect, AppError> {
        if apdu.p1 != 0x00 || apdu.p2 != 0x00 {
            return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2)));
        }
        let (path, rest) = match split_path(&apdu.data) {
            Some(split) => split,
            None => return Ok(self.emit(exchange_id, status(sw::WRONG_DATA))),
        };
        if !is_tron_path(&path) || rest.len() != 32 {
            return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
        }
        let mut digest = [0u8; 32];
        digest.copy_from_slice(rest);
        self.pending = Some(Pending {
            exchange_id,
            path: path.clone(),
            kind: Kind::Hash,
            address: String::new(),
            summary: None,
            digest: Some(digest),
            message: None,
            hash: Some(digest),
            public_key: None,
            confirm: false,
            chain_code: None,
            tip712: None,
        });
        self.stage = Stage::AwaitKey;
        Ok(self.need_key(path, false))
    }

    // ── 0x08 SIGN_PERSONAL_MESSAGE ───────────────────────────────────

    fn handle_sign_message(
        &mut self,
        exchange_id: ExchangeId,
        apdu: &Apdu,
    ) -> Result<Effect, AppError> {
        if apdu.p2 != 0x00 {
            return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2)));
        }
        if apdu.p1 == P1_FIRST || apdu.p1 == P1_SIGN {
            let (path, rest) = match split_path(&apdu.data) {
                Some(split) => split,
                None => return Ok(self.emit(exchange_id, status(sw::WRONG_DATA))),
            };
            if !is_tron_path(&path) || rest.len() < 4 {
                return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
            }
            let declared = u32::from_be_bytes([rest[0], rest[1], rest[2], rest[3]]) as usize;
            if declared > MAX_MESSAGE_BYTES {
                return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
            }
            let body = &rest[4..];
            if body.len() > declared {
                return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
            }
            if body.len() == declared {
                return self.finish_message(exchange_id, path, body.to_vec());
            }
            self.collector = Some(Collector {
                exchange_id,
                path,
                bytes: body.to_vec(),
                declared,
            });
            self.stage = Stage::Collecting;
            return Ok(self.emit_state(
                exchange_id,
                status(sw::OK),
                chain_app_api::OperationState::Collecting,
            ));
        }
        if apdu.p1 != P1_MORE {
            return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2)));
        }
        let Some(collector) = self.collector.as_mut() else {
            return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2)));
        };
        if collector.bytes.len() + apdu.data.len() > collector.declared {
            self.collector = None;
            self.stage = Stage::Idle;
            return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
        }
        collector.bytes.extend_from_slice(&apdu.data);
        collector.exchange_id = exchange_id;
        if collector.bytes.len() < collector.declared {
            return Ok(self.emit_state(
                exchange_id,
                status(sw::OK),
                chain_app_api::OperationState::Collecting,
            ));
        }
        let collector = self.collector.take().expect("collector checked above");
        self.finish_message(collector.exchange_id, collector.path, collector.bytes)
    }

    fn finish_message(
        &mut self,
        exchange_id: ExchangeId,
        path: Vec<u32>,
        message: Vec<u8>,
    ) -> Result<Effect, AppError> {
        let digest = personal_digest(&message);
        self.pending = Some(Pending {
            exchange_id,
            path: path.clone(),
            kind: Kind::Message,
            address: String::new(),
            summary: None,
            digest: Some(digest),
            message: Some(message),
            hash: None,
            public_key: None,
            confirm: false,
            chain_code: None,
            tip712: None,
        });
        self.stage = Stage::AwaitKey;
        Ok(self.need_key(path, false))
    }

    // ── 宿主交互 ─────────────────────────────────────────────────────

    fn need_key(&self, path: Vec<u32>, include_chain_code: bool) -> Effect {
        Effect::NeedPublicKey {
            service_id: 1,
            request: PublicKeyRequest {
                derivation_scheme: DerivationScheme::Bip32Secp256k1,
                curve: Curve::Secp256k1,
                path,
                output: KeyOutput::UncompressedSecp256k1,
                include_chain_code,
            },
        }
    }

    // ── 0x0A GET_ECDH_SECRET ─────────────────────────────────────────

    fn handle_ecdh(&mut self, exchange_id: ExchangeId, apdu: &Apdu) -> Result<Effect, AppError> {
        if apdu.p1 != 0x00 || apdu.p2 != 0x01 {
            return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2)));
        }
        let (path, rest) = match split_path(&apdu.data) {
            Some(split) => split,
            None => return Ok(self.emit(exchange_id, status(sw::WRONG_DATA))),
        };
        if !is_tron_path(&path) || rest.len() != 65 {
            return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
        }
        let peer = rest.to_vec();
        self.pending = Some(Pending {
            exchange_id,
            path: path.clone(),
            kind: Kind::Ecdh,
            address: String::new(),
            summary: None,
            digest: None,
            message: None,
            hash: None,
            public_key: None,
            confirm: false,
            chain_code: None,
            tip712: None,
        });
        self.stage = Stage::AwaitKey;
        Ok(Effect::NeedEcdh {
            service_id: 3,
            request: EcdhRequest {
                derivation_scheme: DerivationScheme::Bip32Secp256k1,
                curve: Curve::Secp256k1,
                path,
                peer_public_key: peer,
            },
        })
    }

    // ── 0x0C SIGN_TIP_712_MESSAGE ────────────────────────────────────

    fn handle_tip712(&mut self, exchange_id: ExchangeId, apdu: &Apdu) -> Result<Effect, AppError> {
        if apdu.p1 != 0x00 || apdu.p2 != 0x00 {
            return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2)));
        }
        let (path, rest) = match split_path(&apdu.data) {
            Some(split) => split,
            None => return Ok(self.emit(exchange_id, status(sw::WRONG_DATA))),
        };
        if !is_tron_path(&path) || rest.len() != 64 {
            return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
        }
        let mut domain = [0u8; 32];
        let mut message = [0u8; 32];
        domain.copy_from_slice(&rest[..32]);
        message.copy_from_slice(&rest[32..]);
        // 官方：keccak256(0x19 0x01 || domainHash || messageHash)
        let mut preimage = Vec::with_capacity(66);
        preimage.extend_from_slice(&[0x19, 0x01]);
        preimage.extend_from_slice(&domain);
        preimage.extend_from_slice(&message);
        let digest = keccak256::hash(&preimage);
        self.pending = Some(Pending {
            exchange_id,
            path: path.clone(),
            kind: Kind::Tip712,
            address: String::new(),
            summary: None,
            digest: Some(digest),
            message: None,
            hash: None,
            public_key: None,
            confirm: false,
            chain_code: None,
            tip712: Some((domain, message)),
        });
        self.stage = Stage::AwaitKey;
        Ok(self.need_key(path, false))
    }

    fn handle_local(
        &mut self,
        request_id: u64,
        command: chain_app_api::LocalCommand,
    ) -> Result<Effect, AppError> {
        match command {
            chain_app_api::LocalCommand::DeriveAccount {
                account_profile_index: 0,
                address_index,
            } if address_index <= 1000 => {
                self.local = Some(request_id);
                self.stage = Stage::AwaitKey;
                Ok(Effect::NeedPublicKey {
                    service_id: 9,
                    request: PublicKeyRequest {
                        derivation_scheme: DerivationScheme::Bip32Secp256k1,
                        curve: Curve::Secp256k1,
                        path: account_path(address_index),
                        output: KeyOutput::UncompressedSecp256k1,
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
        // 本机账户派生：结果直接回给 UI，不涉及 APDU。
        if let Some(request_id) = self.local.take() {
            self.stage = Stage::Idle;
            let payload = match result {
                ServiceResult::PublicKey(key) => match address_from_uncompressed(&key.bytes) {
                    Some(address) => format!(
                        "{{\"address\":\"{address}\",\"public_key\":\"{}\"}}",
                        hex::encode(&key.bytes)
                    )
                    .into_bytes(),
                    None => Vec::new(),
                },
                _ => Vec::new(),
            };
            return Ok(Effect::LocalReply {
                request_id,
                payload,
            });
        }

        // ECDH：没有公钥/审阅，直接回共享点。
        let is_ecdh = self
            .pending
            .as_ref()
            .map(|pending| matches!(pending.kind, Kind::Ecdh))
            .unwrap_or(false);
        if is_ecdh {
            let exchange_id = self.pending.take().map(|p| p.exchange_id).unwrap_or(1);
            self.stage = Stage::Idle;
            return Ok(match result {
                ServiceResult::SharedSecret(secret) if secret.len() == 65 => {
                    let mut payload = secret;
                    payload.extend_from_slice(&status(sw::OK));
                    self.emit(exchange_id, payload)
                }
                _ => self.emit(exchange_id, status(sw::UNKNOWN)),
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
                return Err(AppError::InvalidEvent("unexpected service result".into()))
            }
        };
        let Some(address) = address_from_uncompressed(&key.bytes) else {
            let exchange_id = self.pending.take().map(|p| p.exchange_id).unwrap_or(1);
            self.stage = Stage::Idle;
            return Ok(self.emit(exchange_id, status(sw::UNKNOWN)));
        };

        let Some(pending) = self.pending.as_mut() else {
            return Err(AppError::InvalidEvent("no pending request".into()));
        };
        pending.address = address.clone();
        pending.public_key = Some(key.bytes.clone());
        pending.chain_code = key.chain_code.clone();

        if matches!(pending.kind, Kind::Address) {
            let exchange_id = pending.exchange_id;
            let confirm = pending.confirm;
            let chain_code = pending.chain_code.clone();
            if confirm {
                // 先弹本机确认页；批准后由 handle_review 回地址。
                self.stage = Stage::AwaitReview;
                let fields = vec![Field {
                    label_key: "review.field.address".into(),
                    value: FieldValue::Address {
                        value: address.clone(),
                        network: "Tron".into(),
                        role: "account".into(),
                    },
                }];
                return Ok(Effect::NeedReview {
                    service_id: 2,
                    request: Box::new(ReviewRequest {
                        document: ReviewDocument {
                            operation: OperationKind::AddressConfirmation,
                            network: NetworkId {
                                name: "Tron".into(),
                                chain_id: None,
                            },
                            account: Some(address),
                            sections: vec![ReviewSection {
                                title_key: "review.section.address".into(),
                                fields,
                            }],
                            risks: vec![],
                            parse_status: ParseStatus::Complete,
                        },
                        action: ReviewAction::DisplayAddress {
                            derivation_scheme: DerivationScheme::Bip32Secp256k1,
                            curve: Curve::Secp256k1,
                            path: pending.path.clone(),
                        },
                    }),
                });
            }
            let public_key = key.bytes;
            self.pending = None;
            self.stage = Stage::Idle;
            let mut payload = Vec::with_capacity(1 + 65 + 1 + address.len() + 32 + 2);
            payload.push(public_key.len() as u8);
            payload.extend_from_slice(&public_key);
            payload.push(address.len() as u8);
            payload.extend_from_slice(address.as_bytes());
            if let Some(chain_code) = chain_code {
                payload.extend_from_slice(&chain_code);
            }
            payload.extend_from_slice(&status(sw::OK));
            return Ok(self.emit(exchange_id, payload));
        }

        let request = match pending.kind {
            Kind::Transaction => transaction_review(&address, pending),
            Kind::Hash => hash_review(&address, pending),
            Kind::Message => message_review(&address, pending),
            Kind::Tip712 => tip712_review(&address, pending),
            Kind::Address | Kind::Ecdh => unreachable!("handled above"),
        };
        let Some(request) = request else {
            let exchange_id = pending.exchange_id;
            self.pending = None;
            self.stage = Stage::Idle;
            return Ok(self.emit(exchange_id, status(sw::UNKNOWN)));
        };
        self.stage = Stage::AwaitReview;
        Ok(Effect::NeedReview {
            service_id: 2,
            request: Box::new(request),
        })
    }

    fn handle_review(&mut self, outcome: ReviewOutcome) -> Result<Effect, AppError> {
        let pending = self
            .pending
            .take()
            .ok_or_else(|| AppError::InvalidEvent("no pending review".into()))?;
        self.stage = Stage::Idle;
        if matches!(pending.kind, Kind::Address) {
            // 地址确认：批准后回公钥 + 地址（+ 可选 chain code）。
            let mut payload = Vec::new();
            if matches!(outcome, ReviewOutcome::Approved { .. }) {
                if let Some(public_key) = &pending.public_key {
                    payload.push(public_key.len() as u8);
                    payload.extend_from_slice(public_key);
                    payload.push(pending.address.len() as u8);
                    payload.extend_from_slice(pending.address.as_bytes());
                    if let Some(chain_code) = &pending.chain_code {
                        payload.extend_from_slice(chain_code);
                    }
                    payload.extend_from_slice(&status(sw::OK));
                } else {
                    payload = status(sw::UNKNOWN);
                }
            } else {
                payload = status(sw::DENIED);
            }
            return Ok(self.emit(pending.exchange_id, payload));
        }
        let payload = match outcome {
            ReviewOutcome::Approved { signatures } => {
                if signatures.len() == 1 && signatures[0].bytes.len() == 64 {
                    match signatures[0].recovery_id {
                        Some(recovery) => {
                            let mut out = signatures[0].bytes.clone();
                            // 官方 app-tron 直接回 0/1，不转 27/28。
                            out.push(recovery);
                            out.extend_from_slice(&status(sw::OK));
                            out
                        }
                        None => status(sw::UNKNOWN),
                    }
                } else {
                    status(sw::UNKNOWN)
                }
            }
            ReviewOutcome::Rejected | ReviewOutcome::TimedOut => status(sw::DENIED),
            ReviewOutcome::Failed(_) => status(sw::UNKNOWN),
        };
        Ok(self.emit(pending.exchange_id, payload))
    }
}

impl ChainApp for TronModule {
    fn open(&mut self, _config: SessionConfig) -> Result<(), AppError> {
        Ok(())
    }

    fn step(&mut self, event: Event) -> Result<Effect, AppError> {
        match event {
            Event::Wire {
                exchange_id,
                payload,
                ..
            } => self.handle_apdu(exchange_id, &payload),
            Event::ServiceResult { result, .. } => self.handle_service_result(result),
            Event::ReviewResult { outcome, .. } => self.handle_review(outcome),
            Event::Delivered { .. } => {
                if matches!(self.stage, Stage::Collecting) {
                    return Ok(Effect::AwaitInput);
                }
                Ok(Effect::Finished {
                    status: FinishStatus::Delivered,
                })
            }
            Event::Cancel { .. } => {
                self.pending = None;
                self.collector = None;
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
        self.collector = None;
        self.local = None;
        self.stage = Stage::Idle;
    }
}

// ── 审阅文档 ─────────────────────────────────────────────────────────

fn base_fields(address: &str, summary: &Summary) -> Vec<Field> {
    let mut fields = vec![Field {
        label_key: "review.field.address".into(),
        value: FieldValue::Address {
            value: address.into(),
            network: "Tron".into(),
            role: "account".into(),
        },
    }];
    let multiple = summary.contracts.len() > 1;
    for (index, contract) in summary.contracts.iter().enumerate() {
        if multiple {
            fields.push(Field {
                label_key: "review.field.contract_index".into(),
                value: FieldValue::Text {
                    value: format!("#{}", index + 1),
                },
            });
        }
        fields.push(Field {
            label_key: "review.field.contract_type".into(),
            value: FieldValue::Text {
                value: if contract.known {
                    contract.type_name.clone()
                } else {
                    format!("{} (#{})", contract.type_name, contract.type_id)
                },
            },
        });
        if let Some(to) = &contract.to {
            fields.push(Field {
                label_key: "review.field.to".into(),
                value: FieldValue::Address {
                    value: to.clone(),
                    network: "Tron".into(),
                    role: "recipient".into(),
                },
            });
        }
        if let Some(raw) = contract.amount_sun {
            fields.push(Field {
                label_key: "review.field.amount".into(),
                value: FieldValue::Amount {
                    raw: raw.to_string(),
                    decimals: 6,
                    asset: "TRX".into(),
                    ticker: Some("TRX".into()),
                },
            });
        }
        if let Some(amount) = &contract.trc20_amount {
            fields.push(Field {
                label_key: "review.field.amount".into(),
                value: FieldValue::Text {
                    value: amount.clone(),
                },
            });
        }
        if let Some(contract_address) = &contract.contract {
            fields.push(Field {
                label_key: "review.field.contract".into(),
                value: FieldValue::Address {
                    value: contract_address.clone(),
                    network: "Tron".into(),
                    role: "contract".into(),
                },
            });
        }
        if let Some(selector) = &contract.selector {
            fields.push(Field {
                label_key: "review.field.selector".into(),
                value: FieldValue::Text {
                    value: selector.clone(),
                },
            });
        }
        if let Some(asset) = &contract.asset_name {
            fields.push(Field {
                label_key: "review.field.asset".into(),
                value: FieldValue::Text { value: asset.clone() },
            });
        }
        if let Some(permission) = contract.permission {
            fields.push(Field {
                label_key: "review.field.permission".into(),
                value: FieldValue::Text {
                    value: format!("P{permission}"),
                },
            });
        }
        for line in &contract.generic {
            fields.push(Field {
                label_key: "review.field.param".into(),
                value: FieldValue::Text { value: line.clone() },
            });
        }
    }
    if let Some(fee_limit) = summary.fee_limit_sun {
        fields.push(Field {
            label_key: "review.field.fee_limit".into(),
            value: FieldValue::Fee {
                kind: FeeKind::UpperBound,
                raw: Some(fee_limit.to_string()),
                decimals: 6,
                asset: "TRX".into(),
            },
        });
    }
    fields
}

fn transaction_review(address: &str, pending: &Pending) -> Option<ReviewRequest> {
    let summary = pending.summary.as_ref()?;
    let digest = pending.digest?;
    let mut risks = Vec::new();
    let unknown_types: Vec<String> = summary
        .contracts
        .iter()
        .filter(|contract| !contract.known)
        .map(|contract| format!("{} (#{})", contract.type_name, contract.type_id))
        .collect();
    if !unknown_types.is_empty() {
        // T-022：未知类型不再整笔拒绝，而是给出通用字段 + 明确风险。
        risks.push(Risk {
            code: "tron.unknown_contract_type".into(),
            severity: RiskLevel::Warning,
            parameters: vec![("types".into(), unknown_types.join(", "))],
            source: RiskSource::Module,
        });
    }
    if summary
        .contracts
        .iter()
        .any(|contract| contract.known && !contract.complete)
    {
        risks.push(Risk {
            code: "tron.unknown_selector".into(),
            severity: RiskLevel::Warning,
            parameters: Vec::new(),
            source: RiskSource::Module,
        });
    }
    let critical: Vec<String> = summary
        .contracts
        .iter()
        .filter(|contract| contract.critical)
        .map(|contract| format!("{} (#{})", contract.type_name, contract.type_id))
        .collect();
    if !critical.is_empty() {
        risks.push(Risk {
            code: "tron.critical_contract_type".into(),
            severity: RiskLevel::Critical,
            parameters: vec![("types".into(), critical.join(", "))],
            source: RiskSource::Module,
        });
    }
    let operation = SignOperation {
        operation_id: 1,
        derivation_scheme: DerivationScheme::Bip32Secp256k1,
        curve: Curve::Secp256k1,
        path: pending.path.clone(),
        scheme: SignScheme::EcdsaPrehash {
            digest_len: 32,
            low_s: true,
        },
        input: digest.to_vec(),
        public_parameters: vec![("payload_hex".into(), digest.to_vec())],
    };
    Some(ReviewRequest {
        document: ReviewDocument {
            operation: OperationKind::Transaction,
            network: NetworkId {
                name: "Tron".into(),
                chain_id: None,
            },
            account: Some(address.into()),
            sections: vec![ReviewSection {
                title_key: "review.section.tron".into(),
                fields: base_fields(address, summary),
            }],
            risks,
            parse_status: if summary.complete {
                ParseStatus::Complete
            } else {
                ParseStatus::Partial
            },
        },
        action: ReviewAction::Sign(SignPlan::single(operation)),
    })
}

fn hash_review(address: &str, pending: &Pending) -> Option<ReviewRequest> {
    let digest = pending.digest?;
    let hash = pending.hash?;
    Some(ReviewRequest {
        document: ReviewDocument {
            operation: OperationKind::Transaction,
            network: NetworkId {
                name: "Tron".into(),
                chain_id: None,
            },
            account: Some(address.into()),
            sections: vec![ReviewSection {
                title_key: "review.section.tron".into(),
                fields: vec![
                    Field {
                        label_key: "review.field.address".into(),
                        value: FieldValue::Address {
                            value: address.into(),
                            network: "Tron".into(),
                            role: "account".into(),
                        },
                    },
                    Field {
                        label_key: "review.field.hash".into(),
                        value: FieldValue::Bytes {
                            value: hash.to_vec(),
                        },
                    },
                ],
            }],
            // 0x05 只有摘要，没有合约语义：明确标为「盲签」，让用户看到哈希。
            risks: vec![Risk {
                code: "tron.sign_by_hash".into(),
                severity: RiskLevel::Warning,
                parameters: Vec::new(),
                source: RiskSource::Module,
            }],
            parse_status: ParseStatus::Partial,
        },
        action: ReviewAction::Sign(SignPlan::single(sign_operation(
            &pending.path,
            digest,
            digest.to_vec(),
        ))),
    })
}

fn message_review(address: &str, pending: &Pending) -> Option<ReviewRequest> {
    let digest = pending.digest?;
    let message = pending.message.clone()?;
    let text = String::from_utf8(message.clone())
        .unwrap_or_else(|_| format!("0x{}", hex::encode(&message)));
    Some(ReviewRequest {
        document: ReviewDocument {
            operation: OperationKind::Message,
            network: NetworkId {
                name: "Tron".into(),
                chain_id: None,
            },
            account: Some(address.into()),
            sections: vec![ReviewSection {
                title_key: "review.section.tron".into(),
                fields: vec![
                    Field {
                        label_key: "review.field.address".into(),
                        value: FieldValue::Address {
                            value: address.into(),
                            network: "Tron".into(),
                            role: "account".into(),
                        },
                    },
                    Field {
                        label_key: "review.field.message".into(),
                        value: FieldValue::Text { value: text },
                    },
                    Field {
                        label_key: "review.field.message_hex".into(),
                        value: FieldValue::Bytes {
                            value: message.clone(),
                        },
                    },
                ],
            }],
            risks: vec![],
            parse_status: ParseStatus::Complete,
        },
        action: ReviewAction::Sign(SignPlan::single(sign_operation(
            &pending.path,
            digest,
            message,
        ))),
    })
}

fn tip712_review(address: &str, pending: &Pending) -> Option<ReviewRequest> {
    let digest = pending.digest?;
    let (domain, message) = pending.tip712?;
    Some(ReviewRequest {
        document: ReviewDocument {
            operation: OperationKind::Message,
            network: NetworkId {
                name: "Tron".into(),
                chain_id: None,
            },
            account: Some(address.into()),
            sections: vec![ReviewSection {
                title_key: "review.section.tron".into(),
                fields: vec![
                    Field {
                        label_key: "review.field.address".into(),
                        value: FieldValue::Address {
                            value: address.into(),
                            network: "Tron".into(),
                            role: "account".into(),
                        },
                    },
                    Field {
                        label_key: "review.field.domain_hash".into(),
                        value: FieldValue::Bytes {
                            value: domain.to_vec(),
                        },
                    },
                    Field {
                        label_key: "review.field.struct_hash".into(),
                        value: FieldValue::Bytes {
                            value: message.to_vec(),
                        },
                    },
                ],
            }],
            // 宿主只给两个哈希，无法验证具体授权内容。
            risks: vec![Risk {
                code: "tron.sign_by_hash".into(),
                severity: RiskLevel::Warning,
                parameters: Vec::new(),
                source: RiskSource::Module,
            }],
            parse_status: ParseStatus::Partial,
        },
        action: ReviewAction::Sign(SignPlan::single(sign_operation(
            &pending.path,
            digest,
            digest.to_vec(),
        ))),
    })
}

fn sign_operation(path: &[u32], digest: [u8; 32], payload: Vec<u8>) -> SignOperation {
    SignOperation {
        operation_id: 1,
        derivation_scheme: DerivationScheme::Bip32Secp256k1,
        curve: Curve::Secp256k1,
        path: path.to_vec(),
        scheme: SignScheme::EcdsaPrehash {
            digest_len: 32,
            low_s: true,
        },
        input: digest.to_vec(),
        public_parameters: vec![("payload_hex".into(), payload)],
    }
}

// ── protobuf 最小解析 ────────────────────────────────────────────────

/// 极简 protobuf 读取器：只支持 varint 与 length-delimited。
struct Pb<'a> {
    data: &'a [u8],
    pos: usize,
}

impl<'a> Pb<'a> {
    fn new(data: &'a [u8]) -> Self {
        Self { data, pos: 0 }
    }

    fn varint(&mut self) -> Option<u64> {
        let mut value = 0u64;
        let mut shift = 0u32;
        loop {
            let byte = *self.data.get(self.pos)?;
            self.pos += 1;
            value |= u64::from(byte & 0x7f) << shift;
            if byte & 0x80 == 0 {
                return Some(value);
            }
            shift += 7;
            if shift >= 64 {
                return None;
            }
        }
    }

    fn tag(&mut self) -> Option<(u32, u8)> {
        let key = self.varint()?;
        let field = u32::try_from(key >> 3).ok()?;
        Some((field, (key & 0x07) as u8))
    }

    fn bytes(&mut self) -> Option<&'a [u8]> {
        let len = usize::try_from(self.varint()?).ok()?;
        let end = self.pos.checked_add(len)?;
        let slice = self.data.get(self.pos..end)?;
        self.pos = end;
        Some(slice)
    }

    fn skip(&mut self, wire: u8) -> Option<()> {
        match wire {
            0 => {
                self.varint()?;
            }
            1 => self.pos = self.pos.checked_add(8)?,
            2 => {
                self.bytes()?;
            }
            5 => self.pos = self.pos.checked_add(4)?,
            _ => return None,
        }
        if self.pos > self.data.len() {
            return None;
        }
        Some(())
    }
}

/// `Transaction.raw` → 合约视图列表。
///
/// T-022 起未知合约类型不再整笔拒绝：只要能读出 `Contract.type` 与
/// `Any.value`，就生成「通用视图 + 明确风险」。仍然拒绝的是结构性损坏
/// （没有合约、超过上限、已知类型的必填字段损坏）。
fn parse_transaction(raw: &[u8]) -> Option<Summary> {
    // Transaction: field 1 = raw (length-delimited)
    let mut pb = Pb::new(raw);
    let mut tx_raw: Option<&[u8]> = None;
    while let Some((field, wire)) = pb.tag() {
        match (field, wire) {
            (1, 2) => tx_raw = Some(pb.bytes()?),
            _ => pb.skip(wire)?,
        }
    }
    let tx_raw = tx_raw?;

    // Transaction.raw: field 11 = repeated Contract, field 18 = fee_limit
    let mut contracts: Vec<&[u8]> = Vec::new();
    let mut fee_limit: Option<u64> = None;
    let mut pb = Pb::new(tx_raw);
    while let Some((field, wire)) = pb.tag() {
        match (field, wire) {
            (11, 2) => contracts.push(pb.bytes()?),
            (18, 0) => fee_limit = Some(pb.varint()?),
            _ => pb.skip(wire)?,
        }
    }
    if contracts.is_empty() || contracts.len() > MAX_CONTRACTS {
        return None;
    }

    let mut views = Vec::with_capacity(contracts.len());
    for contract in contracts {
        views.push(parse_contract(contract)?);
    }
    let complete = views.iter().all(|view| view.complete);
    Some(Summary {
        contracts: views,
        fee_limit_sun: fee_limit,
        complete,
    })
}

fn parse_contract(contract: &[u8]) -> Option<ContractView> {
    // Contract: field 1 = type, field 2 = parameter (Any), field 5 = permission_id
    let mut contract_type: Option<u64> = None;
    let mut parameter: Option<&[u8]> = None;
    let mut permission: Option<u64> = None;
    let mut pb = Pb::new(contract);
    while let Some((field, wire)) = pb.tag() {
        match (field, wire) {
            (1, 0) => contract_type = Some(pb.varint()?),
            (2, 2) => parameter = Some(pb.bytes()?),
            (5, 0) => permission = Some(pb.varint()?),
            _ => pb.skip(wire)?,
        }
    }
    let contract_type = contract_type?;
    let parameter = parameter?;

    // Any: field 1 = type_url, field 2 = value
    let mut type_url: Option<&[u8]> = None;
    let mut value: Option<&[u8]> = None;
    let mut pb = Pb::new(parameter);
    while let Some((field, wire)) = pb.tag() {
        match (field, wire) {
            (1, 2) => type_url = Some(pb.bytes()?),
            (2, 2) => value = Some(pb.bytes()?),
            _ => pb.skip(wire)?,
        }
    }
    let value = value.unwrap_or(&[]);

    match contract_type {
        // TransferContract：精确解析，字段损坏仍然拒绝。
        1 => {
            check_type_url(type_url, "TransferContract")?;
            let (to, amount) = parse_transfer(value)?;
            Some(ContractView {
                type_id: 1,
                type_name: "TransferContract".into(),
                to: Some(to),
                amount_sun: Some(amount),
                trc20_amount: None,
                contract: None,
                selector: None,
                asset_name: None,
                permission,
                generic: Vec::new(),
                known: true,
                complete: true,
                critical: false,
            })
        }
        // TransferAssetContract（TRC-10）：asset_name(1) / owner(2) / to(3) / amount(4)。
        2 => {
            check_type_url(type_url, "TransferAssetContract")?;
            let asset = parse_transfer_asset(value)?;
            Some(ContractView {
                type_id: 2,
                type_name: "TransferAssetContract".into(),
                to: Some(asset.to),
                amount_sun: None,
                trc20_amount: Some(asset.amount.to_string()),
                contract: None,
                selector: None,
                asset_name: Some(asset.name),
                permission,
                generic: Vec::new(),
                known: true,
                complete: true,
                critical: false,
            })
        }
        // TriggerSmartContract：未知 selector 仍可展示合约/调用值，标 Partial。
        31 => {
            check_type_url(type_url, "TriggerSmartContract")?;
            let trigger = parse_trigger(value)?;
            let decoded = decode_trc20(&trigger.data);
            Some(ContractView {
                type_id: 31,
                type_name: "TriggerSmartContract".into(),
                to: decoded.as_ref().map(|d| d.to.clone()),
                amount_sun: (trigger.call_value > 0).then_some(trigger.call_value),
                trc20_amount: decoded.as_ref().map(|d| d.amount.clone()),
                contract: Some(trigger.contract),
                selector: trigger.data.get(..4).map(hex::encode),
                asset_name: None,
                permission,
                generic: Vec::new(),
                known: true,
                complete: decoded.is_some(),
                critical: false,
            })
        }
        // 其他类型：通用视图。名称优先取 type_url，其次查表，最后 Unknown(id)。
        other => Some(ContractView {
            type_id: other,
            type_name: type_url_name(type_url)
                .or_else(|| {
                    let name = contract_type_name(other);
                    (!name.is_empty()).then(|| name.to_string())
                })
                .unwrap_or_else(|| format!("Unknown({other})")),
            to: None,
            amount_sun: None,
            trc20_amount: None,
            contract: None,
            selector: None,
            asset_name: None,
            permission,
            generic: generic_fields(value),
            known: false,
            complete: false,
            critical: is_critical_contract(other),
        }),
    }
}

/// 通用字段提取：只做「能看懂就展示」的保守渲染，最多 8 行。
fn generic_fields(data: &[u8]) -> Vec<String> {
    let mut out = Vec::new();
    let mut pb = Pb::new(data);
    while out.len() < 8 {
        let Some((field, wire)) = pb.tag() else {
            break;
        };
        let line = match wire {
            0 => match pb.varint() {
                Some(value) => format!("field {field}: {value}"),
                None => break,
            },
            2 => match pb.bytes() {
                Some(bytes) if bytes.len() == 21 && bytes[0] == 0x41 => {
                    format!("field {field}: {}", tron_address(bytes).unwrap_or_else(|| format!("0x{}", hex::encode(bytes))))
                }
                Some(bytes)
                    if !bytes.is_empty()
                        && bytes.len() <= 64
                        && std::str::from_utf8(bytes).is_ok() =>
                {
                    format!("field {field}: \"{}\"", String::from_utf8_lossy(bytes))
                }
                Some(bytes) => {
                    let shown = hex::encode(&bytes[..bytes.len().min(32)]);
                    let ellipsis = if bytes.len() > 32 { "…" } else { "" };
                    format!("field {field}: 0x{shown}{ellipsis}")
                }
                None => break,
            },
            1 | 5 => {
                if pb.skip(wire).is_none() {
                    break;
                }
                format!("field {field}: <{} byte fixed>", if wire == 1 { 8 } else { 4 })
            }
            _ => break,
        };
        out.push(line);
    }
    out
}

/// `type.googleapis.com/protocol.TransferContract` → `TransferContract`。
fn type_url_name(type_url: Option<&[u8]>) -> Option<String> {
    let url = std::str::from_utf8(type_url?).ok()?;
    let name = url.rsplit('.').next()?;
    (!name.is_empty()).then(|| name.to_string())
}

/// `protocol.ContractType` 名称表（java-tron `Tron.proto`）。
fn contract_type_name(id: u64) -> &'static str {
    match id {
        0 => "AccountCreateContract",
        1 => "TransferContract",
        2 => "TransferAssetContract",
        3 => "VoteAssetContract",
        4 => "VoteWitnessContract",
        5 => "WitnessCreateContract",
        6 => "AssetIssueContract",
        8 => "WitnessUpdateContract",
        9 => "ParticipateAssetIssueContract",
        10 => "AccountUpdateContract",
        11 => "FreezeBalanceContract",
        12 => "UnfreezeBalanceContract",
        13 => "WithdrawBalanceContract",
        14 => "UnfreezeAssetContract",
        15 => "UpdateAssetContract",
        16 => "ProposalCreateContract",
        17 => "ProposalApproveContract",
        18 => "ProposalDeleteContract",
        19 => "SetAccountIdContract",
        20 => "CustomContract",
        30 => "CreateSmartContract",
        31 => "TriggerSmartContract",
        32 => "GetContract",
        33 => "UpdateSettingContract",
        41 => "ExchangeCreateContract",
        42 => "ExchangeInjectContract",
        43 => "ExchangeWithdrawContract",
        44 => "ExchangeTransactionContract",
        45 => "UpdateEnergyLimitContract",
        46 => "AccountPermissionUpdateContract",
        48 => "ClearABIContract",
        49 => "UpdateBrokerageContract",
        51 => "ShieldedTransferContract",
        52 => "MarketSellAssetContract",
        53 => "MarketCancelOrderContract",
        54 => "FreezeBalanceV2Contract",
        55 => "UnfreezeBalanceV2Contract",
        56 => "WithdrawExpireUnfreezeContract",
        57 => "DelegateResourceContract",
        58 => "UnDelegateResourceContract",
        59 => "CancelAllUnfreezeV2Contract",
        _ => "",
    }
}

/// 改权限 / 建合约 / 自定义合约 / 屏蔽交易：确认页必须显示 Critical。
fn is_critical_contract(id: u64) -> bool {
    matches!(id, 20 | 30 | 46 | 51)
}

fn check_type_url(type_url: Option<&[u8]>, expected: &str) -> Option<()> {
    match type_url {
        None => Some(()),
        Some(url) => {
            let url = std::str::from_utf8(url).ok()?;
            url.ends_with(expected).then_some(())
        }
    }
}

/// `TransferContract`：owner(1) / to(2) / amount(3)。owner 只用于校验长度，
/// 展示的账户始终是设备实际签名的派生地址。
fn parse_transfer(value: &[u8]) -> Option<(String, u64)> {
    let mut owner_seen = false;
    let mut to = None;
    let mut amount = None;
    let mut pb = Pb::new(value);
    while let Some((field, wire)) = pb.tag() {
        match (field, wire) {
            (1, 2) => {
                tron_address(pb.bytes()?)?;
                owner_seen = true;
            }
            (2, 2) => to = Some(tron_address(pb.bytes()?)?),
            (3, 0) => amount = Some(pb.varint()?),
            _ => pb.skip(wire)?,
        }
    }
    if !owner_seen {
        return None;
    }
    Some((to?, amount?))
}

struct TransferAsset {
    name: String,
    to: String,
    amount: u64,
}

/// `TransferAssetContract`：asset_name(1) / owner(2) / to(3) / amount(4)。
fn parse_transfer_asset(value: &[u8]) -> Option<TransferAsset> {
    let mut name = None;
    let mut owner_seen = false;
    let mut to = None;
    let mut amount = None;
    let mut pb = Pb::new(value);
    while let Some((field, wire)) = pb.tag() {
        match (field, wire) {
            (1, 2) => {
                name = Some(String::from_utf8(pb.bytes()?.to_vec()).ok()?);
            }
            (2, 2) => {
                tron_address(pb.bytes()?)?;
                owner_seen = true;
            }
            (3, 2) => to = Some(tron_address(pb.bytes()?)?),
            (4, 0) => amount = Some(pb.varint()?),
            _ => pb.skip(wire)?,
        }
    }
    if !owner_seen {
        return None;
    }
    Some(TransferAsset {
        name: name?,
        to: to?,
        amount: amount?,
    })
}

struct Trigger {
    contract: String,
    call_value: u64,
    data: Vec<u8>,
}

/// `TriggerSmartContract`：owner(1) / contract(2) / call_value(3) / data(4)。
fn parse_trigger(value: &[u8]) -> Option<Trigger> {
    let mut contract = None;
    let mut call_value = 0u64;
    let mut data = Vec::new();
    let mut pb = Pb::new(value);
    while let Some((field, wire)) = pb.tag() {
        match (field, wire) {
            (2, 2) => contract = Some(tron_address(pb.bytes()?)?),
            (3, 0) => call_value = pb.varint()?,
            (4, 2) => data = pb.bytes()?.to_vec(),
            _ => pb.skip(wire)?,
        }
    }
    Some(Trigger {
        contract: contract?,
        call_value,
        data,
    })
}

struct Trc20Call {
    to: String,
    amount: String,
}

/// 只解释 TRC-20 的三个常见方法；其余返回 `None`（摘要仍可展示）。
fn decode_trc20(data: &[u8]) -> Option<Trc20Call> {
    if data.len() < 4 {
        return None;
    }
    match &data[..4] {
        // transfer(address,uint256)
        [0xa9, 0x05, 0x9c, 0xbb] => {
            if data.len() < 68 {
                return None;
            }
            Some(Trc20Call {
                to: tron_address(&with_prefix(&data[16..36]))?,
                amount: bytes_to_decimal(&data[36..68]),
            })
        }
        // approve(address,uint256)
        [0x09, 0x5e, 0xa7, 0xb3] => {
            if data.len() < 68 {
                return None;
            }
            Some(Trc20Call {
                to: tron_address(&with_prefix(&data[16..36]))?,
                amount: bytes_to_decimal(&data[36..68]),
            })
        }
        // transferFrom(address,address,uint256)
        [0x23, 0xb8, 0x72, 0xdd] => {
            if data.len() < 100 {
                return None;
            }
            Some(Trc20Call {
                to: tron_address(&with_prefix(&data[48..68]))?,
                amount: bytes_to_decimal(&data[68..100]),
            })
        }
        _ => None,
    }
}

/// EVM 风格 20 字节地址补上 Tron 的 `0x41` 前缀。
fn with_prefix(address: &[u8]) -> Vec<u8> {
    let mut raw = Vec::with_capacity(1 + address.len());
    raw.push(0x41);
    raw.extend_from_slice(address);
    raw
}

fn bytes_to_decimal(bytes: &[u8]) -> String {
    let mut digits = vec![0u8];
    for byte in bytes {
        let mut carry = u32::from(*byte);
        for digit in digits.iter_mut() {
            let value = u32::from(*digit) * 256 + carry;
            *digit = (value % 10) as u8;
            carry = value / 10;
        }
        while carry > 0 {
            digits.push((carry % 10) as u8);
            carry /= 10;
        }
    }
    let text: String = digits.iter().rev().map(|d| char::from(b'0' + d)).collect();
    let trimmed = text.trim_start_matches('0');
    if trimmed.is_empty() {
        "0".to_string()
    } else {
        trimmed.to_string()
    }
}

/// `0x41 || 20B` → base58check；其他长度视为非法地址。
fn tron_address(raw: &[u8]) -> Option<String> {
    if raw.len() != 21 || raw[0] != 0x41 {
        return None;
    }
    Some(base58::encode_check(raw))
}

/// `keccak256("\x19TRON Signed Message:\n" + 十进制长度 + message)`。
fn personal_digest(message: &[u8]) -> [u8; 32] {
    let mut payload = Vec::with_capacity(SIGN_MAGIC.len() + 10 + message.len());
    payload.extend_from_slice(SIGN_MAGIC);
    payload.extend_from_slice(message.len().to_string().as_bytes());
    payload.extend_from_slice(message);
    keccak256::hash(&payload)
}

/// `[count][u32 BE]*[remainder]`。
fn split_path(data: &[u8]) -> Option<(Vec<u32>, &[u8])> {
    let count = *data.first()? as usize;
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

fn is_tron_path(path: &[u32]) -> bool {
    path.len() >= 2 && path[0] == TRON_PREFIX[0] && path[1] == TRON_PREFIX[1]
}

fn address_from_uncompressed(public_key: &[u8]) -> Option<String> {
    if public_key.len() != 65 || public_key[0] != 0x04 {
        return None;
    }
    let hash = keccak256::hash(&public_key[1..]);
    let mut raw = Vec::with_capacity(21);
    raw.push(0x41);
    raw.extend_from_slice(&hash[12..]);
    Some(base58::encode_check(&raw))
}

/// 账户路径：Tron 的账户号在最后一段（`m/44'/195'/0'/0/{account}`）。
fn account_path(index: u32) -> Vec<u32> {
    let mut path = DEFAULT_PATH;
    path[4] = index;
    path.to_vec()
}

pub fn descriptor() -> AppDescriptor {
    AppDescriptor {
        module_id: MODULE_ID.into(),
        module_version: "0.4.0".into(),
        api_version: API_VERSION,
        review_schema_version: 1,
        storage_schema_version: 1,
        protocol_profiles: vec![chain_app_api::ProtocolProfile {
            name: "Tron".into(),
            version: "0.5.0".into(),
            wire: Wire::LedgerApdu,
            supported: vec![
                "E0 02 GET_PUBLIC_KEY (P1 confirm, P2 chaincode)".into(),
                "E0 04 SIGN (raw protobuf, sha256, chunked; precise Transfer/TransferAsset/TriggerSmart, generic fallback; TRC10 token-name chunks)".into(),
                "E0 05 SIGN_TXN_HASH (32B digest)".into(),
                "E0 06 GET_APP_CONFIGURATION".into(),
                "E0 08 SIGN_PERSONAL_MESSAGE (TRON prefix, chunked)".into(),
                "E0 0A GET_ECDH_SECRET".into(),
                "E0 0C SIGN_TIP_712_MESSAGE".into(),
            ],
            unsupported: vec![
                "E0 04 more than 8 contracts / malformed protobuf / broken known-type fields".into(),
            ],
            vector_sources: vec![
                "LedgerHQ/app-tron: src/handlers/{sign,sign_txn_hash,sign_personal_message}.c"
                    .into(),
                "tool/e2e/tests/tron_sign.py".into(),
            ],
        }],
        account_profiles: vec![AccountProfile {
            network: "Tron".into(),
            account_type: "secp256k1".into(),
            default_path: "m/44'/195'/0'/0/0".into(),
            derivation_scheme: DerivationScheme::Bip32Secp256k1,
            curve: Curve::Secp256k1,
        }],
        requested_capabilities: chain_app_api::CapabilitySet {
            derivation_rules: vec![DerivationRule {
                derivation_scheme: DerivationScheme::Bip32Secp256k1,
                curve: Curve::Secp256k1,
                depth: 5,
                hardened_positions: vec![0, 1, 2],
                max_index: 1000,
            }],
            allow_chain_code: true,
            allow_signing: true,
            allow_storage: false,
        },
    }
}

pub struct TronFactory;

impl chain_app_api::ModuleFactory for TronFactory {
    fn describe(&self) -> AppDescriptor {
        descriptor()
    }

    fn create(&self) -> Box<dyn ChainApp> {
        Box::new(TronModule::new())
    }
}
