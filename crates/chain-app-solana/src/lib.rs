//! Solana 链 App（阶段 4）。
//!
//! 线格式与迁移前的 Dart 实现保持一致（`hw-app-solana` INS 表，CLA 0xE0）：
//!
//! - `E0 04 GET_VERSION` → `00 01 00 00` + `9000`；
//! - `E0 05 GET_ADDR`（P1=0x00 直接返回 / P1=0x01 先在本机显示确认）→
//!   **裸 32 字节 Ed25519 公钥** + `9000`（无长度前缀）；
//! - `E0 06 SIGN` / `E0 07 SIGN_OFFCHAIN` → `[path][message]`，单块或按
//!   P2 的 `MORE`/`EXTEND` 分块累积；一次审批后返回 64 字节 Ed25519 签名。
//!
//! 模块不接触 seed：公钥向宿主请求，签名在审批通过后由宿主执行。

use chain_app_api::{
    AppDescriptor, AccountProfile, AppError, ChainApp, Curve, DerivationRule, DerivationScheme,
    Effect, Event, ExchangeId, Field, FieldValue, FinishStatus, KeyOutput, NetworkId, OperationKind,
    ParseStatus, PublicKeyRequest, ReviewAction, ReviewDocument, ReviewOutcome, ReviewRequest,
    ReviewSection, ServiceResult, SessionConfig, SignOperation, SignPlan, SignScheme, Wire,
    API_VERSION,
};
use open_ledger_crypto::base58;

pub mod sw {
    pub const OK: u16 = 0x9000;
    pub const DENIED: u16 = 0x6985;
    pub const WRONG_DATA: u16 = 0x6A80;
    pub const WRONG_P1_P2: u16 = 0x6A86;
    pub const UNKNOWN_INS: u16 = 0x6D00;
    pub const CLA_NOT_SUPPORTED: u16 = 0x6E00;
    pub const UNKNOWN: u16 = 0x6F00;
}

pub const MODULE_ID: &str = "openledger.solana";

const CLA_SOL: u8 = 0xE0;
const INS_GET_VERSION: u8 = 0x04;
const INS_GET_ADDR: u8 = 0x05;
const INS_SIGN: u8 = 0x06;
const INS_SIGN_OFFCHAIN: u8 = 0x07;

const P1_RETURN: u8 = 0x00;
const P1_CONFIRM: u8 = 0x01;

/// `hw-app-solana` 的分块标志：续块 / 还有后续。
const P2_EXTEND: u8 = 0x01;
const P2_MORE: u8 = 0x02;

/// `m/44'/501'/0'/0'`（Solana 账户 0）。
const DEFAULT_PATH: [u32; 4] = [0x8000_002C, 0x8000_01F5, 0x8000_0000, 0x8000_0000];

/// 一次签名最多累积的原始消息字节数。
const MAX_MESSAGE: usize = 4096;

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

/// 消息摘要（仅用于确认页展示，不参与签名）。
#[derive(Debug, Default, PartialEq, Eq)]
struct Summary {
    version: String,
    fee_payer: Option<String>,
    program_id: Option<String>,
    to: Option<String>,
    lamports: Option<String>,
    complete: bool,
}

impl Summary {
    fn parse(message: &[u8]) -> Self {
        let mut summary = Summary {
            version: "legacy".into(),
            ..Default::default()
        };
        let (version, msg) = if !message.is_empty() && message[0] & 0x80 != 0 {
            (format!("v{}", message[0] & 0x7f), &message[1..])
        } else {
            ("legacy".to_string(), message)
        };
        summary.version = version;
        if msg.len() < 3 {
            return summary;
        }
        let Some((account_count, n)) = read_compact_u16(msg, 3) else {
            return summary;
        };
        let mut pos = 3 + n;
        let account_count = account_count as usize;
        if account_count == 0 || pos + account_count * 32 > msg.len() {
            return summary;
        }
        let keys: Vec<&[u8]> = (0..account_count)
            .map(|i| &msg[pos + i * 32..pos + i * 32 + 32])
            .collect();
        pos += account_count * 32;
        if pos + 32 > msg.len() {
            return summary;
        }
        pos += 32; // recent blockhash
        let Some((ix_count, n)) = read_compact_u16(msg, pos) else {
            return summary;
        };
        pos += n;
        summary.fee_payer = Some(base58::encode(keys[0]));

        for _ in 0..ix_count {
            let Some(program_idx) = msg.get(pos).copied() else {
                return summary;
            };
            pos += 1;
            let Some((acct_len, n)) = read_compact_u16(msg, pos) else {
                return summary;
            };
            pos += n;
            let acct_len = acct_len as usize;
            if pos + acct_len > msg.len() {
                return summary;
            }
            let ix_accounts = &msg[pos..pos + acct_len];
            pos += acct_len;
            let Some((data_len, n)) = read_compact_u16(msg, pos) else {
                return summary;
            };
            pos += n;
            let data_len = data_len as usize;
            if pos + data_len > msg.len() {
                return summary;
            }
            let ix_data = &msg[pos..pos + data_len];
            pos += data_len;

            if summary.program_id.is_none() {
                if let Some(key) = keys.get(program_idx as usize) {
                    summary.program_id = Some(base58::encode(key));
                    // System Program（32 × 0x00）的 Transfer 指令：
                    // data = [u32 LE 判别式 = 2][u64 LE lamports]。
                    if key.iter().all(|b| *b == 0)
                        && ix_data.len() >= 12
                        && ix_data[0..4] == [2, 0, 0, 0]
                    {
                        if let Some(to_idx) = ix_accounts.get(1) {
                            if let Some(to_key) = keys.get(*to_idx as usize) {
                                summary.to = Some(base58::encode(to_key));
                            }
                        }
                        let mut buf = [0u8; 8];
                        buf.copy_from_slice(&ix_data[4..12]);
                        summary.lamports = Some(u64::from_le_bytes(buf).to_string());
                        summary.complete = true;
                    }
                }
            }
        }
        summary
    }
}

fn read_compact_u16(data: &[u8], offset: usize) -> Option<(u16, usize)> {
    let first = *data.get(offset)? as u16;
    match first & 0x80 {
        0 => Some((first, 1)),
        _ => {
            let second = *data.get(offset + 1)? as u16;
            Some((((first & 0x7f) << 8) | second, 2))
        }
    }
}

enum Stage {
    Idle,
    /// 分块签名中：已收到 `MORE` 块，等下一帧。
    Collecting,
    AwaitKey,
    AwaitReview,
}

struct Pending {
    exchange_id: ExchangeId,
    path: Vec<u32>,
    address: String,
    /// 待签消息；`None` 表示这是一次地址查询。
    message: Option<Vec<u8>>,
    /// 地址查询是否要求本机确认（P1=0x01）。
    confirm: bool,
    /// 待确认的原始公钥（地址查询直接回 32 字节）。
    public_key: Option<Vec<u8>>,
}

pub struct SolanaModule {
    stage: Stage,
    pending: Option<Pending>,
    /// 本机账户请求的 `request_id`（`LocalCommand::DeriveAccount`）。
    local: Option<u64>,
}

impl Default for SolanaModule {
    fn default() -> Self {
        Self::new()
    }
}

impl SolanaModule {
    pub fn new() -> Self {
        Self {
            stage: Stage::Idle,
            pending: None,
            local: None,
        }
    }

    fn emit(
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
        if apdu.cla != CLA_SOL {
            return Ok(self.emit(
                exchange_id,
                status(sw::CLA_NOT_SUPPORTED),
                chain_app_api::OperationState::Final,
            ));
        }
        match apdu.ins {
            INS_GET_VERSION => Ok(self.emit(
                exchange_id,
                vec![0x00, 0x01, 0x00, 0x00, 0x90, 0x00],
                chain_app_api::OperationState::Final,
            )),
            INS_GET_ADDR => self.handle_get_addr(exchange_id, &apdu),
            INS_SIGN | INS_SIGN_OFFCHAIN => self.handle_sign(exchange_id, &apdu),
            _ => Ok(self.emit(
                exchange_id,
                status(sw::UNKNOWN_INS),
                chain_app_api::OperationState::Final,
            )),
        }
    }

    fn handle_get_addr(
        &mut self,
        exchange_id: ExchangeId,
        apdu: &Apdu,
    ) -> Result<Effect, AppError> {
        // 迁移前的实现拒绝空数据（没有默认 Solana 地址查询）。
        if apdu.data.is_empty() {
            return Ok(self.emit(
                exchange_id,
                status(sw::WRONG_DATA),
                chain_app_api::OperationState::Final,
            ));
        }
        let path = match parse_path(&apdu.data) {
            Some(path) => path,
            None => {
                return Ok(self.emit(
                    exchange_id,
                    status(sw::WRONG_DATA),
                    chain_app_api::OperationState::Final,
                ))
            }
        };
        let confirm = match apdu.p1 {
            P1_RETURN => false,
            P1_CONFIRM => true,
            _ => {
                return Ok(self.emit(
                    exchange_id,
                    status(sw::WRONG_P1_P2),
                    chain_app_api::OperationState::Final,
                ))
            }
        };
        self.pending = Some(Pending {
            exchange_id,
            path: path.clone(),
            address: String::new(),
            message: None,
            confirm,
            public_key: None,
        });
        self.stage = Stage::AwaitKey;
        Ok(Effect::NeedPublicKey {
            service_id: 1,
            request: key_request(path),
        })
    }

    fn handle_sign(
        &mut self,
        exchange_id: ExchangeId,
        apdu: &Apdu,
    ) -> Result<Effect, AppError> {
        let extend = apdu.p2 & P2_EXTEND != 0;
        let more = apdu.p2 & P2_MORE != 0;

        if extend {
            // 续块：只有原始消息字节，路径来自首块。
            let Some(pending) = self.pending.as_mut() else {
                return Ok(self.emit(
                    exchange_id,
                    status(sw::WRONG_P1_P2),
                    chain_app_api::OperationState::Final,
                ));
            };
            let Some(message) = pending.message.as_mut() else {
                return Ok(self.emit(
                    exchange_id,
                    status(sw::WRONG_P1_P2),
                    chain_app_api::OperationState::Final,
                ));
            };
            if message.len() + apdu.data.len() > MAX_MESSAGE {
                self.pending = None;
                self.stage = Stage::Idle;
                return Ok(self.emit(
                    exchange_id,
                    status(sw::WRONG_DATA),
                    chain_app_api::OperationState::Final,
                ));
            }
            message.extend_from_slice(&apdu.data);
            pending.exchange_id = exchange_id;
            if more {
                self.stage = Stage::Collecting;
                return Ok(self.emit(
                    exchange_id,
                    status(sw::OK),
                    chain_app_api::OperationState::Collecting,
                ));
            }
            let path = pending.path.clone();
            self.stage = Stage::AwaitKey;
            return Ok(Effect::NeedPublicKey {
                service_id: 3,
                request: key_request(path),
            });
        }

        // 首块：`[path][message]`；OKX 会在最前面多一个 num_signers 字节。
        let data = strip_num_signers_prefix(&apdu.data);
        let Some((path, message)) = split_path(data) else {
            return Ok(self.emit(
                exchange_id,
                status(sw::WRONG_DATA),
                chain_app_api::OperationState::Final,
            ));
        };
        if message.is_empty() {
            return Ok(self.emit(
                exchange_id,
                status(sw::WRONG_DATA),
                chain_app_api::OperationState::Final,
            ));
        }
        if message.len() > MAX_MESSAGE {
            return Ok(self.emit(
                exchange_id,
                status(sw::WRONG_DATA),
                chain_app_api::OperationState::Final,
            ));
        }
        self.pending = Some(Pending {
            exchange_id,
            path: path.clone(),
            address: String::new(),
            message: Some(message.to_vec()),
            confirm: false,
            public_key: None,
        });
        if more {
            self.stage = Stage::Collecting;
            return Ok(self.emit(
                exchange_id,
                status(sw::OK),
                chain_app_api::OperationState::Collecting,
            ));
        }
        self.stage = Stage::AwaitKey;
        Ok(Effect::NeedPublicKey {
            service_id: 3,
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
                ServiceResult::PublicKey(key) if key.bytes.len() == 32 => {
                    let address = base58::encode(&key.bytes);
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
                return Ok(self.emit(
                    exchange_id,
                    status(sw::UNKNOWN),
                    chain_app_api::OperationState::Final,
                ));
            }
            ServiceResult::Storage(_) | ServiceResult::SharedSecret(_) => {
                return Err(AppError::InvalidEvent("unexpected storage result".into()))
            }
        };
        if key.bytes.len() != 32 {
            let exchange_id = self.pending.take().map(|p| p.exchange_id).unwrap_or(1);
            self.stage = Stage::Idle;
            return Ok(self.emit(
                exchange_id,
                status(sw::UNKNOWN),
                chain_app_api::OperationState::Final,
            ));
        }
        let address = base58::encode(&key.bytes);

        let (exchange_id, path, message, confirm) = {
            let pending = self
                .pending
                .as_mut()
                .ok_or_else(|| AppError::InvalidEvent("no pending request".into()))?;
            pending.address = address.clone();
            pending.public_key = Some(key.bytes.clone());
            (
                pending.exchange_id,
                pending.path.clone(),
                pending.message.clone(),
                pending.confirm,
            )
        };

        let Some(message) = message else {
            // 地址查询：P1=0x00 直接回裸公钥；P1=0x01 先弹本机确认页。
            if !confirm {
                self.pending = None;
                self.stage = Stage::Idle;
                let mut out = key.bytes;
                out.extend_from_slice(&status(sw::OK));
                return Ok(self.emit(
                    exchange_id,
                    out,
                    chain_app_api::OperationState::Final,
                ));
            }
            self.stage = Stage::AwaitReview;
            return Ok(Effect::NeedReview {
                service_id: 2,
                request: Box::new(ReviewRequest {
                    document: ReviewDocument {
                        operation: OperationKind::AddressConfirmation,
                        network: NetworkId {
                            name: "Solana".into(),
                            chain_id: None,
                        },
                        account: Some(address.clone()),
                        sections: vec![ReviewSection {
                            title_key: "review.section.address".into(),
                            fields: vec![Field {
                                label_key: "review.field.address".into(),
                                value: FieldValue::Address {
                                    value: address,
                                    network: "Solana".into(),
                                    role: "account".into(),
                                },
                            }],
                        }],
                        risks: vec![],
                        parse_status: ParseStatus::Complete,
                    },
                    action: ReviewAction::DisplayAddress {
                        derivation_scheme: DerivationScheme::Slip10Ed25519,
                        curve: Curve::Ed25519,
                        path,
                    },
                }),
            });
        };

        let summary = Summary::parse(&message);
        let mut fields = vec![
            Field {
                label_key: "review.field.address".into(),
                value: FieldValue::Address {
                    value: address.clone(),
                    network: "Solana".into(),
                    role: "account".into(),
                },
            },
            Field {
                label_key: "review.field.message_size".into(),
                value: FieldValue::Text {
                    value: message.len().to_string(),
                },
            },
        ];
        if let Some(to) = &summary.to {
            fields.push(Field {
                label_key: "review.field.to".into(),
                value: FieldValue::Address {
                    value: to.clone(),
                    network: "Solana".into(),
                    role: "recipient".into(),
                },
            });
        }
        if let Some(lamports) = &summary.lamports {
            fields.push(Field {
                label_key: "review.field.amount".into(),
                value: FieldValue::Amount {
                    raw: lamports.clone(),
                    decimals: 9,
                    asset: "SOL".into(),
                    ticker: Some("SOL".into()),
                },
            });
        }
        if let Some(program) = &summary.program_id {
            fields.push(Field {
                label_key: "review.field.program".into(),
                value: FieldValue::Text {
                    value: program.clone(),
                },
            });
        }
        fields.push(Field {
            label_key: "review.field.version".into(),
            value: FieldValue::Text {
                value: summary.version.clone(),
            },
        });

        let operation = SignOperation {
            operation_id: 1,
            derivation_scheme: DerivationScheme::Slip10Ed25519,
            curve: Curve::Ed25519,
            path,
            scheme: SignScheme::Ed25519Message,
            input: message.clone(),
            public_parameters: vec![("payload_hex".into(), message.clone())],
        };
        self.stage = Stage::AwaitReview;
        Ok(Effect::NeedReview {
            service_id: 4,
            request: Box::new(ReviewRequest {
                document: ReviewDocument {
                    operation: OperationKind::Transaction,
                    network: NetworkId {
                        name: "Solana".into(),
                        chain_id: None,
                    },
                    account: Some(address),
                    sections: vec![ReviewSection {
                        title_key: "review.section.solana".into(),
                        fields,
                    }],
                    risks: if summary.complete {
                        vec![]
                    } else {
                        vec![chain_app_api::Risk {
                            code: "solana.unparsed_message".into(),
                            severity: chain_app_api::RiskLevel::Warning,
                            parameters: Vec::new(),
                            source: chain_app_api::RiskSource::Module,
                        }]
                    },
                    parse_status: if summary.complete {
                        ParseStatus::Complete
                    } else {
                        ParseStatus::Partial
                    },
                },
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
                if pending.message.is_none() {
                    // 地址确认：批准即回裸公钥。
                    let mut out = pending.public_key.unwrap_or_default();
                    out.extend_from_slice(&status(sw::OK));
                    out
                } else if signatures.len() == 1 && signatures[0].bytes.len() == 64 {
                    let mut out = signatures[0].bytes.clone();
                    out.extend_from_slice(&status(sw::OK));
                    out
                } else {
                    status(sw::UNKNOWN)
                }
            }
            ReviewOutcome::Rejected | ReviewOutcome::TimedOut => status(sw::DENIED),
            ReviewOutcome::Failed(_) => status(sw::UNKNOWN),
        };
        Ok(self.emit(
            pending.exchange_id,
            payload,
            chain_app_api::OperationState::Final,
        ))
    }
}

impl ChainApp for SolanaModule {
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
            Event::Delivered { .. } => match self.stage {
                // 分块签名中：等下一帧，不结束会话。
                Stage::Collecting => Ok(Effect::AwaitInput),
                _ => Ok(Effect::Finished {
                    status: FinishStatus::Delivered,
                }),
            },
            Event::Cancel { .. } => {
                self.pending = None;
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

/// 账户路径：Solana 的账户号在第三段（`m/44'/501'/{account}'/0'`）。
fn account_path(index: u32) -> Vec<u32> {
    let mut path = DEFAULT_PATH;
    path[2] = 0x8000_0000 | index;
    path.to_vec()
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

/// `[count][u32 BE]*[remainder]`；空数据用默认路径。
fn split_path(data: &[u8]) -> Option<(Vec<u32>, &[u8])> {
    if data.is_empty() {
        return Some((DEFAULT_PATH.to_vec(), &[]));
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

fn parse_path(data: &[u8]) -> Option<Vec<u32>> {
    let (path, rest) = split_path(data)?;
    if rest.is_empty() {
        Some(path)
    } else {
        None
    }
}

/// OKX 在 Solana 签名首帧前多带一个 `num_signers` 字节（见旧 Dart 实现）。
fn strip_num_signers_prefix(data: &[u8]) -> &[u8] {
    if data.len() > 1 && data[0] == 0x01 && (2..=5).contains(&data[1]) {
        &data[1..]
    } else {
        data
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
            name: "Solana".into(),
            version: "1.7.0".into(),
            wire: Wire::LedgerApdu,
            supported: vec![
                "E0 04 GET_VERSION".into(),
                "E0 05 GET_ADDR (bare 32B Ed25519)".into(),
                "E0 06/07 SIGN (single/multi-chunk)".into(),
            ],
            unsupported: vec!["E0 05 P1 outside {0,1}".into()],
            vector_sources: vec!["tool/e2e/tests/sol_sign.py".into()],
        }],
        account_profiles: vec![AccountProfile {
            network: "Solana".into(),
            account_type: "ed25519".into(),
            default_path: "m/44'/501'/0'/0'".into(),
            derivation_scheme: DerivationScheme::Slip10Ed25519,
            curve: Curve::Ed25519,
        }],
        requested_capabilities: chain_app_api::CapabilitySet {
            derivation_rules: vec![DerivationRule {
                derivation_scheme: DerivationScheme::Slip10Ed25519,
                curve: Curve::Ed25519,
                depth: 4,
                hardened_positions: vec![0, 1, 2, 3],
                max_index: 1000,
            }],
            allow_chain_code: false,
            allow_signing: true,
            allow_storage: false,
        },
    }
}

pub struct SolanaFactory;

impl chain_app_api::ModuleFactory for SolanaFactory {
    fn describe(&self) -> AppDescriptor {
        descriptor()
    }

    fn create(&self) -> Box<dyn ChainApp> {
        Box::new(SolanaModule::new())
    }
}
