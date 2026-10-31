//! 现行 `E1 04 SIGN_PSBT` 的协议状态机（M2）。
//!
//! 设备不接收完整 PSBT，只拿到 Merkle 化的摘要；所有字段都要通过 `0xE000`
//! 反向请求主机（`GET_PREIMAGE` / `GET_MERKLE_LEAF_PROOF` / `GET_MORE_ELEMENTS`）。
//! 这里把「下一步该说什么」与「刚收到的字节怎么解释」拆成两个入口，`lib.rs`
//! 只负责把它们映射成 `Effect`。
//!
//! 范围：默认单密钥钱包（`pkh` / `sh(wpkh)` / `wpkh` / `tr`），sighash
//! `DEFAULT` / `ALL`，一笔最多 16 个输入/输出。注册钱包、多签、MuSig2 不在本期。

use chain_app_api::{
    Curve, DerivationScheme, FeeKind, Field, FieldValue, KeyOutput, NetworkId, OperationKind,
    ParseStatus, PublicKeyRequest, ReviewAction, ReviewDocument, ReviewRequest, ReviewSection,
    Risk, RiskLevel, RiskSource, Signature, SignOperation, SignPlan, SignScheme,
};
use open_ledger_crypto::{base58, bech32, sha256};

use crate::psbt::{
    self, address_type_for_template, bip143_sighash, bip341_sighash, legacy_sighash,
    parse_key_origin, parse_policy_header, script_code_p2wpkh, script_pubkey, verify_leaf,
    write_varint, Reader, Tx, TxOut, GLOBAL_FALLBACK_LOCKTIME, GLOBAL_INPUT_COUNT,
    GLOBAL_OUTPUT_COUNT, GLOBAL_TX_VERSION, GLOBAL_VERSION, IN_BIP32_DERIVATION,
    IN_NON_WITNESS_UTXO, IN_OUTPUT_INDEX, IN_PREVIOUS_TXID, IN_REQUIRED_HEIGHT_LOCKTIME,
    IN_REQUIRED_TIME_LOCKTIME, IN_SEQUENCE, IN_SIGHASH_TYPE, IN_WITNESS_UTXO, OUT_AMOUNT,
    OUT_BIP32_DERIVATION, OUT_SCRIPT,
};
use crate::{AddressType, Network};

/// 单张 map 与整笔交易的条目上限：防止主机用超大 PSBT 拖死设备。
const MAX_MAP_ENTRIES: u64 = 64;
const MAX_INPUTS: usize = 16;
const MAX_OUTPUTS: usize = 16;

/// 设备发起的客户端命令（与官方 `client_command.py` 一致）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RequestKind {
    Preimage,
    LeafProof,
    LeafIndex,
    MoreElements,
    Yield,
}

/// 流程产出的下一个动作。
pub enum FlowAction {
    /// 以 `0xE000` 发出；`expect` 决定下一个 `F8 01` 怎么解释。
    Request {
        bytes: Vec<u8>,
        expect: RequestKind,
    },
    /// 向宿主索取派生公钥。
    NeedKey(PublicKeyRequest),
    /// 悬挂审阅。
    Review(Box<ReviewRequest>),
    /// 终态：payload 已含状态字。
    Finish(Vec<u8>),
}

struct MapBuf {
    size: u64,
    keys_root: [u8; 32],
    vals_root: [u8; 32],
    entries: Vec<(Vec<u8>, Vec<u8>)>,
}

impl MapBuf {
    fn get(&self, key: &[u8]) -> Option<&[u8]> {
        self.entries
            .iter()
            .find(|(candidate, _)| candidate.as_slice() == key)
            .map(|(_, value)| value.as_slice())
    }
}

/// 分片应答的续收状态。
struct Gather {
    needed: usize,
    element_len: usize,
    data: Vec<u8>,
}

struct Policy {
    address_type: AddressType,
    network: Network,
    /// `[purpose', coin', account']`，全硬化。
    path: [u32; 3],
    keys_root: [u8; 32],
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Step {
    Policy,
    Template,
    KeyProof,
    KeyInfo,
    InputCommit(u32),
    InputCommitPreimage(u32),
    OutputCommit(u32),
    OutputCommitPreimage(u32),
    MapKeyProof,
    MapKeyPreimage,
    MapValueProof,
    MapValuePreimage,
    Verify,
    Derive,
    Review,
    Yield,
}

/// 一个需要派生公钥的输入或找零输出。
struct DeriveJob {
    input: Option<usize>,
    change_output: Option<usize>,
    path: Vec<u32>,
    pubkey: Vec<u8>,
    script: Vec<u8>,
}

pub struct SignFlow {
    wallet_id: [u8; 32],
    n_inputs: u32,
    n_outputs: u32,
    inputs_root: [u8; 32],
    outputs_root: [u8; 32],
    /// 下标 0 = global，接着是输入，再接输出。
    maps: Vec<MapBuf>,
    step: Step,
    gather: Option<Gather>,
    /// 最近一次请求返回的叶子哈希，供随后的 `GET_PREIMAGE` 使用。
    pending_leaf: [u8; 32],
    pending_key: Vec<u8>,
    policy: Option<Policy>,
    /// 策略里 `sha256(descriptor_template)` 的值；模板本体要另外取预映像。
    template_hash: Option<[u8; 32]>,
    map_cursor: usize,
    entry_cursor: u64,
    /// global map 的条目先读完，再读输入/输出 map 的条目。
    global_done: bool,
    /// 解析结果。
    tx: Option<Tx>,
    prevouts: Vec<TxOut>,
    jobs: Vec<DeriveJob>,
    job_cursor: usize,
    operations: Vec<SignOperation>,
    signatures: Vec<Option<Signature>>,
    yield_cursor: usize,
}

impl SignFlow {
    /// 解析 `E1 04` 的输入数据；`None` 表示结构不可用（回 `6A80`）。
    pub fn start(payload: &[u8]) -> Option<Self> {
        let mut reader = Reader::new(payload);
        let global_size = reader.varint()?;
        let global_keys = reader.array32()?;
        let global_vals = reader.array32()?;
        let n_inputs = u32::try_from(reader.varint()?).ok()?;
        let inputs_root = reader.array32()?;
        let n_outputs = u32::try_from(reader.varint()?).ok()?;
        let outputs_root = reader.array32()?;
        let wallet_id = reader.array32()?;
        let hmac = reader.take(32)?;
        if !reader.is_empty() {
            return None;
        }
        // 只支持默认钱包：hmac 必须全零。
        if hmac.iter().any(|byte| *byte != 0) {
            return None;
        }
        if n_inputs == 0
            || n_inputs as usize > MAX_INPUTS
            || n_outputs as usize > MAX_OUTPUTS
            || global_size == 0
            || global_size > MAX_MAP_ENTRIES
        {
            return None;
        }
        Some(Self {
            wallet_id,
            n_inputs,
            n_outputs,
            inputs_root,
            outputs_root,
            maps: vec![MapBuf {
                size: global_size,
                keys_root: global_keys,
                vals_root: global_vals,
                entries: Vec::new(),
            }],
            step: Step::Policy,
            gather: None,
            pending_leaf: [0u8; 32],
            pending_key: Vec::new(),
            policy: None,
            template_hash: None,
            map_cursor: 0,
            entry_cursor: 0,
            global_done: false,
            tx: None,
            prevouts: Vec::new(),
            jobs: Vec::new(),
            job_cursor: 0,
            operations: Vec::new(),
            signatures: Vec::new(),
            yield_cursor: 0,
        })
    }

    /// 下一个动作。调用方在每次投递/服务/审批之后重新调用。
    pub fn advance(&mut self) -> FlowAction {
        if self.gather.is_some() {
            return FlowAction::Request {
                bytes: vec![0xA0],
                expect: RequestKind::MoreElements,
            };
        }
        match self.step {
            Step::Policy => FlowAction::Request {
                bytes: preimage_request(&self.wallet_id),
                expect: RequestKind::Preimage,
            },
            Step::Template => match self.template_hash {
                Some(hash) => FlowAction::Request {
                    bytes: preimage_request(&hash),
                    expect: RequestKind::Preimage,
                },
                None => self.fail(crate::sw::WRONG_DATA),
            },
            Step::KeyProof => FlowAction::Request {
                bytes: leaf_proof_request(&self.keys_root(), 1, 0),
                expect: RequestKind::LeafProof,
            },
            Step::KeyInfo => FlowAction::Request {
                bytes: preimage_request(&self.pending_leaf),
                expect: RequestKind::Preimage,
            },
            Step::InputCommit(index) => FlowAction::Request {
                bytes: leaf_proof_request(&self.inputs_root, self.n_inputs as u64, index as u64),
                expect: RequestKind::LeafProof,
            },
            Step::InputCommitPreimage(_) => FlowAction::Request {
                bytes: preimage_request(&self.pending_leaf),
                expect: RequestKind::Preimage,
            },
            Step::OutputCommit(index) => FlowAction::Request {
                bytes: leaf_proof_request(&self.outputs_root, self.n_outputs as u64, index as u64),
                expect: RequestKind::LeafProof,
            },
            Step::OutputCommitPreimage(_) => FlowAction::Request {
                bytes: preimage_request(&self.pending_leaf),
                expect: RequestKind::Preimage,
            },
            Step::MapKeyProof => {
                let map = &self.maps[self.map_cursor];
                FlowAction::Request {
                    bytes: leaf_proof_request(&map.keys_root, map.size, self.entry_cursor),
                    expect: RequestKind::LeafProof,
                }
            }
            Step::MapKeyPreimage => FlowAction::Request {
                bytes: preimage_request(&self.pending_leaf),
                expect: RequestKind::Preimage,
            },
            Step::MapValueProof => {
                let map = &self.maps[self.map_cursor];
                FlowAction::Request {
                    bytes: leaf_proof_request(&map.vals_root, map.size, self.entry_cursor),
                    expect: RequestKind::LeafProof,
                }
            }
            Step::MapValuePreimage => FlowAction::Request {
                bytes: preimage_request(&self.pending_leaf),
                expect: RequestKind::Preimage,
            },
            Step::Verify => match self.build_jobs() {
                Ok(()) => {
                    self.job_cursor = 0;
                    self.step = Step::Derive;
                    self.advance()
                }
                Err(status) => self.fail(status),
            },
            Step::Derive => {
                if self.job_cursor >= self.jobs.len() {
                    self.step = Step::Review;
                    return self.advance();
                }
                let job = &self.jobs[self.job_cursor];
                FlowAction::NeedKey(PublicKeyRequest {
                    derivation_scheme: DerivationScheme::Bip32Secp256k1,
                    curve: Curve::Secp256k1,
                    path: job.path.clone(),
                    output: KeyOutput::CompressedSecp256k1,
                    include_chain_code: false,
                })
            }
            Step::Review => match self.build_review() {
                Ok(request) => FlowAction::Review(Box::new(request)),
                Err(status) => self.fail(status),
            },
            Step::Yield => {
                if self.yield_cursor >= self.operations.len() {
                    return self.fail(crate::sw::OK);
                }
                match self.yield_bytes(self.yield_cursor) {
                    Some(bytes) => FlowAction::Request {
                        bytes,
                        expect: RequestKind::Yield,
                    },
                    None => self.fail(crate::sw::UNKNOWN),
                }
            }
        }
    }

    /// 处理主机的 `F8 01` 应答。
    pub fn receive(&mut self, kind: RequestKind, data: &[u8]) -> Result<(), u16> {
        if let Some(gather) = self.gather.as_mut() {
            if kind != RequestKind::MoreElements {
                return Err(crate::sw::BAD_STATE);
            }
            let mut reader = Reader::new(data);
            let count = reader.u8().ok_or(crate::sw::WRONG_DATA)? as usize;
            let element_len = reader.u8().ok_or(crate::sw::WRONG_DATA)? as usize;
            if element_len != gather.element_len
                || count * element_len > reader.rest().len()
            {
                return Err(crate::sw::WRONG_DATA);
            }
            gather.data.extend_from_slice(&reader.rest()[..count * element_len]);
            if gather.data.len() >= gather.needed {
                let mut gather = self.gather.take().unwrap();
                gather.data.truncate(gather.needed);
                return match self.step {
                    Step::Policy
                    | Step::Template
                    | Step::KeyInfo
                    | Step::InputCommitPreimage(_)
                    | Step::OutputCommitPreimage(_)
                    | Step::MapKeyPreimage
                    | Step::MapValuePreimage => self.complete_preimage(gather.data),
                    _ => self.complete_leaf(gather.data),
                };
            }
            return Ok(());
        }

        match (kind, self.step) {
            (RequestKind::Preimage, _) => {
                let mut reader = Reader::new(data);
                let total = usize::try_from(reader.varint().ok_or(crate::sw::WRONG_DATA)?)
                    .map_err(|_| crate::sw::WRONG_DATA)?;
                let sent = reader.u8().ok_or(crate::sw::WRONG_DATA)? as usize;
                if sent > reader.rest().len() || sent > total {
                    return Err(crate::sw::WRONG_DATA);
                }
                let mut bytes = reader.rest()[..sent].to_vec();
                if sent < total {
                    self.gather = Some(Gather {
                        needed: total - sent,
                        element_len: 1,
                        data: std::mem::take(&mut bytes),
                    });
                    return Ok(());
                }
                self.complete_preimage(bytes)
            }
            (RequestKind::LeafProof, _) => {
                let mut reader = Reader::new(data);
                let leaf = reader.array32().ok_or(crate::sw::WRONG_DATA)?;
                let proof_len = reader.u8().ok_or(crate::sw::WRONG_DATA)? as usize;
                let count = reader.u8().ok_or(crate::sw::WRONG_DATA)? as usize;
                if count > proof_len || reader.rest().len() < count * 32 {
                    return Err(crate::sw::WRONG_DATA);
                }
                self.pending_leaf = leaf;
                let mut proof = reader.rest()[..count * 32].to_vec();
                if count < proof_len {
                    self.gather = Some(Gather {
                        needed: (proof_len - count) * 32,
                        element_len: 32,
                        data: std::mem::take(&mut proof),
                    });
                    return Ok(());
                }
                self.complete_leaf(proof)
            }
            (RequestKind::Yield, Step::Yield) => {
                if !data.is_empty() {
                    return Err(crate::sw::WRONG_DATA);
                }
                self.yield_cursor += 1;
                Ok(())
            }
            _ => Err(crate::sw::BAD_STATE),
        }
    }

    /// 宿主返回的公钥：先核对是不是 PSBT 里声称的那一个，再核对脚本。
    pub fn on_public_key(&mut self, bytes: &[u8]) -> Result<(), u16> {
        if self.step != Step::Derive || self.job_cursor >= self.jobs.len() {
            return Err(crate::sw::BAD_STATE);
        }
        let policy = self.policy.as_ref().ok_or(crate::sw::BAD_STATE)?;
        let job = &self.jobs[self.job_cursor];
        if bytes != job.pubkey.as_slice() {
            return Err(crate::sw::WRONG_DATA);
        }
        let expected = script_pubkey(policy.address_type, bytes).ok_or(crate::sw::WRONG_DATA)?;
        if expected != job.script {
            return Err(crate::sw::WRONG_DATA);
        }
        if let Some(index) = job.input {
            let digest = self.input_sighash(index, bytes)?;
            let hash_type = self.input_hash_type(index);
            self.operations.push(SignOperation {
                operation_id: index as u32 + 1,
                derivation_scheme: DerivationScheme::Bip32Secp256k1,
                curve: Curve::Secp256k1,
                path: job.path.clone(),
                scheme: if policy.address_type == AddressType::Taproot {
                    SignScheme::SchnorrTaprootKeyPath { hash_type }
                } else {
                    SignScheme::EcdsaPrehash {
                        digest_len: 32,
                        low_s: true,
                    }
                },
                input: digest.to_vec(),
                public_parameters: Vec::new(),
            });
        }
        self.job_cursor += 1;
        Ok(())
    }

    /// 审批结果：按 operation_id 对齐，进入逐个 YIELD。
    pub fn on_signatures(&mut self, signatures: Vec<Signature>) -> Result<(), u16> {
        if self.step != Step::Review {
            return Err(crate::sw::BAD_STATE);
        }
        self.signatures = (0..self.operations.len()).map(|_| None).collect();
        for signature in signatures {
            let slot = self
                .operations
                .iter()
                .position(|op| op.operation_id == signature.operation_id)
                .ok_or(crate::sw::UNKNOWN)?;
            self.signatures[slot] = Some(signature);
        }
        if self.signatures.iter().any(|slot| slot.is_none()) {
            return Err(crate::sw::UNKNOWN);
        }
        self.yield_cursor = 0;
        self.step = Step::Yield;
        Ok(())
    }

    fn fail(&self, status: u16) -> FlowAction {
        FlowAction::Finish(status.to_be_bytes().to_vec())
    }

    fn keys_root(&self) -> [u8; 32] {
        self.policy
            .as_ref()
            .map(|policy| policy.keys_root)
            .unwrap_or([0u8; 32])
    }

    // ── 应答完成后的状态推进 ──────────────────────────────────────────

    fn complete_preimage(&mut self, bytes: Vec<u8>) -> Result<(), u16> {
        match self.step {
            Step::Policy => {
                if sha256::hash(&bytes) != self.wallet_id {
                    return Err(crate::sw::WRONG_DATA);
                }
                let header =
                    parse_policy_header(&bytes).ok_or(crate::sw::WRONG_DATA)?;
                if header.name_len != 0 || header.key_count != 1 {
                    return Err(crate::sw::WRONG_DATA);
                }
                self.template_hash = Some(header.template_hash);
                self.policy = Some(Policy {
                    address_type: AddressType::NativeSegwit,
                    network: Network::Mainnet,
                    path: [0; 3],
                    keys_root: header.keys_root,
                });
                self.step = Step::Template;
            }
            Step::Template => {
                let text = std::str::from_utf8(&bytes).map_err(|_| crate::sw::WRONG_DATA)?;
                let address_type =
                    address_type_for_template(text).ok_or(crate::sw::WRONG_DATA)?;
                if let Some(policy) = self.policy.as_mut() {
                    policy.address_type = address_type;
                }
                self.step = Step::KeyProof;
            }
            Step::KeyInfo => {
                let info = bytes.strip_prefix(&[0x00]).ok_or(crate::sw::WRONG_DATA)?;
                let (_, path) = parse_key_origin(info).ok_or(crate::sw::WRONG_DATA)?;
                let policy = self.policy.as_mut().ok_or(crate::sw::BAD_STATE)?;
                let purpose = path[0] - 0x8000_0000;
                if purpose != policy.address_type.purpose() || path[2] < 0x8000_0000 {
                    return Err(crate::sw::WRONG_DATA);
                }
                if path[2] - 0x8000_0000 > 100 {
                    return Err(crate::sw::WRONG_DATA);
                }
                policy.network = match path[1] - 0x8000_0000 {
                    0 => Network::Mainnet,
                    1 => Network::Testnet,
                    _ => return Err(crate::sw::WRONG_DATA),
                };
                policy.path = path;
                // 先枚举 global map（tx_version / 计数 / locktime 都在里面）。
                self.map_cursor = 0;
                self.entry_cursor = 0;
                self.step = Step::MapKeyProof;
            }
            Step::InputCommitPreimage(index) => {
                let map = parse_commitment(
                    bytes.strip_prefix(&[0x00]).ok_or(crate::sw::WRONG_DATA)?,
                )
                .ok_or(crate::sw::WRONG_DATA)?;
                self.maps.push(map);
                let next = index + 1;
                self.step = if next < self.n_inputs {
                    Step::InputCommit(next)
                } else if self.n_outputs > 0 {
                    Step::OutputCommit(0)
                } else {
                    self.begin_entries()
                };
            }
            Step::OutputCommitPreimage(index) => {
                let map = parse_commitment(
                    bytes.strip_prefix(&[0x00]).ok_or(crate::sw::WRONG_DATA)?,
                )
                .ok_or(crate::sw::WRONG_DATA)?;
                self.maps.push(map);
                let next = index + 1;
                self.step = if next < self.n_outputs {
                    Step::OutputCommit(next)
                } else {
                    self.begin_entries()
                };
            }
            Step::MapKeyPreimage => {
                self.pending_key = bytes
                    .strip_prefix(&[0x00])
                    .ok_or(crate::sw::WRONG_DATA)?
                    .to_vec();
                self.step = Step::MapValueProof;
            }
            Step::MapValuePreimage => {
                let value = bytes
                    .strip_prefix(&[0x00])
                    .ok_or(crate::sw::WRONG_DATA)?
                    .to_vec();
                let key = std::mem::take(&mut self.pending_key);
                self.maps[self.map_cursor].entries.push((key, value));
                self.advance_entry();
            }
            _ => return Err(crate::sw::BAD_STATE),
        }
        Ok(())
    }

    fn complete_leaf(&mut self, proof: Vec<u8>) -> Result<(), u16> {
        let nodes: Vec<[u8; 32]> = proof.as_chunks::<32>().0.to_vec();
        let (root, size, index) = match self.step {
            Step::KeyProof => (self.keys_root(), 1, 0),
            Step::InputCommit(index) => (self.inputs_root, self.n_inputs as u64, index as u64),
            Step::OutputCommit(index) => (self.outputs_root, self.n_outputs as u64, index as u64),
            Step::MapKeyProof => (
                self.maps[self.map_cursor].keys_root,
                self.maps[self.map_cursor].size,
                self.entry_cursor,
            ),
            Step::MapValueProof => (
                self.maps[self.map_cursor].vals_root,
                self.maps[self.map_cursor].size,
                self.entry_cursor,
            ),
            _ => return Err(crate::sw::BAD_STATE),
        };
        if !verify_leaf(&root, size, index, &self.pending_leaf, &nodes) {
            return Err(crate::sw::WRONG_DATA);
        }
        self.step = match self.step {
            Step::KeyProof => Step::KeyInfo,
            Step::InputCommit(index) => Step::InputCommitPreimage(index),
            Step::OutputCommit(index) => Step::OutputCommitPreimage(index),
            Step::MapKeyProof => Step::MapKeyPreimage,
            Step::MapValueProof => Step::MapValuePreimage,
            _ => unreachable!(),
        };
        Ok(())
    }

    fn advance_entry(&mut self) {
        self.entry_cursor += 1;
        while self.map_cursor < self.maps.len()
            && self.entry_cursor >= self.maps[self.map_cursor].size
        {
            self.entry_cursor = 0;
            self.map_cursor += 1;
        }
        if self.map_cursor >= self.maps.len() {
            if !self.global_done {
                // global map 读完了，接着读输入/输出的 commit。
                self.global_done = true;
                self.map_cursor = 0;
                self.entry_cursor = 0;
                self.step = if self.n_inputs > 0 {
                    Step::InputCommit(0)
                } else if self.n_outputs > 0 {
                    Step::OutputCommit(0)
                } else {
                    Step::Verify
                };
            } else {
                self.step = Step::Verify;
            }
            return;
        }
        self.step = Step::MapKeyProof;
    }

    /// 读完所有 commit 之后，从头枚举输入/输出 map（跳过已经读过的 global）。
    fn begin_entries(&mut self) -> Step {
        self.map_cursor = 1;
        self.entry_cursor = 0;
        while self.map_cursor < self.maps.len() && self.maps[self.map_cursor].size == 0 {
            self.map_cursor += 1;
        }
        if self.map_cursor >= self.maps.len() {
            Step::Verify
        } else {
            Step::MapKeyProof
        }
    }

    // ── 解析并校验交易 ────────────────────────────────────────────────

    fn build_jobs(&mut self) -> Result<(), u16> {
        let policy = self.policy.as_ref().ok_or(crate::sw::BAD_STATE)?;
        let global = &self.maps[0];

        let tx_version = read_u32_le(global.get(&[GLOBAL_TX_VERSION]).ok_or(crate::sw::WRONG_DATA)?)
            .ok_or(crate::sw::WRONG_DATA)? as i32;
        let input_count = read_varint(global.get(&[GLOBAL_INPUT_COUNT]).ok_or(crate::sw::WRONG_DATA)?)
            .ok_or(crate::sw::WRONG_DATA)?;
        let output_count =
            read_varint(global.get(&[GLOBAL_OUTPUT_COUNT]).ok_or(crate::sw::WRONG_DATA)?)
                .ok_or(crate::sw::WRONG_DATA)?;
        if input_count != self.n_inputs as u64 || output_count != self.n_outputs as u64 {
            return Err(crate::sw::WRONG_DATA);
        }
        if let Some(version) = global.get(&[GLOBAL_VERSION]) {
            if read_u32_le(version) != Some(2) {
                return Err(crate::sw::WRONG_DATA);
            }
        }
        let lock_time = global
            .get(&[GLOBAL_FALLBACK_LOCKTIME])
            .map(|bytes| read_u32_le(bytes).ok_or(crate::sw::WRONG_DATA))
            .transpose()?
            .unwrap_or(0);

        let mut inputs = Vec::with_capacity(self.n_inputs as usize);
        let mut prevouts = Vec::with_capacity(self.n_inputs as usize);
        let mut jobs = Vec::new();

        for index in 0..self.n_inputs as usize {
            let map = &self.maps[1 + index];
            if map.get(&[IN_REQUIRED_TIME_LOCKTIME]).is_some()
                || map.get(&[IN_REQUIRED_HEIGHT_LOCKTIME]).is_some()
            {
                return Err(crate::sw::WRONG_DATA);
            }
            let txid = map
                .get(&[IN_PREVIOUS_TXID])
                .and_then(|bytes| <[u8; 32]>::try_from(bytes).ok())
                .ok_or(crate::sw::WRONG_DATA)?;
            let vout = read_u32_le(map.get(&[IN_OUTPUT_INDEX]).ok_or(crate::sw::WRONG_DATA)?)
                .ok_or(crate::sw::WRONG_DATA)?;
            let sequence = map
                .get(&[IN_SEQUENCE])
                .map(|bytes| read_u32_le(bytes).ok_or(crate::sw::WRONG_DATA))
                .transpose()?
                .unwrap_or(0xFFFF_FFFF);
            let prevout = previous_output(map, vout, &txid)?;
            inputs.push(psbt::TxIn {
                previous_output: psbt::OutPoint { txid, vout },
                script_sig: Vec::new(),
                sequence,
            });
            prevouts.push(prevout.clone());
            if let Some(derivation) = find_derivation(map, IN_BIP32_DERIVATION, &policy.path)? {
                jobs.push(DeriveJob {
                    input: Some(index),
                    change_output: None,
                    path: derivation.0,
                    pubkey: derivation.1,
                    script: prevout.script_pubkey,
                });
            }
        }

        let mut outputs = Vec::with_capacity(self.n_outputs as usize);
        for index in 0..self.n_outputs as usize {
            let map = &self.maps[1 + self.n_inputs as usize + index];
            let value = read_u64_le(map.get(&[OUT_AMOUNT]).ok_or(crate::sw::WRONG_DATA)?)
                .ok_or(crate::sw::WRONG_DATA)?;
            let script_pubkey = map
                .get(&[OUT_SCRIPT])
                .ok_or(crate::sw::WRONG_DATA)?
                .to_vec();
            outputs.push(TxOut {
                value,
                script_pubkey: script_pubkey.clone(),
            });
            if let Some(derivation) = find_derivation(map, OUT_BIP32_DERIVATION, &policy.path)? {
                // 只把 change=1 的输出当找零；change=0 出现在输出里意味着主机
                // 在隐藏一笔对外付款，直接拒绝。
                if derivation.0[3] != 0x8000_0000 + 1 && derivation.0[3] != 1 {
                    return Err(crate::sw::WRONG_DATA);
                }
                jobs.push(DeriveJob {
                    input: None,
                    change_output: Some(index),
                    path: derivation.0,
                    pubkey: derivation.1,
                    script: script_pubkey,
                });
            }
        }

        if jobs.iter().all(|job| job.input.is_none()) {
            // 没有任何属于本钱包的输入：没有可签的内容。
            return Err(crate::sw::WRONG_DATA);
        }

        let input_total: u64 = prevouts.iter().map(|out| out.value).sum();
        let output_total: u64 = outputs.iter().map(|out| out.value).sum();
        if output_total > input_total {
            return Err(crate::sw::WRONG_DATA);
        }

        self.tx = Some(Tx {
            version: tx_version,
            inputs,
            outputs,
            lock_time,
        });
        self.prevouts = prevouts;
        self.jobs = jobs;
        Ok(())
    }

    fn input_hash_type(&self, index: usize) -> u8 {
        let map = &self.maps[1 + index];
        map.get(&[IN_SIGHASH_TYPE])
            .and_then(read_u32_le)
            .map(|value| value as u8)
            .unwrap_or(0)
    }

    fn input_sighash(&self, index: usize, pubkey: &[u8]) -> Result<[u8; 32], u16> {
        let policy = self.policy.as_ref().ok_or(crate::sw::BAD_STATE)?;
        let tx = self.tx.as_ref().ok_or(crate::sw::BAD_STATE)?;
        let prevout = self.prevouts.get(index).ok_or(crate::sw::WRONG_DATA)?;
        let hash_type = self.input_hash_type(index);
        match policy.address_type {
            AddressType::Taproot => {
                bip341_sighash(tx, index, &self.prevouts, hash_type).ok_or(crate::sw::WRONG_DATA)
            }
            AddressType::NativeSegwit | AddressType::NestedSegwit => {
                if hash_type != 0 && hash_type != 1 {
                    return Err(crate::sw::WRONG_DATA);
                }
                let script_code = script_code_p2wpkh(pubkey);
                bip143_sighash(tx, index, &script_code, prevout.value, 1)
                    .ok_or(crate::sw::WRONG_DATA)
            }
            AddressType::Legacy => {
                if hash_type != 0 && hash_type != 1 {
                    return Err(crate::sw::WRONG_DATA);
                }
                legacy_sighash(tx, index, &prevout.script_pubkey, 1)
                    .ok_or(crate::sw::WRONG_DATA)
            }
        }
    }

    fn build_review(&self) -> Result<ReviewRequest, u16> {
        let policy = self.policy.as_ref().ok_or(crate::sw::BAD_STATE)?;
        let tx = self.tx.as_ref().ok_or(crate::sw::BAD_STATE)?;
        let network_name = policy.network.display_name();

        let mut fields = Vec::new();
        let mut change_value: u64 = 0;
        for (index, output) in tx.outputs.iter().enumerate() {
            let change = self
                .jobs
                .iter()
                .any(|job| job.change_output == Some(index));
            if change {
                change_value += output.value;
                continue;
            }
            fields.push(Field {
                label_key: "review.field.to".into(),
                value: FieldValue::Address {
                    value: display_script(&output.script_pubkey, policy.network),
                    network: network_name.into(),
                    role: "recipient".into(),
                },
            });
            fields.push(Field {
                label_key: "review.field.amount".into(),
                value: FieldValue::Amount {
                    raw: output.value.to_string(),
                    decimals: 8,
                    asset: "BTC".into(),
                    ticker: Some("BTC".into()),
                },
            });
        }
        let input_total: u64 = self.prevouts.iter().map(|out| out.value).sum();
        let output_total: u64 = tx.outputs.iter().map(|out| out.value).sum();
        let fee = input_total - output_total;
        fields.push(Field {
            label_key: "review.field.fee".into(),
            value: FieldValue::Fee {
                kind: FeeKind::Known,
                raw: Some(fee.to_string()),
                decimals: 8,
                asset: "BTC".into(),
            },
        });
        fields.push(Field {
            label_key: "review.field.inputs".into(),
            value: FieldValue::Text {
                value: tx.inputs.len().to_string(),
            },
        });
        if change_value > 0 {
            fields.push(Field {
                label_key: "review.field.change".into(),
                value: FieldValue::Amount {
                    raw: change_value.to_string(),
                    decimals: 8,
                    asset: "BTC".into(),
                    ticker: Some("BTC".into()),
                },
            });
        }
        fields.push(Field {
            label_key: "review.field.fee_rate".into(),
            value: FieldValue::Text {
                value: format!("{} sat/vB", fee_rate(tx, policy.address_type, fee)),
            },
        });
        if tx.inputs.iter().any(|input| input.sequence < 0xFFFF_FFFE) {
            fields.push(Field {
                label_key: "review.field.rbf".into(),
                value: FieldValue::Text { value: "yes".into() },
            });
        }
        if tx.lock_time != 0 {
            fields.push(Field {
                label_key: "review.field.locktime".into(),
                value: FieldValue::Text {
                    value: tx.lock_time.to_string(),
                },
            });
        }

        let account = self
            .jobs
            .iter()
            .find(|job| job.input.is_some())
            .and_then(|job| policy.address_type.encode(&job.pubkey, policy.network));

        Ok(ReviewRequest {
            document: ReviewDocument {
                operation: OperationKind::Transaction,
                network: NetworkId {
                    name: network_name.into(),
                    chain_id: None,
                },
                account,
                sections: vec![ReviewSection {
                    title_key: "review.section.bitcoin".into(),
                    fields,
                }],
                risks: vec![Risk {
                    code: "bitcoin.psbt".into(),
                    severity: RiskLevel::Info,
                    parameters: vec![(
                        "policy".into(),
                        policy.address_type.as_str().into(),
                    )],
                    source: RiskSource::Module,
                }],
                parse_status: ParseStatus::Complete,
            },
            action: ReviewAction::Sign(SignPlan {
                operations: self.operations.clone(),
            }),
        })
    }

    fn yield_bytes(&self, cursor: usize) -> Option<Vec<u8>> {
        let operation = self.operations.get(cursor)?;
        let signature = self.signatures.get(cursor)?.as_ref()?;
        if signature.bytes.len() != 64 {
            return None;
        }
        let input_index = (operation.operation_id - 1) as usize;
        let job = self.jobs.iter().find(|job| job.input == Some(input_index))?;
        let policy = self.policy.as_ref()?;

        let mut payload = vec![0x10];
        write_varint(&mut payload, input_index as u64);
        if policy.address_type == AddressType::Taproot {
            payload.push(32);
            payload.extend_from_slice(&job.pubkey[1..]);
            payload.extend_from_slice(&signature.bytes);
            let hash_type = match operation.scheme {
                SignScheme::SchnorrTaprootKeyPath { hash_type } => hash_type,
                _ => return None,
            };
            if hash_type != 0 {
                payload.push(hash_type);
            }
        } else {
            payload.push(33);
            payload.extend_from_slice(&job.pubkey);
            payload.extend_from_slice(&psbt::der_encode(&signature.bytes)?);
            payload.push(1);
        }
        Some(payload)
    }
}

// ── 小工具 ──────────────────────────────────────────────────────────────

fn preimage_request(hash: &[u8; 32]) -> Vec<u8> {
    let mut out = Vec::with_capacity(34);
    out.push(0x40);
    out.push(0x00);
    out.extend_from_slice(hash);
    out
}

fn leaf_proof_request(root: &[u8; 32], size: u64, index: u64) -> Vec<u8> {
    let mut out = Vec::with_capacity(48);
    out.push(0x41);
    out.extend_from_slice(root);
    write_varint(&mut out, size);
    write_varint(&mut out, index);
    out
}

fn parse_commitment(bytes: &[u8]) -> Option<MapBuf> {
    let mut reader = Reader::new(bytes);
    let size = reader.varint()?;
    if size > MAX_MAP_ENTRIES {
        return None;
    }
    let keys_root = reader.array32()?;
    let vals_root = reader.array32()?;
    if !reader.is_empty() {
        return None;
    }
    Some(MapBuf {
        size,
        keys_root,
        vals_root,
        entries: Vec::new(),
    })
}

fn read_u32_le(bytes: &[u8]) -> Option<u32> {
    (bytes.len() == 4).then(|| u32::from_le_bytes(bytes.try_into().unwrap()))
}

fn read_u64_le(bytes: &[u8]) -> Option<u64> {
    (bytes.len() == 8).then(|| u64::from_le_bytes(bytes.try_into().unwrap()))
}

fn read_varint(bytes: &[u8]) -> Option<u64> {
    let mut reader = Reader::new(bytes);
    let value = reader.varint()?;
    if !reader.is_empty() {
        return None;
    }
    Some(value)
}

fn varint_len(value: u64) -> u64 {
    match value {
        0..=0xFC => 1,
        0xFD..=0xFFFF => 3,
        0x1_0000..=0xFFFF_FFFF => 5,
        _ => 9,
    }
}

/// 签名前的最终 `vsize` 上界估算。
///
/// 审阅发生在签名之前，拿不到真实的 DER 长度，因此按最坏情况计：
/// ECDSA 用 72 字节 DER（实际 70–72），`scriptSig` / witness 的推入前缀
/// 各算 1 字节。费率是给人看的量级判断，不做逐字节承诺。
fn estimated_vsize(tx: &Tx, address_type: AddressType) -> u64 {
    let mut base = 4 + varint_len(tx.inputs.len() as u64);
    let mut witness = 0u64;
    for input in &tx.inputs {
        base += 36 + varint_len(input.script_sig.len() as u64) + 4;
        base += input.script_sig.len() as u64;
        match address_type {
            // P2PKH scriptSig：`push(sig)` + `push(pubkey)`。
            AddressType::Legacy => base += 1 + 73 + 1 + 33,
            // 嵌套 SegWit：scriptSig 只放 22 字节 redeemScript。
            AddressType::NestedSegwit => {
                base += 1 + 22;
                witness += 1 + (1 + 73) + (1 + 33);
            }
            AddressType::NativeSegwit => witness += 1 + (1 + 73) + (1 + 33),
            // taproot key-path：只有一个 64 字节 Schnorr 签名。
            AddressType::Taproot => witness += 1 + (1 + 64),
        }
    }
    for output in &tx.outputs {
        base += 8 + varint_len(output.script_pubkey.len() as u64);
        base += output.script_pubkey.len() as u64;
    }
    base += 4; // nLockTime
    let weight = base * 4 + witness;
    weight.div_ceil(4)
}

fn fee_rate(tx: &Tx, address_type: AddressType, fee: u64) -> u64 {
    let vsize = estimated_vsize(tx, address_type).max(1);
    // 四舍五入，避免 1.5 被截成 1。
    (fee + vsize / 2) / vsize
}

/// `PSBT_IN_WITNESS_UTXO` 优先；没有就解析 `PSBT_IN_NON_WITNESS_UTXO`，
/// 并校验它确实就是 `prev_txid` 指向的那笔交易。
fn previous_output(map: &MapBuf, vout: u32, prev_txid: &[u8; 32]) -> Result<TxOut, u16> {
    if let Some(bytes) = map.get(&[IN_WITNESS_UTXO]) {
        let mut reader = Reader::new(bytes);
        let value = reader.u64_le().ok_or(crate::sw::WRONG_DATA)?;
        let script_pubkey = reader.var_bytes().ok_or(crate::sw::WRONG_DATA)?.to_vec();
        if !reader.is_empty() {
            return Err(crate::sw::WRONG_DATA);
        }
        return Ok(TxOut {
            value,
            script_pubkey,
        });
    }
    let raw = map.get(&[IN_NON_WITNESS_UTXO]).ok_or(crate::sw::WRONG_DATA)?;
    let tx = Tx::parse(raw).ok_or(crate::sw::WRONG_DATA)?;
    if &tx.txid() != prev_txid {
        return Err(crate::sw::WRONG_DATA);
    }
    tx.outputs
        .get(vout as usize)
        .cloned()
        .ok_or(crate::sw::WRONG_DATA)
}

/// 在 map 里找「属于本钱包」的派生条目：`key = tag || pubkey`，
/// `value = fingerprint(4) || path(4×n)`，路径分量按 BIP-174 是小端。
type DerivationEntry = (Vec<u32>, Vec<u8>);

fn find_derivation(
    map: &MapBuf,
    tag: u8,
    policy_path: &[u32; 3],
) -> Result<Option<DerivationEntry>, u16> {
    for (key, value) in &map.entries {
        if key.len() != 34 || key[0] != tag {
            continue;
        }
        if value.len() < 4 || (value.len() - 4) % 4 != 0 {
            continue;
        }
        let mut path = Vec::with_capacity((value.len() - 4) / 4);
        for chunk in value[4..].as_chunks::<4>().0 {
            path.push(u32::from_le_bytes(*chunk));
        }
        // 前缀必须是策略来源；后面只能有 change 与 index 两段。
        if path.len() != 5 || path[..3] != policy_path[..] {
            continue;
        }
        if path[4] >= 0x8000_0000 {
            return Err(crate::sw::WRONG_DATA);
        }
        return Ok(Some((path, key[1..].to_vec())));
    }
    Ok(None)
}

/// 把常见 `scriptPubKey` 渲染成地址；认不出时回退成十六进制。
fn display_script(script: &[u8], network: Network) -> String {
    match script {
        [0x76, 0xA9, 0x14, hash @ .., 0x88, 0xAC] if hash.len() == 20 => {
            let mut payload = Vec::with_capacity(21);
            payload.push(network.p2pkh_version());
            payload.extend_from_slice(hash);
            base58::encode_check(&payload)
        }
        [0xA9, 0x14, hash @ .., 0x87] if hash.len() == 20 => {
            let mut payload = Vec::with_capacity(21);
            payload.push(network.p2sh_version());
            payload.extend_from_slice(hash);
            base58::encode_check(&payload)
        }
        [0x00, 0x14, program @ ..] if program.len() == 20 => {
            bech32::encode(network.hrp(), 0, program)
        }
        [0x00, 0x20, program @ ..] if program.len() == 32 => {
            bech32::encode(network.hrp(), 0, program)
        }
        [0x51, 0x20, program @ ..] if program.len() == 32 => {
            bech32::encode_segwit(network.hrp(), 1, program)
        }
        _ => hex::encode(script),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn minimal_header() -> Vec<u8> {
        let mut data = Vec::new();
        write_varint(&mut data, 1); // global map size
        data.extend_from_slice(&[0x11; 32]);
        data.extend_from_slice(&[0x22; 32]);
        write_varint(&mut data, 1); // n_inputs
        data.extend_from_slice(&[0x33; 32]);
        write_varint(&mut data, 2); // n_outputs
        data.extend_from_slice(&[0x44; 32]);
        data.extend_from_slice(&[0x55; 32]); // wallet_id
        data.extend_from_slice(&[0u8; 32]); // hmac
        data
    }

    #[test]
    fn start_accepts_the_minimal_header_and_asks_for_the_policy() {
        let data = minimal_header();
        let mut flow = SignFlow::start(&data).expect("header must parse");
        match flow.advance() {
            FlowAction::Request { bytes, expect } => {
                assert_eq!(expect, RequestKind::Preimage);
                assert_eq!(bytes[0], 0x40);
                assert_eq!(&bytes[2..34], &[0x55; 32]);
            }
            _ => panic!("expected a preimage request"),
        }
    }

    #[test]
    fn start_rejects_a_non_zero_wallet_hmac() {
        let mut data = minimal_header();
        let last = data.len() - 1;
        data[last] = 0x01;
        assert!(SignFlow::start(&data).is_none());
    }
}
