//! Sui 链 App（阶段 4）。
//!
//! **非标准实现**：以下编号与 Ledger 官方 `app-sui` 都不一致，真实主机会拒绝。
//!
//! 官方 `app-sui`（`docs/apdu.md`，`rust-app/src/interface.rs`）：
//! `CLA = 0x00`（全部命令），`P1`/`P2` 必须为 0，`0x01 VERIFY_ADDRESS`、
//! `0x02 GET_PUBKEY`、`0x03 SIGN_TX`、`0x22 PROVIDE_TOKEN_DYNAMIC_DESCRIPTOR`、
//! `0xFE GET_VERSION_STR`、`0xFF QUIT_APP`；大包走 Block Protocol 分块，
//! 签名命令由设备解析完整 BCS 交易前导与指令。
//!
//! 我们的实现：`CLA 0x07`（官方不存在），`0x02` 取地址、`0x04` 签「宿主给的
//! 消息字节」。因此：
//!
//! - 签名必须在确认页声明 `blind-signing`（设备没有解析 BCS 交易）；
//! - 与官方对齐（含 Block Protocol）另开 ticket，见 D-021 的后果；
//! - 不得把 `0x04` 改叫官方 `0x03`：编号对齐但语义不同更糟。
//!
//! 线格式细节：
//!
//! - `07 02 GET_PUBLIC_KEY` → ASCII 地址 `0x…` + `9000`
//!   （地址 = `blake2b(0x00 || ed25519_pubkey)`）；
//! - `07 04 SIGN_TX` → `[path][message]`，一次审批后返回 64 字节 Ed25519 签名。

use chain_app_api::{
    AccountProfile, AppDescriptor, AppError, ChainApp, Curve, DerivationRule, DerivationScheme,
    Effect, Event, ExchangeId, Field, FieldValue, FinishStatus, KeyOutput, NetworkId, OperationKind,
    ParseStatus, PublicKeyRequest, ReviewAction, ReviewDocument, ReviewOutcome, ReviewRequest,
    ReviewSection, Risk, RiskLevel, RiskSource, ServiceResult, SessionConfig, SignOperation,
    SignPlan, SignScheme, Wire, API_VERSION,
};
use open_ledger_crypto::blake2b;

pub mod sw {
    pub const OK: u16 = 0x9000;
    pub const DENIED: u16 = 0x6985;
    pub const WRONG_DATA: u16 = 0x6A80;
    pub const UNKNOWN_INS: u16 = 0x6D00;
    pub const CLA_NOT_SUPPORTED: u16 = 0x6E00;
    pub const UNKNOWN: u16 = 0x6F00;
}

pub const MODULE_ID: &str = "openledger.sui";

const CLA_SUI: u8 = 0x07;
const INS_GET_PUBLIC_KEY: u8 = 0x02;
const INS_SIGN_TX: u8 = 0x04;

/// `m/44'/784'/0'/0'/0'`。
const DEFAULT_PATH: [u32; 5] = [
    0x8000_002C,
    0x8000_0310,
    0x8000_0000,
    0x8000_0000,
    0x8000_0000,
];

const MAX_MESSAGE: usize = 4096;

struct Apdu {
    cla: u8,
    ins: u8,
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
            data,
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
    /// 待签消息；`None` 表示这是一次地址查询。
    message: Option<Vec<u8>>,
}

pub struct SuiModule {
    stage: Stage,
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
        if apdu.cla != CLA_SUI {
            return Ok(self.emit(exchange_id, status(sw::CLA_NOT_SUPPORTED)));
        }
        match apdu.ins {
            INS_GET_PUBLIC_KEY => self.handle_get_address(exchange_id, &apdu.data),
            INS_SIGN_TX => self.handle_sign(exchange_id, &apdu.data),
            _ => Ok(self.emit(exchange_id, status(sw::UNKNOWN_INS))),
        }
    }

    fn handle_get_address(
        &mut self,
        exchange_id: ExchangeId,
        data: &[u8],
    ) -> Result<Effect, AppError> {
        // 迁移前的实现拒绝空数据。
        if data.is_empty() {
            return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
        }
        let (path, rest) = match split_path(data) {
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
            message: None,
        });
        self.stage = Stage::AwaitKey;
        Ok(Effect::NeedPublicKey {
            service_id: 1,
            request: key_request(path),
        })
    }

    fn handle_sign(&mut self, exchange_id: ExchangeId, data: &[u8]) -> Result<Effect, AppError> {
        let (path, message) = match split_path(data) {
            Some(split) => split,
            None => return Ok(self.emit(exchange_id, status(sw::WRONG_DATA))),
        };
        if message.is_empty() || message.len() > MAX_MESSAGE {
            return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
        }
        self.pending = Some(Pending {
            exchange_id,
            path: path.clone(),
            address: String::new(),
            message: Some(message.to_vec()),
        });
        self.stage = Stage::AwaitKey;
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
        // 本机账户派生：结果直接回给 UI，不涉及 APDU。
        if let Some(request_id) = self.local.take() {
            self.stage = Stage::Idle;
            let payload = match result {
                ServiceResult::PublicKey(key) if key.bytes.len() == 32 => {
                    let address = sui_address(&key.bytes);
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
        let address = sui_address(&key.bytes);

        let (exchange_id, path, message) = {
            let pending = self
                .pending
                .as_mut()
                .ok_or_else(|| AppError::InvalidEvent("no pending request".into()))?;
            pending.address = address.clone();
            (
                pending.exchange_id,
                pending.path.clone(),
                pending.message.clone(),
            )
        };

        let Some(message) = message else {
            // 地址查询：ASCII 地址 + 9000（与迁移前一致）。
            self.pending = None;
            self.stage = Stage::Idle;
            let mut payload = address.into_bytes();
            payload.extend_from_slice(&status(sw::OK));
            return Ok(self.emit(exchange_id, payload));
        };

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
            service_id: 3,
            request: Box::new(ReviewRequest {
                document: ReviewDocument {
                    operation: OperationKind::Transaction,
                    network: NetworkId {
                        name: "Sui".into(),
                        chain_id: None,
                    },
                    account: Some(address.clone()),
                    sections: vec![ReviewSection {
                        title_key: "review.section.sui".into(),
                        fields: vec![
                            Field {
                                label_key: "review.field.address".into(),
                                value: FieldValue::Address {
                                    value: address,
                                    network: "Sui".into(),
                                    role: "account".into(),
                                },
                            },
                            Field {
                                label_key: "review.field.message_size".into(),
                                value: FieldValue::Text {
                                    value: message.len().to_string(),
                                },
                            },
                            Field {
                                label_key: "review.field.message_hex".into(),
                                value: FieldValue::Bytes { value: message },
                            },
                        ],
                    }],
                    // 设备只签宿主给的消息字节，没有解析 BCS 交易：盲签必须显式。
                    risks: vec![Risk {
                        code: "blind-signing".into(),
                        severity: RiskLevel::Critical,
                        parameters: vec![(
                            "reason".into(),
                            "host supplied message bytes; BCS transaction not parsed".into(),
                        )],
                        source: RiskSource::Module,
                    }],
                    parse_status: ParseStatus::Partial,
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
                if signatures.len() == 1 && signatures[0].bytes.len() == 64 {
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
        Ok(self.emit(pending.exchange_id, payload))
    }
}

impl ChainApp for SuiModule {
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
            Event::Delivered { .. } => Ok(Effect::Finished {
                status: FinishStatus::Delivered,
            }),
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

/// 账户路径：Sui 的账户号在第三段（`m/44'/784'/{account}'/0'/0'`）。
fn account_path(index: u32) -> Vec<u32> {
    let mut path = DEFAULT_PATH;
    path[2] = 0x8000_0000 | index;
    path.to_vec()
}

/// Sui 地址：`0x` + `blake2b(0x00 || pubkey)`。
fn sui_address(public_key: &[u8]) -> String {
    let mut input = Vec::with_capacity(1 + public_key.len());
    input.push(0x00);
    input.extend_from_slice(public_key);
    format!("0x{}", hex::encode(blake2b::hash(&input)))
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

pub fn descriptor() -> AppDescriptor {
    AppDescriptor {
        module_id: MODULE_ID.into(),
        module_version: "0.1.0".into(),
        api_version: API_VERSION,
        review_schema_version: 1,
        storage_schema_version: 1,
        protocol_profiles: vec![chain_app_api::ProtocolProfile {
            name: "Sui".into(),
            version: "0.1.0".into(),
            wire: Wire::LedgerApdu,
            supported: vec![
                "07 02 GET_PUBLIC_KEY (non-standard CLA; official app uses 0x00 0x02)".into(),
                "07 04 SIGN_TX (own extension: host-supplied bytes; blind signing)".into(),
            ],
            unsupported: vec![
                "official CLA 0x00 command set (0x01 VERIFY_ADDRESS / 0x03 SIGN_TX / 0x22 descriptor)".into(),
                "Block Protocol chunking".into(),
            ],
            vector_sources: vec!["tool/e2e/tests/sui_sign.py".into()],
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
