//! Bitcoin 链 App（阶段 3）。
//!
//! 迁移范围与现有 Dart 实现保持一致，但把「多输入」做成一等能力：
//!
//! - `E1 40 GET_WALLET_PUBLIC_KEY`：按路径返回 P2WPKH 地址（bech32）。
//! - `E1 44 SIGN_TRANSACTION`：`[path][input_count][sighash(32)]*count`，
//!   一次审批为多个输入产出签名，按输入顺序拼接返回。
//!
//! 与 ETH 一样，模块不接触 seed：公钥向宿主请求，签名由宿主在批准后执行。

use chain_app_api::{
    AppDescriptor, AppError, ChainApp, Curve, DerivationRule, DerivationScheme, Effect, Event,
    ExchangeId, Field, FieldValue, FinishStatus, KeyOutput, NetworkId, OperationKind,
    ParseStatus, PublicKeyRequest, ReviewAction, ReviewDocument, ReviewOutcome, ReviewRequest,
    ReviewSection, ServiceResult, SessionConfig, SignOperation, SignPlan, SignScheme, Wire,
    API_VERSION,
};
use open_ledger_crypto::{bech32, hash160};

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
const INS_GET_PUBLIC_KEY: u8 = 0x40;
const INS_SIGN_TX: u8 = 0x44;

/// `m/84'/0'/0'/0/0`（BIP-84 P2WPKH）。
const DEFAULT_PATH: [u32; 5] = [0x8000_0054, 0x8000_0000, 0x8000_0000, 0, 0];

/// 一笔交易最多接受的输入数；超过即拒，避免一次审批绑过多签名。
const MAX_INPUTS: usize = 16;

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
    /// 待签摘要；`None` 表示这是地址查询。
    sighashes: Option<Vec<[u8; 32]>>,
}

pub struct BitcoinModule {
    stage: Stage,
    pending: Option<Pending>,
    /// 本机账户请求的 `request_id`（`LocalCommand::DeriveAccount`）。
    local: Option<u64>,
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
        if apdu.p1 != 0x00 || apdu.p2 != 0x00 {
            return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2)));
        }
        match apdu.ins {
            INS_GET_PUBLIC_KEY => self.handle_get_public_key(exchange_id, &apdu.data),
            INS_SIGN_TX => self.handle_sign(exchange_id, &apdu.data),
            _ => Ok(self.emit(exchange_id, status(sw::UNKNOWN_INS))),
        }
    }

    fn handle_get_public_key(
        &mut self,
        exchange_id: ExchangeId,
        data: &[u8],
    ) -> Result<Effect, AppError> {
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
            sighashes: None,
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

    fn handle_sign(
        &mut self,
        exchange_id: ExchangeId,
        data: &[u8],
    ) -> Result<Effect, AppError> {
        let (path, rest) = match split_path(data) {
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
        let mut sighashes = Vec::with_capacity(count);
        for chunk in digests.as_chunks::<32>().0 {
            sighashes.push(*chunk);
        }

        self.pending = Some(Pending {
            exchange_id,
            path: path.clone(),
            address: String::new(),
            sighashes: Some(sighashes),
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
        // 本机账户派生：结果直接回给 UI，不涉及 APDU。
        if let Some(request_id) = self.local.take() {
            self.stage = Stage::Idle;
            let payload = match result {
                ServiceResult::PublicKey(key) => match p2wpkh_address(&key.bytes) {
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
        let address = match p2wpkh_address(&key.bytes) {
            Some(address) => address,
            None => {
                let exchange_id = self.pending.take().map(|p| p.exchange_id).unwrap_or(1);
                self.stage = Stage::Idle;
                return Ok(self.emit(exchange_id, status(sw::UNKNOWN)));
            }
        };

        let (exchange_id, path, sighashes) = {
            let pending = self
                .pending
                .as_mut()
                .ok_or_else(|| AppError::InvalidEvent("no pending request".into()))?;
            pending.address = address.clone();
            (
                pending.exchange_id,
                pending.path.clone(),
                pending.sighashes.clone(),
            )
        };

        let Some(sighashes) = sighashes else {
            // 地址查询：ASCII 地址 + 9000（与迁移前的线格式一致）。
            let mut payload = address.into_bytes();
            payload.extend_from_slice(&status(sw::OK));
            self.pending = None;
            self.stage = Stage::Idle;
            return Ok(self.emit(exchange_id, payload));
        };

        let operations: Vec<SignOperation> = sighashes
            .iter()
            .enumerate()
            .map(|(index, digest)| SignOperation {
                operation_id: index as u32 + 1,
                derivation_scheme: DerivationScheme::Bip32Secp256k1,
                curve: Curve::Secp256k1,
                path: path.clone(),
                scheme: SignScheme::EcdsaPrehash {
                    digest_len: 32,
                    low_s: true,
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
                        name: "Bitcoin".into(),
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
                                    network: "Bitcoin".into(),
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
                    risks: vec![],
                    parse_status: ParseStatus::Complete,
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
        let expected = pending
            .sighashes
            .as_ref()
            .map(Vec::len)
            .ok_or_else(|| AppError::InvalidEvent("review without sighashes".into()))?;

        let payload = match outcome {
            ReviewOutcome::Approved { signatures } => {
                if signatures.len() != expected {
                    status(sw::UNKNOWN)
                } else {
                    let mut out = Vec::with_capacity(expected * 65 + 2);
                    let mut complete = true;
                    for signature in &signatures {
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

/// 账户路径：BTC 的账户号在最后一段（`m/84'/0'/0'/0/{account}`）。
fn account_path(index: u32) -> Vec<u32> {
    let mut path = DEFAULT_PATH;
    path[4] = index;
    path.to_vec()
}

/// P2WPKH 地址：`bech32("bc", 0, hash160(pubkey))`。
fn p2wpkh_address(compressed_pubkey: &[u8]) -> Option<String> {
    if compressed_pubkey.len() != 33 {
        return None;
    }
    let hash = hash160::hash(compressed_pubkey);
    Some(bech32::encode("bc", 0, &hash))
}

/// `[count][u32 BE]*` → 路径；空数据用默认 `m/84'/0'/0'/0/0`。
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
            name: "Bitcoin".into(),
            version: "2.4.0".into(),
            wire: Wire::LedgerApdu,
            supported: vec![
                "E1 40 GET_WALLET_PUBLIC_KEY (P2WPKH)".into(),
                "E1 44 SIGN_TRANSACTION (multi-input)".into(),
            ],
            unsupported: vec![],
            vector_sources: vec!["tool/e2e/tests/btc_sign.py".into()],
        }],
        account_profiles: vec![chain_app_api::AccountProfile {
            network: "Bitcoin".into(),
            account_type: "p2wpkh".into(),
            default_path: "m/84'/0'/0'/0/0".into(),
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
