//! NEAR 链 App。
//!
//! 协议对齐 LedgerHQ/app-near（Rust 版）：
//!
//! - `80 04 GET_PUBLIC_KEY`：`P1=0` 显示并确认、`P1=1` 静默；`CData` 固定为
//!   5 个 4 字节大端路径项（`m/44'/397'/0'/0'/1'`），响应 32 字节公钥。
//! - `80 02 SIGN_TRANSACTION`：`CData` 为 `[path][borsh tx]` 的分块流，
//!   `P1=0x00` 表示还有后续块、`P1=0x80` 为末块；签名对象是
//!   `sha256(原始 borsh 交易字节)`，响应 64 字节 Ed25519 签名。
//! - `80 06 GET_VERSION`；其余 INS（含 NEP-413 / NEP-366）暂不实现，回 `6D00`。
//!
//! 交易内嵌的 `public_key` 必须与路径派生的公钥一致（`0xB00D`），否则拒绝：
//! 这是 app-near 的 `PublicKeyMismatch` 保护，避免签出不属于该账户的授权。

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
    pub const WRONG_DATA: u16 = 0x6A80;
    pub const WRONG_P1_P2: u16 = 0x6A86;
    pub const UNKNOWN_INS: u16 = 0x6D00;
    pub const CLA_NOT_SUPPORTED: u16 = 0x6E00;
    pub const UNKNOWN: u16 = 0x6F00;
    /// 交易内嵌公钥 ≠ 路径派生公钥（app-near `PublicKeyMismatch`）。
    pub const PUBLIC_KEY_MISMATCH: u16 = 0xB00D;
}

pub const MODULE_ID: &str = "openledger.near";

const CLA_NEAR: u8 = 0x80;
const INS_SIGN_TRANSACTION: u8 = 2;
const INS_GET_PUBLIC_KEY: u8 = 4;
const INS_GET_VERSION: u8 = 6;

const P1_DISPLAY: u8 = 0x00;
const P1_SILENT: u8 = 0x01;
const P1_LAST_CHUNK: u8 = 0x80;

/// APDU 路径固定 5 项（`ALLOWED_PATH_LEN`）。
const PATH_COMPONENTS: usize = 5;
const PATH_BYTES: usize = PATH_COMPONENTS * 4;

/// 设备账户路径 `m/44'/397'/{account}'/0'/1'`（near-ledger-js 的账户 0 默认
/// 路径是 `44'/397'/0'/0'/1'`；第 3 段随账户变化）。
const ACCOUNT_PATH: [u32; 5] = [
    0x8000_002C,
    0x8000_018D,
    0x8000_0000,
    0x8000_0000,
    0x8000_0001,
];

const MAX_TX: usize = 4096;

struct Apdu {
    cla: u8,
    ins: u8,
    p1: u8,
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
            data,
        })
    }
}

fn status(code: u16) -> Vec<u8> {
    code.to_be_bytes().to_vec()
}

/// 从 borsh 交易前缀里能安全读到的字段。
struct TxPrefix {
    signer_id: String,
    public_key: Vec<u8>,
    receiver_id: String,
    action_count: u32,
    /// 单笔 Transfer 的押金（yoctoNEAR）；其它形态无法完整跳过动作，不做猜测。
    transfer: Option<u128>,
}

struct Reader<'a> {
    bytes: &'a [u8],
    offset: usize,
}

impl<'a> Reader<'a> {
    fn new(bytes: &'a [u8]) -> Self {
        Self { bytes, offset: 0 }
    }

    fn take(&mut self, len: usize) -> Option<&'a [u8]> {
        let end = self.offset.checked_add(len)?;
        if end > self.bytes.len() {
            return None;
        }
        let out = &self.bytes[self.offset..end];
        self.offset = end;
        Some(out)
    }

    fn u8(&mut self) -> Option<u8> {
        Some(self.take(1)?[0])
    }

    fn u32(&mut self) -> Option<u32> {
        Some(u32::from_le_bytes(self.take(4)?.try_into().ok()?))
    }

    fn u64(&mut self) -> Option<u64> {
        Some(u64::from_le_bytes(self.take(8)?.try_into().ok()?))
    }

    fn string(&mut self) -> Option<String> {
        let len = self.u32()? as usize;
        let bytes = self.take(len)?;
        Some(String::from_utf8_lossy(bytes).into_owned())
    }
}

/// borsh `Transaction` 的前缀：signer_id / public_key / nonce / receiver_id /
/// block_hash / actions。
fn parse_tx_prefix(tx: &[u8]) -> Option<TxPrefix> {
    let mut reader = Reader::new(tx);
    let signer_id = reader.string()?;
    let tag = reader.u8()?;
    let public_key = match tag {
        0 => reader.take(32)?.to_vec(),
        1 => reader.take(64)?.to_vec(),
        _ => return None,
    };
    let _nonce = reader.u64()?;
    let receiver_id = reader.string()?;
    let _block_hash = reader.take(32)?;
    let action_count = reader.u32()?;

    // 只有一个 Transfer 时能确定金额；其它组合需要逐个完整解析动作，标 Partial。
    let transfer = if action_count == 1 {
        match reader.u8()? {
            3 => Some(u128::from_le_bytes(reader.take(16)?.try_into().ok()?)),
            _ => None,
        }
    } else {
        None
    };

    Some(TxPrefix {
        signer_id,
        public_key,
        receiver_id,
        action_count,
        transfer,
    })
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
    public_key: Vec<u8>,
    /// `None` 表示这是一次地址查询。
    tx: Option<Vec<u8>>,
    prefix: Option<TxPrefix>,
    display: bool,
}

pub struct NearModule {
    stage: Stage,
    pending: Option<Pending>,
    local: Option<u64>,
    /// SIGN_TRANSACTION 的跨帧缓冲（`[path][tx]`）。
    buffer: Vec<u8>,
}

impl Default for NearModule {
    fn default() -> Self {
        Self::new()
    }
}

impl NearModule {
    pub fn new() -> Self {
        Self {
            stage: Stage::Idle,
            pending: None,
            local: None,
            buffer: Vec::new(),
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
        if apdu.cla != CLA_NEAR {
            return Ok(self.emit(exchange_id, status(sw::CLA_NOT_SUPPORTED)));
        }
        match apdu.ins {
            INS_GET_PUBLIC_KEY => self.handle_get_public_key(exchange_id, &apdu),
            INS_SIGN_TRANSACTION => self.handle_sign(exchange_id, &apdu),
            INS_GET_VERSION => {
                let mut payload = vec![2, 0, 0];
                payload.extend_from_slice(&status(sw::OK));
                Ok(self.emit(exchange_id, payload))
            }
            _ => Ok(self.emit(exchange_id, status(sw::UNKNOWN_INS))),
        }
    }

    fn handle_get_public_key(
        &mut self,
        exchange_id: ExchangeId,
        apdu: &Apdu,
    ) -> Result<Effect, AppError> {
        let display = match apdu.p1 {
            P1_DISPLAY => true,
            P1_SILENT => false,
            _ => return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2))),
        };
        let Some(path) = parse_apdu_path(&apdu.data) else {
            return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
        };
        self.stage = Stage::AwaitKey;
        self.pending = Some(Pending {
            exchange_id,
            path: path.clone(),
            address: String::new(),
            public_key: Vec::new(),
            tx: None,
            prefix: None,
            display,
        });
        Ok(Effect::NeedPublicKey {
            service_id: 1,
            request: key_request(path),
        })
    }

    fn handle_sign(&mut self, exchange_id: ExchangeId, apdu: &Apdu) -> Result<Effect, AppError> {
        if apdu.p1 & !P1_LAST_CHUNK != 0 {
            return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2)));
        }
        if self.buffer.len() + apdu.data.len() > PATH_BYTES + MAX_TX {
            self.buffer.clear();
            return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
        }
        self.buffer.extend_from_slice(&apdu.data);

        if apdu.p1 & P1_LAST_CHUNK == 0 {
            return Ok(self.emit_collecting(exchange_id));
        }

        let raw = std::mem::take(&mut self.buffer);
        if raw.len() <= PATH_BYTES {
            return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
        }
        let Some(path) = parse_apdu_path(&raw[..PATH_BYTES]) else {
            return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
        };
        let tx = raw[PATH_BYTES..].to_vec();
        let Some(prefix) = parse_tx_prefix(&tx) else {
            return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
        };

        self.stage = Stage::AwaitKey;
        self.pending = Some(Pending {
            exchange_id,
            path: path.clone(),
            address: String::new(),
            public_key: Vec::new(),
            tx: Some(tx),
            prefix: Some(prefix),
            display: false,
        });
        Ok(Effect::NeedPublicKey {
            service_id: 2,
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
        if let Some(request_id) = self.local.take() {
            self.stage = Stage::Idle;
            let payload = match result {
                ServiceResult::PublicKey(key) if key.bytes.len() == 32 => {
                    let address = hex::encode(&key.bytes);
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
        let address = hex::encode(&key.bytes);
        pending.address = address.clone();
        pending.public_key = key.bytes.clone();
        let exchange_id = pending.exchange_id;
        let path = pending.path.clone();
        let display = pending.display;
        let tx = pending.tx.clone();
        let prefix = pending.prefix.take();

        let Some(tx) = tx else {
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

        let prefix = prefix.ok_or_else(|| AppError::InvalidEvent("no tx prefix".into()))?;
        if prefix.public_key != key.bytes {
            self.pending = None;
            self.stage = Stage::Idle;
            return Ok(self.emit(exchange_id, status(sw::PUBLIC_KEY_MISMATCH)));
        }

        let digest = sha256::hash(&tx);
        let operation = SignOperation {
            operation_id: 1,
            derivation_scheme: DerivationScheme::Slip10Ed25519,
            curve: Curve::Ed25519,
            path,
            scheme: SignScheme::Ed25519Message,
            input: digest.to_vec(),
            public_parameters: vec![
                ("payload_hex".into(), tx.clone()),
                ("digest_hex".into(), digest.to_vec()),
            ],
        };
        self.stage = Stage::AwaitReview;
        Ok(Effect::NeedReview {
            service_id: 4,
            request: Box::new(ReviewRequest {
                document: transaction_document(&address, &prefix, &tx),
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
                if pending.tx.is_some() {
                    match signatures.first() {
                        Some(signature) if signature.bytes.len() == 64 => {
                            let mut out = signature.bytes.clone();
                            out.extend_from_slice(&status(sw::OK));
                            out
                        }
                        _ => status(sw::UNKNOWN),
                    }
                } else {
                    // 地址确认：没有签名，回显模块派生的公钥。
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

impl ChainApp for NearModule {
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
                // 分块签名还在收集：确认这一帧后继续等下一帧。
                if !self.buffer.is_empty() {
                    return Ok(Effect::AwaitInput);
                }
                Ok(Effect::Finished {
                    status: FinishStatus::Delivered,
                })
            }
            Event::Cancel { .. } => {
                self.pending = None;
                self.buffer.clear();
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
        self.buffer.clear();
        self.stage = Stage::Idle;
    }
}

fn account_path(index: u32) -> Vec<u32> {
    let mut path = ACCOUNT_PATH;
    path[2] = 0x8000_0000 | index;
    path.to_vec()
}

/// APDU 里的路径没有长度前缀：正好 5 项（20 字节）。
fn parse_apdu_path(data: &[u8]) -> Option<Vec<u32>> {
    if data.len() != PATH_BYTES {
        return None;
    }
    Some(
        data.as_chunks::<4>()
            .0
            .iter()
            .map(|chunk| u32::from_be_bytes(*chunk))
            .collect(),
    )
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

fn address_document(address: &str) -> ReviewDocument {
    ReviewDocument {
        operation: OperationKind::AddressConfirmation,
        network: NetworkId {
            name: "NEAR".into(),
            chain_id: None,
        },
        account: Some(address.to_string()),
        sections: vec![ReviewSection {
            title_key: "review.section.near".into(),
            fields: vec![Field {
                label_key: "review.field.address".into(),
                value: FieldValue::Address {
                    value: address.to_string(),
                    network: "NEAR".into(),
                    role: "account".into(),
                },
            }],
        }],
        risks: vec![],
        parse_status: ParseStatus::Complete,
    }
}

fn transaction_document(address: &str, prefix: &TxPrefix, tx: &[u8]) -> ReviewDocument {
    let mut lines = vec![
        format!("Signer: {}", prefix.signer_id),
        format!("Receiver: {}", prefix.receiver_id),
        format!("Public key: {}", hex::encode(&prefix.public_key)),
        format!("Actions: {}", prefix.action_count),
    ];
    if let Some(deposit) = prefix.transfer {
        lines.push(format!("Deposit: {deposit} yoctoNEAR"));
    }
    ReviewDocument {
        operation: OperationKind::Transaction,
        network: NetworkId {
            name: "NEAR".into(),
            chain_id: None,
        },
        account: Some(address.to_string()),
        sections: vec![ReviewSection {
            title_key: "review.section.near".into(),
            fields: vec![
                Field {
                    label_key: "review.field.message".into(),
                    value: FieldValue::Text {
                        value: lines.join("\n"),
                    },
                },
                Field {
                    label_key: "review.field.message_hex".into(),
                    value: FieldValue::Bytes {
                        value: tx.to_vec(),
                    },
                },
            ],
        }],
        risks: vec![],
        // 非单笔 Transfer 时只解析到动作数量，不假装看懂了参数。
        parse_status: if prefix.transfer.is_some() || prefix.action_count == 0 {
            ParseStatus::Complete
        } else {
            ParseStatus::Partial
        },
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
            name: "NEAR".into(),
            version: "2.0.0".into(),
            wire: Wire::LedgerApdu,
            supported: vec![
                "80 04 GET_PUBLIC_KEY (display/silent, 5-component path)".into(),
                "80 02 SIGN_TRANSACTION (chunked borsh, sha256 + ed25519)".into(),
                "80 06 GET_VERSION".into(),
            ],
            unsupported: vec![
                "80 05 GET_WALLET_ID".into(),
                "80 07 NEP-413 message signing".into(),
                "80 08 NEP-366 delegate action signing".into(),
                "non-hardened SLIP-10 path components".into(),
            ],
            vector_sources: vec!["LedgerHQ/app-near src/utils/crypto/path.rs".into()],
        }],
        account_profiles: vec![AccountProfile {
            network: "NEAR".into(),
            account_type: "ed25519".into(),
            default_path: "m/44'/397'/0'/0'/1'".into(),
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

pub struct NearFactory;

impl chain_app_api::ModuleFactory for NearFactory {
    fn describe(&self) -> AppDescriptor {
        descriptor()
    }

    fn create(&self) -> Box<dyn ChainApp> {
        Box::new(NearModule::new())
    }
}
