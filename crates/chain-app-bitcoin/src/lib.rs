//! Bitcoin 链 App（阶段 3）。
//!
//! 协议实现状态：**官方 `E1 04 SIGN_PSBT` 已按 2.1.0+ 语义实现**（默认单密钥
//! 钱包：`pkh` / `sh(wpkh)` / `wpkh` / `tr`，sighash `DEFAULT` / `ALL`），
//! 主机需要支持 `0xE000` 反向请求；注册钱包、多签、MuSig2、`E1 00/03/05` 尚未实现。
//!
//! `E1 40 GET_WALLET_PUBLIC_KEY` 是本仓扩展：legacy 编号落在现行 App 的 CLA 上，
//! 真实主机不会发它，只用于地址查询与真机回归，且已显式标注为非标准。
//!
//! 两套官方 Bitcoin APDU 协议：
//!
//! - legacy app（`CLA 0xE0`）：`0x40 GET_WALLET_PUBLIC_KEY` / `0x42 GET_TRUSTED_INPUT` /
//!   `0x44 HASH_INPUT_START` / `0x48 HASH_SIGN` / `0x4A HASH_INPUT_FINALIZE_FULL`，
//!   摘要由设备自己算。
//! - 现行 app（`CLA 0xE1`，协议 2.1.0+）：`0x00 GET_EXTENDED_PUBKEY` /
//!   `0x03 GET_WALLET_ADDRESS` / `0x04 SIGN_PSBT`，`P1` 必须为 0、`P2` 是协议版本；
//!   `SIGN_PSBT` 是 Merkleized 交互协议，设备会反向请求 `GET_PREIMAGE` /
//!   `GET_MERKLE_LEAF_PROOF`。
//!
//! **不得再占用官方编号并赋予不同语义**（D-021）：旧的 `E1 44 SIGN_DIGEST`
//! （主机交摘要、设备盲签）已删除，签名只走 `E1 04`；真机签名用例见
//! `tool/e2e/tests/btc_psbt.py`。
//!
//! 具体命令：
//!
//! - `E1 40`：P1 = 是否在设备上确认地址（0/1），P2 = 网络（高 4 位）+ 地址格式
//!   （低 4 位：0 legacy / 1 p2sh / 2 bech32 / 4 bech32m），按路径派生公钥后编码。
//! - `E1 04`：PSBTv2 的 Merkle 化摘要，见 [`flow`]。
//! - `F8 01 CONTINUE`：回答设备发起的 `0xE000`。
//!
//! 与 ETH 一样，模块不接触 seed：公钥向宿主请求，签名由宿主在批准后执行。
//!
//! ## 交互通道（`0xE000` / `F8 01`）
//!
//! 现行协议允许设备在给出最终状态字前随时回 `SW_INTERRUPTED_EXECUTION
//! (0xE000)`：响应数据首字节是客户端命令码（`0x10` YIELD / `0x40` GET_PREIMAGE /
//! `0x41` GET_MERKLE_LEAF_PROOF / `0x42` GET_MERKLE_LEAF_INDEX / `0xA0`
//! GET_MORE_ELEMENTS），主机必须用 `F8 01 CONTINUE` 回答。
//!
//! 运行时一侧的约定：这类响应以 `OperationState::Collecting` 发出，模块收到
//! `Event::Delivered` 后回 `Effect::AwaitInput`（不是 `Finished`，那会把会话标成
//! 结束）；下一个 `F8 01` 帧再进入同一会话继续。M1 只落地这条通道，产生的
//! 请求由 M2 的 PSBT 流程使用。

use chain_app_api::{
    AppDescriptor, AppError, ChainApp, Curve, DeliveryAck, DerivationRule, DerivationScheme, Effect,
    Event, ExchangeId, Field, FieldValue, FinishStatus, KeyOutput, NetworkId, OperationKind,
    OperationState, ParseStatus, PublicKeyRequest, ReviewAction, ReviewDocument, ReviewOutcome,
    ReviewRequest, ReviewSection, ServiceResult, SessionConfig, Wire, API_VERSION,
};
use open_ledger_crypto::{base58, bech32, hash160, secp256k1};

pub mod flow;
pub mod psbt;

pub mod sw {
    pub const OK: u16 = 0x9000;
    pub const DENIED: u16 = 0x6985;
    pub const WRONG_DATA: u16 = 0x6A80;
    pub const WRONG_P1_P2: u16 = 0x6A86;
    pub const WRONG_DATA_LENGTH: u16 = 0x6A87;
    pub const UNKNOWN_INS: u16 = 0x6D00;
    pub const CLA_NOT_SUPPORTED: u16 = 0x6E00;
    pub const UNKNOWN: u16 = 0x6F00;
    /// 官方 `SW_BAD_STATE`：命令在不该出现的状态到达。
    pub const BAD_STATE: u16 = 0xB007;
    /// 官方 `SW_INTERRUPTED_EXECUTION`：设备主动请求主机应答。
    pub const INTERRUPTED: u16 = 0xE000;
}

pub const MODULE_ID: &str = "openledger.bitcoin";

const CLA_BTC: u8 = 0xE1;
/// 框架通道（`F8 01 CONTINUE`），只用于回答 `0xE000`。
const CLA_FRAMEWORK: u8 = 0xF8;
const INS_CONTINUE: u8 = 0x01;

/// 设备发起的客户端命令码（官方 `client_command.py`）。
const CCMD_YIELD: u8 = 0x10;
#[allow(dead_code)] // M2 的 PSBT 流程才会产生这些请求。
const CCMD_GET_PREIMAGE: u8 = 0x40;
#[allow(dead_code)]
const CCMD_GET_MERKLE_LEAF_PROOF: u8 = 0x41;
#[allow(dead_code)]
const CCMD_GET_MERKLE_LEAF_INDEX: u8 = 0x42;
#[allow(dead_code)]
const CCMD_GET_MORE_ELEMENTS: u8 = 0xA0;

/// 协议版本：现行 app 要求 `P2 = 1`。
const PROTOCOL_VERSION: u8 = 1;
/// `0x40` 沿用 legacy 编号，但在官方现行 app 里 `0x40` 未分配（见模块文档）。
const INS_GET_PUBLIC_KEY: u8 = 0x40;

/// 官方现行 app 的 `E1 00 GET_EXTENDED_PUBKEY` / `E1 05 GET_MASTER_FINGERPRINT`。
/// 官方客户端（`@ledgerhq/hw-app-btc`）在 `SIGN_PSBT` 之前会先问这两个。
const INS_GET_EXTENDED_PUBKEY: u8 = 0x00;
const INS_GET_MASTER_FINGERPRINT: u8 = 0x05;

/// 官方现行 app 的 `E1 04 SIGN_PSBT`（Merkleized 交互）。
const INS_SIGN_PSBT: u8 = 0x04;

/// Bitcoin 网络。只影响地址编码、默认 coin type 与审阅文案，不改变密钥。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Network {
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
pub(crate) enum AddressType {
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
        // case-1 APDU：没有 Lc，数据为空。主机回答 `YIELD` 时会发
        // `F8 01 00 01`（不带 Lc=0 字节），必须按空数据接受。
        let data = match bytes.get(4) {
            None => Vec::new(),
            Some(lc) => {
                let end = 5 + *lc as usize;
                if bytes.len() < end {
                    return None;
                }
                bytes[5..end].to_vec()
            }
        };
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
    AwaitKey,
    AwaitReview,
    /// 已经发出 `0xE000`，正在等主机的 `F8 01 CONTINUE`。
    AwaitHost,
}

/// 设备已经发出、正在等主机回答的客户端命令。
///
/// M1 只会产生 [`ClientRequest::Yield`]；其余变体由 M2 的 PSBT 流程使用，
/// 现在到达即视为状态错乱。
#[derive(Debug, Clone, PartialEq, Eq)]
#[allow(dead_code)] // 除 Yield 外的变体由 M2 的 PSBT 流程构造。
enum ClientRequest {
    /// `0x10`：设备把一个值交给主机（签名等），主机回空 CONTINUE。
    Yield,
    /// `0x40`：按 `sha256(preimage)` 取预映像。
    Preimage { hash: [u8; 32] },
    /// `0x41`：取 Merkle 叶子证明。
    LeafProof {
        root: [u8; 32],
        size: u64,
        index: u64,
    },
    /// `0x42`：按叶子哈希查下标。
    LeafIndex { root: [u8; 32], leaf: [u8; 32] },
    /// `0xA0`：取排队中的剩余元素。
    MoreElements,
}

struct Pending {
    exchange_id: ExchangeId,
    path: Vec<u32>,
    address: String,
    address_type: AddressType,
    network: Network,
    /// 地址查询时是否要用户确认（P1 = 1）。
    display: bool,
}

/// `E1 00 GET_EXTENDED_PUBKEY`：先取账户公钥+链码，再取父公钥算父指纹。
struct XpubPending {
    exchange_id: ExchangeId,
    path: Vec<u32>,
    /// `(compressed pubkey, chain code)`，第一步的结果。
    key: Option<(Vec<u8>, [u8; 32])>,
}

pub struct BitcoinModule {
    stage: Stage,
    pending: Option<Pending>,
    /// 本机账户请求的 `request_id` 与所选地址类型（`LocalCommand::DeriveAccount`）。
    local: Option<(u64, AddressType)>,
    /// 已发出但还没收到 `F8 01` 的客户端命令。
    pending_request: Option<ClientRequest>,
    /// 正在执行的 `SIGN_PSBT` 流程。
    flow: Option<flow::SignFlow>,
    /// 当前等待的客户端命令类型；`F8 01` 进来时按它解释。
    flow_expect: flow::RequestKind,
    /// 流程所属的 exchange_id（跨多轮 `F8 01` 保持不变）。
    flow_exchange: ExchangeId,
    /// `E1 05` 待回的主指纹。
    fingerprint_pending: Option<ExchangeId>,
    /// `E1 00` 待回的 xpub。
    xpub_pending: Option<XpubPending>,
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
            pending_request: None,
            flow: None,
            flow_expect: flow::RequestKind::Preimage,
            flow_exchange: 0,
            fingerprint_pending: None,
            xpub_pending: None,
        }
    }

    fn emit(&self, exchange_id: ExchangeId, payload: Vec<u8>) -> Effect {
        Effect::Emit {
            wire: Wire::LedgerApdu,
            exchange_id,
            payload,
            state: OperationState::Final,
        }
    }

    /// 发一条 `0xE000` 请求，把会话挂到 [`Stage::AwaitHost`]。
    ///
    /// [request] 是客户端命令字节（含命令码），状态字由本方法追加。
    fn interrupt(
        &mut self,
        exchange_id: ExchangeId,
        request: Vec<u8>,
        expect: ClientRequest,
    ) -> Effect {
        self.pending_request = Some(expect);
        self.stage = Stage::AwaitHost;
        let mut payload = request;
        payload.extend_from_slice(&status(sw::INTERRUPTED));
        Effect::Emit {
            wire: Wire::LedgerApdu,
            exchange_id,
            payload,
            state: OperationState::Collecting,
        }
    }

    /// 把 `YIELD` 交给主机：`10 <payload>`，之后等一个空 CONTINUE。
    #[allow(dead_code)] // M2 的签名下发会用；M1 先由单测驱动。
    fn yield_to_host(&mut self, exchange_id: ExchangeId, payload: &[u8]) -> Effect {
        let mut request = Vec::with_capacity(1 + payload.len());
        request.push(CCMD_YIELD);
        request.extend_from_slice(payload);
        self.interrupt(exchange_id, request, ClientRequest::Yield)
    }

    /// 处理主机的 `F8 01 CONTINUE`。
    ///
    /// 只有 `AwaitHost` 状态接受它；其他状态回 `B007`（官方 `SW_BAD_STATE`）。
    fn handle_continue(
        &mut self,
        exchange_id: ExchangeId,
        p1: u8,
        p2: u8,
        data: &[u8],
    ) -> Result<Effect, AppError> {
        if p1 != 0x00 || p2 != PROTOCOL_VERSION {
            return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2)));
        }
        if self.stage != Stage::AwaitHost {
            return Ok(self.emit(exchange_id, status(sw::BAD_STATE)));
        }
        // 标准流程独占这条通道。
        if self.flow.is_some() {
            let expect = self.flow_expect;
            let Some(flow) = self.flow.as_mut() else {
                return Ok(self.emit(exchange_id, status(sw::BAD_STATE)));
            };
            if let Err(code) = flow.receive(expect, data) {
                self.flow = None;
                self.stage = Stage::Idle;
                return Ok(self.emit(exchange_id, status(code)));
            }
            return self.advance_flow();
        }
        let Some(request) = self.pending_request.take() else {
            return Ok(self.emit(exchange_id, status(sw::BAD_STATE)));
        };

        match request {
            // YIELD 的应答必须是空数据；随后本段交互结束。
            ClientRequest::Yield => {
                if !data.is_empty() {
                    self.stage = Stage::Idle;
                    return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
                }
                self.stage = Stage::Idle;
                Ok(self.emit(exchange_id, status(sw::OK)))
            }
            // 其余请求还没有产生者（M2 才接入 PSBT），到达即视为状态错乱。
            _ => {
                self.stage = Stage::Idle;
                Ok(self.emit(exchange_id, status(sw::BAD_STATE)))
            }
        }
    }

    /// 驱动 `SIGN_PSBT` 流程的下一个动作。
    ///
    /// 每一轮只产出一个效果：要么发 `0xE000`、要么向宿主取公钥、要么挂审批，
    /// 要么以最终状态字收尾。
    fn advance_flow(&mut self) -> Result<Effect, AppError> {
        let exchange_id = self.flow_exchange;
        let action = match self.flow.as_mut() {
            Some(flow) => flow.advance(),
            None => return Ok(self.emit(exchange_id, status(sw::BAD_STATE))),
        };
        match action {
            flow::FlowAction::Request { bytes, expect } => {
                self.flow_expect = expect;
                self.stage = Stage::AwaitHost;
                let mut payload = bytes;
                payload.extend_from_slice(&status(sw::INTERRUPTED));
                Ok(Effect::Emit {
                    wire: Wire::LedgerApdu,
                    exchange_id,
                    payload,
                    state: OperationState::Collecting,
                })
            }
            flow::FlowAction::NeedKey(request) => {
                self.stage = Stage::AwaitKey;
                Ok(Effect::NeedPublicKey {
                    service_id: 21,
                    request,
                })
            }
            flow::FlowAction::Review(request) => {
                self.stage = Stage::AwaitReview;
                Ok(Effect::NeedReview {
                    service_id: 22,
                    request,
                })
            }
            flow::FlowAction::Finish(payload) => {
                self.flow = None;
                self.stage = Stage::Idle;
                Ok(self.emit(exchange_id, payload))
            }
        }
    }

    fn handle_apdu(&mut self, exchange_id: ExchangeId, bytes: &[u8]) -> Result<Effect, AppError> {
        let apdu =
            Apdu::parse(bytes).ok_or_else(|| AppError::BadRequest("truncated APDU".into()))?;
        // 等主机回答时只接受框架通道的 CONTINUE，别的命令一律状态错乱。
        if (self.stage == Stage::AwaitHost || self.flow.is_some())
            && apdu.cla != CLA_FRAMEWORK
        {
            return Ok(self.emit(exchange_id, status(sw::BAD_STATE)));
        }
        // 框架通道：只承载 `F8 01 CONTINUE`，且只属于发出过 `0xE000` 的会话。
        if apdu.cla == CLA_FRAMEWORK {
            if apdu.ins != INS_CONTINUE {
                return Ok(self.emit(exchange_id, status(sw::UNKNOWN_INS)));
            }
            return self.handle_continue(exchange_id, apdu.p1, apdu.p2, &apdu.data);
        }
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
            INS_GET_EXTENDED_PUBKEY => self.handle_get_extended_pubkey(
                exchange_id,
                apdu.p1,
                apdu.p2,
                &apdu.data,
            ),
            INS_GET_MASTER_FINGERPRINT => {
                if apdu.p1 != 0x00 || apdu.p2 != PROTOCOL_VERSION || !apdu.data.is_empty() {
                    return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2)));
                }
                self.fingerprint_pending = Some(exchange_id);
                self.stage = Stage::AwaitKey;
                Ok(Effect::NeedPublicKey {
                    service_id: 5,
                    request: PublicKeyRequest {
                        derivation_scheme: DerivationScheme::Bip32Secp256k1,
                        curve: Curve::Secp256k1,
                        path: Vec::new(),
                        output: KeyOutput::CompressedSecp256k1,
                        include_chain_code: false,
                    },
                })
            }
            INS_SIGN_PSBT => {
                if apdu.p1 != 0x00 || apdu.p2 != PROTOCOL_VERSION {
                    return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2)));
                }
                let Some(sign_flow) = flow::SignFlow::start(&apdu.data) else {
                    return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
                };
                self.flow = Some(sign_flow);
                self.flow_exchange = exchange_id;
                self.advance_flow()
            }
            _ => Ok(self.emit(exchange_id, status(sw::UNKNOWN_INS))),
        }
    }

    /// 官方 `E1 00 GET_EXTENDED_PUBKEY`：`[display:1][count:1][4B BE]*`，
    /// 返回 ASCII 序列化的 xpub（官方客户端直接 `toString("ascii")` 再 base58 解码）。
    fn handle_get_extended_pubkey(
        &mut self,
        exchange_id: ExchangeId,
        p1: u8,
        p2: u8,
        data: &[u8],
    ) -> Result<Effect, AppError> {
        if p1 != 0x00 || p2 != PROTOCOL_VERSION {
            return Ok(self.emit(exchange_id, status(sw::WRONG_P1_P2)));
        }
        let Some((&display, rest)) = data.split_first() else {
            return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
        };
        let Some((&count, rest)) = rest.split_first() else {
            return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
        };
        let count = count as usize;
        if display > 1 || count > 6 || rest.len() != count * 4 {
            return Ok(self.emit(exchange_id, status(sw::WRONG_DATA)));
        }
        let path: Vec<u32> = rest
            .as_chunks::<4>()
            .0
            .iter()
            .map(|chunk| u32::from_be_bytes(*chunk))
            .collect();
        self.xpub_pending = Some(XpubPending {
            exchange_id,
            path: path.clone(),
            key: None,
        });
        self.stage = Stage::AwaitKey;
        Ok(Effect::NeedPublicKey {
            service_id: 6,
            request: PublicKeyRequest {
                derivation_scheme: DerivationScheme::Bip32Secp256k1,
                curve: Curve::Secp256k1,
                path,
                output: KeyOutput::CompressedSecp256k1,
                include_chain_code: true,
            },
        })
    }

    /// `E1 00` 的两步取证：账户公钥 + 父公钥（父指纹），然后序列化 xpub。
    fn handle_xpub_result(&mut self, result: ServiceResult) -> Result<Effect, AppError> {
        let Some(pending) = self.xpub_pending.take() else {
            return Err(AppError::InvalidEvent("no xpub request".into()));
        };
        let exchange_id = pending.exchange_id;
        let ServiceResult::PublicKey(key) = result else {
            self.stage = Stage::Idle;
            return Ok(self.emit(exchange_id, status(sw::UNKNOWN)));
        };
        if pending.key.is_none() {
            let Some(chain_code) = key
                .chain_code
                .as_deref()
                .and_then(|bytes| <[u8; 32]>::try_from(bytes).ok())
            else {
                self.stage = Stage::Idle;
                return Ok(self.emit(exchange_id, status(sw::UNKNOWN)));
            };
            // depth ≤ 1 时没有父公钥可取（m 或 m/purpose'），父指纹留零。
            if pending.path.len() <= 1 {
                let payload = xpub_payload(&pending.path, &key.bytes, &chain_code, None)
                    .unwrap_or_else(|| status(sw::UNKNOWN));
                self.stage = Stage::Idle;
                return Ok(self.emit(exchange_id, payload));
            }
            let parent_path = pending.path[..pending.path.len() - 1].to_vec();
            self.xpub_pending = Some(XpubPending {
                exchange_id,
                path: pending.path,
                key: Some((key.bytes, chain_code)),
            });
            self.stage = Stage::AwaitKey;
            return Ok(Effect::NeedPublicKey {
                service_id: 7,
                request: PublicKeyRequest {
                    derivation_scheme: DerivationScheme::Bip32Secp256k1,
                    curve: Curve::Secp256k1,
                    path: parent_path,
                    output: KeyOutput::CompressedSecp256k1,
                    include_chain_code: false,
                },
            });
        }
        let (pubkey, chain_code) = pending.key.expect("checked above");
        let payload = xpub_payload(&pending.path, &pubkey, &chain_code, Some(&key.bytes))
            .unwrap_or_else(|| status(sw::UNKNOWN));
        self.stage = Stage::Idle;
        Ok(self.emit(exchange_id, payload))
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
            display: p1 == 1,
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
        // 标准 SIGN_PSBT 流程：只接受公钥结果。
        if self.flow.is_some() {
            let ServiceResult::PublicKey(key) = result else {
                self.flow = None;
                self.stage = Stage::Idle;
                return Ok(self.emit(self.flow_exchange, status(sw::UNKNOWN)));
            };
            let outcome = match self.flow.as_mut() {
                Some(flow) => flow.on_public_key(&key.bytes),
                None => Err(sw::BAD_STATE),
            };
            return match outcome {
                Ok(()) => self.advance_flow(),
                Err(code) => {
                    self.flow = None;
                    self.stage = Stage::Idle;
                    Ok(self.emit(self.flow_exchange, status(code)))
                }
            };
        }
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
        // `E1 05`：主指纹 = hash160(主公钥)[0..4]。
        if let Some(exchange_id) = self.fingerprint_pending.take() {
            self.stage = Stage::Idle;
            let payload = match result {
                ServiceResult::PublicKey(key) if key.bytes.len() == 33 => {
                    let mut out = hash160::hash(&key.bytes)[..4].to_vec();
                    out.extend_from_slice(&status(sw::OK));
                    out
                }
                _ => status(sw::UNKNOWN),
            };
            return Ok(self.emit(exchange_id, payload));
        }
        if self.xpub_pending.is_some() {
            return self.handle_xpub_result(result);
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

        let (exchange_id, path, display, network_name) = {
            let pending = self
                .pending
                .as_mut()
                .ok_or_else(|| AppError::InvalidEvent("no pending request".into()))?;
            pending.address = address.clone();
            (
                pending.exchange_id,
                pending.path.clone(),
                pending.display,
                pending.network.display_name(),
            )
        };

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
        Ok(Effect::NeedReview {
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
        })
    }

    fn handle_review(&mut self, outcome: ReviewOutcome) -> Result<Effect, AppError> {
        // 标准 SIGN_PSBT 流程：批准后逐个 YIELD，拒绝则 6985。
        if self.flow.is_some() {
            let result = match (&mut self.flow, outcome) {
                (Some(flow), ReviewOutcome::Approved { signatures }) => {
                    flow.on_signatures(signatures)
                }
                (_, ReviewOutcome::Rejected) | (_, ReviewOutcome::TimedOut) => {
                    Err(sw::DENIED)
                }
                _ => Err(sw::UNKNOWN),
            };
            return match result {
                Ok(()) => self.advance_flow(),
                Err(code) => {
                    self.flow = None;
                    self.stage = Stage::Idle;
                    Ok(self.emit(self.flow_exchange, status(code)))
                }
            };
        }
        let pending = self
            .pending
            .take()
            .ok_or_else(|| AppError::InvalidEvent("no pending review".into()))?;
        self.stage = Stage::Idle;

        // 地址确认：批准后把地址回给主机，拒绝/超时回 6985。
        let payload = match outcome {
            ReviewOutcome::Approved { .. } => {
                let mut out = pending.address.into_bytes();
                out.extend_from_slice(&status(sw::OK));
                out
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
                Stage::Idle | Stage::AwaitHost => self.handle_apdu(exchange_id, &payload),
                _ => Err(AppError::InvalidEvent("busy".into())),
            },
            Event::ServiceResult { result, .. } => self.handle_service_result(result),
            Event::ReviewResult { outcome, .. } => self.handle_review(outcome),
            // 发了 `0xE000` 之后必须挂起：回 `Finished` 会让 runtime 把会话标成
            // 结束，主机的 `F8 01` 就再也进不来。
            Event::Delivered { ack, .. } => {
                if self.stage == Stage::AwaitHost {
                    debug_assert_eq!(ack, DeliveryAck::Acknowledged);
                    Ok(Effect::AwaitInput)
                } else {
                    Ok(Effect::Finished {
                        status: FinishStatus::Delivered,
                    })
                }
            }
            Event::Cancel { .. } => {
                self.pending = None;
                self.local = None;
                self.pending_request = None;
                self.flow = None;
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
        self.pending_request = None;
        self.flow = None;
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

/// 路径的 coin type 决定 xpub 版本字节：`0'` → `xpub`，其余（测试网/regtest）→ `tpub`。
fn network_from_path(path: &[u32]) -> Network {
    match path.get(1).map(|component| component & 0x7FFF_FFFF) {
        Some(1) => Network::Testnet,
        _ => Network::Mainnet,
    }
}

/// 78 字节 BIP-32 扩展公钥 → ASCII（含状态字）。父指纹只在能拿到父公钥时计算。
fn xpub_payload(
    path: &[u32],
    pubkey: &[u8],
    chain_code: &[u8; 32],
    parent_pubkey: Option<&[u8]>,
) -> Option<Vec<u8>> {
    if pubkey.len() != 33 {
        return None;
    }
    let version: u32 = match network_from_path(path) {
        Network::Mainnet => 0x0488_B21E,
        _ => 0x0435_87CF,
    };
    let parent_fingerprint: [u8; 4] = parent_pubkey
        .and_then(|bytes| bytes.get(..33))
        .map(|bytes| {
            let digest = hash160::hash(bytes);
            [digest[0], digest[1], digest[2], digest[3]]
        })
        .unwrap_or([0u8; 4]);
    let mut body = Vec::with_capacity(78);
    body.extend_from_slice(&version.to_be_bytes());
    body.push(u8::try_from(path.len()).ok()?);
    body.extend_from_slice(&parent_fingerprint);
    body.extend_from_slice(&path.last().copied().unwrap_or(0).to_be_bytes());
    body.extend_from_slice(chain_code);
    body.extend_from_slice(pubkey);
    let mut payload = base58::encode_check(&body).into_bytes();
    payload.extend_from_slice(&status(sw::OK));
    Some(payload)
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
                "F8 01 CONTINUE (framework channel answering 0xE000)".into(),
                "E1 04 SIGN_PSBT (default single-key wallets: pkh / sh(wpkh) / wpkh / tr)".into(),
            ],
            unsupported: vec![
                "cashaddr (BCH)".into(),
                "E1 00 GET_EXTENDED_PUBKEY / E1 02 REGISTER_WALLET / E1 03 GET_WALLET_ADDRESS / E1 05 GET_MASTER_FINGERPRINT".into(),
                "legacy HASH_INPUT_START / HASH_INPUT_FINALIZE_FULL / HASH_SIGN flow".into(),
            ],
            vector_sources: vec![
                "tool/e2e/tests/btc_psbt.py".into(),
                "crates/chain-app-bitcoin/tests/psbt_sign.rs".into(),
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
            // `E1 05` 需要主密钥（depth 0），`E1 00` 需要账户级（depth 3）与
            // 其父级（depth 2，用于父指纹）；地址仍在 depth 5。
            derivation_rules: vec![
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
                DerivationRule {
                    derivation_scheme: DerivationScheme::Bip32Secp256k1,
                    curve: Curve::Secp256k1,
                    depth: 5,
                    hardened_positions: vec![0, 1, 2],
                    max_index: 1000,
                },
            ],
            // 官方 `GET_EXTENDED_PUBKEY` 必须返回链码，否则官方客户端算不出 wallet id。
            allow_chain_code: true,
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

#[cfg(test)]
mod tests {
    use super::*;

    fn delivered(exchange_id: ExchangeId) -> Event {
        Event::Delivered {
            exchange_id,
            ack: DeliveryAck::Acknowledged,
        }
    }

    fn wire(exchange_id: ExchangeId, payload: Vec<u8>) -> Event {
        Event::Wire {
            exchange_id,
            wire: Wire::LedgerApdu,
            payload,
        }
    }

    fn emit_parts(effect: Effect) -> (ExchangeId, Vec<u8>, OperationState) {
        match effect {
            Effect::Emit {
                exchange_id,
                payload,
                state,
                ..
            } => (exchange_id, payload, state),
            other => panic!("expected Emit, got {other:?}"),
        }
    }

    /// `0xE000` → 投递确认必须挂起 → `F8 01` 收尾。这条链就是 M1 的全部契约。
    #[test]
    fn interrupted_interaction_suspends_then_finishes() {
        let mut module = BitcoinModule::new();

        let (exchange, payload, state) = emit_parts(module.yield_to_host(7, &[0xAA, 0xBB]));
        assert_eq!(exchange, 7);
        assert_eq!(state, OperationState::Collecting);
        assert_eq!(payload, vec![0x10, 0xAA, 0xBB, 0xE0, 0x00]);

        assert!(matches!(module.step(delivered(7)), Ok(Effect::AwaitInput)));

        let (exchange, payload, state) = emit_parts(
            module
                .step(wire(8, vec![0xF8, 0x01, 0x00, 0x01, 0x00]))
                .unwrap(),
        );
        assert_eq!(exchange, 8);
        assert_eq!(payload, vec![0x90, 0x00]);
        assert_eq!(state, OperationState::Final);
        assert!(matches!(
            module.step(delivered(8)),
            Ok(Effect::Finished { .. })
        ));
    }

    /// 主机的 `toBytes()` 对空数据发 case-1 APDU（4 字节，没有 Lc）。
    /// 设备必须把它当成空 `CONTINUE`，而不是「截断」。
    #[test]
    fn continue_accepts_a_case_one_apdu_without_lc() {
        let mut module = BitcoinModule::new();
        module.yield_to_host(1, &[0x01]);
        let (_, payload, _) = emit_parts(module.step(wire(2, vec![0xF8, 0x01, 0x00, 0x01])).unwrap());
        assert_eq!(payload, status(sw::OK));
    }

    /// 没有悬挂请求时收到 CONTINUE：官方 `SW_BAD_STATE`，不是 6D00/6E00。
    #[test]
    fn continue_without_pending_request_is_bad_state() {
        let mut module = BitcoinModule::new();
        let (_, payload, _) =
            emit_parts(module.step(wire(1, vec![0xF8, 0x01, 0x00, 0x01, 0x00])).unwrap());
        assert_eq!(payload, status(sw::BAD_STATE));
    }

    /// `P2` 是协议版本，必须是 1。
    #[test]
    fn continue_with_wrong_protocol_version_is_rejected() {
        let mut module = BitcoinModule::new();
        module.yield_to_host(1, &[0x01]);
        let (_, payload, _) =
            emit_parts(module.step(wire(2, vec![0xF8, 0x01, 0x00, 0x00, 0x00])).unwrap());
        assert_eq!(payload, status(sw::WRONG_P1_P2));
    }

    /// 等主机回答时，任何非框架命令都是状态错乱。
    #[test]
    fn app_command_while_waiting_for_host_is_bad_state() {
        let mut module = BitcoinModule::new();
        module.yield_to_host(1, &[0x01]);
        let (_, payload, _) =
            emit_parts(module.step(wire(2, vec![0xE1, 0x40, 0x00, 0x00, 0x00])).unwrap());
        assert_eq!(payload, status(sw::BAD_STATE));
    }

    /// YIELD 的 CONTINUE 必须为空。
    #[test]
    fn yield_reply_must_be_empty() {
        let mut module = BitcoinModule::new();
        module.yield_to_host(1, &[0x01]);
        let (_, payload, _) =
            emit_parts(module.step(wire(2, vec![0xF8, 0x01, 0x00, 0x01, 0x01, 0x00])).unwrap());
        assert_eq!(payload, status(sw::WRONG_DATA));
    }
}
