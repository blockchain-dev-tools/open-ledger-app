//! 链 App 宿主的 C 句柄导出（阶段 2b）。
//!
//! 只覆盖已经迁移完成的命令：ETH `E0 02 GET_PUBLIC_KEY`。其余 APDU 仍由
//! Dart 的旧实现处理，两边互不影响；适配器在 BLE 分发处按 `CLA/INS` 选择
//! 走哪一边。
//!
//! 设计约束（与 D-016 一致）：
//!
//! - 不跨 FFI 暴露 Rust 内存布局：入参是十六进制字符串，出参是单行 JSON。
//! - seed 只进不出；`chain_host_set_seed` 之后 Rust 侧持有，Dart 无法读回。
//! - 审批与密钥运算都在 Rust 内闭环：`chain_host_resolve` 返回的就是回给
//!   外部钱包的完整响应字节。
//! - APDU 响应经 BLE 同步写出，故 `Emit` 立即记为已投递（`Acknowledged`），
//!   调用方不需要额外的 delivered 回调。

use std::collections::HashMap;
use std::ffi::CStr;
use std::os::raw::c_char;
use std::ptr;
use std::sync::{Arc, Mutex};

use chain_app_api::manifest::{CapabilitySet, DerivationRule, HARDENED};
use chain_app_api::{
    Curve, DeliveryAck, DerivationScheme, EcdhRequest, Field, FieldValue, FinishStatus,
    HostError, KeyOutput, KeyService, LocalCommand, ModuleFactory, OperationKind, OperationState,
    ParseStatus, PublicKey, PublicKeyRequest, ReviewAction, ReviewDocument, RiskLevel, RiskSource,
    SignAuthorization, SignOperation, SignScheme, Signature, StorageScope, StorageService, Wire,
};
use chain_app_runtime::{Budget, ReviewDecision, Runtime, RuntimeReply};

use crate::types::FfiResult;

pub const MODULE_ID: &str = "openledger.ethereum";
pub const BTC_MODULE_ID: &str = "openledger.bitcoin";
pub const SOL_MODULE_ID: &str = "openledger.solana";
pub const TRON_MODULE_ID: &str = "openledger.tron";
pub const SUI_MODULE_ID: &str = "openledger.sui";
pub const NEAR_MODULE_ID: &str = "openledger.near";
pub const TON_MODULE_ID: &str = "openledger.ton";

// ── 宿主服务实现 ──────────────────────────────────────────────────────

/// 密钥服务：seed 只在 Rust 侧保存，派生按 BIP-32 进行。
struct HostKeyService {
    seed: Mutex<Option<Vec<u8>>>,
}

impl HostKeyService {
    fn new() -> Self {
        Self {
            seed: Mutex::new(None),
        }
    }

    fn set_seed(&self, seed: Vec<u8>) {
        let mut guard = self.seed.lock().unwrap_or_else(|e| e.into_inner());
        guard.replace(seed);
    }

    fn clear(&self) {
        let mut guard = self.seed.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(mut seed) = guard.take() {
            seed.iter_mut().for_each(|b| *b = 0);
        }
    }

    fn locked(&self) -> bool {
        self.seed
            .lock()
            .map(|guard| guard.is_none())
            .unwrap_or(true)
    }
}

impl KeyService for HostKeyService {
    fn public_key(&self, request: &PublicKeyRequest) -> Result<PublicKey, HostError> {
        if !request.curve.matches(request.derivation_scheme) {
            return Err(HostError::Denied("scheme/curve mismatch".into()));
        }
        if !matches!(
            request.output,
            KeyOutput::UncompressedSecp256k1
                | KeyOutput::CompressedSecp256k1
                | KeyOutput::Ed25519
        ) {
            return Err(HostError::Denied("unsupported key output".into()));
        }
        let seed = self.seed()?;
        let path = format_path(&request.path);
        match (request.derivation_scheme, request.curve) {
            (DerivationScheme::Bip32Secp256k1, Curve::Secp256k1) => {
                if request.output == KeyOutput::Ed25519 {
                    return Err(HostError::Denied("ed25519 output needs slip-10".into()));
                }
                let (private_key, chain_code) =
                    open_ledger_biz::hdkey::derive_secp256k1_extended(&seed, &path)
                        .map_err(|e| HostError::Unavailable(e.to_string()))?;
                let compressed = request.output == KeyOutput::CompressedSecp256k1;
                let bytes =
                    open_ledger_crypto::secp256k1::public_key_bytes(&private_key, compressed)
                        .map_err(|e| HostError::Unavailable(e.to_string()))?;
                Ok(PublicKey {
                    bytes,
                    chain_code: if request.include_chain_code {
                        Some(chain_code.to_vec())
                    } else {
                        None
                    },
                })
            }
            (DerivationScheme::Slip10Ed25519, Curve::Ed25519) => {
                if request.output != KeyOutput::Ed25519 || request.include_chain_code {
                    return Err(HostError::Denied("ed25519 has no chain code".into()));
                }
                let private_key =
                    open_ledger_biz::hdkey::derive_ed25519_private_key(&seed, &path)
                        .map_err(|e| HostError::Unavailable(e.to_string()))?;
                let private_key = zeroize::Zeroizing::new(private_key);
                let bytes = open_ledger_crypto::ed25519::public_key_bytes(private_key.as_slice())
                    .map_err(|e| HostError::Unavailable(e.to_string()))?;
                Ok(PublicKey {
                    bytes,
                    chain_code: None,
                })
            }
            _ => Err(HostError::Denied("unsupported derivation scheme".into())),
        }
    }

    fn sign(
        &self,
        _auth: &SignAuthorization,
        operation: &SignOperation,
    ) -> Result<Signature, HostError> {
        if !operation.curve.matches(operation.derivation_scheme) {
            return Err(HostError::Denied("scheme/curve mismatch".into()));
        }
        let seed = self.seed()?;
        let path = format_path(&operation.path);
        match operation.scheme {
            SignScheme::EcdsaPrehash { digest_len, .. } => {
                if operation.curve != Curve::Secp256k1 {
                    return Err(HostError::Denied(
                        "signing requires secp256k1/BIP-32".into(),
                    ));
                }
                if usize::from(digest_len) != operation.input.len() || digest_len != 32 {
                    return Err(HostError::Denied(
                        "secp256k1 signing expects a 32-byte digest".into(),
                    ));
                }
                let mut digest = [0u8; 32];
                digest.copy_from_slice(&operation.input);
                let (private_key, _chain_code) =
                    open_ledger_biz::hdkey::derive_secp256k1_extended(&seed, &path)
                        .map_err(|e| HostError::Unavailable(e.to_string()))?;
                let private_key = zeroize::Zeroizing::new(private_key);
                // v 位由模块按协议拼装（legacy 27/28、EIP-155 链 ID、typed tx 0/1），
                // 密钥服务只回原始 recovery id 与 r||s。
                let signature = open_ledger_crypto::secp256k1::sign_prehash_recoverable(
                    private_key.as_slice(),
                    &digest,
                    |recovery_bit| recovery_bit,
                )
                .map_err(|e| HostError::Unavailable(e.to_string()))?;
                Ok(Signature {
                    operation_id: operation.operation_id,
                    bytes: signature[1..65].to_vec(),
                    recovery_id: Some(signature[0]),
                })
            }
            SignScheme::SchnorrTaprootKeyPath { hash_type } => {
                if operation.curve != Curve::Secp256k1 {
                    return Err(HostError::Denied(
                        "taproot signing requires secp256k1/BIP-32".into(),
                    ));
                }
                if operation.input.len() != 32 {
                    return Err(HostError::Denied(
                        "taproot signing expects a 32-byte sighash".into(),
                    ));
                }
                let (private_key, _chain_code) =
                    open_ledger_biz::hdkey::derive_secp256k1_extended(&seed, &path)
                        .map_err(|e| HostError::Unavailable(e.to_string()))?;
                let private_key = zeroize::Zeroizing::new(private_key);
                // BIP-341：hash_type 非默认值时必须把 1 字节 hash_type 拼在 sighash 后面。
                let mut message = operation.input.clone();
                if hash_type != 0 {
                    message.push(hash_type);
                }
                let bytes = open_ledger_crypto::secp256k1::schnorr_sign_taproot(
                    private_key.as_slice(),
                    &message,
                )
                .map_err(|e| HostError::Unavailable(e.to_string()))?;
                Ok(Signature {
                    operation_id: operation.operation_id,
                    bytes,
                    recovery_id: None,
                })
            }
            SignScheme::Ed25519Message => {
                if operation.curve != Curve::Ed25519 {
                    return Err(HostError::Denied("ed25519 scheme requires ed25519".into()));
                }
                let private_key =
                    open_ledger_biz::hdkey::derive_ed25519_private_key(&seed, &path)
                        .map_err(|e| HostError::Unavailable(e.to_string()))?;
                let private_key = zeroize::Zeroizing::new(private_key);
                let bytes = open_ledger_crypto::ed25519::sign(
                    private_key.as_slice(),
                    &operation.input,
                )
                .map_err(|e| HostError::Unavailable(e.to_string()))?;
                Ok(Signature {
                    operation_id: operation.operation_id,
                    bytes,
                    recovery_id: None,
                })
            }
        }
    }

    fn ecdh(&self, request: &EcdhRequest) -> Result<Vec<u8>, HostError> {
        if !request.curve.matches(request.derivation_scheme)
            || request.curve != Curve::Secp256k1
        {
            return Err(HostError::Denied("ecdh requires secp256k1/BIP-32".into()));
        }
        let seed = self.seed()?;
        let path = format_path(&request.path);
        let (private_key, _chain_code) =
            open_ledger_biz::hdkey::derive_secp256k1_extended(&seed, &path)
                .map_err(|e| HostError::Unavailable(e.to_string()))?;
        let private_key = zeroize::Zeroizing::new(private_key);
        open_ledger_crypto::secp256k1::ecdh_shared_point(
            private_key.as_slice(),
            &request.peer_public_key,
        )
        .map_err(|e| HostError::Unavailable(e.to_string()))
    }
}

impl HostKeyService {
    /// 复制一份 seed；锁定时返回 `Unavailable`。
    fn seed(&self) -> Result<Vec<u8>, HostError> {
        let guard = self.seed.lock().unwrap_or_else(|e| e.into_inner());
        guard
            .clone()
            .ok_or_else(|| HostError::Unavailable("wallet locked".into()))
    }
}

/// 阶段 2b 的模块没有存储能力（`allow_storage: false`），被调用即视为缺陷。
struct NoStorage;

impl StorageService for NoStorage {
    fn read(&mut self, _scope: &StorageScope, _key: &str) -> Result<Option<Vec<u8>>, HostError> {
        Err(HostError::Storage("storage not provided".into()))
    }

    fn write(
        &mut self,
        _scope: &StorageScope,
        _key: &str,
        _value: Vec<u8>,
    ) -> Result<(), HostError> {
        Err(HostError::Storage("storage not provided".into()))
    }

    fn delete(&mut self, _scope: &StorageScope, _key: &str) -> Result<(), HostError> {
        Err(HostError::Storage("storage not provided".into()))
    }
}

// ── 句柄 ──────────────────────────────────────────────────────────────

pub struct ChainHost {
    runtime: Runtime,
    keys: Arc<HostKeyService>,
    sessions: HashMap<String, chain_app_api::SessionId>,
    active: Option<String>,
}

impl ChainHost {
    fn new() -> Result<Self, String> {
        Self::assemble(vec![
            Arc::new(chain_app_ethereum::EthereumFactory) as Arc<dyn ModuleFactory>,
            Arc::new(chain_app_bitcoin::BitcoinFactory),
            Arc::new(chain_app_solana::SolanaFactory),
            Arc::new(chain_app_tron::TronFactory),
            Arc::new(chain_app_sui::SuiFactory),
            Arc::new(chain_app_near::NearFactory),
            Arc::new(chain_app_ton::TonFactory),
        ])
    }

    fn assemble(factories: Vec<Arc<dyn ModuleFactory>>) -> Result<Self, String> {
        let keys = Arc::new(HostKeyService::new());
        let key_service: Arc<dyn KeyService> = keys.clone();
        let mut runtime = Runtime::new("default", Budget::default(), key_service, Box::new(NoStorage));
        for factory in factories {
            runtime
                .register_module(factory, &host_policy())
                .map_err(|e| e.to_string())?;
        }
        let mut host = Self {
            runtime,
            keys,
            sessions: HashMap::new(),
            active: None,
        };
        host.open(MODULE_ID)?;
        Ok(host)
    }

    /// 切换到指定模块；同一时刻只保留一个活动 App（模拟 QUIT_APP）。
    fn open(&mut self, module_id: &str) -> Result<(), String> {
        if let Some(previous) = self.active.take() {
            if let Some(session) = self.sessions.remove(&previous) {
                self.runtime
                    .close(session, chain_app_api::CancelReason::HostShutdown);
            }
        }
        let (session, _) = self
            .runtime
            .open_app(module_id)
            .map_err(|e| e.to_string())?;
        self.sessions.insert(module_id.to_string(), session);
        self.active = Some(module_id.to_string());
        Ok(())
    }

    fn reopen(&mut self) -> Result<(), String> {
        let module = self
            .active
            .clone()
            .unwrap_or_else(|| MODULE_ID.to_string());
        self.open(&module)
    }

    fn session(&self) -> Result<chain_app_api::SessionId, String> {
        self.active
            .as_ref()
            .and_then(|module| self.sessions.get(module).copied())
            .ok_or_else(|| "no open app".to_string())
    }

    /// 把 `RuntimeReply` 渲染成单行 JSON，并为 `Emit` 完成投递确认。
    ///
    /// APDU 的写出发送方是同步的，所以这里直接记 `Acknowledged`。投递之后
    /// Runtime 会把本次操作视为完成，下一次请求需要新的模块会话。
    fn complete(&mut self, reply: RuntimeReply) -> Result<String, String> {
        let rendered = render_reply(&reply);
        if let RuntimeReply::Emit {
            exchange_id,
            state,
            ..
        } = reply
        {
            let session = self.session()?;
            let _ = self
                .runtime
                .delivery_result(session, exchange_id, DeliveryAck::Acknowledged);
            // 多块收集时模块还在等下一帧，会话必须保留；只有 Final 才收尾。
            if state == OperationState::Final {
                self.reopen()?;
            }
        }
        Ok(rendered)
    }
}

/// 只用「编码后的模块」装配宿主：真实 APDU 会完整走一遍 Event/Effect 的字节。
///
/// 测试专用；换成动态库或 WASM 载体时，替换的就是这里的装配方式。
#[cfg(test)]
impl ChainHost {
    fn new_encoded() -> Result<Self, String> {
        use chain_app_api::wire::EncodedFactory;
        Self::assemble(vec![
            Arc::new(EncodedFactory::new(chain_app_ethereum::EthereumFactory))
                as Arc<dyn ModuleFactory>,
            Arc::new(EncodedFactory::new(chain_app_bitcoin::BitcoinFactory)),
            Arc::new(EncodedFactory::new(chain_app_solana::SolanaFactory)),
            Arc::new(EncodedFactory::new(chain_app_tron::TronFactory)),
            Arc::new(EncodedFactory::new(chain_app_sui::SuiFactory)),
            Arc::new(EncodedFactory::new(chain_app_near::NearFactory)),
            Arc::new(EncodedFactory::new(chain_app_ton::TonFactory)),
        ])
    }
}

fn host_policy() -> CapabilitySet {
    CapabilitySet {
        derivation_rules: vec![
            // ETH / BTC / Tron：`m/44|84'/coin'/0'/0/index`。
            DerivationRule {
                derivation_scheme: DerivationScheme::Bip32Secp256k1,
                curve: Curve::Secp256k1,
                depth: 5,
                hardened_positions: vec![0, 1, 2],
                max_index: 1000,
            },
            // BTC 官方协议：`E1 05` 需要主密钥（depth 0），`E1 00` 需要账户级
            // （depth 3）与父级（depth 2，用于父指纹）。
            DerivationRule {
                derivation_scheme: DerivationScheme::Bip32Secp256k1,
                curve: Curve::Secp256k1,
                depth: 0,
                hardened_positions: vec![],
                max_index: 0,
            },
            DerivationRule {
                derivation_scheme: DerivationScheme::Bip32Secp256k1,
                curve: Curve::Secp256k1,
                depth: 2,
                hardened_positions: vec![0, 1],
                max_index: 1000,
            },
            DerivationRule {
                derivation_scheme: DerivationScheme::Bip32Secp256k1,
                curve: Curve::Secp256k1,
                depth: 3,
                hardened_positions: vec![0, 1, 2],
                max_index: 1000,
            },
            // Solana：`m/44'/501'/{account}'/0'`（全硬化，4 段）。
            DerivationRule {
                derivation_scheme: DerivationScheme::Slip10Ed25519,
                curve: Curve::Ed25519,
                depth: 4,
                hardened_positions: vec![0, 1, 2, 3],
                max_index: 1000,
            },
            // Sui：`m/44'/784'/{account}'/0'/0'`；NEAR：`m/44'/397'/{account}'/0'/1'`
            //（都是全硬化，5 段）。
            DerivationRule {
                derivation_scheme: DerivationScheme::Slip10Ed25519,
                curve: Curve::Ed25519,
                depth: 5,
                hardened_positions: vec![0, 1, 2, 3, 4],
                max_index: 1000,
            },
            // TON 账户：`m/44'/607'/0'/0'/{account}'/0'`（全硬化，6 段）。
            DerivationRule {
                derivation_scheme: DerivationScheme::Slip10Ed25519,
                curve: Curve::Ed25519,
                depth: 6,
                hardened_positions: vec![0, 1, 2, 3, 4, 5],
                max_index: 1000,
            },
            // TON host 的其它合法路径：官方 app 只要求 `m/44'/607'/` 起头、至少 3 段。
            DerivationRule {
                derivation_scheme: DerivationScheme::Slip10Ed25519,
                curve: Curve::Ed25519,
                depth: 3,
                hardened_positions: vec![0, 1, 2],
                max_index: 1000,
            },
        ],
        allow_chain_code: true,
        allow_signing: true,
        allow_storage: false,
    }
}

// ── 渲染 ──────────────────────────────────────────────────────────────

fn render_reply(reply: &RuntimeReply) -> String {
    match reply {
        RuntimeReply::Emit {
            exchange_id,
            payload,
            ..
        } => format!(
            "{{\"kind\":\"emit\",\"exchange\":{exchange_id},\"payload\":\"{}\"}}",
            hex::encode(payload)
        ),
        RuntimeReply::Review {
            review_id,
            document,
            action,
        } => render_review(*review_id, document, action),
        RuntimeReply::Finished { status } => format!(
            "{{\"kind\":\"finished\",\"status\":\"{}\"}}",
            finish_status(*status)
        ),
        RuntimeReply::LocalReply { request_id, payload } => format!(
            "{{\"kind\":\"local\",\"request_id\":{request_id},\"payload\":\"{}\"}}",
            hex::encode(payload)
        ),
        RuntimeReply::AwaitInput => "{\"kind\":\"await_input\"}".to_string(),
    }
}

fn finish_status(status: FinishStatus) -> &'static str {
    match status {
        FinishStatus::Delivered => "delivered",
        FinishStatus::Rejected => "rejected",
        FinishStatus::Cancelled => "cancelled",
        FinishStatus::Failed => "failed",
    }
}

fn render_review(review_id: u64, document: &ReviewDocument, action: &ReviewAction) -> String {
    let action_json = match action {
        ReviewAction::DisplayAddress { path, .. } => format!(
            "{{\"type\":\"display_address\",\"path\":\"{}\"}}",
            json_escape(&format_path(path))
        ),
        ReviewAction::ChangeSetting { key, .. } => format!(
            "{{\"type\":\"change_setting\",\"key\":\"{}\"}}",
            json_escape(key)
        ),
        ReviewAction::Sign(plan) => {
            let operations: Vec<String> = plan
                .operations
                .iter()
                .map(|operation| {
                    let parameters: Vec<String> = operation
                        .public_parameters
                        .iter()
                        .map(|(key, value)| {
                            format!("\"{}\":\"{}\"", json_escape(key), hex::encode(value))
                        })
                        .collect();
                    format!(
                        "{{\"operation_id\":{},\"public_parameters\":{{{}}}}}",
                        operation.operation_id,
                        parameters.join(",")
                    )
                })
                .collect();
            format!(
                "{{\"type\":\"sign\",\"operations\":[{}]}}",
                operations.join(",")
            )
        }
    };
    let sections: Vec<String> = document
        .sections
        .iter()
        .map(|section| {
            let fields: Vec<String> = section.fields.iter().map(render_field).collect();
            format!(
                "{{\"title_key\":\"{}\",\"fields\":[{}]}}",
                json_escape(&section.title_key),
                fields.join(",")
            )
        })
        .collect();
    let risks: Vec<String> = document
        .risks
        .iter()
        .map(|risk| {
            format!(
                "{{\"code\":\"{}\",\"severity\":\"{}\",\"source\":\"{}\"}}",
                json_escape(&risk.code),
                risk_level(risk.severity),
                risk_source(&risk.source)
            )
        })
        .collect();
    format!(
        "{{\"kind\":\"review\",\"review_id\":{review_id},\"action\":{action_json},\
         \"document\":{{\"operation\":\"{}\",\"network\":{{\"name\":\"{}\",\"chain_id\":{}}},\
         \"account\":{},\"parse_status\":\"{}\",\"sections\":[{}],\"risks\":[{}]}}}}",
        operation_kind(document.operation),
        json_escape(&document.network.name),
        document
            .network
            .chain_id
            .map(|id| id.to_string())
            .unwrap_or_else(|| "null".to_string()),
        document
            .account
            .as_ref()
            .map(|a| format!("\"{}\"", json_escape(a)))
            .unwrap_or_else(|| "null".to_string()),
        parse_status(document.parse_status),
        sections.join(","),
        risks.join(",")
    )
}

fn render_field(field: &Field) -> String {
    format!(
        "{{\"label_key\":\"{}\",\"value\":{}}}",
        json_escape(&field.label_key),
        render_value(&field.value)
    )
}

fn render_value(value: &FieldValue) -> String {
    match value {
        FieldValue::Address {
            value,
            network,
            role,
        } => format!(
            "{{\"type\":\"address\",\"value\":\"{}\",\"network\":\"{}\",\"role\":\"{}\"}}",
            json_escape(value),
            json_escape(network),
            json_escape(role)
        ),
        FieldValue::Amount {
            raw,
            decimals,
            asset,
            ticker,
        } => format!(
            "{{\"type\":\"amount\",\"raw\":\"{}\",\"decimals\":{decimals},\"asset\":\"{}\",\"ticker\":{}}}",
            json_escape(raw),
            json_escape(asset),
            ticker
                .as_ref()
                .map(|t| format!("\"{}\"", json_escape(t)))
                .unwrap_or_else(|| "null".to_string())
        ),
        FieldValue::Fee {
            kind,
            raw,
            decimals,
            asset,
        } => format!(
            "{{\"type\":\"fee\",\"kind\":\"{}\",\"raw\":{},\"decimals\":{decimals},\"asset\":\"{}\"}}",
            fee_kind(*kind),
            raw.as_ref()
                .map(|r| format!("\"{}\"", json_escape(r)))
                .unwrap_or_else(|| "null".to_string()),
            json_escape(asset)
        ),
        FieldValue::Text { value } => format!(
            "{{\"type\":\"text\",\"value\":\"{}\"}}",
            json_escape(value)
        ),
        FieldValue::Bytes { value } => format!(
            "{{\"type\":\"bytes\",\"value\":\"{}\"}}",
            hex::encode(value)
        ),
        FieldValue::Structured { entries } => {
            let inner: Vec<String> = entries.iter().map(render_field).collect();
            format!("{{\"type\":\"structured\",\"entries\":[{}]}}", inner.join(","))
        }
        FieldValue::Boolean(flag) => format!("{{\"type\":\"boolean\",\"value\":{flag}}}"),
    }
}

fn operation_kind(kind: OperationKind) -> &'static str {
    match kind {
        OperationKind::Transaction => "transaction",
        OperationKind::Message => "message",
        OperationKind::AddressConfirmation => "address_confirmation",
        OperationKind::SettingsChange => "settings_change",
    }
}

fn parse_status(status: ParseStatus) -> &'static str {
    match status {
        ParseStatus::Complete => "complete",
        ParseStatus::Partial => "partial",
        ParseStatus::Opaque => "opaque",
    }
}

fn risk_level(level: RiskLevel) -> &'static str {
    match level {
        RiskLevel::Info => "info",
        RiskLevel::Warning => "warning",
        RiskLevel::Critical => "critical",
    }
}

fn risk_source(source: &RiskSource) -> String {
    match source {
        RiskSource::Module => "module".to_string(),
        RiskSource::Host => "host".to_string(),
        RiskSource::External { provider, verified } => format!(
            "external:{}:{}",
            json_escape(provider),
            if *verified { "verified" } else { "unverified" }
        ),
    }
}

fn fee_kind(kind: chain_app_api::FeeKind) -> &'static str {
    match kind {
        chain_app_api::FeeKind::Known => "known",
        chain_app_api::FeeKind::UpperBound => "upper_bound",
        chain_app_api::FeeKind::Estimated => "estimated",
        chain_app_api::FeeKind::Unknown => "unknown",
    }
}

fn json_escape(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for c in input.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out
}

/// `[44', 60', 0', 0, 0]` → `m/44'/60'/0'/0/0`。
fn format_path(path: &[u32]) -> String {
    let mut out = String::from("m");
    for component in path {
        if *component >= HARDENED {
            out.push_str(&format!("/{}'", component - HARDENED));
        } else {
            out.push_str(&format!("/{component}"));
        }
    }
    out
}

// ── C 导出 ────────────────────────────────────────────────────────────

fn null_err() -> *mut FfiResult {
    FfiResult::err(99, "null pointer".into()).into_ptr()
}

unsafe fn host_mut<'a>(host: *mut ChainHost) -> Option<&'a mut ChainHost> {
    host.as_mut()
}

/// 创建宿主并打开 ETH 模块会话。返回不透明句柄，失败时为 null。
#[no_mangle]
pub extern "C" fn chain_host_new() -> *mut ChainHost {
    match ChainHost::new() {
        Ok(host) => Box::into_raw(Box::new(host)),
        Err(_) => ptr::null_mut(),
    }
}

/// 释放宿主句柄并清零 seed。
///
/// # Safety
/// `host` 必须来自 [`chain_host_new`]，且此后不再被使用。
#[no_mangle]
pub unsafe extern "C" fn chain_host_free(host: *mut ChainHost) {
    if !host.is_null() {
        let host = Box::from_raw(host);
        host.keys.clear();
    }
}

/// 设置 seed（64 字节的十六进制）。空字符串表示锁定并清空 seed。
///
/// # Safety
/// `host` 必须来自 [`chain_host_new`]；`seed_hex` 必须是以 NUL 结尾的字符串或 null。
#[no_mangle]
pub unsafe extern "C" fn chain_host_set_seed(
    host: *mut ChainHost,
    seed_hex: *const c_char,
) -> *mut FfiResult {
    let host = match host_mut(host) {
        Some(host) => host,
        None => return null_err(),
    };
    let text = if seed_hex.is_null() {
        ""
    } else {
        match CStr::from_ptr(seed_hex).to_str() {
            Ok(text) => text,
            Err(_) => return FfiResult::err(1, "seed is not valid utf-8".into()).into_ptr(),
        }
    };
    if text.is_empty() {
        host.keys.clear();
        host.runtime.lock();
        if let Err(error) = host.reopen() {
            return FfiResult::err(2, error).into_ptr();
        }
        return FfiResult::ok("{\"kind\":\"locked\"}".into()).into_ptr();
    }
    let seed = match hex::decode(text) {
        Ok(seed) => seed,
        Err(_) => return FfiResult::err(1, "seed is not valid hex".into()).into_ptr(),
    };
    if seed.len() != 64 {
        return FfiResult::err(1, "seed must be 64 bytes".into()).into_ptr();
    }
    let was_locked = host.keys.locked();
    host.keys.set_seed(seed);
    if was_locked {
        // 锁定期间旧 epoch 的授权全部作废，重新打开会话。
        host.runtime.lock();
        if let Err(error) = host.reopen() {
            return FfiResult::err(2, error).into_ptr();
        }
    }
    FfiResult::ok("{\"kind\":\"seed_set\"}".into()).into_ptr()
}

/// 提交一帧完整 APDU（十六进制）。返回 JSON：`emit` / `review` / 其他。
///
/// # Safety
/// `host` 必须来自 [`chain_host_new`]；`apdu_hex` 必须是以 NUL 结尾的字符串或 null。
#[no_mangle]
pub unsafe extern "C" fn chain_host_submit(
    host: *mut ChainHost,
    apdu_hex: *const c_char,
) -> *mut FfiResult {
    let host = match host_mut(host) {
        Some(host) => host,
        None => return null_err(),
    };
    let apdu = if apdu_hex.is_null() {
        return FfiResult::err(1, "null apdu".into()).into_ptr();
    } else {
        match CStr::from_ptr(apdu_hex).to_str().map(hex::decode) {
            Ok(Ok(apdu)) => apdu,
            _ => return FfiResult::err(1, "apdu is not valid hex".into()).into_ptr(),
        }
    };
    let session = match host.session() {
        Ok(session) => session,
        Err(error) => return FfiResult::err(2, error).into_ptr(),
    };
    match host
        .runtime
        .submit_wire(session, Wire::LedgerApdu, apdu)
    {
        Ok(reply) => match host.complete(reply) {
            Ok(json) => FfiResult::ok(json).into_ptr(),
            Err(error) => FfiResult::err(2, error).into_ptr(),
        },
        Err(error) => FfiResult::err(3, error.to_string()).into_ptr(),
    }
}

/// 审批结果：`approved != 0` 为批准。返回与 `chain_host_submit` 同构的 JSON。
///
/// # Safety
/// `host` 必须来自 [`chain_host_new`]，且仍指向同一个宿主。
#[no_mangle]
pub unsafe extern "C" fn chain_host_resolve(
    host: *mut ChainHost,
    review_id: u64,
    approved: u8,
) -> *mut FfiResult {
    let host = match host_mut(host) {
        Some(host) => host,
        None => return null_err(),
    };
    let session = match host.session() {
        Ok(session) => session,
        Err(error) => return FfiResult::err(2, error).into_ptr(),
    };
    let decision = if approved != 0 {
        ReviewDecision::Approve
    } else {
        ReviewDecision::Reject
    };
    match host.runtime.resolve_review(session, review_id, decision) {
        Ok(reply) => match host.complete(reply) {
            Ok(json) => FfiResult::ok(json).into_ptr(),
            Err(error) => FfiResult::err(2, error).into_ptr(),
        },
        Err(error) => FfiResult::err(3, error.to_string()).into_ptr(),
    }
}

/// 显式重新打开模块会话（`OPEN_APP`）。返回 `{"kind":"opened"}`。
///
/// 切换到指定模块（`module_id` 为 null/空时重开当前 App）。
///
/// # Safety
/// `host` 必须来自 [`chain_host_new`]；`module_id` 必须是以 NUL 结尾的字符串或 null。
#[no_mangle]
pub unsafe extern "C" fn chain_host_open_app(
    host: *mut ChainHost,
    module_id: *const c_char,
) -> *mut FfiResult {
    let host = match host_mut(host) {
        Some(host) => host,
        None => return null_err(),
    };
    let requested = if module_id.is_null() {
        None
    } else {
        match CStr::from_ptr(module_id).to_str() {
            Ok(text) if !text.is_empty() => Some(text.to_string()),
            Ok(_) => None,
            Err(_) => return FfiResult::err(1, "module id is not valid utf-8".into()).into_ptr(),
        }
    };
    let opened = match requested {
        Some(module) => host.open(&module),
        None => host.reopen(),
    };
    match opened {
        Ok(()) => FfiResult::ok("{\"kind\":\"opened\"}".into()).into_ptr(),
        Err(error) => FfiResult::err(2, error).into_ptr(),
    }
}

/// 本机账户派生（`LocalCommand::DeriveAccount`）。返回
/// `{"kind":"local","payload":"<hex>"}`，payload 是
/// `{"address":"…","public_key":"<hex>"}` 的 UTF-8 JSON；模块拒绝时 payload 为空。
///
/// # Safety
/// `host` 必须来自 [`chain_host_new`]；`module_id` 必须以 NUL 结尾。
#[no_mangle]
pub unsafe extern "C" fn chain_host_derive_account(
    host: *mut ChainHost,
    module_id: *const c_char,
    account_profile_index: u32,
    address_index: u32,
) -> *mut FfiResult {
    let host = match host_mut(host) {
        Some(host) => host,
        None => return null_err(),
    };
    if host.runtime.pending_reviews() > 0 {
        return FfiResult::err(4, "a review is pending".into()).into_ptr();
    }
    let requested = if module_id.is_null() {
        return FfiResult::err(1, "null module id".into()).into_ptr();
    } else {
        match CStr::from_ptr(module_id).to_str() {
            Ok(text) if !text.is_empty() => text.to_string(),
            Ok(_) => return FfiResult::err(1, "empty module id".into()).into_ptr(),
            Err(_) => return FfiResult::err(1, "module id is not valid utf-8".into()).into_ptr(),
        }
    };
    if let Err(error) = host.open(&requested) {
        return FfiResult::err(2, error).into_ptr();
    }
    let session = match host.session() {
        Ok(session) => session,
        Err(error) => return FfiResult::err(2, error).into_ptr(),
    };
    let command = LocalCommand::DeriveAccount {
        account_profile_index: account_profile_index as u16,
        address_index,
    };
    match host.runtime.submit_local(session, 1, command) {
        Ok(reply) => match host.complete(reply) {
            Ok(json) => FfiResult::ok(json).into_ptr(),
            Err(error) => FfiResult::err(2, error).into_ptr(),
        },
        Err(error) => FfiResult::err(3, error.to_string()).into_ptr(),
    }
}

/// 锁定：清空 seed 并作废所有待批准请求。
///
/// # Safety
/// `host` 必须来自 [`chain_host_new`]，且仍指向同一个宿主。
#[no_mangle]
pub unsafe extern "C" fn chain_host_lock(host: *mut ChainHost) -> *mut FfiResult {
    let host = match host_mut(host) {
        Some(host) => host,
        None => return null_err(),
    };
    host.keys.clear();
    host.runtime.lock();
    if let Err(error) = host.reopen() {
        return FfiResult::err(2, error).into_ptr();
    }
    FfiResult::ok("{\"kind\":\"locked\"}".into()).into_ptr()
}

#[cfg(test)]
mod tests {
    use std::ffi::CString;

    use super::*;

    const MNEMONIC: &str = "abandon abandon abandon abandon abandon abandon \
                            abandon abandon abandon abandon abandon about";
    /// 协议响应里的地址是 40 字符 ASCII，不带 `0x`（与官方 app-ethereum 一致）。
    const EXPECTED_ADDRESS: &str = "9858EfFD232B4033E47d90003D41EC34EcaEda94";

    fn seed_hex() -> String {
        hex::encode(open_ledger_crypto::bip39::mnemonic_to_seed(MNEMONIC, "").unwrap())
    }

    /// 与真机基线一致的 GET_PUBLIC_KEY（P1=0x00, 无路径）。
    fn get_public_key() -> Vec<u8> {
        vec![0xE0, 0x02, 0x00, 0x00, 0x00]
    }

    fn call(host: *mut ChainHost, apdu: &[u8]) -> String {
        let hex_apdu = CString::new(hex::encode(apdu)).unwrap();
        unsafe {
            let result = chain_host_submit(host, hex_apdu.as_ptr());
            assert!(!result.is_null());
            let result_ref = &*result;
            assert_eq!(result_ref.error_code, 0, "{}", error_msg(result_ref));
            let data = CStr::from_ptr(result_ref.data).to_str().unwrap().to_string();
            crate::types::free_ffi_result(result);
            data
        }
    }

    fn error_msg(result: &FfiResult) -> String {
        if result.error_msg.is_null() {
            return String::new();
        }
        unsafe { CStr::from_ptr(result.error_msg).to_string_lossy().into_owned() }
    }

    fn set_seed(host: *mut ChainHost, seed: &str) {
        let text = CString::new(seed).unwrap();
        unsafe {
            let result = chain_host_set_seed(host, text.as_ptr());
            let result_ref = &*result;
            assert_eq!(result_ref.error_code, 0, "{}", error_msg(result_ref));
            crate::types::free_ffi_result(result);
        }
    }

    fn emit_payload(json: &str) -> Vec<u8> {
        let marker = "\"payload\":\"";
        let start = json.find(marker).expect("emit payload") + marker.len();
        let rest = &json[start..];
        let end = rest.find('"').expect("payload end");
        hex::decode(&rest[..end]).unwrap()
    }

    #[test]
    fn returns_the_same_address_as_the_device_baseline() {
        let host = chain_host_new();
        assert!(!host.is_null());
        set_seed(host, &seed_hex());

        let json = call(host, &get_public_key());
        assert!(json.starts_with("{\"kind\":\"emit\""), "{json}");
        let payload = emit_payload(&json);
        // 0x41 | 65B 公钥 | 长度 | ASCII 地址 | 90 00
        assert_eq!(payload[0], 0x41);
        let address_len = payload[66] as usize;
        let address = std::str::from_utf8(&payload[67..67 + address_len]).unwrap();
        assert_eq!(address, EXPECTED_ADDRESS);
        assert_eq!(&payload[payload.len() - 2..], &[0x90, 0x00]);

        unsafe { chain_host_free(host) };
    }

    #[test]
    fn locked_host_answers_security_status_instead_of_a_key() {
        let host = chain_host_new();
        assert!(!host.is_null());

        let json = call(host, &get_public_key());
        let payload = emit_payload(&json);
        assert_eq!(payload, vec![0x6F, 0x00]);

        unsafe { chain_host_free(host) };
    }

    #[test]
    fn confirmation_parks_a_review_and_rejection_returns_user_denied() {
        let host = chain_host_new();
        set_seed(host, &seed_hex());

        // P1=0x01 → 需要用户确认，宿主收到 review。
        let json = call(host, &[0xE0, 0x02, 0x01, 0x00, 0x00]);
        assert!(json.contains("\"kind\":\"review\""), "{json}");
        assert!(json.contains(EXPECTED_ADDRESS), "{json}");
        let review_id = json
            .split("\"review_id\":")
            .nth(1)
            .and_then(|rest| rest.split(',').next())
            .and_then(|id| id.parse::<u64>().ok())
            .expect("review id");

        unsafe {
            let result = chain_host_resolve(host, review_id, 0);
            let result_ref = &*result;
            assert_eq!(result_ref.error_code, 0, "{}", error_msg(result_ref));
            let data = CStr::from_ptr(result_ref.data).to_str().unwrap().to_string();
            crate::types::free_ffi_result(result);
            assert_eq!(emit_payload(&data), vec![0x69, 0x85]);
            chain_host_free(host);
        }
    }

    #[test]
    fn unknown_ins_is_rejected_by_the_module_not_by_the_adapter() {
        let host = chain_host_new();
        set_seed(host, &seed_hex());

        let json = call(host, &[0xE0, 0x0F, 0x00, 0x00, 0x00]);
        assert_eq!(emit_payload(&json), vec![0x6D, 0x00]);

        unsafe { chain_host_free(host) };
    }

    #[test]
    fn chain_code_is_only_appended_for_p2_one() {
        let host = chain_host_new();
        set_seed(host, &seed_hex());

        let plain = emit_payload(&call(host, &[0xE0, 0x02, 0x00, 0x00, 0x00]));
        let extended = emit_payload(&call(host, &[0xE0, 0x02, 0x00, 0x01, 0x00]));
        assert_eq!(extended.len(), plain.len() + 32);

        unsafe { chain_host_free(host) };
    }

    #[test]
    fn path_formatting_keeps_hardened_markers() {
        assert_eq!(
            format_path(&[0x8000_002C, 0x8000_003C, 0x8000_0000, 0, 7]),
            "m/44'/60'/0'/0/7"
        );
    }

    #[test]
    fn bitcoin_app_opens_and_returns_a_p2wpkh_address() {
        let host = chain_host_new();
        assert!(!host.is_null());
        set_seed(host, &seed_hex());

        open_module(host, BTC_MODULE_ID);

        let payload = emit_payload(&call(host, &bitcoin_address_request()));
        assert_eq!(&payload[payload.len() - 2..], &[0x90, 0x00]);
        let address = std::str::from_utf8(&payload[..payload.len() - 2]).unwrap();

        let seed = open_ledger_crypto::bip39::mnemonic_to_seed(MNEMONIC, "").unwrap();
        let expected = open_ledger_biz::btc::derive_address(&seed, "m/84'/0'/0'/0/0").unwrap();
        assert_eq!(address, expected);
        assert!(address.starts_with("bc1q"), "{address}");

        unsafe { chain_host_free(host) };
    }

    /// 四种地址格式各走一遍宿主：确保 P2 映射与官方 app 一致。
    #[test]
    fn bitcoin_host_answers_all_four_address_formats() {
        let host = chain_host_new();
        assert!(!host.is_null());
        set_seed(host, &seed_hex());
        open_module(host, BTC_MODULE_ID);
        let seed = hex::decode(seed_hex()).unwrap();

        let cases: [(u8, &str); 4] = [
            (0x00, "m/44'/0'/0'/0/0"),
            (0x01, "m/49'/0'/0'/0/0"),
            (0x02, "m/84'/0'/0'/0/0"),
            (0x04, "m/86'/0'/0'/0/0"),
        ];
        for (p2, path) in cases {
            let mut data = vec![5u8];
            let purpose: u32 = path[2..4].parse().unwrap();
            for component in [0x8000_0000 + purpose, 0x8000_0000, 0x8000_0000, 0, 0] {
                data.extend_from_slice(&component.to_be_bytes());
            }
            let mut request = vec![0xE1, 0x40, 0x00, p2, data.len() as u8];
            request.extend_from_slice(&data);
            let payload = emit_payload(&call(host, &request));
            let address = std::str::from_utf8(&payload[..payload.len() - 2]).unwrap();
            assert_eq!(
                address,
                open_ledger_biz::btc::derive_address(&seed, path).unwrap(),
                "path {path}"
            );
        }

        unsafe { chain_host_free(host) };
    }

    /// 宿主必须自己完成 taproot tweak 与 Schnorr 签名。
    fn default_path() -> Vec<u32> {
        vec![0x8000_002C, 0x8000_003C, 0x8000_0000, 0, 0]
    }

    fn authorization() -> SignAuthorization {
        SignAuthorization {
            review_id: 1,
            epoch: 1,
            vault: "default".into(),
            module_id: MODULE_ID.into(),
            module_version: "0.1.0".into(),
            operation_id: 7,
        }
    }

    fn prehash(digest: [u8; 32]) -> SignOperation {
        SignOperation {
            operation_id: 7,
            derivation_scheme: DerivationScheme::Bip32Secp256k1,
            curve: Curve::Secp256k1,
            path: default_path(),
            scheme: SignScheme::EcdsaPrehash {
                digest_len: 32,
                low_s: true,
            },
            input: digest.to_vec(),
            public_parameters: Vec::new(),
        }
    }

    fn personal_digest(message: &[u8]) -> [u8; 32] {
        let mut payload = Vec::new();
        payload.extend_from_slice(
            format!("\x19Ethereum Signed Message:\n{}", message.len()).as_bytes(),
        );
        payload.extend_from_slice(message);
        open_ledger_crypto::keccak256::hash(&payload)
    }

    #[test]
    fn signing_matches_the_legacy_personal_message_path() {
        let keys = HostKeyService::new();
        keys.set_seed(hex::decode(seed_hex()).unwrap());

        let message = b"Hello Open Ledger App";
        let signature = keys
            .sign(&authorization(), &prehash(personal_digest(message)))
            .unwrap();

        // 密钥服务只回 r||s + recovery id；v 由模块按协议拼。
        assert_eq!(signature.bytes.len(), 64);
        let recovery = signature.recovery_id.expect("recovery id");
        assert!(recovery <= 1);

        // RFC6979 确定性：同一私钥/消息必须与旧 Dart 路径逐字节一致。
        let seed = hex::decode(seed_hex()).unwrap();
        let private_key = open_ledger_biz::hdkey::derive_secp256k1_private_key(
            &seed,
            "m/44'/60'/0'/0/0",
        )
        .unwrap();
        let legacy = open_ledger_biz::eth::sign_personal_message(&private_key, message).unwrap();
        assert_eq!(legacy[0], 27 + recovery);
        assert_eq!(&legacy[1..], &signature.bytes[..]);
    }

    #[test]
    fn signing_is_refused_while_locked() {
        let keys = HostKeyService::new();
        let error = keys
            .sign(&authorization(), &prehash(personal_digest(b"hi")))
            .unwrap_err();
        assert!(matches!(error, HostError::Unavailable(_)), "{error:?}");
    }

    #[test]
    fn signing_rejects_non_sha256_digests_and_other_schemes() {
        let keys = HostKeyService::new();
        keys.set_seed(hex::decode(seed_hex()).unwrap());

        let mut short = prehash([0u8; 32]);
        short.scheme = SignScheme::EcdsaPrehash {
            digest_len: 20,
            low_s: true,
        };
        short.input = vec![0u8; 20];
        assert!(keys.sign(&authorization(), &short).is_err());
    }

    #[test]
    fn ed25519_signing_matches_the_legacy_solana_path() {
        let keys = HostKeyService::new();
        keys.set_seed(hex::decode(seed_hex()).unwrap());

        let path = vec![0x8000_002C, 0x8000_01F5, 0x8000_0000, 0x8000_0000];
        let operation = SignOperation {
            operation_id: 9,
            derivation_scheme: DerivationScheme::Slip10Ed25519,
            curve: Curve::Ed25519,
            path: path.clone(),
            scheme: SignScheme::Ed25519Message,
            input: b"solana message".to_vec(),
            public_parameters: Vec::new(),
        };
        let signature = keys.sign(&authorization(), &operation).unwrap();
        assert_eq!(signature.bytes.len(), 64);
        assert!(signature.recovery_id.is_none());

        let seed = hex::decode(seed_hex()).unwrap();
        let private_key = open_ledger_biz::hdkey::derive_ed25519_private_key(
            &seed,
            "m/44'/501'/0'/0'",
        )
        .unwrap();
        let legacy = open_ledger_biz::solana::sign_message(&private_key, b"solana message").unwrap();
        assert_eq!(signature.bytes, legacy);

        // 独立验签：ed25519-dalek 对同一条消息验证通过。
        let public_key = open_ledger_crypto::ed25519::public_key_bytes(&private_key).unwrap();
        let verifying =
            ed25519_dalek::VerifyingKey::from_bytes(&public_key.try_into().unwrap()).unwrap();
        let sig = ed25519_dalek::Signature::from_slice(&signature.bytes).unwrap();
        verifying.verify_strict(b"solana message", &sig).unwrap();
    }

    fn open_module(host: *mut ChainHost, module: &str) {
        let text = CString::new(module).unwrap();
        unsafe {
            let result = chain_host_open_app(host, text.as_ptr());
            let result_ref = &*result;
            assert_eq!(result_ref.error_code, 0, "{}", error_msg(result_ref));
            crate::types::free_ffi_result(result);
        }
    }

    fn path_with(components: &[u32]) -> Vec<u8> {
        let mut out = vec![components.len() as u8];
        for component in components {
            out.extend_from_slice(&component.to_be_bytes());
        }
        out
    }

    fn solana_path() -> Vec<u8> {
        path_with(&[0x8000_002C, 0x8000_01F5, 0x8000_0000, 0x8000_0000])
    }

    fn sui_path() -> Vec<u8> {
        path_with(&[
            0x8000_002C,
            0x8000_0310,
            0x8000_0000,
            0x8000_0000,
            0x8000_0000,
        ])
    }

    fn tron_path() -> Vec<u8> {
        path_with(&[0x8000_002C, 0x8000_00C3, 0x8000_0000, 0, 0])
    }

    fn apdu(cla: u8, ins: u8, data: &[u8]) -> Vec<u8> {
        let mut out = vec![cla, ins, 0x00, 0x00, data.len() as u8];
        out.extend_from_slice(data);
        out
    }

    #[test]
    fn solana_module_returns_the_bare_pubkey_and_signs_after_approval() {
        let host = chain_host_new();
        assert!(!host.is_null());
        set_seed(host, &seed_hex());
        open_module(host, SOL_MODULE_ID);

        let payload = emit_payload(&call(host, &apdu(0xE0, 0x05, &solana_path())));
        assert_eq!(payload.len(), 34);
        assert_eq!(&payload[32..], &[0x90, 0x00]);

        let seed = hex::decode(seed_hex()).unwrap();
        let private_key =
            open_ledger_biz::hdkey::derive_ed25519_private_key(&seed, "m/44'/501'/0'/0'").unwrap();
        let public_key = open_ledger_crypto::ed25519::public_key_bytes(&private_key).unwrap();
        assert_eq!(&payload[..32], public_key.as_slice());

        // 单块签名：先挂审阅，批准后返回 64 字节签名。
        let message = b"host-level solana message";
        let mut data = solana_path();
        data.extend_from_slice(message);
        let json = call(host, &apdu(0xE0, 0x06, &data));
        assert!(json.contains("\"kind\":\"review\""), "{json}");
        let review_id = json
            .split("\"review_id\":")
            .nth(1)
            .and_then(|rest| rest.split(',').next())
            .and_then(|id| id.parse::<u64>().ok())
            .expect("review id");
        unsafe {
            let result = chain_host_resolve(host, review_id, 1);
            let result_ref = &*result;
            assert_eq!(result_ref.error_code, 0, "{}", error_msg(result_ref));
            let data = CStr::from_ptr(result_ref.data).to_str().unwrap().to_string();
            crate::types::free_ffi_result(result);
            let signature = emit_payload(&data);
            assert_eq!(signature.len(), 66);
            let expected =
                open_ledger_crypto::ed25519::sign(&private_key, message).unwrap();
            assert_eq!(&signature[..64], expected.as_slice());
            chain_host_free(host);
        }
    }

    #[test]
    fn sui_module_returns_the_sui_address() {
        let host = chain_host_new();
        set_seed(host, &seed_hex());
        open_module(host, SUI_MODULE_ID);

        let payload = emit_payload(&call(host, &apdu(0x07, 0x02, &sui_path())));
        assert_eq!(&payload[payload.len() - 2..], &[0x90, 0x00]);
        let address = std::str::from_utf8(&payload[..payload.len() - 2]).unwrap();

        let seed = hex::decode(seed_hex()).unwrap();
        let expected =
            open_ledger_biz::sui::derive_address(&seed, "m/44'/784'/0'/0'/0'").unwrap();
        assert_eq!(address, expected);

        unsafe { chain_host_free(host) };
    }

    #[test]
    fn tron_module_returns_the_address_and_signs_a_hash() {
        let host = chain_host_new();
        set_seed(host, &seed_hex());
        open_module(host, TRON_MODULE_ID);

        let payload = emit_payload(&call(host, &apdu(0xE0, 0x02, &tron_path())));
        assert_eq!(payload[0], 65);
        let addr_len = payload[66] as usize;
        let address = std::str::from_utf8(&payload[67..67 + addr_len]).unwrap();
        let seed = hex::decode(seed_hex()).unwrap();
        let expected =
            open_ledger_biz::tron::derive_address(&seed, "m/44'/195'/0'/0/0").unwrap();
        assert_eq!(address, expected);

        // 0x05：路径 + 32 字节摘要 → 审阅 → 批准 → r||s||v(0/1)。
        let mut data = tron_path();
        data.extend_from_slice(&[0x11u8; 32]);
        let json = call(host, &apdu(0xE0, 0x05, &data));
        assert!(json.contains("\"kind\":\"review\""), "{json}");
        let review_id = json
            .split("\"review_id\":")
            .nth(1)
            .and_then(|rest| rest.split(',').next())
            .and_then(|id| id.parse::<u64>().ok())
            .expect("review id");
        unsafe {
            let result = chain_host_resolve(host, review_id, 1);
            let result_ref = &*result;
            assert_eq!(result_ref.error_code, 0, "{}", error_msg(result_ref));
            let rendered = CStr::from_ptr(result_ref.data).to_str().unwrap().to_string();
            crate::types::free_ffi_result(result);
            let signature = emit_payload(&rendered);
            assert_eq!(signature.len(), 67);
            assert!(signature[64] <= 1);
            assert_eq!(&signature[65..], &[0x90, 0x00]);
        }

        unsafe { chain_host_free(host) };
    }

    /// `chain_host_derive_account` 的英文注释见导出函数。
    fn derive_account(host: *mut ChainHost, module: &str, index: u32) -> String {
        let text = CString::new(module).unwrap();
        let json = unsafe {
            let result = chain_host_derive_account(host, text.as_ptr(), 0, index);
            assert!(!result.is_null());
            let result_ref = &*result;
            assert_eq!(result_ref.error_code, 0, "{}", error_msg(result_ref));
            let data = CStr::from_ptr(result_ref.data).to_str().unwrap().to_string();
            crate::types::free_ffi_result(result);
            data
        };
        let marker = "\"payload\":\"";
        let start = json.find(marker).expect("local payload") + marker.len();
        let end = json[start..].find('"').expect("payload end") + start;
        let payload = hex::decode(&json[start..end]).expect("payload hex");
        let text = String::from_utf8(payload).expect("payload utf-8");
        text.split("\"address\":\"")
            .nth(1)
            .and_then(|rest| rest.split('"').next())
            .expect("address")
            .to_string()
    }

    #[test]
    fn local_account_derivation_matches_every_chain_library() {
        let host = chain_host_new();
        set_seed(host, &seed_hex());
        let seed = hex::decode(seed_hex()).unwrap();

        assert_eq!(
            derive_account(host, MODULE_ID, 0),
            open_ledger_biz::eth::derive_address(&seed, "m/44'/60'/0'/0/0").unwrap()
        );
        assert_eq!(
            derive_account(host, BTC_MODULE_ID, 0),
            open_ledger_biz::btc::derive_address(&seed, "m/84'/0'/0'/0/0").unwrap()
        );
        assert_eq!(
            derive_account(host, SOL_MODULE_ID, 0),
            open_ledger_biz::solana::derive_address(&seed, "m/44'/501'/0'/0'").unwrap()
        );
        assert_eq!(
            derive_account(host, TRON_MODULE_ID, 0),
            open_ledger_biz::tron::derive_address(&seed, "m/44'/195'/0'/0/0").unwrap()
        );
        assert_eq!(
            derive_account(host, SUI_MODULE_ID, 0),
            open_ledger_biz::sui::derive_address(&seed, "m/44'/784'/0'/0'/0'").unwrap()
        );

        // 账户号必须落在各链约定的路径段上。
        assert_eq!(
            derive_account(host, MODULE_ID, 1),
            open_ledger_biz::eth::derive_address(&seed, "m/44'/60'/0'/0/1").unwrap()
        );
        assert_eq!(
            derive_account(host, SOL_MODULE_ID, 1),
            open_ledger_biz::solana::derive_address(&seed, "m/44'/501'/1'/0'").unwrap()
        );
        assert_eq!(
            derive_account(host, SUI_MODULE_ID, 1),
            open_ledger_biz::sui::derive_address(&seed, "m/44'/784'/1'/0'/0'").unwrap()
        );

        unsafe { chain_host_free(host) };
    }

    fn review_id(json: &str) -> u64 {
        json.split("\"review_id\":")
            .nth(1)
            .and_then(|rest| rest.split(',').next())
            .and_then(|id| id.parse::<u64>().ok())
            .expect("review id")
    }

    fn resolve_review(host: *mut ChainHost, review_id: u64, approve: bool) -> String {
        unsafe {
            let result = chain_host_resolve(host, review_id, u8::from(approve));
            assert!(!result.is_null());
            let result_ref = &*result;
            assert_eq!(result_ref.error_code, 0, "{}", error_msg(result_ref));
            let data = CStr::from_ptr(result_ref.data).to_str().unwrap().to_string();
            crate::types::free_ffi_result(result);
            data
        }
    }

    /// `E1 40`，P1=0（不确认地址），P2=2（bech32），data = m/84'/0'/0'/0/0。
    fn bitcoin_address_request() -> Vec<u8> {
        let mut data = vec![5u8];
        for component in [0x8000_0054u32, 0x8000_0000, 0x8000_0000, 0, 0] {
            data.extend_from_slice(&component.to_be_bytes());
        }
        let mut out = vec![0xE1, 0x40, 0x00, 0x02, data.len() as u8];
        out.extend_from_slice(&data);
        out
    }

    fn solana_sign_request() -> Vec<u8> {
        let mut data = solana_path();
        data.extend_from_slice(b"host-level solana message");
        apdu(0xE0, 0x06, &data)
    }

    fn tron_sign_request() -> Vec<u8> {
        let mut data = tron_path();
        data.extend_from_slice(&[0x11u8; 32]);
        apdu(0xE0, 0x05, &data)
    }

    /// 同一串真实 APDU 分别喂给「直连模块」和「编码后模块」的宿主，
    /// 断言两条链路逐字节一致：这说明 Event/Effect 的线格式足以承载全部流量。
    #[test]
    fn serialised_module_boundary_matches_the_direct_path() {
        let direct = chain_host_new();
        assert!(!direct.is_null());
        let encoded = Box::into_raw(Box::new(ChainHost::new_encoded().expect("encoded host")));
        set_seed(direct, &seed_hex());
        set_seed(encoded, &seed_hex());

        // (要切换的模块, APDU, 是否在挂起审阅后批准)
        let steps: Vec<(Option<&str>, Vec<u8>, Option<bool>)> = vec![
            (None, get_public_key(), None),
            (None, vec![0xE0, 0x02, 0x01, 0x00, 0x00], Some(true)),
            (Some(BTC_MODULE_ID), bitcoin_address_request(), None),
            (Some(SOL_MODULE_ID), apdu(0xE0, 0x05, &solana_path()), None),
            (Some(SOL_MODULE_ID), solana_sign_request(), Some(true)),
            (Some(TRON_MODULE_ID), apdu(0xE0, 0x02, &tron_path()), None),
            (Some(TRON_MODULE_ID), tron_sign_request(), Some(true)),
            (Some(SUI_MODULE_ID), apdu(0x07, 0x02, &sui_path()), None),
        ];

        for (module, request, approve) in steps {
            if let Some(module) = module {
                open_module(direct, module);
                open_module(encoded, module);
            }
            let expected = call(direct, &request);
            let actual = call(encoded, &request);
            assert_eq!(
                actual,
                expected,
                "module {module:?} apdu {}",
                hex::encode(&request)
            );

            if let Some(approve) = approve {
                let expected_id = review_id(&expected);
                assert_eq!(review_id(&actual), expected_id);
                assert_eq!(
                    resolve_review(encoded, expected_id, approve),
                    resolve_review(direct, expected_id, approve)
                );
            }
        }

        // 本机账户派生走 LocalRequest，同样要能跨边界。
        assert_eq!(
            derive_account(encoded, BTC_MODULE_ID, 3),
            derive_account(direct, BTC_MODULE_ID, 3)
        );

        unsafe {
            chain_host_free(direct);
            chain_host_free(encoded);
        }
    }
}
