//! PSBTv2（BIP-370）解析、Merkle 证明校验与 Bitcoin 签名摘要。
//!
//! 只做纯计算：不发起宿主要求、不接触 seed。`lib.rs` 的流程用这里的结果拼出
//! 审阅文档与签名计划。
//!
//! 覆盖范围（M2）：默认单密钥钱包 —— `pkh(@0/**)` / `sh(wpkh(@0/**))` /
//! `wpkh(@0/**)` / `tr(@0/**)`，sighash 只接受 `DEFAULT` / `ALL`。

use open_ledger_crypto::{hash160, secp256k1, sha256, sha256d};

use crate::AddressType;

// ── PSBTv2 字段编号（BIP-370） ──────────────────────────────────────────

pub const GLOBAL_TX_VERSION: u8 = 0x02;
pub const GLOBAL_FALLBACK_LOCKTIME: u8 = 0x03;
pub const GLOBAL_INPUT_COUNT: u8 = 0x04;
pub const GLOBAL_OUTPUT_COUNT: u8 = 0x05;
pub const GLOBAL_VERSION: u8 = 0xFB;

pub const IN_NON_WITNESS_UTXO: u8 = 0x00;
pub const IN_WITNESS_UTXO: u8 = 0x01;
pub const IN_SIGHASH_TYPE: u8 = 0x03;
pub const IN_REDEEM_SCRIPT: u8 = 0x04;
pub const IN_WITNESS_SCRIPT: u8 = 0x05;
pub const IN_BIP32_DERIVATION: u8 = 0x06;
pub const IN_PREVIOUS_TXID: u8 = 0x0E;
pub const IN_OUTPUT_INDEX: u8 = 0x0F;
pub const IN_SEQUENCE: u8 = 0x10;
pub const IN_REQUIRED_TIME_LOCKTIME: u8 = 0x11;
pub const IN_REQUIRED_HEIGHT_LOCKTIME: u8 = 0x12;

pub const OUT_REDEEM_SCRIPT: u8 = 0x00;
pub const OUT_WITNESS_SCRIPT: u8 = 0x01;
pub const OUT_BIP32_DERIVATION: u8 = 0x02;
pub const OUT_AMOUNT: u8 = 0x03;
pub const OUT_SCRIPT: u8 = 0x04;

/// 只实现的 sighash：`DEFAULT`（taproot）与 `ALL`。
pub const SIGHASH_DEFAULT: u8 = 0x00;
pub const SIGHASH_ALL: u8 = 0x01;

// ── 字节读取 ────────────────────────────────────────────────────────────

/// 只前进不分配的游标；越界一律返回 `None`。
pub struct Reader<'a> {
    data: &'a [u8],
    pos: usize,
}

impl<'a> Reader<'a> {
    pub fn new(data: &'a [u8]) -> Self {
        Self { data, pos: 0 }
    }

    pub fn rest(&self) -> &'a [u8] {
        &self.data[self.pos..]
    }

    pub fn is_empty(&self) -> bool {
        self.pos == self.data.len()
    }

    pub fn take(&mut self, count: usize) -> Option<&'a [u8]> {
        let end = self.pos.checked_add(count)?;
        if end > self.data.len() {
            return None;
        }
        let slice = &self.data[self.pos..end];
        self.pos = end;
        Some(slice)
    }

    pub fn u8(&mut self) -> Option<u8> {
        self.take(1).map(|slice| slice[0])
    }

    pub fn u32_le(&mut self) -> Option<u32> {
        self.take(4).map(|slice| u32::from_le_bytes(slice.try_into().unwrap()))
    }

    pub fn u64_le(&mut self) -> Option<u64> {
        self.take(8).map(|slice| u64::from_le_bytes(slice.try_into().unwrap()))
    }

    pub fn array32(&mut self) -> Option<[u8; 32]> {
        self.take(32).map(|slice| slice.try_into().unwrap())
    }

    /// Bitcoin CompactSize。
    pub fn varint(&mut self) -> Option<u64> {
        let first = self.u8()?;
        Some(match first {
            0xFD => u16::from_le_bytes(self.take(2)?.try_into().unwrap()) as u64,
            0xFE => u32::from_le_bytes(self.take(4)?.try_into().unwrap()) as u64,
            0xFF => u64::from_le_bytes(self.take(8)?.try_into().unwrap()),
            value => value as u64,
        })
    }

    /// `varint(len) || bytes`。
    pub fn var_bytes(&mut self) -> Option<&'a [u8]> {
        let len = usize::try_from(self.varint()?).ok()?;
        self.take(len)
    }
}

pub fn write_varint(out: &mut Vec<u8>, value: u64) {
    match value {
        0..=0xFC => out.push(value as u8),
        0xFD..=0xFFFF => {
            out.push(0xFD);
            out.extend_from_slice(&(value as u16).to_le_bytes());
        }
        0x1_0000..=0xFFFF_FFFF => {
            out.push(0xFE);
            out.extend_from_slice(&(value as u32).to_le_bytes());
        }
        _ => {
            out.push(0xFF);
            out.extend_from_slice(&value.to_le_bytes());
        }
    }
}

// ── Merkle（官方 `merkle.md`：左完全树） ─────────────────────────────────

pub fn element_hash(element: &[u8]) -> [u8; 32] {
    let mut buffer = Vec::with_capacity(1 + element.len());
    buffer.push(0x00);
    buffer.extend_from_slice(element);
    sha256::hash(&buffer)
}

fn combine(left: &[u8; 32], right: &[u8; 32]) -> [u8; 32] {
    let mut buffer = [0u8; 65];
    buffer[0] = 0x01;
    buffer[1..33].copy_from_slice(left);
    buffer[33..].copy_from_slice(right);
    sha256::hash(&buffer)
}

fn largest_power_of_two_less_than(n: u64) -> u64 {
    if n.is_power_of_two() {
        n / 2
    } else {
        1u64 << (63 - n.leading_zeros())
    }
}

/// 用叶子哈希 + 证明重算根，校验该叶子确实在 `root` 下。
///
/// 树的形状是官方的「左完全树」：左子树取 `< n` 的最大 2 的幂。
/// 证明按官方顺序给出：叶子向上，因此最深层在 `proof[0]`。
pub fn verify_leaf(
    root: &[u8; 32],
    size: u64,
    index: u64,
    leaf: &[u8; 32],
    proof: &[[u8; 32]],
) -> bool {
    if size == 0 || index >= size {
        return false;
    }
    // 先从根往下算出每一层走左还是走右，再自底向上合成。
    let mut directions = Vec::new();
    let mut remaining = size;
    let mut position = index;
    while remaining > 1 {
        let left_size = largest_power_of_two_less_than(remaining);
        if position < left_size {
            directions.push(true);
            remaining = left_size;
        } else {
            directions.push(false);
            remaining -= left_size;
            position -= left_size;
        }
    }
    if directions.len() != proof.len() {
        return false;
    }
    let mut node = *leaf;
    for (level, goes_left) in directions.iter().enumerate().rev() {
        let sibling = &proof[proof.len() - 1 - level];
        node = if *goes_left {
            combine(&node, sibling)
        } else {
            combine(sibling, &node)
        };
    }
    node == *root
}

// ── 钱包策略（BIP-388） ─────────────────────────────────────────────────

/// 序列化策略里我们需要的部分。
pub struct PolicyHeader {
    pub name_len: u64,
    pub template_len: u64,
    pub template_hash: [u8; 32],
    pub key_count: u64,
    pub keys_root: [u8; 32],
}

/// 解析 `wallet.serialize()`；只接受版本 2。
pub fn parse_policy_header(bytes: &[u8]) -> Option<PolicyHeader> {
    let mut reader = Reader::new(bytes);
    if reader.u8()? != 0x02 {
        return None;
    }
    let name_len = reader.u8()? as u64;
    reader.take(usize::try_from(name_len).ok()?)?;
    let template_len = reader.varint()?;
    let template_hash = reader.array32()?;
    let key_count = reader.varint()?;
    let keys_root = reader.array32()?;
    if !reader.is_empty() {
        return None;
    }
    Some(PolicyHeader {
        name_len,
        template_len,
        template_hash,
        key_count,
        keys_root,
    })
}

/// 四种默认单密钥模板 → 地址类型。
pub(crate) fn address_type_for_template(template: &str) -> Option<AddressType> {
    match template {
        "pkh(@0/**)" => Some(AddressType::Legacy),
        "sh(wpkh(@0/**))" => Some(AddressType::NestedSegwit),
        "wpkh(@0/**)" => Some(AddressType::NativeSegwit),
        "tr(@0/**)" => Some(AddressType::Taproot),
        _ => None,
    }
}

/// 解析 `[fingerprint/purpose'/coin'/account']xpub…` 的来源路径。
///
/// 只认 3 段全硬化；指纹与 xpub 文本本身不参与签名校验（签名锚定在脚本上）。
pub fn parse_key_origin(key_info: &[u8]) -> Option<(u32, [u32; 3])> {
    let text = std::str::from_utf8(key_info).ok()?;
    let rest = text.strip_prefix('[')?;
    let (origin, _xpub) = rest.split_once(']')?;
    let mut parts = origin.split('/');
    let fingerprint = u32::from_str_radix(parts.next()?, 16).ok()?;
    let segments: Vec<&str> = parts.collect();
    if segments.len() != 3 {
        return None;
    }
    let mut path = [0u32; 3];
    for (slot, text) in path.iter_mut().zip(segments) {
        let value = text.strip_suffix('\'')?;
        *slot = 0x8000_0000 + value.parse::<u32>().ok()?;
    }
    Some((fingerprint, path))
}

// ── 脚本 ────────────────────────────────────────────────────────────────

/// 由压缩公钥得到该地址类型的 `scriptPubKey`。
pub(crate) fn script_pubkey(address_type: AddressType, compressed: &[u8]) -> Option<Vec<u8>> {
    if compressed.len() != 33 {
        return None;
    }
    Some(match address_type {
        AddressType::Legacy => {
            let mut script = Vec::with_capacity(25);
            script.extend_from_slice(&[0x76, 0xA9, 0x14]);
            script.extend_from_slice(&hash160::hash(compressed));
            script.extend_from_slice(&[0x88, 0xAC]);
            script
        }
        AddressType::NestedSegwit => {
            let mut inner = Vec::with_capacity(22);
            inner.extend_from_slice(&[0x00, 0x14]);
            inner.extend_from_slice(&hash160::hash(compressed));
            let mut script = Vec::with_capacity(23);
            script.extend_from_slice(&[0xA9, 0x14]);
            script.extend_from_slice(&hash160::hash(&inner));
            script.push(0x87);
            script
        }
        AddressType::NativeSegwit => {
            let mut script = Vec::with_capacity(22);
            script.extend_from_slice(&[0x00, 0x14]);
            script.extend_from_slice(&hash160::hash(compressed));
            script
        }
        AddressType::Taproot => {
            let output_key = secp256k1::taproot_output_key(&compressed[1..]).ok()?;
            let mut script = Vec::with_capacity(34);
            script.extend_from_slice(&[0x51, 0x20]);
            script.extend_from_slice(&output_key);
            script
        }
    })
}

/// BIP-143 的 scriptCode（P2WPKH，嵌套 SegWit 相同）。
///
/// 返回 25 字节脚本本体；长度前缀由 [`bip143_sighash`] 追加。
pub fn script_code_p2wpkh(compressed: &[u8]) -> Vec<u8> {
    let mut script = Vec::with_capacity(25);
    script.extend_from_slice(&[0x76, 0xA9, 0x14]);
    script.extend_from_slice(&hash160::hash(compressed));
    script.extend_from_slice(&[0x88, 0xAC]);
    script
}

// ── 交易 ────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OutPoint {
    pub txid: [u8; 32],
    pub vout: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TxIn {
    pub previous_output: OutPoint,
    pub script_sig: Vec<u8>,
    pub sequence: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TxOut {
    pub value: u64,
    pub script_pubkey: Vec<u8>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Tx {
    pub version: i32,
    pub inputs: Vec<TxIn>,
    pub outputs: Vec<TxOut>,
    pub lock_time: u32,
}

impl Tx {
    /// 解析完整交易（含可选 witness），用于 `PSBT_IN_NON_WITNESS_UTXO`。
    pub fn parse(bytes: &[u8]) -> Option<Self> {
        let mut reader = Reader::new(bytes);
        let version = reader.u32_le()? as i32;
        let mut witness = false;
        let input_count = {
            let marker = reader.rest().first().copied()?;
            if marker == 0x00 {
                if reader.u8()? != 0x00 {
                    return None;
                }
                if reader.u8()? != 0x01 {
                    return None;
                }
                witness = true;
                reader.varint()?
            } else {
                reader.varint()?
            }
        };
        let mut inputs = Vec::with_capacity(usize::try_from(input_count).ok()?);
        for _ in 0..input_count {
            let txid = reader.array32()?;
            let vout = reader.u32_le()?;
            let script_sig = reader.var_bytes()?.to_vec();
            let sequence = reader.u32_le()?;
            inputs.push(TxIn {
                previous_output: OutPoint { txid, vout },
                script_sig,
                sequence,
            });
        }
        let output_count = reader.varint()?;
        let mut outputs = Vec::with_capacity(usize::try_from(output_count).ok()?);
        for _ in 0..output_count {
            let value = reader.u64_le()?;
            let script_pubkey = reader.var_bytes()?.to_vec();
            outputs.push(TxOut {
                value,
                script_pubkey,
            });
        }
        if witness {
            for _ in 0..inputs.len() {
                let items = reader.varint()?;
                for _ in 0..items {
                    reader.var_bytes()?;
                }
            }
        }
        let lock_time = reader.u32_le()?;
        Some(Self {
            version,
            inputs,
            outputs,
            lock_time,
        })
    }

    /// 交易 ID（内部字节序），用于校验 `non_witness_utxo`。
    pub fn txid(&self) -> [u8; 32] {
        let empty = vec![Vec::new(); self.inputs.len()];
        sha256d::hash(&self.serialize_with(&empty))
    }

    /// 序列化（不含 witness）；`script_sigs` 替换输入的 scriptSig。
    fn serialize_with(&self, script_sigs: &[Vec<u8>]) -> Vec<u8> {
        let mut out = Vec::new();
        out.extend_from_slice(&self.version.to_le_bytes());
        write_varint(&mut out, self.inputs.len() as u64);
        for (input, script_sig) in self.inputs.iter().zip(script_sigs) {
            out.extend_from_slice(&input.previous_output.txid);
            out.extend_from_slice(&input.previous_output.vout.to_le_bytes());
            write_varint(&mut out, script_sig.len() as u64);
            out.extend_from_slice(script_sig);
            out.extend_from_slice(&input.sequence.to_le_bytes());
        }
        write_varint(&mut out, self.outputs.len() as u64);
        for output in &self.outputs {
            out.extend_from_slice(&output.value.to_le_bytes());
            write_varint(&mut out, output.script_pubkey.len() as u64);
            out.extend_from_slice(&output.script_pubkey);
        }
        out.extend_from_slice(&self.lock_time.to_le_bytes());
        out
    }
}

/// 交易在签名时的骨架：全部 scriptSig 为空。
pub fn tx_for_signing(tx: &Tx) -> Tx {
    let mut copy = tx.clone();
    for input in &mut copy.inputs {
        input.script_sig.clear();
    }
    copy
}

// ── sighash ─────────────────────────────────────────────────────────────

/// 传统 P2PKH：把第 `index` 个输入的 scriptSig 换成 scriptCode，追加 4 字节
/// little-endian sighash type，再做 double-SHA256。
pub fn legacy_sighash(tx: &Tx, index: usize, script_code: &[u8], sighash_type: u32) -> Option<[u8; 32]> {
    if index >= tx.inputs.len() {
        return None;
    }
    let mut script_sigs = vec![Vec::new(); tx.inputs.len()];
    script_sigs[index] = script_code.to_vec();
    let mut body = tx_for_signing(tx).serialize_with(&script_sigs);
    body.extend_from_slice(&sighash_type.to_le_bytes());
    Some(sha256d::hash(&body))
}

fn outpoint_bytes(input: &TxIn) -> [u8; 36] {
    let mut out = [0u8; 36];
    out[..32].copy_from_slice(&input.previous_output.txid);
    out[32..].copy_from_slice(&input.previous_output.vout.to_le_bytes());
    out
}

fn txout_bytes(output: &TxOut) -> Vec<u8> {
    let mut out = Vec::with_capacity(8 + 1 + output.script_pubkey.len());
    out.extend_from_slice(&output.value.to_le_bytes());
    write_varint(&mut out, output.script_pubkey.len() as u64);
    out.extend_from_slice(&output.script_pubkey);
    out
}

/// BIP-143（SegWit v0）。
pub fn bip143_sighash(
    tx: &Tx,
    index: usize,
    script_code: &[u8],
    amount: u64,
    sighash_type: u32,
) -> Option<[u8; 32]> {
    if index >= tx.inputs.len() {
        return None;
    }
    let mut prevouts = Vec::with_capacity(tx.inputs.len() * 36);
    let mut sequences = Vec::with_capacity(tx.inputs.len() * 4);
    for input in &tx.inputs {
        prevouts.extend_from_slice(&outpoint_bytes(input));
        sequences.extend_from_slice(&input.sequence.to_le_bytes());
    }
    let mut outputs = Vec::new();
    for output in &tx.outputs {
        outputs.extend_from_slice(&txout_bytes(output));
    }
    let input = &tx.inputs[index];
    let mut preimage = Vec::with_capacity(156 + script_code.len());
    preimage.extend_from_slice(&tx.version.to_le_bytes());
    preimage.extend_from_slice(&sha256d::hash(&prevouts));
    preimage.extend_from_slice(&sha256d::hash(&sequences));
    preimage.extend_from_slice(&outpoint_bytes(input));
    write_varint(&mut preimage, script_code.len() as u64);
    preimage.extend_from_slice(script_code);
    preimage.extend_from_slice(&amount.to_le_bytes());
    preimage.extend_from_slice(&input.sequence.to_le_bytes());
    preimage.extend_from_slice(&sha256d::hash(&outputs));
    preimage.extend_from_slice(&tx.lock_time.to_le_bytes());
    preimage.extend_from_slice(&sighash_type.to_le_bytes());
    Some(sha256d::hash(&preimage))
}

/// BIP-341 key-path，只支持 `DEFAULT` / `ALL`（不带 ANYONECANPAY）。
///
/// `prevouts` 必须覆盖全部输入（金额 + scriptPubKey），这是非 ANYONECANPAY
/// 摘要的前提。
pub fn bip341_sighash(
    tx: &Tx,
    index: usize,
    prevouts: &[TxOut],
    hash_type: u8,
) -> Option<[u8; 32]> {
    if index >= tx.inputs.len() || prevouts.len() != tx.inputs.len() {
        return None;
    }
    if hash_type != SIGHASH_DEFAULT && hash_type != SIGHASH_ALL {
        return None;
    }
    let mut prevout_bytes = Vec::with_capacity(tx.inputs.len() * 36);
    let mut amounts = Vec::with_capacity(tx.inputs.len() * 8);
    let mut scripts = Vec::new();
    let mut sequences = Vec::with_capacity(tx.inputs.len() * 4);
    for (input, prevout) in tx.inputs.iter().zip(prevouts) {
        prevout_bytes.extend_from_slice(&outpoint_bytes(input));
        amounts.extend_from_slice(&prevout.value.to_le_bytes());
        write_varint(&mut scripts, prevout.script_pubkey.len() as u64);
        scripts.extend_from_slice(&prevout.script_pubkey);
        sequences.extend_from_slice(&input.sequence.to_le_bytes());
    }
    let mut outputs = Vec::new();
    for output in &tx.outputs {
        outputs.extend_from_slice(&txout_bytes(output));
    }

    let mut body = Vec::new();
    body.push(hash_type);
    body.extend_from_slice(&tx.version.to_le_bytes());
    body.extend_from_slice(&tx.lock_time.to_le_bytes());
    body.extend_from_slice(&sha256::hash(&prevout_bytes));
    body.extend_from_slice(&sha256::hash(&amounts));
    body.extend_from_slice(&sha256::hash(&scripts));
    body.extend_from_slice(&sha256::hash(&sequences));
    body.extend_from_slice(&sha256::hash(&outputs));
    body.push(0x00); // spend_type：无 annex、key-path
    body.extend_from_slice(&(index as u32).to_le_bytes());
    Some(secp256k1::tagged_hash("TapSighash", &[&[0x00], &body]))
}

// ── DER ─────────────────────────────────────────────────────────────────

fn der_integer(value: &[u8]) -> Vec<u8> {
    let mut start = 0;
    while start + 1 < value.len() && value[start] == 0x00 && value[start + 1] & 0x80 == 0 {
        start += 1;
    }
    let trimmed = &value[start..];
    let mut out = Vec::with_capacity(trimmed.len() + 3);
    out.push(0x02);
    if trimmed[0] & 0x80 != 0 {
        out.push(trimmed.len() as u8 + 1);
        out.push(0x00);
        out.extend_from_slice(trimmed);
    } else {
        out.push(trimmed.len() as u8);
        out.extend_from_slice(trimmed);
    }
    out
}

/// 64 字节紧凑签名（r‖s）→ DER。
pub fn der_encode(compact: &[u8]) -> Option<Vec<u8>> {
    if compact.len() != 64 {
        return None;
    }
    let r = der_integer(&compact[..32]);
    let s = der_integer(&compact[32..]);
    let mut out = Vec::with_capacity(r.len() + s.len() + 2);
    out.push(0x30);
    out.push((r.len() + s.len()) as u8);
    out.extend_from_slice(&r);
    out.extend_from_slice(&s);
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 官方 `merkle.md` 的构造规则：叶子 `sha256(0x00‖el)`，内部
    /// `sha256(0x01‖l‖r)`，左子树取 `< n` 的最大 2 的幂。
    fn build_tree(elements: &[&[u8]]) -> (u64, Vec<[u8; 32]>) {
        let leaves: Vec<[u8; 32]> = elements.iter().map(|el| element_hash(el)).collect();
        (leaves.len() as u64, leaves)
    }

    fn root_of(leaves: &[[u8; 32]], begin: usize, size: usize) -> [u8; 32] {
        if size == 1 {
            return leaves[begin];
        }
        let left = largest_power_of_two_less_than(size as u64) as usize;
        combine(
            &root_of(leaves, begin, left),
            &root_of(leaves, begin + left, size - left),
        )
    }

    fn proof_of(leaves: &[[u8; 32]], begin: usize, size: usize, index: usize) -> Vec<[u8; 32]> {
        if size == 1 {
            return Vec::new();
        }
        let left = largest_power_of_two_less_than(size as u64) as usize;
        if index < left {
            let mut proof = proof_of(leaves, begin, left, index);
            proof.push(root_of(leaves, begin + left, size - left));
            proof
        } else {
            let mut proof = proof_of(leaves, begin + left, size - left, index - left);
            proof.push(root_of(leaves, begin, left));
            proof
        }
    }

    #[test]
    fn merkle_proofs_verify_for_every_leaf_and_odd_sizes() {
        for count in 1..=9usize {
            let elements: Vec<Vec<u8>> = (0..count)
                .map(|i| format!("element-{i}").into_bytes())
                .collect();
            let refs: Vec<&[u8]> = elements.iter().map(|el| el.as_slice()).collect();
            let (size, leaves) = build_tree(&refs);
            let root = root_of(&leaves, 0, count);
            for index in 0..count {
                let proof = proof_of(&leaves, 0, count, index);
                assert!(
                    verify_leaf(&root, size, index as u64, &leaves[index], &proof),
                    "count={count} index={index}"
                );
                // 篡改任何一片叶子都必须失败
                let mut wrong = leaves[index];
                wrong[0] ^= 0x01;
                assert!(!verify_leaf(&root, size, index as u64, &wrong, &proof));
            }
        }
    }

    #[test]
    fn compact_size_round_trips() {
        for value in [0u64, 0xFC, 0xFD, 0xFFFF, 0x1_0000, u32::MAX as u64, 1 << 40] {
            let mut out = Vec::new();
            write_varint(&mut out, value);
            assert_eq!(Reader::new(&out).varint(), Some(value));
        }
    }

    #[test]
    fn policy_header_parses_the_official_layout() {
        let template = b"wpkh(@0/**)";
        let mut policy = vec![0x02, 0x00];
        write_varint(&mut policy, template.len() as u64);
        policy.extend_from_slice(&sha256::hash(template));
        write_varint(&mut policy, 1);
        policy.extend_from_slice(&[0xAB; 32]);

        let header = parse_policy_header(&policy).unwrap();
        assert_eq!(header.name_len, 0);
        assert_eq!(header.template_len, template.len() as u64);
        assert_eq!(header.template_hash, sha256::hash(template));
        assert_eq!(header.key_count, 1);
        assert_eq!(header.keys_root, [0xAB; 32]);
    }

    #[test]
    fn key_origin_requires_three_hardened_segments() {
        let (fingerprint, path) =
            parse_key_origin(b"[73c5da0a/84'/0'/0']xpub6CatWdiZiodmUeTDp8LT5or8nmbKNcuyvz7WyksVFkKB4RHwCD3XyuvPEbvqAQY3rAPshWcMLoP2fMFMKHPJ4ZeZXYVUhLv1VMrjPC7PW6V").unwrap();
        assert_eq!(fingerprint, 0x73c5da0a);
        assert_eq!(path, [0x8000_0054, 0x8000_0000, 0x8000_0000]);
        assert!(parse_key_origin(b"[73c5da0a/84'/0']xpub").is_none());
        assert!(parse_key_origin(b"xpub6Cat").is_none());
    }

    #[test]
    fn script_pubkey_matches_the_four_default_types() {
        let pubkey = hex::decode(
            "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798",
        )
        .unwrap();
        assert_eq!(
            hex::encode(script_pubkey(AddressType::NativeSegwit, &pubkey).unwrap()),
            "0014751e76e8199196d454941c45d1b3a323f1433bd6"
        );
        assert_eq!(
            hex::encode(script_pubkey(AddressType::Legacy, &pubkey).unwrap()),
            "76a914751e76e8199196d454941c45d1b3a323f1433bd688ac"
        );
        // BIP-86 官方向量：内部键 x-only cc8a4bc6… → 输出键 a60869f0…
        let mut pubkey = vec![0x02];
        pubkey.extend_from_slice(
            &hex::decode("cc8a4bc64d897bddc5fbc2f670f7a8ba0b386779106cf1223c6fc5d7cd6fc115")
                .unwrap(),
        );
        assert_eq!(
            hex::encode(script_pubkey(AddressType::Taproot, &pubkey).unwrap()),
            "5120a60869f0dbcf1dc659c9cecbaf8050135ea9e8cdc487053f1dc6880949dc684c"
        );
    }

    #[test]
    fn der_encoding_matches_known_boundaries() {
        // r 最高位为 1 时要补 0x00，s 的前导零要去掉。
        let mut compact = vec![0u8; 64];
        compact[0] = 0x80;
        compact[32] = 0x00;
        compact[33] = 0x7F;
        let der = der_encode(&compact).unwrap();
        assert_eq!(der[0], 0x30);
        // r = 0x80… → 补 0x00 后 33 字节
        assert_eq!(&der[2..4], &[0x02, 0x21]);
        assert_eq!(der[4], 0x00);
        // s = 0x00 0x7F… → 去掉前导零后 31 字节
        assert_eq!(&der[37..39], &[0x02, 0x1F]);
    }

    #[test]
    fn bip143_matches_the_bip_vector() {
        // BIP-143 官方向量（P2WPKH，sighash ALL）。
        let unsigned = hex::decode(
            "0100000002fff7f7881a8099afa6940d42d1e7f6362bec38171ea3edf433541db4e4ad969f0000000000eeffffffef51e1b804cc89d182d279655c3aa89e815b1b309fe287d9b2b55d57b90ec68a0100000000ffffffff02202cb206000000001976a9148280b37df378db99f66f85c95a783a76ac7a6d5988ac9093510d000000001976a9143bde42dbee7e4dbe6a21b2d50ce2f0167faa815988ac11000000",
        )
        .unwrap();
        let tx = Tx::parse(&unsigned).unwrap();
        let script_code = hex::decode("76a9141d0f172a0ecb48aee1be1f2687d2963ae33f71a188ac").unwrap();
        let sighash = bip143_sighash(&tx, 1, &script_code, 600000000, 1).unwrap();
        assert_eq!(
            hex::encode(sighash),
            "c37af31116d1b27caf68aae9e3ac82f1477929014d5b917657d0eb49478cb670"
        );
    }

    #[test]
    fn bip341_only_accepts_default_and_all() {
        let tx = Tx {
            version: 2,
            inputs: vec![TxIn {
                previous_output: OutPoint {
                    txid: [0x11; 32],
                    vout: 0,
                },
                script_sig: Vec::new(),
                sequence: 0xFFFF_FFFD,
            }],
            outputs: vec![TxOut {
                value: 50_000,
                script_pubkey: vec![0x51, 0x20, 0x22, 0x33],
            }],
            lock_time: 0,
        };
        let prevout = TxOut {
            value: 100_000,
            script_pubkey: vec![0x51, 0x20, 0x44, 0x55],
        };
        assert!(bip341_sighash(&tx, 0, &[prevout.clone()], SIGHASH_DEFAULT).is_some());
        assert!(bip341_sighash(&tx, 0, &[prevout.clone()], SIGHASH_ALL).is_some());
        // SINGLE / ANYONECANPAY 不在本期
        assert!(bip341_sighash(&tx, 0, &[prevout.clone()], 0x03).is_none());
        assert!(bip341_sighash(&tx, 0, &[prevout.clone()], 0x81).is_none());
        // 缺 prevout 或越界输入
        assert!(bip341_sighash(&tx, 0, &[], SIGHASH_DEFAULT).is_none());
        assert!(bip341_sighash(&tx, 3, &[prevout], SIGHASH_DEFAULT).is_none());
    }

    #[test]
    fn bip341_commits_to_prevout_amounts() {
        let tx = Tx {
            version: 2,
            inputs: vec![TxIn {
                previous_output: OutPoint {
                    txid: [0x11; 32],
                    vout: 1,
                },
                script_sig: Vec::new(),
                sequence: 0,
            }],
            outputs: vec![],
            lock_time: 0,
        };
        let script = vec![0x00, 0x14, 0xAA, 0xBB];
        let first = bip341_sighash(
            &tx,
            0,
            &[TxOut {
                value: 1,
                script_pubkey: script.clone(),
            }],
            SIGHASH_DEFAULT,
        )
        .unwrap();
        let second = bip341_sighash(
            &tx,
            0,
            &[TxOut {
                value: 2,
                script_pubkey: script,
            }],
            SIGHASH_DEFAULT,
        )
        .unwrap();
        assert_ne!(first, second);
    }
}
