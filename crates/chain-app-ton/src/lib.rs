//! TON 链 App。
//!
//! 协议对齐 ton-blockchain/ledger-app-ton：
//!
//! - `E0 03 GET_VERSION`、`E0 04 GET_APP_NAME`；
//! - `E0 05 GET_PUBLIC_KEY`：`P1=0` 静默、`P1=1` 显示确认；`CData` 为
//!   `[count][u32 BE × count]`，路径至少 3 段且以 `m/44'/607'/` 开头；
//! - `E0 06 SIGN_TX`：首包 `P2=0x03` 携带路径，后续 `P2=0x02`（还有）/`0x00`
//!   （末包）携带交易请求字节（见 `TRANSACTION.md`）。签名对象是 v4r2
//!   `TransactionOrder` cell 的表示哈希，响应
//!   `[len=64][signature][len=32][hash]`。
//!
//! 只支持**无 state-init、无 payload/hints 的普通转账**：这两种形态需要完整的
//! cell 引用与提示解析，未实现前一律回 `B010`，不猜测。`GET_ADDRESS_PROOF`
//! 与 `SIGN_DATA`（TON Connect）同样回 `6D00`。

use chain_app_api::{
    AccountProfile, AppDescriptor, AppError, ChainApp, Curve, DerivationRule, DerivationScheme,
    Effect, Event, ExchangeId, Field, FieldValue, FinishStatus, KeyOutput, NetworkId,
    OperationKind, ParseStatus, PublicKeyRequest, ReviewAction, ReviewDocument, ReviewOutcome,
    ReviewRequest, ReviewSection, ServiceResult, SessionConfig, SignOperation, SignPlan,
    SignScheme, Wire, API_VERSION,
};
use open_ledger_crypto::sha256;

pub mod sw {
    pub const OK: u16 = 0x9000;
    pub const DENIED: u16 = 0x6985;
    pub const WRONG_P1_P2: u16 = 0x6A86;
    pub const WRONG_DATA_LENGTH: u16 = 0x6A87;
    pub const UNKNOWN_INS: u16 = 0x6D00;
    pub const CLA_NOT_SUPPORTED: u16 = 0x6E00;
    pub const UNKNOWN: u16 = 0x6F00;
    pub const TX_PARSING_FAIL: u16 = 0xB010;
}

pub const MODULE_ID: &str = "openledger.ton";

const CLA_TON: u8 = 0xE0;
const INS_GET_VERSION: u8 = 0x03;
const INS_GET_APP_NAME: u8 = 0x04;
const INS_GET_PUBLIC_KEY: u8 = 0x05;
const INS_SIGN_TX: u8 = 0x06;

/// SIGN_TX 的分包标记。
const P2_FIRST_AND_MORE: u8 = 0x03;
const P2_MORE: u8 = 0x02;
const P2_LAST: u8 = 0x00;

/// v4r2 的 subwallet_id。
const SUBWALLET_ID: u32 = 698_983_191;
/// 交易请求总长上限（官方实现）。
const MAX_TX: usize = 510;

/// 设备账户路径 `m/44'/607'/0'/0'/{account}'/0'`（ton-ledger 的
/// `pathForAccount`：network / workchain / account / 预留合约位）。
const DEFAULT_ACCOUNT_PATH: [u32; 6] = [
    0x8000_002C,
    0x8000_025F,
    0x8000_0000,
    0x8000_0000,
    0x8000_0000,
    0x8000_0000,
];

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

// ── Cell 构造 ─────────────────────────────────────────────────────────

/// 位级写入器；`finish` 按 TON 的规则用 `1` 补位到字节边界。
struct Bits {
    bytes: Vec<u8>,
    bit_len: usize,
}

impl Bits {
    fn new() -> Self {
        Self {
            bytes: Vec::new(),
            bit_len: 0,
        }
    }

    fn push_bit(&mut self, bit: bool) {
        if self.bit_len % 8 == 0 {
            self.bytes.push(0);
        }
        if bit {
            let index = self.bit_len / 8;
            self.bytes[index] |= 1 << (7 - self.bit_len % 8);
        }
        self.bit_len += 1;
    }

    fn push_uint(&mut self, value: u64, bits: usize) {
        for shift in (0..bits).rev() {
            self.push_bit((value >> shift) & 1 == 1);
        }
    }

    fn push_bytes(&mut self, bytes: &[u8]) {
        for byte in bytes {
            self.push_uint(u64::from(*byte), 8);
        }
    }

    fn finish(mut self) -> (usize, Vec<u8>) {
        let bit_len = self.bit_len;
        if bit_len % 8 != 0 {
            self.push_bit(true);
            while self.bit_len % 8 != 0 {
                self.push_bit(false);
            }
        }
        (bit_len, self.bytes)
    }
}

/// 普通 cell 的表示哈希：`d1 · d2 · data · (depth · hash) × refs`。
fn cell_hash(bits: usize, data: &[u8], refs: &[(u16, [u8; 32])]) -> [u8; 32] {
    let d1 = (refs.len() as u8) << 4;
    let d2 = ((bits / 8) * 2 + usize::from(bits % 8 != 0)) as u8;
    let mut buf = Vec::with_capacity(2 + data.len() + refs.len() * 34);
    buf.push(d1);
    buf.push(d2);
    buf.extend_from_slice(data);
    for (depth, hash) in refs {
        buf.extend_from_slice(&depth.to_be_bytes());
        buf.extend_from_slice(hash);
    }
    sha256::hash(&buf)
}

/// `TRANSACTION.md` 里的交易请求（仅普通转账）。
#[derive(Clone)]
struct TxOrder {
    seqno: u32,
    timeout: u32,
    /// VarUInteger 的原始字节（大端）。
    value: Vec<u8>,
    chain: u8,
    to_hash: [u8; 32],
    bounce: bool,
    send_mode: u8,
}

impl TxOrder {
    /// 构造 v4r2 的 `TransactionOrder` cell，返回 (签名哈希, 用于审阅的地址)。
    fn order_hash(&self) -> [u8; 32] {
        let mut message = Bits::new();
        message.push_bit(false); // int_msg_info$0
        message.push_bit(true); // ihr_disabled
        message.push_bit(self.bounce);
        message.push_bit(false); // bounced
        message.push_uint(0, 2); // src: addr_none
        message.push_uint(2, 2); // dest: addr_std$10
        message.push_bit(false); // anycast: nothing
        message.push_uint(u64::from(self.chain), 8);
        message.push_bytes(&self.to_hash);
        message.push_uint(self.value.len() as u64, 4);
        message.push_bytes(&self.value);
        message.push_bit(false); // extra currencies: empty
        message.push_uint(0, 4); // ihr_fee
        message.push_uint(0, 4); // fwd_fee
        message.push_uint(0, 64); // created_lt
        message.push_uint(0, 32); // created_at
        message.push_bit(false); // no state-init
        message.push_bit(false); // body inline
        let (bits, data) = message.finish();
        let message_hash = cell_hash(bits, &data, &[]);

        let mut order = Bits::new();
        order.push_uint(u64::from(SUBWALLET_ID), 32);
        order.push_uint(u64::from(self.timeout), 32);
        order.push_uint(u64::from(self.seqno), 32);
        order.push_uint(0, 8); // op: simple order
        order.push_uint(u64::from(self.send_mode), 8);
        let (bits, data) = order.finish();
        // 内部消息 cell 没有引用，深度为 0。
        cell_hash(bits, &data, &[(0, message_hash)])
    }
}

fn parse_tx(bytes: &[u8]) -> Option<TxOrder> {
    let mut offset = 0usize;
    let mut take = |len: usize| -> Option<&[u8]> {
        let end = offset.checked_add(len)?;
        if end > bytes.len() {
            return None;
        }
        let out = &bytes[offset..end];
        offset = end;
        Some(out)
    };

    if take(1)?[0] != 0x00 {
        return None;
    }
    let seqno = u32::from_be_bytes(take(4)?.try_into().ok()?);
    let timeout = u32::from_be_bytes(take(4)?.try_into().ok()?);
    let value_len = take(1)?[0] as usize;
    if value_len > 15 {
        return None;
    }
    let value = take(value_len)?.to_vec();
    let chain = take(1)?[0];
    let to_hash: [u8; 32] = take(32)?.try_into().ok()?;
    let bounce = match take(1)?[0] {
        0 => false,
        1 => true,
        _ => return None,
    };
    let send_mode = take(1)?[0];
    // state-init / payload / hints 均未实现；出现即拒绝，不静默忽略。
    for _ in 0..3 {
        if take(1)?[0] != 0x00 {
            return None;
        }
    }
    if offset != bytes.len() {
        return None;
    }
    Some(TxOrder {
        seqno,
        timeout,
        value,
        chain,
        to_hash,
        bounce,
        send_mode,
    })
}

// ── 模块 ──────────────────────────────────────────────────────────────

enum Stage {
    Idle,
    AwaitKey,
    AwaitReview,
}

struct SignState {
    path: Vec<u32>,
    tx: Vec<u8>,
}

struct Pending {
    exchange_id: ExchangeId,
    path: Vec<u32>,
    address: String,
    public_key: Vec<u8>,
    order: Option<TxOrder>,
    display: bool,
}

pub struct TonModule {
    stage: Stage,
    pending: Option<Pending>,
    local: Option<u64>,
    sign: Option<SignState>,
}

impl Default for TonModule {
    fn default() -> Self {
        Self::new()
    }
}

impl TonModule {
    pub fn new() -> Self {
        Self {
            stage: Stage::Idle,
            pending: None,
            local: None,
            sign: None,
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

    fn emit_collecting(&self, exchange_id: ExchangeId) -> Effect {
        Effect::Emit {
            wire: Wire::LedgerApdu,
            exchange_id,
            payload: status(sw::OK),
            state: chain_app_api::OperationState::Collecting,
        }
    }

    fn handle_apdu(&mut self, exchange_id: ExchangeId, bytes: &[u8]) -> Result<Effect, AppError> {
        let apdu =
            Apdu::parse(bytes).ok_or_else(|| AppError::BadRequest("truncated APDU".into()))?;
        if apdu.cla != CLA_TON {
            return Ok(self.emit(exchange_id, status(sw::CLA_NOT_SUPPORTED)));
        }
        match apdu.ins {
            INS_GET_VERSION => {
                let mut payload = vec![1, 0, 0];
                payload.extend_from_slice(&status(sw::OK));
                Ok(self.emit(exchange_id, payload))
            }
            INS_GET_APP_NAME => {
                let mut payload = b"TON".to_vec();
                payload.extend_from_slice(&status(sw::OK));
                Ok(self.emit(exchange_id, payload))
            }
            INS_GET_PUBLIC_KEY => self.handle_get_public_key(exchange_id, &apdu),
            INS_SIGN_TX => self.handle_sign(exchange_id, &apdu),
            _ => Ok(self.emit(exchange_id, status(sw::UNKNOWN_INS))),
        }
    }

    fn handle_get_public_key(
        &mut self,
        exchange_id: ExchangeId,
        apdu: &Apdu,
    ) -> Result<Effect, AppError> {
        let display = match apdu.p1 {
            0 => false,
            1 => true,
            _ => return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2))),
        };
        if apdu.p2 > 0x03 {
            return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2)));
        }
        let Some(path) = parse_path(&apdu.data) else {
            return Ok(self.emit(exchange_id, status(sw::WRONG_DATA_LENGTH)));
        };
        self.stage = Stage::AwaitKey;
        self.pending = Some(Pending {
            exchange_id,
            path: path.clone(),
            address: String::new(),
            public_key: Vec::new(),
            order: None,
            display,
        });
        Ok(Effect::NeedPublicKey {
            service_id: 1,
            request: key_request(path),
        })
    }

    fn handle_sign(&mut self, exchange_id: ExchangeId, apdu: &Apdu) -> Result<Effect, AppError> {
        match apdu.p2 {
            P2_FIRST_AND_MORE => {
                let Some(path) = parse_path_prefix(&apdu.data) else {
                    return Ok(self.emit(exchange_id, status(sw::WRONG_DATA_LENGTH)));
                };
                let rest = &apdu.data[1 + path.len() * 4..];
                let mut tx = rest.to_vec();
                tx.truncate(MAX_TX);
                self.sign = Some(SignState { path, tx });
                Ok(self.emit_collecting(exchange_id))
            }
            P2_MORE => {
                let Some(state) = self.sign.as_mut() else {
                    return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2)));
                };
                if state.tx.len() + apdu.data.len() > MAX_TX {
                    self.sign = None;
                    return Ok(self.emit(exchange_id, status(sw::TX_PARSING_FAIL)));
                }
                state.tx.extend_from_slice(&apdu.data);
                Ok(self.emit_collecting(exchange_id))
            }
            P2_LAST => {
                let Some(mut state) = self.sign.take() else {
                    return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2)));
                };
                if state.tx.len() + apdu.data.len() > MAX_TX {
                    return Ok(self.emit(exchange_id, status(sw::TX_PARSING_FAIL)));
                }
                state.tx.extend_from_slice(&apdu.data);
                let Some(order) = parse_tx(&state.tx) else {
                    return Ok(self.emit(exchange_id, status(sw::TX_PARSING_FAIL)));
                };
                self.stage = Stage::AwaitKey;
                self.pending = Some(Pending {
                    exchange_id,
                    path: state.path.clone(),
                    address: String::new(),
                    public_key: Vec::new(),
                    order: Some(order),
                    display: false,
                });
                Ok(Effect::NeedPublicKey {
                    service_id: 2,
                    request: key_request(state.path),
                })
            }
            _ => Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2))),
        }
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
        if let Some(request_id) = self.local.take() {
            self.stage = Stage::Idle;
            let payload = match result {
                ServiceResult::PublicKey(key) if key.bytes.len() == 32 => {
                    let address = open_ledger_biz::ton::encode_address(
                        &open_ledger_biz::ton::state_init_hash(
                            key.bytes.as_slice().try_into().expect("32 bytes"),
                        ),
                    );
                    format!(
                        "{{\"address\":\"{address}\",\"public_key\":\"{}\"}}",
                        hex::encode(&key.bytes)
                    )
                    .into_bytes()
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
        if key.bytes.len() != 32 {
            let exchange_id = self.pending.take().map(|p| p.exchange_id).unwrap_or(1);
            self.stage = Stage::Idle;
            return Ok(self.emit(exchange_id, status(sw::UNKNOWN)));
        }

        let Some(pending) = self.pending.as_mut() else {
            return Err(AppError::InvalidEvent("no pending request".into()));
        };
        let public_key: [u8; 32] = key.bytes.as_slice().try_into().expect("32 bytes");
        let address = open_ledger_biz::ton::encode_address(
            &open_ledger_biz::ton::state_init_hash(&public_key),
        );
        pending.address = address.clone();
        pending.public_key = key.bytes.clone();
        let exchange_id = pending.exchange_id;
        let path = pending.path.clone();
        let display = pending.display;
        let order = pending.order.clone();

        let Some(order) = order else {
            if display {
                self.stage = Stage::AwaitReview;
                return Ok(Effect::NeedReview {
                    service_id: 3,
                    request: Box::new(ReviewRequest {
                        document: address_document(&address),
                        action: ReviewAction::DisplayAddress {
                            derivation_scheme: DerivationScheme::Slip10Ed25519,
                            curve: Curve::Ed25519,
                            path,
                        },
                    }),
                });
            }
            self.pending = None;
            self.stage = Stage::Idle;
            let mut payload = key.bytes;
            payload.extend_from_slice(&status(sw::OK));
            return Ok(self.emit(exchange_id, payload));
        };

        // TON 直接对 TransactionOrder cell 的表示哈希签名，没有域前缀。
        let hash = order.order_hash();

        let operation = SignOperation {
            operation_id: 1,
            derivation_scheme: DerivationScheme::Slip10Ed25519,
            curve: Curve::Ed25519,
            path,
            scheme: SignScheme::Ed25519Message,
            input: hash.to_vec(),
            public_parameters: vec![("hash_hex".into(), hash.to_vec())],
        };
        self.stage = Stage::AwaitReview;
        Ok(Effect::NeedReview {
            service_id: 4,
            request: Box::new(ReviewRequest {
                document: transaction_document(&address, &order, &hash),
                action: ReviewAction::Sign(SignPlan::single(operation)),
            }),
        })
    }

    fn handle_review(&mut self, outcome: ReviewOutcome) -> Result<Effect, AppError> {
        let pending = self
            .pending
            .take()
            .ok_or_else(|| AppError::InvalidEvent("no pending review".into()))?;
        self.stage = Stage::Idle;
        let payload = match outcome {
            ReviewOutcome::Approved { signatures } => {
                if pending.order.is_some() {
                    match signatures.first() {
                        Some(signature) if signature.bytes.len() == 64 => {
                            let hash = pending
                                .order
                                .as_ref()
                                .map(|order| order.order_hash())
                                .expect("order checked above");
                            let mut out = Vec::with_capacity(98);
                            out.push(64);
                            out.extend_from_slice(&signature.bytes);
                            out.push(32);
                            out.extend_from_slice(&hash);
                            out.extend_from_slice(&status(sw::OK));
                            out
                        }
                        _ => status(sw::UNKNOWN),
                    }
                } else {
                    let mut out = pending.public_key.clone();
                    out.extend_from_slice(&status(sw::OK));
                    out
                }
            }
            ReviewOutcome::Rejected | ReviewOutcome::TimedOut => status(sw::DENIED),
            ReviewOutcome::Failed(_) => status(sw::UNKNOWN),
        };
        Ok(self.emit(pending.exchange_id, payload))
    }
}

impl ChainApp for TonModule {
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
                // 首包/续包确认后继续等下一帧交易数据。
                if self.sign.is_some() {
                    return Ok(Effect::AwaitInput);
                }
                Ok(Effect::Finished {
                    status: FinishStatus::Delivered,
                })
            }
            Event::Cancel { .. } => {
                self.pending = None;
                self.sign = None;
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
        self.sign = None;
        self.local = None;
        self.stage = Stage::Idle;
    }
}

fn account_path(index: u32) -> Vec<u32> {
    let mut path = DEFAULT_ACCOUNT_PATH;
    path[4] = 0x8000_0000 | index;
    path.to_vec()
}

fn parse_path_prefix(data: &[u8]) -> Option<Vec<u32>> {
    let count = *data.first()? as usize;
    if count == 0 || count > 10 {
        return None;
    }
    let end = 1 + count.checked_mul(4)?;
    if data.len() < end {
        return None;
    }
    let mut path = Vec::with_capacity(count);
    for chunk in data[1..end].as_chunks::<4>().0 {
        path.push(u32::from_be_bytes(*chunk));
    }
    if path.len() < 3 || path[0] != 0x8000_002C || path[1] != 0x8000_025F {
        return None;
    }
    Some(path)
}

fn parse_path(data: &[u8]) -> Option<Vec<u32>> {
    let path = parse_path_prefix(data)?;
    (data.len() == 1 + path.len() * 4).then_some(path)
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

/// 交易里的目标地址：workchain 0 用 v4r2 的可读地址，其余显示原始形式。
fn to_address(order: &TxOrder) -> String {
    if order.chain == 0x00 {
        open_ledger_biz::ton::encode_address(&order.to_hash)
    } else {
        format!("{}:{}", order.chain, hex::encode(order.to_hash))
    }
}

fn address_document(address: &str) -> ReviewDocument {
    ReviewDocument {
        operation: OperationKind::AddressConfirmation,
        network: NetworkId {
            name: "TON".into(),
            chain_id: None,
        },
        account: Some(address.to_string()),
        sections: vec![ReviewSection {
            title_key: "review.section.ton".into(),
            fields: vec![Field {
                label_key: "review.field.address".into(),
                value: FieldValue::Address {
                    value: address.to_string(),
                    network: "TON".into(),
                    role: "account".into(),
                },
            }],
        }],
        risks: vec![],
        parse_status: ParseStatus::Complete,
    }
}

fn transaction_document(address: &str, order: &TxOrder, hash: &[u8; 32]) -> ReviewDocument {
    let amount = order
        .value
        .iter()
        .fold(0u128, |acc, byte| (acc << 8) | u128::from(*byte));
    let summary = format!(
        "To: {}\nAmount: {amount} nanoton\nBounce: {}\nSend mode: {}\nSeqno: {}\nValid until: {}",
        to_address(order),
        order.bounce,
        order.send_mode,
        order.seqno,
        order.timeout
    );
    ReviewDocument {
        operation: OperationKind::Transaction,
        network: NetworkId {
            name: "TON".into(),
            chain_id: None,
        },
        account: Some(address.to_string()),
        sections: vec![ReviewSection {
            title_key: "review.section.ton".into(),
            fields: vec![
                Field {
                    label_key: "review.field.message".into(),
                    value: FieldValue::Text { value: summary },
                },
                Field {
                    label_key: "review.field.message_hex".into(),
                    value: FieldValue::Bytes {
                        value: hash.to_vec(),
                    },
                },
            ],
        }],
        risks: vec![],
        parse_status: ParseStatus::Complete,
    }
}

pub fn descriptor() -> AppDescriptor {
    AppDescriptor {
        module_id: MODULE_ID.into(),
        module_version: "0.1.0".into(),
        api_version: API_VERSION,
        review_schema_version: 1,
        storage_schema_version: 1,
        protocol_profiles: vec![chain_app_api::ProtocolProfile {
            name: "TON".into(),
            version: "1.0.0".into(),
            wire: Wire::LedgerApdu,
            supported: vec![
                "E0 03 GET_VERSION".into(),
                "E0 04 GET_APP_NAME".into(),
                "E0 05 GET_PUBLIC_KEY (display/silent)".into(),
                "E0 06 SIGN_TX (v4r2, simple transfers, chunked)".into(),
            ],
            unsupported: vec![
                "E0 06 state-init / payload / hints".into(),
                "E0 08 GET_ADDRESS_PROOF".into(),
                "E0 09 SIGN_DATA".into(),
            ],
            vector_sources: vec!["ton-blockchain/ledger-app-ton doc/TRANSACTION.md".into()],
        }],
        account_profiles: vec![AccountProfile {
            network: "TON".into(),
            account_type: "ed25519".into(),
            default_path: "m/44'/607'/0'/0'/0'/0'".into(),
            derivation_scheme: DerivationScheme::Slip10Ed25519,
            curve: Curve::Ed25519,
        }],
        requested_capabilities: chain_app_api::CapabilitySet {
            derivation_rules: vec![
                // 账户路径：`m/44'/607'/0'/0'/{account}'/0'`（全硬化，6 段）。
                DerivationRule {
                    derivation_scheme: DerivationScheme::Slip10Ed25519,
                    curve: Curve::Ed25519,
                    depth: 6,
                    hardened_positions: vec![0, 1, 2, 3, 4, 5],
                    max_index: 1000,
                },
                // 官方 app 只要求 `m/44'/607'/` 起头、至少 3 段；保留窄路径，
                // 便于 host 用其它合法路径查询。
                DerivationRule {
                    derivation_scheme: DerivationScheme::Slip10Ed25519,
                    curve: Curve::Ed25519,
                    depth: 3,
                    hardened_positions: vec![0, 1, 2],
                    max_index: 1000,
                },
            ],
            allow_chain_code: false,
            allow_signing: true,
            allow_storage: false,
        },
    }
}

pub struct TonFactory;

impl chain_app_api::ModuleFactory for TonFactory {
    fn describe(&self) -> AppDescriptor {
        descriptor()
    }

    fn create(&self) -> Box<dyn ChainApp> {
        Box::new(TonModule::new())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 普通转账的 order 哈希必须稳定：它是钱包端独立重建 cell 后比对的对象。
    #[test]
    fn order_hash_pins_the_v4r2_cell_layout() {
        let order = TxOrder {
            seqno: 1,
            timeout: 0x6000_0000,
            value: 1_000_000_000u64.to_be_bytes().to_vec(),
            chain: 0x00,
            to_hash: [0xAB; 32],
            bounce: false,
            send_mode: 3,
        };
        assert_eq!(hex::encode(order.order_hash()), "831103d2b0f32abc03366aa491096b508257e82a66f436b00f68af0b8bf600d8");
    }
}
