//! Sui 链 App —— 对齐官方 `LedgerHQ/app-sui` 的 APDU 语义。
//!
//! 事实来源（`app-sui` `develop`，`rust-app/Cargo.toml` 版本 1.5.11）：
//!
//! - `docs/apdu.md`：`CLA 0x00` 且 `P1`/`P2` 必须为 0；`0x00 GET_VERSION`、
//!   `0x01 VERIFY_ADDRESS`、`0x02 GET_PUBKEY`、`0x03 SIGN_TX`、
//!   `0x22 PROVIDE_TRUSTED_DYNAMIC_DESCRIPTOR`、`0xFE GET_VERSION_STR`、`0xFF QUIT_APP`。
//! - `docs/block-protocol.md` 与 `tests/application_client/client.py`：**所有**命令都套
//!   Block Protocol，`START`/`GET_CHUNK`/`RESULT_FINAL` 由 [`block`] 实现。
//! - `rust-app/src/interface.rs`：路径与公钥的线格式是 `[n][u32 **little-endian**]*n`；
//!   返回 `[pubkey_len][pubkey][address_len][address]`。
//! - `rust-app/src/implementation.rs`：`SIGN_TX` 签的是**整段交易字节**的 BLAKE2b-256，
//!   且解析必须刚好吃掉宿主声明的长度；解析不出可展示字段时**拒绝**（未开盲签）。
//!
//! 状态字按 `ledger_device_sdk` 的实际取值（与 `apdu.md` 的状态表不同）：
//! `9000` 成功、`6985` 用户拒绝、`6E00` CLA 不符、`6E01` INS/P1/P2 不符、
//! `6E03` 长度错误、`6982` 无数据；不可识别的交易回 `6808`（`SW_NOT_SUPPORTED`，
//! 即「拒绝盲签」）。`0x22` 依赖 Ledger PKI/CAL，本期不实现，回 `6D00`。

pub mod bcs;
pub mod block;

use chain_app_api::{
    AccountProfile, AppDescriptor, AppError, ChainApp, Curve, DerivationRule, DerivationScheme,
    Effect, Event, ExchangeId, FeeKind, Field, FieldValue, FinishStatus, KeyOutput, NetworkId,
    OperationKind, OperationState, ParseStatus, PublicKeyRequest, ReviewAction, ReviewDocument,
    ReviewOutcome, ReviewRequest, ReviewSection, ServiceResult, SessionConfig, SignOperation,
    SignPlan, SignScheme, Wire, API_VERSION,
};
use open_ledger_crypto::blake2b;

pub mod sw {
    pub const OK: u16 = 0x9000;
    /// `StatusWords::UserCancelled`。
    pub const DENIED: u16 = 0x6985;
    /// `StatusWords::NothingReceived`。
    pub const NOTHING_RECEIVED: u16 = 0x6982;
    /// `SW_NOT_SUPPORTED`：交易无法被本机解析，拒绝盲签。
    pub const NOT_SUPPORTED: u16 = 0x6808;
    /// `StatusWords::BadCla`。
    pub const BAD_CLA: u16 = 0x6E00;
    /// `StatusWords::BadIns`：INS 未实现，或 CLA/P1/P2 组合与官方不一致。
    pub const BAD_INS: u16 = 0x6E01;
    /// `StatusWords::BadLen`。
    pub const BAD_LEN: u16 = 0x6E03;
    /// `StatusWords::Unknown`。
    pub const UNKNOWN: u16 = 0x6D00;
}

pub const MODULE_ID: &str = "openledger.sui";

const CLA_SUI: u8 = 0x00;
const INS_GET_VERSION: u8 = 0x00;
const INS_VERIFY_ADDRESS: u8 = 0x01;
const INS_GET_PUBKEY: u8 = 0x02;
const INS_SIGN_TX: u8 = 0x03;
const INS_TOKEN_DESCRIPTOR: u8 = 0x22;
const INS_GET_VERSION_STR: u8 = 0xFE;
const INS_QUIT_APP: u8 = 0xFF;

/// 官方 `rust-app/Cargo.toml` 的版本号；官方 JS 客户端要求 `major > 0` 才会带对象表。
const APP_VERSION: [u8; 3] = [1, 5, 11];
const APP_NAME: &str = "sui";

/// `m/44'/784'/0'/0'/0'`。
const DEFAULT_PATH: [u32; 5] = [
    0x8000_002C,
    0x8000_0310,
    0x8000_0000,
    0x8000_0000,
    0x8000_0000,
];

const MAX_PATH_DEPTH: usize = 10;

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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Stage {
    Idle,
    /// 正在按 Block Protocol 收集参数。
    Collecting,
    /// 等待宿主派生公钥。
    AwaitKey,
    /// 等待用户在确认页上决定（地址确认或签名）。
    AwaitReview,
}

struct Pending {
    exchange_id: ExchangeId,
    ins: u8,
    path: Vec<u32>,
    /// 待签的整段交易字节（`SIGN_TX` 才有）；签名对象就是它本身。
    tx: Vec<u8>,
    /// 已解析的交易（`SIGN_TX` 才有）。
    transfer: Option<bcs::Transfer>,
    public_key: Vec<u8>,
    address: String,
}

pub struct SuiModule {
    stage: Stage,
    request: Option<block::Request>,
    /// 收集中的命令编号；`GET_CHUNK` 回包必须与它一致。
    request_ins: u8,
    pending: Option<Pending>,
    /// 本机账户请求的 `request_id`（`LocalCommand::DeriveAccount`）。
    local: Option<u64>,
}

impl Default for SuiModule {
    fn default() -> Self {
        Self::new()
    }
}

impl SuiModule {
    pub fn new() -> Self {
        Self {
            stage: Stage::Idle,
            request: None,
            request_ins: 0,
            pending: None,
            local: None,
        }
    }

    /// 成功收尾：`RESULT_FINAL` 指令 + 结果 + `9000`，会话结束。
    fn reply_final(&self, exchange_id: ExchangeId, result: &[u8]) -> Effect {
        let mut payload = block::final_reply(result);
        payload.extend_from_slice(&status(sw::OK));
        Effect::Emit {
            wire: Wire::LedgerApdu,
            exchange_id,
            payload,
            state: OperationState::Final,
        }
    }

    /// 只要状态字（错误路径与官方一致：不附加 LedgerToHost 指令）。
    fn reply_status(&self, exchange_id: ExchangeId, code: u16) -> Effect {
        Effect::Emit {
            wire: Wire::LedgerApdu,
            exchange_id,
            payload: status(code),
            state: OperationState::Final,
        }
    }

    /// `GET_CHUNK`：指令 + 哈希 + `9000`，会话保持。
    fn reply_chunk(&self, exchange_id: ExchangeId, hash: &[u8; block::HASH_LEN]) -> Effect {
        let mut payload = block::get_chunk_reply(hash);
        payload.extend_from_slice(&status(sw::OK));
        Effect::Emit {
            wire: Wire::LedgerApdu,
            exchange_id,
            payload,
            state: OperationState::Collecting,
        }
    }

    fn abort(&mut self) {
        self.request = None;
        self.pending = None;
        self.stage = Stage::Idle;
    }

    fn handle_apdu(&mut self, exchange_id: ExchangeId, bytes: &[u8]) -> Result<Effect, AppError> {
        let apdu =
            Apdu::parse(bytes).ok_or_else(|| AppError::BadRequest("truncated APDU".into()))?;
        if apdu.cla != CLA_SUI {
            return Ok(self.reply_status(exchange_id, sw::BAD_CLA));
        }
        // 官方 `interface.rs`：`P1`/`P2` 必须为 0，否则按 BadIns 处理。
        if apdu.p1 != 0 || apdu.p2 != 0 {
            return Ok(self.reply_status(exchange_id, sw::BAD_INS));
        }
        if self.stage == Stage::Collecting {
            return self.handle_chunk(exchange_id, apdu.ins, &apdu.data);
        }
        if self.stage != Stage::Idle {
            // 审批/派生期间不接受新命令；保持原状态，等 ServiceResult/ReviewResult。
            return Ok(self.reply_status(exchange_id, sw::BAD_INS));
        }
        if apdu.data.is_empty() {
            return Ok(self.reply_status(exchange_id, sw::NOTHING_RECEIVED));
        }
        if apdu.data[0] != block::HOST_START {
            return Ok(self.reply_status(exchange_id, sw::BAD_INS));
        }
        self.handle_start(exchange_id, apdu.ins, apdu.data)
    }

    fn handle_start(
        &mut self,
        exchange_id: ExchangeId,
        ins: u8,
        data: Vec<u8>,
    ) -> Result<Effect, AppError> {
        match ins {
            // 无参数命令：不必让主机多跑一轮，直接给最终结果（协议允许）。
            INS_GET_VERSION => {
                let mut result = APP_VERSION.to_vec();
                result.extend_from_slice(APP_NAME.as_bytes());
                Ok(self.reply_final(exchange_id, &result))
            }
            INS_GET_VERSION_STR => {
                let text = format!(
                    "{}.{}.{}",
                    APP_VERSION[0], APP_VERSION[1], APP_VERSION[2]
                );
                Ok(self.reply_final(exchange_id, text.as_bytes()))
            }
            INS_QUIT_APP => Ok(self.reply_final(exchange_id, &[])),
            INS_TOKEN_DESCRIPTOR => Ok(self.reply_status(exchange_id, sw::UNKNOWN)),
            INS_VERIFY_ADDRESS | INS_GET_PUBKEY | INS_SIGN_TX => {
                let (request, progress) = match block::Request::start(&data) {
                    Ok(value) => value,
                    Err(error) => {
                        return Ok(self.reply_status(exchange_id, block_status(error)));
                    }
                };
                let expected = if ins == INS_SIGN_TX { 2..=3 } else { 1..=1 };
                if !expected.contains(&request.params().len()) {
                    return Ok(self.reply_status(exchange_id, sw::BAD_LEN));
                }
                self.request = Some(request);
                self.request_ins = ins;
                self.stage = Stage::Collecting;
                match progress {
                    block::Progress::NeedChunk(hash) => Ok(self.reply_chunk(exchange_id, &hash)),
                    // 参数个数为 0 不会到这里（`START` 至少一个哈希）。
                    block::Progress::Complete => Ok(self.reply_status(exchange_id, sw::BAD_LEN)),
                }
            }
            _ => Ok(self.reply_status(exchange_id, sw::BAD_INS)),
        }
    }

    fn handle_chunk(
        &mut self,
        exchange_id: ExchangeId,
        ins: u8,
        data: &[u8],
    ) -> Result<Effect, AppError> {
        if ins != self.request_ins {
            self.abort();
            return Ok(self.reply_status(exchange_id, sw::BAD_INS));
        }
        // 主机重发 `START`：按新的一轮重新开始。
        if data.first() == Some(&block::HOST_START) {
            return self.handle_start(exchange_id, ins, data.to_vec());
        }
        let Some(request) = self.request.as_mut() else {
            self.abort();
            return Ok(self.reply_status(exchange_id, sw::BAD_INS));
        };
        match request.receive(data) {
            Ok(block::Progress::NeedChunk(hash)) => Ok(self.reply_chunk(exchange_id, &hash)),
            Ok(block::Progress::Complete) => {
                let Some(request) = self.request.take() else {
                    self.stage = Stage::Idle;
                    return Ok(self.reply_status(exchange_id, sw::BAD_INS));
                };
                let params = request.params().to_vec();
                self.stage = Stage::Idle;
                self.dispatch(exchange_id, ins, &params)
            }
            Err(error) => {
                self.abort();
                Ok(self.reply_status(exchange_id, block_status(error)))
            }
        }
    }

    /// 参数收齐后按命令分派。
    fn dispatch(
        &mut self,
        exchange_id: ExchangeId,
        ins: u8,
        params: &[Vec<u8>],
    ) -> Result<Effect, AppError> {
        // `SIGN_TX` 的参数顺序是 [交易, 路径, 对象表]；其余命令只有路径。
        let (path_param, tx_param) = if ins == INS_SIGN_TX {
            (params.get(1), params.first())
        } else {
            (params.first(), None)
        };
        let Some(path) = path_param.and_then(|param| parse_path(param)) else {
            return Ok(self.reply_status(exchange_id, sw::BAD_LEN));
        };
        let transfer = if let Some(tx_param) = tx_param {
            let Some(tx) = parse_transaction_param(tx_param) else {
                return Ok(self.reply_status(exchange_id, sw::BAD_LEN));
            };
            match bcs::parse_transaction(tx) {
                bcs::Parsed::Transfer(transfer) => Some(transfer),
                // 官方在未开盲签时拒绝：这里不创建审阅，直接 `6808`。
                bcs::Parsed::Unsupported => {
                    return Ok(self.reply_status(exchange_id, sw::NOT_SUPPORTED))
                }
            }
        } else {
            None
        };
        let tx = tx_param
            .and_then(|param| parse_transaction_param(param))
            .unwrap_or_default()
            .to_vec();
        self.pending = Some(Pending {
            exchange_id,
            ins,
            path: path.clone(),
            tx,
            transfer,
            public_key: Vec::new(),
            address: String::new(),
        });
        self.stage = Stage::AwaitKey;
        Ok(Effect::NeedPublicKey {
            service_id: if ins == INS_SIGN_TX { 2 } else { 1 },
            request: key_request(path),
        })
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
                    request: key_request(account_path(address_index)),
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
                ServiceResult::PublicKey(key) if key.bytes.len() == 32 => format!(
                    "{{\"address\":\"{}\",\"public_key\":\"{}\"}}",
                    sui_address(&key.bytes),
                    hex::encode(&key.bytes)
                )
                .into_bytes(),
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
                return Ok(self.reply_status(exchange_id, sw::UNKNOWN));
            }
            ServiceResult::Storage(_) | ServiceResult::SharedSecret(_) => {
                return Err(AppError::InvalidEvent("unexpected storage result".into()))
            }
        };
        if key.bytes.len() != 32 {
            let exchange_id = self.pending.take().map(|p| p.exchange_id).unwrap_or(1);
            self.stage = Stage::Idle;
            return Ok(self.reply_status(exchange_id, sw::UNKNOWN));
        }

        let address = sui_address(&key.bytes);
        let address_bytes = sui_address_bytes(&key.bytes);
        let (exchange_id, ins, path, transfer, tx) = {
            let pending = self
                .pending
                .as_mut()
                .ok_or_else(|| AppError::InvalidEvent("no pending request".into()))?;
            pending.public_key = key.bytes.clone();
            pending.address = address.clone();
            (
                pending.exchange_id,
                pending.ins,
                pending.path.clone(),
                pending.transfer.clone(),
                pending.tx.clone(),
            )
        };

        // `0x02 GET_PUBKEY`：不经确认，直接回 `[len][pubkey][len][address]`。
        if ins == INS_GET_PUBKEY {
            self.pending = None;
            self.stage = Stage::Idle;
            return Ok(self.reply_final(
                exchange_id,
                &sui_key_reply(&key.bytes, &address_bytes),
            ));
        }

        let document = match (ins, transfer.as_ref()) {
            (INS_SIGN_TX, Some(transfer)) => sign_document(&address, transfer),
            _ => address_document(&address),
        };
        self.stage = Stage::AwaitReview;
        Ok(Effect::NeedReview {
            service_id: 3,
            request: Box::new(ReviewRequest {
                document,
                action: if ins == INS_SIGN_TX {
                    ReviewAction::Sign(SignPlan::single(SignOperation {
                        operation_id: 1,
                        derivation_scheme: DerivationScheme::Slip10Ed25519,
                        curve: Curve::Ed25519,
                        path,
                        scheme: SignScheme::Ed25519Message,
                        // 设备签的是宿主交来的整段交易字节（官方 `implementation.rs`）。
                        input: tx,
                        public_parameters: Vec::new(),
                    }))
                } else {
                    ReviewAction::DisplayAddress {
                        derivation_scheme: DerivationScheme::Slip10Ed25519,
                        curve: Curve::Ed25519,
                        path,
                    }
                },
            }),
        })
    }

    fn handle_review(&mut self, outcome: ReviewOutcome) -> Result<Effect, AppError> {
        let pending = self
            .pending
            .take()
            .ok_or_else(|| AppError::InvalidEvent("no pending review".into()))?;
        self.stage = Stage::Idle;
        match outcome {
            ReviewOutcome::Approved { signatures } => {
                if pending.ins == INS_SIGN_TX {
                    if signatures.len() == 1 && signatures[0].bytes.len() == 64 {
                        return Ok(self.reply_final(pending.exchange_id, &signatures[0].bytes));
                    }
                    return Ok(self.reply_status(pending.exchange_id, sw::UNKNOWN));
                }
                let address_bytes = sui_address_bytes(&pending.public_key);
                Ok(self.reply_final(
                    pending.exchange_id,
                    &sui_key_reply(&pending.public_key, &address_bytes),
                ))
            }
            ReviewOutcome::Rejected | ReviewOutcome::TimedOut => {
                Ok(self.reply_status(pending.exchange_id, sw::DENIED))
            }
            ReviewOutcome::Failed(_) => Ok(self.reply_status(pending.exchange_id, sw::UNKNOWN)),
        }
    }
}

impl ChainApp for SuiModule {
    fn open(&mut self, _config: SessionConfig) -> Result<(), AppError> {
        self.request = None;
        self.pending = None;
        self.local = None;
        self.stage = Stage::Idle;
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
            // 收集阶段必须挂起会话，否则主机的下一帧 `GET_CHUNK_RESPONSE` 进不来。
            Event::Delivered { .. } => {
                if self.stage == Stage::Collecting {
                    Ok(Effect::AwaitInput)
                } else {
                    Ok(Effect::Finished {
                        status: FinishStatus::Delivered,
                    })
                }
            }
            Event::Cancel { .. } => {
                self.abort();
                self.local = None;
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
        self.abort();
        self.local = None;
    }
}

fn block_status(error: block::BlockError) -> u16 {
    match error {
        block::BlockError::Unexpected => sw::BAD_INS,
        block::BlockError::BadLen => sw::BAD_LEN,
        block::BlockError::Integrity => sw::UNKNOWN,
    }
}

/// 账户路径：Sui 的账户号在第三段（`m/44'/784'/{account}'/0'/0'`）。
fn account_path(index: u32) -> Vec<u32> {
    let mut path = DEFAULT_PATH;
    path[2] = 0x8000_0000 | index;
    path.to_vec()
}

/// Sui 地址：`0x` + `blake2b(0x00 || pubkey)`。
fn sui_address_bytes(public_key: &[u8]) -> [u8; 32] {
    let mut input = Vec::with_capacity(1 + public_key.len());
    input.push(0x00);
    input.extend_from_slice(public_key);
    blake2b::hash(&input)
}

fn sui_address(public_key: &[u8]) -> String {
    format!("0x{}", hex::encode(sui_address_bytes(public_key)))
}

/// `[32][pubkey][32][address]`，与官方 `get_address_apdu` 一致。
fn sui_key_reply(public_key: &[u8], address: &[u8; 32]) -> Vec<u8> {
    let mut out = Vec::with_capacity(2 + public_key.len() + address.len());
    out.push(public_key.len() as u8);
    out.extend_from_slice(public_key);
    out.push(address.len() as u8);
    out.extend_from_slice(address);
    out
}

fn key_request(path: Vec<u32>) -> PublicKeyRequest {
    PublicKeyRequest {
        derivation_scheme: DerivationScheme::Slip10Ed25519,
        curve: Curve::Ed25519,
        path,
        output: KeyOutput::Ed25519,
        include_chain_code: false,
    }
}

/// `[count][u32 **little-endian**]*count`（官方 `Bip32Key`）。
fn parse_path(data: &[u8]) -> Option<Vec<u32>> {
    let Some((&count, rest)) = data.split_first() else {
        return None;
    };
    let count = count as usize;
    if count == 0 || count > MAX_PATH_DEPTH || rest.len() != count * 4 {
        return None;
    }
    let mut path = Vec::with_capacity(count);
    for chunk in rest.chunks_exact(4) {
        path.push(u32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]));
    }
    // 官方 `get_address_apdu` 只要求 `m/44'/784'` 前缀；我们的钱包固定 5 段全硬化。
    if path.len() != 5 || path[..2] != DEFAULT_PATH[..2] {
        return None;
    }
    if path.iter().any(|component| component & 0x8000_0000 == 0) {
        return None;
    }
    Some(path)
}

/// `SIGN_TX` 的参数 1：`[u32 little-endian len][tx bytes]`。
fn parse_transaction_param(param: &[u8]) -> Option<&[u8]> {
    if param.len() < 4 {
        return None;
    }
    let len = u32::from_le_bytes([param[0], param[1], param[2], param[3]]) as usize;
    let tx = param.get(4..4 + len)?;
    if tx.len() != len {
        return None;
    }
    Some(tx)
}

fn address_document(address: &str) -> ReviewDocument {
    ReviewDocument {
        operation: OperationKind::AddressConfirmation,
        network: NetworkId {
            name: "Sui".into(),
            chain_id: None,
        },
        account: Some(address.into()),
        sections: vec![ReviewSection {
            title_key: "review.section.sui".into(),
            fields: vec![Field {
                label_key: "review.field.address".into(),
                value: FieldValue::Address {
                    value: address.into(),
                    network: "Sui".into(),
                    role: "account".into(),
                },
            }],
        }],
        risks: Vec::new(),
        parse_status: ParseStatus::Complete,
    }
}

fn sign_document(address: &str, transfer: &bcs::Transfer) -> ReviewDocument {
    let native = transfer.asset == bcs::Asset::Native;
    let recipient = format!("0x{}", hex::encode(transfer.recipient));
    let fields = vec![
        Field {
            label_key: "review.field.to".into(),
            value: FieldValue::Address {
                value: recipient,
                network: "Sui".into(),
                role: "recipient".into(),
            },
        },
        Field {
            label_key: "review.field.asset".into(),
            value: FieldValue::Text {
                value: if native {
                    "SUI".into()
                } else {
                    // 代币的精度来自对象元数据（需要 Ledger PKI），本期只给 base units。
                    "token (base units)".into()
                },
            },
        },
        Field {
            label_key: "review.field.amount".into(),
            value: FieldValue::Amount {
                raw: transfer.amount.to_string(),
                decimals: if native { bcs::SUI_DECIMALS } else { 0 },
                asset: if native { "SUI".into() } else { "TOKEN".into() },
                ticker: if native { Some("SUI".into()) } else { None },
            },
        },
        Field {
            label_key: "review.field.max_fee".into(),
            value: FieldValue::Fee {
                kind: FeeKind::UpperBound,
                raw: Some(transfer.gas_budget.to_string()),
                decimals: bcs::SUI_DECIMALS,
                asset: "SUI".into(),
            },
        },
        Field {
            label_key: "review.field.gas_price".into(),
            value: FieldValue::Text {
                value: transfer.gas_price.to_string(),
            },
        },
        Field {
            label_key: "review.field.gas_payment".into(),
            value: FieldValue::Text {
                value: if transfer.gas_payments == 0 {
                    "address balance".into()
                } else {
                    format!("{} coin(s)", transfer.gas_payments)
                },
            },
        },
    ];
    ReviewDocument {
        operation: OperationKind::Transaction,
        network: NetworkId {
            name: "Sui".into(),
            chain_id: None,
        },
        account: Some(address.into()),
        sections: vec![ReviewSection {
            title_key: "review.section.sui".into(),
            fields,
        }],
        // 字段全部来自本机 BCS 解析；没有部分可读的情况（不可解析即已拒绝）。
        risks: Vec::new(),
        parse_status: ParseStatus::Complete,
    }
}

pub fn descriptor() -> AppDescriptor {
    AppDescriptor {
        module_id: MODULE_ID.into(),
        module_version: "0.2.0".into(),
        api_version: API_VERSION,
        review_schema_version: 1,
        storage_schema_version: 1,
        protocol_profiles: vec![chain_app_api::ProtocolProfile {
            name: "Sui".into(),
            version: "1.5.11".into(),
            wire: Wire::LedgerApdu,
            supported: vec![
                "00 GET_VERSION (official; Block Protocol)".into(),
                "00 01 VERIFY_ADDRESS (official)".into(),
                "00 02 GET_PUBKEY (official)".into(),
                "00 03 SIGN_TX (official; device parses BCS, native + token transfers)".into(),
                "00 FE GET_VERSION_STR (official)".into(),
                "00 FF QUIT_APP (official; the app resets its own context)".into(),
            ],
            unsupported: vec![
                "00 22 PROVIDE_TRUSTED_DYNAMIC_DESCRIPTOR (needs Ledger PKI/CAL)".into(),
                "MoveCall / MergeCoins / send-max / SIP-58 funds-withdrawal transactions".into(),
            ],
            vector_sources: vec![
                "crates/chain-app-sui/tests/standard_protocol.rs".into(),
                "tool/e2e/tests/sui_sign.py".into(),
            ],
        }],
        account_profiles: vec![AccountProfile {
            network: "Sui".into(),
            account_type: "ed25519".into(),
            default_path: "m/44'/784'/0'/0'/0'".into(),
            derivation_scheme: DerivationScheme::Slip10Ed25519,
            curve: Curve::Ed25519,
        }],
        requested_capabilities: chain_app_api::CapabilitySet {
            derivation_rules: vec![DerivationRule {
                derivation_scheme: DerivationScheme::Slip10Ed25519,
                curve: Curve::Ed25519,
                depth: 5,
                hardened_positions: vec![0, 1, 2, 3, 4],
                max_index: 1000,
            }],
            allow_chain_code: false,
            allow_signing: true,
            allow_storage: false,
        },
    }
}

pub struct SuiFactory;

impl chain_app_api::ModuleFactory for SuiFactory {
    fn describe(&self) -> AppDescriptor {
        descriptor()
    }

    fn create(&self) -> Box<dyn ChainApp> {
        Box::new(SuiModule::new())
    }
}
