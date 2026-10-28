//! Ethereum 链 App（阶段 2 纵向切片 A：`GET_PUBLIC_KEY`）。
//!
//! 本模块只实现官方 app-ethereum 的 `INS 0x02`：地址直接返回（P1=0x00）与
//! 地址显示确认（P1=0x01）。交易、personal message 与 EIP-712 仍留在 Dart，
//! 由后续切片迁入。
//!
//! 模块不接触 seed：公钥通过 `NeedPublicKey` 向宿主请求，地址由公钥本地计算。

use chain_app_api::{
    AppDescriptor, AppError, CancelReason, CapabilitySet, ChainApp, Curve, DerivationRule,
    DerivationScheme, Effect, Event, ExchangeId, Field, FieldValue, FinishStatus, KeyOutput,
    NetworkId, OperationKind, OperationState, ParseStatus, PublicKeyRequest, ReviewAction,
    ReviewDocument, ReviewOutcome, ReviewRequest, ReviewSection, ServiceResult, SessionConfig,
    SignOperation, SignPlan, SignScheme, Wire, API_VERSION,
};
use open_ledger_crypto::rlp::{rlp_addr, rlp_val_uint};

pub mod sw {
    pub const OK: u16 = 0x9000;
    pub const DENIED: u16 = 0x6985;
    pub const WRONG_DATA: u16 = 0x6A80;
    pub const WRONG_P1_P2: u16 = 0x6A86;
    pub const UNKNOWN_INS: u16 = 0x6D00;
    pub const CLA_NOT_SUPPORTED: u16 = 0x6E00;
    pub const UNKNOWN: u16 = 0x6F00;
}

const CLA_ETH: u8 = 0xE0;
const INS_GET_PUBLIC_KEY: u8 = 0x02;
const INS_SIGN_TX: u8 = 0x04;
const INS_SIGN_PERSONAL: u8 = 0x08;
const INS_SIGN_EIP712: u8 = 0x0C;
const P1_RETURN: u8 = 0x00;
const P1_CONFIRM: u8 = 0x01;
const P1_FIRST_BLOCK: u8 = 0x00;
const P1_MORE_BLOCK: u8 = 0x80;
const P2_NO_CHAIN_CODE: u8 = 0x00;
const P2_CHAIN_CODE: u8 = 0x01;
const P2_PERSONAL: u8 = 0x00;
const P2_PROCESS: u8 = 0x00;
const P2_STORE_ONLY: u8 = 0x01;
const P2_START_FLOW: u8 = 0x02;
const P2_EIP712_V0: u8 = 0x00;

/// 与宿主单帧预算一致；超出即拒，不分配。
const MAX_PERSONAL_MESSAGE: usize = 4096;
/// 交易 RLP 上限（多分片累积）。
const MAX_TX_BYTES: usize = 32 * 1024;

const DEFAULT_PATH: [u32; 5] = [
    0x8000_002c, // 44'
    0x8000_003c, // 60'
    0x8000_0000, // 0'
    0,
    0,
];

/// 解析后的 APDU。模块只看到完整一帧，分帧与重组属于传输适配器。
pub struct Apdu {
    pub cla: u8,
    pub ins: u8,
    pub p1: u8,
    pub p2: u8,
    pub data: Vec<u8>,
}

impl Apdu {
    pub fn parse(bytes: &[u8]) -> Option<Self> {
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

/// BIP-32 路径编码：`len(1) + len × u32 BE`。空数据表示使用默认路径。
pub fn parse_path(data: &[u8]) -> Option<Vec<u32>> {
    if data.is_empty() {
        return Some(DEFAULT_PATH.to_vec());
    }
    let count = data[0] as usize;
    if data.len() != 1 + count * 4 || count == 0 {
        return None;
    }
    let mut path = Vec::with_capacity(count);
    for chunk in data[1..].as_chunks::<4>().0 {
        path.push(u32::from_be_bytes(*chunk));
    }
    Some(path)
}

/// EIP-55 校验和地址（不含 `0x`）。官方 app 用同样的大小写编码。
pub fn checksum_address(address: &[u8; 20]) -> String {
    let lower = hex_lower(address);
    let hash = open_ledger_crypto::keccak256::hash(lower.as_bytes());
    lower
        .chars()
        .enumerate()
        .map(|(i, c)| {
            if !c.is_ascii_alphabetic() {
                return c;
            }
            let nibble = (hash[i / 2] >> (if i % 2 == 0 { 4 } else { 0 })) & 0x0F;
            if nibble >= 8 {
                c.to_ascii_uppercase()
            } else {
                c
            }
        })
        .collect()
}

fn hex_lower(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// 由未压缩公钥（0x04 || X || Y）计算地址。
pub fn address_from_uncompressed(public_key: &[u8]) -> Option<[u8; 20]> {
    if public_key.len() != 65 || public_key[0] != 0x04 {
        return None;
    }
    let hash = open_ledger_crypto::keccak256::hash(&public_key[1..]);
    let mut address = [0u8; 20];
    address.copy_from_slice(&hash[12..]);
    Some(address)
}

/// 官方 `cmd_get_public_key.c` 的响应布局：
/// `0x41 | 65B 公钥 | 地址长度 | ASCII 地址 | [32B chain code] | 90 00`
pub fn public_key_response(
    public_key: &[u8],
    address: &str,
    chain_code: Option<&[u8]>,
) -> Vec<u8> {
    let address_bytes = address.as_bytes();
    let mut out = Vec::with_capacity(1 + 65 + 1 + address_bytes.len() + 32 + 2);
    out.push(0x41);
    out.extend_from_slice(public_key);
    out.push(address_bytes.len() as u8);
    out.extend_from_slice(address_bytes);
    if let Some(code) = chain_code {
        out.extend_from_slice(code);
    }
    out.extend_from_slice(&sw::OK.to_be_bytes());
    out
}

fn status(code: u16) -> Vec<u8> {
    code.to_be_bytes().to_vec()
}

enum Stage {
    Idle,
    AwaitKey,
    AwaitReview,
    /// personal message 首块已收，还在等后续块（未到声明长度）。
    CollectingPersonal,
    /// 交易 RLP 还没收全（按 RLP 头算出的总长判断）。
    CollectingTx,
}

/// 已冻结、待审阅的签名语义。载荷由模块持有，签名由宿主执行。
#[derive(Clone)]
enum SignKind {
    Personal {
        message: Vec<u8>,
    },
    Transaction {
        /// 完整 RLP（typed tx 含首字节 type）。
        bytes: Vec<u8>,
        typed: bool,
    },
    Eip712 {
        domain_hash: [u8; 32],
        struct_hash: [u8; 32],
    },
}

struct Pending {
    exchange_id: ExchangeId,
    path: Vec<u32>,
    confirm: bool,
    with_chain_code: bool,
    public_key: Vec<u8>,
    address: String,
    chain_code: Option<Vec<u8>>,
    /// 签名类请求；地址确认时为 `None`。
    sign: Option<SignKind>,
    /// personal message 协议声明的总长；其他情况为 0。
    declared: usize,
}

/// 交易分片缓冲：首块带路径，续块只有字节。
struct TxBuffer {
    exchange_id: ExchangeId,
    path: Vec<u32>,
    bytes: Vec<u8>,
    store_only: bool,
}

pub struct EthereumModule {
    stage: Stage,
    pending: Option<Pending>,
    tx: Option<TxBuffer>,
    /// 本机账户请求的 `request_id`（`LocalCommand::DeriveAccount`）。
    local: Option<u64>,
}

impl Default for EthereumModule {
    fn default() -> Self {
        Self::new()
    }
}

impl EthereumModule {
    pub fn new() -> Self {
        Self {
            stage: Stage::Idle,
            pending: None,
            tx: None,
            local: None,
        }
    }

    fn emit(&self, exchange_id: ExchangeId, payload: Vec<u8>) -> Effect {
        self.emit_state(exchange_id, payload, OperationState::Final)
    }

    fn emit_state(
        &self,
        exchange_id: ExchangeId,
        payload: Vec<u8>,
        state: OperationState,
    ) -> Effect {
        Effect::Emit {
            wire: Wire::LedgerApdu,
            exchange_id,
            payload,
            state,
        }
    }

    fn handle_apdu(&mut self, exchange_id: ExchangeId, bytes: &[u8]) -> Result<Effect, AppError> {
        let apdu = Apdu::parse(bytes).ok_or_else(|| AppError::BadRequest("truncated APDU".into()))?;
        if apdu.cla != CLA_ETH {
            return Ok(self.emit(exchange_id, status(sw::CLA_NOT_SUPPORTED)));
        }
        if apdu.ins == INS_SIGN_PERSONAL {
            return self.handle_personal(exchange_id, &apdu);
        }
        if apdu.ins == INS_SIGN_TX {
            return self.handle_transaction(exchange_id, &apdu);
        }
        if apdu.ins == INS_SIGN_EIP712 {
            return self.handle_eip712(exchange_id, &apdu);
        }
        // 收集续块期间不接受其他命令，避免把半条消息与地址请求搅在一起。
        if matches!(
            self.stage,
            Stage::CollectingPersonal | Stage::CollectingTx
        ) {
            return Ok(self.emit(exchange_id, status(sw::UNKNOWN_INS)));
        }
        if apdu.ins != INS_GET_PUBLIC_KEY {
            return Ok(self.emit(exchange_id, status(sw::UNKNOWN_INS)));
        }
        if apdu.p1 != P1_RETURN && apdu.p1 != P1_CONFIRM {
            return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2)));
        }
        if apdu.p2 != P2_NO_CHAIN_CODE && apdu.p2 != P2_CHAIN_CODE {
            return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2)));
        }
        let path = match parse_path(&apdu.data) {
            Some(path) => path,
            None => return Ok(self.emit(exchange_id, status(sw::WRONG_DATA))),
        };

        self.pending = Some(Pending {
            exchange_id,
            path: path.clone(),
            confirm: apdu.p1 == P1_CONFIRM,
            with_chain_code: apdu.p2 == P2_CHAIN_CODE,
            public_key: Vec::new(),
            address: String::new(),
            chain_code: None,
            sign: None,
            declared: 0,
        });
        self.stage = Stage::AwaitKey;
        Ok(Effect::NeedPublicKey {
            service_id: 1,
            request: PublicKeyRequest {
                derivation_scheme: DerivationScheme::Bip32Secp256k1,
                curve: Curve::Secp256k1,
                path,
                output: KeyOutput::UncompressedSecp256k1,
                include_chain_code: apdu.p2 == P2_CHAIN_CODE,
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
                        "{{\"address\":\"0x{}\",\"public_key\":\"{}\"}}",
                        checksum_address(&address),
                        hex_lower(&key.bytes)
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
        let address = match address_from_uncompressed(&key.bytes) {
            Some(address) => address,
            None => {
                let exchange_id = self.pending.take().map(|p| p.exchange_id).unwrap_or(1);
                self.stage = Stage::Idle;
                return Ok(self.emit(exchange_id, status(sw::UNKNOWN)));
            }
        };
        let address_text = checksum_address(&address);

        let (exchange_id, path, confirm, with_chain_code, sign) = {
            let pending = self
                .pending
                .as_mut()
                .ok_or_else(|| AppError::InvalidEvent("no pending request".into()))?;
            pending.public_key = key.bytes.clone();
            pending.address = address_text.clone();
            pending.chain_code = key.chain_code.clone();
            (
                pending.exchange_id,
                pending.path.clone(),
                pending.confirm,
                pending.with_chain_code,
                pending.sign.clone(),
            )
        };

        // 签名类请求：地址只用于展示，随后进入审阅。
        if let Some(sign) = sign {
            let request = match sign {
                SignKind::Personal { message } => personal_review(&address_text, &path, &message),
                SignKind::Transaction { bytes, typed } => {
                    match transaction_review(&address_text, &path, &bytes, typed) {
                        Some(request) => request,
                        None => {
                            self.pending = None;
                            self.stage = Stage::Idle;
                            return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
                        }
                    }
                }
                SignKind::Eip712 {
                    domain_hash,
                    struct_hash,
                } => eip712_review(&address_text, &path, &domain_hash, &struct_hash),
            };
            self.stage = Stage::AwaitReview;
            return Ok(Effect::NeedReview {
                service_id: 3,
                request: Box::new(request),
            });
        }

        if !confirm {
            let payload = public_key_response(
                &key.bytes,
                &address_text,
                if with_chain_code {
                    key.chain_code.as_deref()
                } else {
                    None
                },
            );
            self.pending = None;
            self.stage = Stage::Idle;
            return Ok(self.emit(exchange_id, payload));
        }

        self.stage = Stage::AwaitReview;
        Ok(Effect::NeedReview {
            service_id: 2,
            request: Box::new(ReviewRequest {
                document: ReviewDocument {
                    operation: OperationKind::AddressConfirmation,
                    network: NetworkId {
                        name: "Ethereum".into(),
                        chain_id: Some(1),
                    },
                    account: Some(address_text.clone()),
                    sections: vec![ReviewSection {
                        title_key: "review.section.address".into(),
                        fields: vec![Field {
                            label_key: "review.field.address".into(),
                            value: FieldValue::Address {
                                value: address_text,
                                network: "Ethereum".into(),
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
        })
    }

    fn handle_review(&mut self, outcome: ReviewOutcome) -> Result<Effect, AppError> {
        let pending = self
            .pending
            .take()
            .ok_or_else(|| AppError::InvalidEvent("no pending review".into()))?;
        self.stage = Stage::Idle;
        let payload = match &pending.sign {
            Some(kind) => {
                // typed tx（EIP-2930/1559）的 v 是 0/1；legacy 与消息、EIP-712 用 27/28。
                let v_base: u8 = match kind {
                    SignKind::Transaction { typed: true, .. } => 0,
                    _ => 27,
                };
                match outcome {
                    ReviewOutcome::Approved { signatures } => match signatures.first() {
                        Some(signature) if signature.bytes.len() == 64 => {
                            match signature.recovery_id {
                                Some(recovery) => {
                                    let mut out = Vec::with_capacity(67);
                                    out.push(v_base + recovery);
                                    out.extend_from_slice(&signature.bytes);
                                    out.extend_from_slice(&status(sw::OK));
                                    out
                                }
                                None => status(sw::UNKNOWN),
                            }
                        }
                        _ => status(sw::UNKNOWN),
                    },
                    ReviewOutcome::Rejected | ReviewOutcome::TimedOut => status(sw::DENIED),
                    ReviewOutcome::Failed(_) => status(sw::UNKNOWN),
                }
            }
            None => match outcome {
                ReviewOutcome::Approved { .. } => public_key_response(
                    &pending.public_key,
                    &pending.address,
                    if pending.with_chain_code {
                        pending.chain_code.as_deref()
                    } else {
                        None
                    },
                ),
                ReviewOutcome::Rejected | ReviewOutcome::TimedOut => status(sw::DENIED),
                ReviewOutcome::Failed(_) => status(sw::UNKNOWN),
            },
        };
        Ok(self.emit(pending.exchange_id, payload))
    }

    /// `E0 08 SIGN_PERSONAL_MESSAGE`。
    ///
    /// 首块布局 `[path][length u32 BE][chunk]`，续块只有 chunk；`P2` 必须为
    /// 0x00。收集中每帧回 9000（`Collecting`），凑满声明长度后进入签名审阅。
    fn handle_personal(
        &mut self,
        exchange_id: ExchangeId,
        apdu: &Apdu,
    ) -> Result<Effect, AppError> {
        if apdu.p2 != P2_PERSONAL {
            return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2)));
        }
        match apdu.p1 {
            P1_FIRST_BLOCK => {
                let (path, rest) = match split_path(&apdu.data) {
                    Some(split) => split,
                    None => return Ok(self.emit(exchange_id, status(sw::WRONG_DATA))),
                };
                if rest.len() < 4 {
                    return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
                }
                let declared =
                    u32::from_be_bytes([rest[0], rest[1], rest[2], rest[3]]) as usize;
                let chunk = &rest[4..];
                if declared == 0 || declared > MAX_PERSONAL_MESSAGE || chunk.len() > declared {
                    return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
                }
                let buffer = chunk.to_vec();
                if buffer.len() < declared {
                    self.pending = Some(Pending {
                        exchange_id,
                        path,
                        confirm: false,
                        with_chain_code: false,
                        public_key: Vec::new(),
                        address: String::new(),
                        chain_code: None,
                        sign: Some(SignKind::Personal { message: buffer }),
                        declared,
                    });
                    self.stage = Stage::CollectingPersonal;
                    return Ok(self.emit_state(
                        exchange_id,
                        status(sw::OK),
                        OperationState::Collecting,
                    ));
                }
                self.begin_personal_review(exchange_id, path, buffer)
            }
            P1_MORE_BLOCK => {
                if !matches!(self.stage, Stage::CollectingPersonal) {
                    return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
                }
                let (path, complete, message, declared) = {
                    let pending = self
                        .pending
                        .as_mut()
                        .ok_or_else(|| AppError::InvalidEvent("collecting without buffer".into()))?;
                    let buffer = match pending.sign.as_mut() {
                        Some(SignKind::Personal { message }) => message,
                        _ => {
                            return Err(AppError::InvalidEvent(
                                "collecting without buffer".into(),
                            ))
                        }
                    };
                    if buffer.len() + apdu.data.len() > pending.declared {
                        return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
                    }
                    buffer.extend_from_slice(&apdu.data);
                    pending.exchange_id = exchange_id;
                    (
                        pending.path.clone(),
                        buffer.len() == pending.declared,
                        buffer.clone(),
                        pending.declared,
                    )
                };
                if !complete {
                    debug_assert!(message.len() < declared);
                    return Ok(self.emit_state(
                        exchange_id,
                        status(sw::OK),
                        OperationState::Collecting,
                    ));
                }
                self.begin_personal_review(exchange_id, path, message)
            }
            _ => Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2))),
        }
    }

    fn begin_personal_review(
        &mut self,
        exchange_id: ExchangeId,
        path: Vec<u32>,
        message: Vec<u8>,
    ) -> Result<Effect, AppError> {
        self.pending = Some(Pending {
            exchange_id,
            path: path.clone(),
            confirm: false,
            with_chain_code: false,
            public_key: Vec::new(),
            address: String::new(),
            chain_code: None,
            sign: Some(SignKind::Personal { message }),
            declared: 0,
        });
        self.stage = Stage::AwaitKey;
        Ok(Effect::NeedPublicKey {
            service_id: 3,
            request: PublicKeyRequest {
                derivation_scheme: DerivationScheme::Bip32Secp256k1,
                curve: Curve::Secp256k1,
                path,
                output: KeyOutput::UncompressedSecp256k1,
                include_chain_code: false,
            },
        })
    }

    /// `E0 04 SIGN_ETH_TRANSACTION`（legacy / EIP-2930 / EIP-1559）。
    ///
    /// 首块 `[path][rlp...]`，续块只有 RLP 字节；完整性由 RLP 头算出的总长
    /// 判断，而不是客户端声明。`P2=0x01` 只接收不签名，`P2=0x02` 是开始握手。
    fn handle_transaction(
        &mut self,
        exchange_id: ExchangeId,
        apdu: &Apdu,
    ) -> Result<Effect, AppError> {
        if apdu.p1 != P1_FIRST_BLOCK && apdu.p1 != P1_MORE_BLOCK {
            return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2)));
        }
        if apdu.p2 != P2_PROCESS && apdu.p2 != P2_STORE_ONLY && apdu.p2 != P2_START_FLOW {
            return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2)));
        }
        if apdu.p2 == P2_START_FLOW {
            self.tx = None;
            self.stage = Stage::Idle;
            return Ok(self.emit(exchange_id, status(sw::OK)));
        }
        let store_only = apdu.p2 == P2_STORE_ONLY;

        if apdu.p1 == P1_FIRST_BLOCK {
            let (path, rest) = match split_path(&apdu.data) {
                Some(split) => split,
                None => {
                    self.tx = None;
                    self.stage = Stage::Idle;
                    return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
                }
            };
            if rest.is_empty() || rest.len() > MAX_TX_BYTES {
                self.tx = None;
                self.stage = Stage::Idle;
                return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
            }
            self.tx = Some(TxBuffer {
                exchange_id,
                path,
                bytes: rest.to_vec(),
                store_only,
            });
            self.stage = Stage::CollectingTx;
            return self.advance_tx(exchange_id);
        }

        if !matches!(self.stage, Stage::CollectingTx) || apdu.data.is_empty() {
            return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
        }
        {
            let tx = match self.tx.as_mut() {
                Some(tx) => tx,
                None => return Ok(self.emit(exchange_id, status(sw::WRONG_DATA))),
            };
            if tx.bytes.len() + apdu.data.len() > MAX_TX_BYTES {
                self.tx = None;
                self.stage = Stage::Idle;
                return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
            }
            tx.bytes.extend_from_slice(&apdu.data);
            tx.exchange_id = exchange_id;
        }
        self.advance_tx(exchange_id)
    }

    fn advance_tx(&mut self, exchange_id: ExchangeId) -> Result<Effect, AppError> {
        let complete = match self.tx.as_ref() {
            Some(tx) => tx_total_len(&tx.bytes).is_some_and(|total| tx.bytes.len() >= total),
            None => false,
        };
        if !complete {
            return Ok(self.emit_state(
                exchange_id,
                status(sw::OK),
                OperationState::Collecting,
            ));
        }

        let tx = match self.tx.take() {
            Some(tx) => tx,
            None => return Ok(self.emit(exchange_id, status(sw::UNKNOWN))),
        };
        if tx.store_only {
            self.stage = Stage::Idle;
            return Ok(self.emit(exchange_id, status(sw::OK)));
        }

        let typed = tx.bytes[0] <= 0x7f;
        self.pending = Some(Pending {
            exchange_id,
            path: tx.path.clone(),
            confirm: false,
            with_chain_code: false,
            public_key: Vec::new(),
            address: String::new(),
            chain_code: None,
            sign: Some(SignKind::Transaction {
                bytes: tx.bytes,
                typed,
            }),
            declared: 0,
        });
        self.stage = Stage::AwaitKey;
        Ok(Effect::NeedPublicKey {
            service_id: 4,
            request: PublicKeyRequest {
                derivation_scheme: DerivationScheme::Bip32Secp256k1,
                curve: Curve::Secp256k1,
                path: tx.path,
                output: KeyOutput::UncompressedSecp256k1,
                include_chain_code: false,
            },
        })
    }

    /// `E0 0C SIGN_EIP_712_MESSAGE`，只实现 V0 单步（`P2=0x00`）。
    fn handle_eip712(
        &mut self,
        exchange_id: ExchangeId,
        apdu: &Apdu,
    ) -> Result<Effect, AppError> {
        if apdu.p1 != P1_FIRST_BLOCK || apdu.p2 != P2_EIP712_V0 {
            // V1 流式形态未实现，明确拒绝而不是误读。
            return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2)));
        }
        let (path, rest) = match split_path(&apdu.data) {
            Some(split) => split,
            None => return Ok(self.emit(exchange_id, status(sw::WRONG_DATA))),
        };
        if rest.len() != 64 {
            return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
        }
        let mut domain_hash = [0u8; 32];
        let mut struct_hash = [0u8; 32];
        domain_hash.copy_from_slice(&rest[..32]);
        struct_hash.copy_from_slice(&rest[32..]);

        self.pending = Some(Pending {
            exchange_id,
            path: path.clone(),
            confirm: false,
            with_chain_code: false,
            public_key: Vec::new(),
            address: String::new(),
            chain_code: None,
            sign: Some(SignKind::Eip712 {
                domain_hash,
                struct_hash,
            }),
            declared: 0,
        });
        self.stage = Stage::AwaitKey;
        Ok(Effect::NeedPublicKey {
            service_id: 5,
            request: PublicKeyRequest {
                derivation_scheme: DerivationScheme::Bip32Secp256k1,
                curve: Curve::Secp256k1,
                path,
                output: KeyOutput::UncompressedSecp256k1,
                include_chain_code: false,
            },
        })
    }
}

/// 一个 RLP item 的总字节数；typed tx 要把首字节 type 算回去。
///
/// 还没收全时返回 `None`（RLP 头本身不完整），调用方据此继续收集。
fn tx_total_len(bytes: &[u8]) -> Option<usize> {
    if bytes.is_empty() {
        return None;
    }
    let (body, typed) = if bytes[0] <= 0x7f {
        (&bytes[1..], true)
    } else {
        (bytes, false)
    };
    if body.is_empty() {
        return None;
    }
    let total = rlp::Rlp::new(body).payload_info().ok()?.total();
    Some(if typed { total + 1 } else { total })
}

/// 审阅展示需要的交易字段。解析失败即视为坏数据，绝不盲签。
struct ParsedTx {
    to: String,
    value: String,
    gas: String,
    gas_price: String,
    nonce: String,
    data: Vec<u8>,
    chain_id: Option<u64>,
}

fn parse_tx(bytes: &[u8], typed: bool) -> Option<ParsedTx> {
    let body = if typed { &bytes[1..] } else { bytes };
    let rlp = rlp::Rlp::new(body);
    let count = rlp.item_count().ok()?;
    let (price_idx, gas_idx, to_idx, value_idx, data_idx) = if typed {
        (3, 4, 5, 6, 7)
    } else {
        (1, 2, 3, 4, 5)
    };
    if count <= data_idx {
        return None;
    }
    let nonce = rlp_val_uint(&rlp.at(0).ok()?);
    let gas_price = rlp_val_uint(&rlp.at(price_idx).ok()?);
    let gas = rlp_val_uint(&rlp.at(gas_idx).ok()?);
    let to = rlp_addr(&rlp.at(to_idx).ok()?);
    let value = rlp_val_uint(&rlp.at(value_idx).ok()?);
    let data = rlp
        .at(data_idx)
        .ok()
        .and_then(|item| item.data().ok())
        .unwrap_or(&[])
        .to_vec();
    let chain_id = if typed {
        rlp_val_uint(&rlp.at(0).ok()?).parse::<u64>().ok()
    } else if count > 6 {
        rlp_val_uint(&rlp.at(6).ok()?).parse::<u64>().ok()
    } else {
        None
    };
    Some(ParsedTx {
        to,
        value,
        gas,
        gas_price,
        nonce,
        data,
        chain_id,
    })
}

fn transaction_review(
    address: &str,
    path: &[u32],
    bytes: &[u8],
    typed: bool,
) -> Option<ReviewRequest> {
    let parsed = parse_tx(bytes, typed)?;
    let digest = open_ledger_crypto::keccak256::hash(bytes);

    let mut fields = vec![
        Field {
            label_key: "review.field.to".into(),
            value: FieldValue::Address {
                value: parsed.to.clone(),
                network: "Ethereum".into(),
                role: "recipient".into(),
            },
        },
        Field {
            label_key: "review.field.value".into(),
            value: FieldValue::Amount {
                raw: parsed.value.clone(),
                decimals: 18,
                asset: "ETH".into(),
                ticker: Some("ETH".into()),
            },
        },
        Field {
            label_key: "review.field.gas".into(),
            value: FieldValue::Text {
                value: parsed.gas.clone(),
            },
        },
        Field {
            label_key: "review.field.gas_price".into(),
            value: FieldValue::Amount {
                raw: parsed.gas_price.clone(),
                decimals: 18,
                asset: "ETH".into(),
                ticker: Some("ETH".into()),
            },
        },
        Field {
            label_key: "review.field.nonce".into(),
            value: FieldValue::Text {
                value: parsed.nonce.clone(),
            },
        },
    ];
    if !parsed.data.is_empty() {
        fields.push(Field {
            label_key: "review.field.data".into(),
            value: FieldValue::Bytes {
                value: parsed.data.clone(),
            },
        });
    }

    Some(ReviewRequest {
        document: ReviewDocument {
            operation: OperationKind::Transaction,
            network: NetworkId {
                name: "Ethereum".into(),
                chain_id: parsed.chain_id,
            },
            account: Some(format!("0x{address}")),
            sections: vec![ReviewSection {
                title_key: "review.section.transaction".into(),
                fields,
            }],
            risks: vec![],
            parse_status: ParseStatus::Complete,
        },
        action: ReviewAction::Sign(SignPlan::single(SignOperation {
            operation_id: 1,
            derivation_scheme: DerivationScheme::Bip32Secp256k1,
            curve: Curve::Secp256k1,
            path: path.to_vec(),
            scheme: SignScheme::EcdsaPrehash {
                digest_len: 32,
                low_s: true,
            },
            input: digest.to_vec(),
            public_parameters: vec![("payload_hex".into(), bytes.to_vec())],
        })),
    })
}

fn eip712_review(
    address: &str,
    path: &[u32],
    domain_hash: &[u8; 32],
    struct_hash: &[u8; 32],
) -> ReviewRequest {
    let mut payload = Vec::with_capacity(66);
    payload.push(0x19);
    payload.push(0x01);
    payload.extend_from_slice(domain_hash);
    payload.extend_from_slice(struct_hash);
    let digest = open_ledger_crypto::keccak256::hash(&payload);

    ReviewRequest {
        document: ReviewDocument {
            operation: OperationKind::Message,
            network: NetworkId {
                name: "Ethereum".into(),
                chain_id: Some(1),
            },
            account: Some(format!("0x{address}")),
            sections: vec![ReviewSection {
                title_key: "review.section.eip712".into(),
                fields: vec![
                    Field {
                        label_key: "review.field.domain_hash".into(),
                        value: FieldValue::Text {
                            value: format!("0x{}", hex_lower(domain_hash)),
                        },
                    },
                    Field {
                        label_key: "review.field.struct_hash".into(),
                        value: FieldValue::Text {
                            value: format!("0x{}", hex_lower(struct_hash)),
                        },
                    },
                ],
            }],
            risks: vec![],
            parse_status: ParseStatus::Complete,
        },
        action: ReviewAction::Sign(SignPlan::single(SignOperation {
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
        })),
    }
}

/// 拆出 `[path][remainder]`；`path` 必须带显式长度前缀。
fn split_path(data: &[u8]) -> Option<(Vec<u32>, &[u8])> {
    if data.is_empty() {
        return None;
    }
    let count = data[0] as usize;
    let end = 1 + count.checked_mul(4)?;
    if count == 0 || data.len() < end {
        return None;
    }
    let path = parse_path(&data[..end])?;
    Some((path, &data[end..]))
}

/// EIP-191 personal message 摘要。
fn personal_digest(message: &[u8]) -> [u8; 32] {
    let prefix = format!("\x19Ethereum Signed Message:\n{}", message.len());
    let mut payload = Vec::with_capacity(prefix.len() + message.len());
    payload.extend_from_slice(prefix.as_bytes());
    payload.extend_from_slice(message);
    open_ledger_crypto::keccak256::hash(&payload)
}

fn personal_review(address: &str, path: &[u32], message: &[u8]) -> ReviewRequest {
    let digest = personal_digest(message);
    ReviewRequest {
        document: ReviewDocument {
            operation: OperationKind::Message,
            network: NetworkId {
                name: "Ethereum".into(),
                chain_id: Some(1),
            },
            account: Some(format!("0x{address}")),
            sections: vec![ReviewSection {
                title_key: "review.section.message".into(),
                fields: vec![
                    Field {
                        label_key: "review.field.message".into(),
                        value: FieldValue::Text {
                            value: String::from_utf8_lossy(message).into_owned(),
                        },
                    },
                    Field {
                        label_key: "review.field.message_hex".into(),
                        value: FieldValue::Bytes {
                            value: message.to_vec(),
                        },
                    },
                ],
            }],
            risks: vec![],
            parse_status: ParseStatus::Complete,
        },
        action: ReviewAction::Sign(SignPlan::single(SignOperation {
            operation_id: 1,
            derivation_scheme: DerivationScheme::Bip32Secp256k1,
            curve: Curve::Secp256k1,
            path: path.to_vec(),
            scheme: SignScheme::EcdsaPrehash {
                digest_len: 32,
                low_s: true,
            },
            input: digest.to_vec(),
            public_parameters: vec![("payload_hex".into(), message.to_vec())],
        })),
    }
}

impl ChainApp for EthereumModule {
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
                Stage::Idle | Stage::CollectingPersonal | Stage::CollectingTx => {
                    self.handle_apdu(exchange_id, &payload)
                }
                _ => Err(AppError::InvalidEvent("busy".into())),
            },
            Event::ServiceResult { result, .. } => self.handle_service_result(result),
            Event::ReviewResult { outcome, .. } => self.handle_review(outcome),
            Event::Delivered { .. } => {
                // 多块收集还在进行：本轮的 9000 已送出，但不能结束会话，
                // 否则下一块无处可去。
                if matches!(
                    self.stage,
                    Stage::CollectingPersonal | Stage::CollectingTx
                ) {
                    return Ok(Effect::AwaitInput);
                }
                Ok(Effect::Finished {
                    status: FinishStatus::Delivered,
                })
            }
            Event::Cancel { .. } => {
                self.pending = None;
                self.tx = None;
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

    fn close(&mut self, _reason: CancelReason) {
        self.pending = None;
        // I9：锁定/断连时不得留下半条交易或消息的缓冲。
        self.tx = None;
        self.local = None;
        self.stage = Stage::Idle;
    }
}

/// 账户路径：EVM 的账户号在最后一段（`m/44'/60'/0'/0/{account}`）。
fn account_path(index: u32) -> Vec<u32> {
    let mut path = DEFAULT_PATH;
    path[4] = index;
    path.to_vec()
}

/// 模块清单。阶段 2 切片 A 只声明已迁移的命令，其余明确标为不支持。
pub fn descriptor() -> AppDescriptor {
    AppDescriptor {
        module_id: "openledger.ethereum".into(),
        module_version: "0.1.0".into(),
        api_version: API_VERSION,
        review_schema_version: 1,
        storage_schema_version: 1,
        protocol_profiles: vec![chain_app_api::ProtocolProfile {
            name: "Ethereum".into(),
            version: "1.10.3".into(),
            wire: Wire::LedgerApdu,
            supported: vec![
                "E0 02 GET_PUBLIC_KEY".into(),
                "E0 04 SIGN_ETH_TRANSACTION".into(),
                "E0 08 SIGN_PERSONAL_MESSAGE".into(),
                "E0 0C SIGN_EIP_712 (V0)".into(),
            ],
            unsupported: vec!["E0 0C V1 streaming".into()],
            vector_sources: vec![
                "spec/apdu + tool/e2e/tests/{ble_regression,sign_message,sign_transaction,sign_eip712}.py"
                    .into(),
            ],
        }],
        account_profiles: vec![chain_app_api::AccountProfile {
            network: "Ethereum".into(),
            account_type: "default".into(),
            default_path: "m/44'/60'/0'/0/0".into(),
            derivation_scheme: DerivationScheme::Bip32Secp256k1,
            curve: Curve::Secp256k1,
        }],
        requested_capabilities: CapabilitySet {
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

pub struct EthereumFactory;

impl chain_app_api::ModuleFactory for EthereumFactory {
    fn describe(&self) -> AppDescriptor {
        descriptor()
    }

    fn create(&self) -> Box<dyn ChainApp> {
        Box::new(EthereumModule::new())
    }
}
