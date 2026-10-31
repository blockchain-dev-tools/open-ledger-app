//! Ledger Block Protocol（官方 `app-sui` 的**全部**命令都套这一层）。
//!
//! 依据 `LedgerHQ/app-sui` `docs/block-protocol.md` 与 `tests/application_client/client.py`：
//!
//! - APDU data 首字节是 HostToLedger 指令，其后是负载；
//! - 设备回包首字节是 LedgerToHost 指令，其后是负载，状态字固定 `9000`；
//! - 每个参数按 180 字节切块，块 = `sha256(下一块) || 本块数据`，
//!   最后一块的「下一块哈希」为 32 个 0；
//! - `START` 的负载是每个参数**首块**的哈希按顺序拼接。
//!
//! 官方客户端连 `GET_VERSION` 都走这条路径（参数是一个 1 字节的占位），
//! 所以这里不是「大交易才用」的可选分块，而是唯一的命令入口。

use open_ledger_crypto::sha256;

/// 主机 → 设备（APDU data 首字节）。
pub const HOST_START: u8 = 0x00;
pub const HOST_GET_CHUNK_SUCCESS: u8 = 0x01;
pub const HOST_GET_CHUNK_FAILURE: u8 = 0x02;
pub const HOST_PUT_CHUNK_RESPONSE: u8 = 0x03;
pub const HOST_RESULT_ACCUMULATING_RESPONSE: u8 = 0x04;

/// 设备 → 主机（APDU 回包首字节）。
pub const REPLY_ACCUMULATING: u8 = 0x00;
pub const REPLY_FINAL: u8 = 0x01;
pub const REPLY_GET_CHUNK: u8 = 0x02;
pub const REPLY_PUT_CHUNK: u8 = 0x03;

pub const HASH_LEN: usize = 32;
pub const CHUNK_SIZE: usize = 180;
/// 官方 `SIGN_TX` 最多三个参数（交易、路径、对象表）。
pub const MAX_PARAMS: usize = 3;
/// 单参数累计上限，防止主机用无限分块拖死设备。
pub const MAX_PARAM_LEN: usize = 8 * 1024;

const ZERO_HASH: [u8; HASH_LEN] = [0u8; HASH_LEN];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BlockError {
    /// 指令/参数个数不合法（官方 `SW_CLA_OR_INS_NOT_SUPPORTED` 一族）。
    Unexpected,
    /// 长度不合法或超出预算。
    BadLen,
    /// 哈希校验失败，或主机报告缺失该块。
    Integrity,
}

/// 一次 `START`/`GET_CHUNK` 之后的下一步。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Progress {
    /// 还需要主机提供这个哈希对应的块。
    NeedChunk([u8; HASH_LEN]),
    /// 所有参数已收齐。
    Complete,
}

/// 一条命令的参数收集状态；跨多个 APDU 存活。
pub struct Request {
    params: Vec<Vec<u8>>,
    hashes: Vec<[u8; HASH_LEN]>,
    current: usize,
    requested: Option<[u8; HASH_LEN]>,
}

impl Request {
    /// 处理 `START`：只记录各参数首块哈希，返回第一个请求。
    pub fn start(data: &[u8]) -> Result<(Self, Progress), BlockError> {
        if data.is_empty() || data[0] != HOST_START {
            return Err(BlockError::Unexpected);
        }
        let payload = &data[1..];
        if payload.is_empty() || payload.len() % HASH_LEN != 0 {
            return Err(BlockError::BadLen);
        }
        let count = payload.len() / HASH_LEN;
        if count > MAX_PARAMS {
            return Err(BlockError::BadLen);
        }
        let mut hashes = Vec::with_capacity(count);
        for chunk in payload.chunks_exact(HASH_LEN) {
            let mut hash = [0u8; HASH_LEN];
            hash.copy_from_slice(chunk);
            hashes.push(hash);
        }
        let first = hashes[0];
        Ok((
            Self {
                params: vec![Vec::new(); count],
                hashes,
                current: 0,
                requested: Some(first),
            },
            Progress::NeedChunk(first),
        ))
    }

    /// 处理 `GET_CHUNK_RESPONSE_*`；`data` 含指令字节。
    pub fn receive(&mut self, data: &[u8]) -> Result<Progress, BlockError> {
        let Some(instruction) = data.first().copied() else {
            return Err(BlockError::BadLen);
        };
        match instruction {
            HOST_GET_CHUNK_SUCCESS => {}
            // 主机明确表示拿不到数据：不是协议错乱，但也没有可签的内容。
            HOST_GET_CHUNK_FAILURE => return Err(BlockError::Integrity),
            _ => return Err(BlockError::Unexpected),
        }
        let requested = self.requested.ok_or(BlockError::Unexpected)?;
        let block = &data[1..];
        if block.len() <= HASH_LEN || block.len() > HASH_LEN + CHUNK_SIZE {
            return Err(BlockError::BadLen);
        }
        if sha256::hash(block) != requested {
            return Err(BlockError::Integrity);
        }
        let mut next = [0u8; HASH_LEN];
        next.copy_from_slice(&block[..HASH_LEN]);
        let chunk = &block[HASH_LEN..];

        let param = &mut self.params[self.current];
        // 非末块必须满 180 字节，否则「下一块哈希」的链就没有意义。
        if next != ZERO_HASH && chunk.len() != CHUNK_SIZE {
            return Err(BlockError::BadLen);
        }
        if param.len() + chunk.len() > MAX_PARAM_LEN {
            return Err(BlockError::BadLen);
        }
        param.extend_from_slice(chunk);

        if next != ZERO_HASH {
            self.requested = Some(next);
            return Ok(Progress::NeedChunk(next));
        }
        self.current += 1;
        if self.current == self.params.len() {
            self.requested = None;
            return Ok(Progress::Complete);
        }
        let hash = self.hashes[self.current];
        self.requested = Some(hash);
        Ok(Progress::NeedChunk(hash))
    }

    pub fn params(&self) -> &[Vec<u8>] {
        &self.params
    }

    pub fn requested(&self) -> Option<[u8; HASH_LEN]> {
        self.requested
    }
}

/// `GET_CHUNK` 回包：指令 + 哈希。
pub fn get_chunk_reply(hash: &[u8; HASH_LEN]) -> Vec<u8> {
    let mut out = Vec::with_capacity(1 + HASH_LEN);
    out.push(REPLY_GET_CHUNK);
    out.extend_from_slice(hash);
    out
}

/// `RESULT_FINAL` 回包：指令 + 结果。
pub fn final_reply(payload: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(1 + payload.len());
    out.push(REPLY_FINAL);
    out.extend_from_slice(payload);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 独立构造一条参数链（与官方客户端 `#sendChunks` 同一算法）。
    fn chain(param: &[u8]) -> (Vec<u8>, Vec<([u8; 32], Vec<u8>)>) {
        let mut blocks = Vec::new();
        let mut last = ZERO_HASH;
        for chunk in param.chunks(CHUNK_SIZE).collect::<Vec<_>>().into_iter().rev() {
            let mut block = Vec::with_capacity(HASH_LEN + chunk.len());
            block.extend_from_slice(&last);
            block.extend_from_slice(chunk);
            last = sha256::hash(&block);
            blocks.push((last, block));
        }
        (last.to_vec(), blocks)
    }

    #[test]
    fn single_chunk_round_trip() {
        let param = b"\x05hello".to_vec();
        let (first_hash, blocks) = chain(&param);
        let mut start = vec![HOST_START];
        start.extend_from_slice(&first_hash);
        let (mut request, progress) = Request::start(&start).unwrap();
        assert_eq!(progress, Progress::NeedChunk(blocks[0].0));

        let mut reply = vec![HOST_GET_CHUNK_SUCCESS];
        reply.extend_from_slice(&blocks[0].1);
        assert_eq!(request.receive(&reply).unwrap(), Progress::Complete);
        assert_eq!(request.params(), &[param]);
    }

    #[test]
    fn multi_chunk_round_trip() {
        let param: Vec<u8> = (0..400u32).map(|i| (i % 251) as u8).collect();
        let (first_hash, blocks) = chain(&param);
        let mut start = vec![HOST_START];
        start.extend_from_slice(&first_hash);
        let (mut request, _) = Request::start(&start).unwrap();
        // `chain()` 按「从尾到头」生成，这里反转成主机发送顺序。
        let ordered: Vec<([u8; 32], Vec<u8>)> = blocks.into_iter().rev().collect();
        for (index, (_, block)) in ordered.iter().enumerate() {
            let mut reply = vec![HOST_GET_CHUNK_SUCCESS];
            reply.extend_from_slice(block);
            let progress = request.receive(&reply).unwrap();
            if index + 1 == ordered.len() {
                assert_eq!(progress, Progress::Complete);
            } else {
                assert_eq!(progress, Progress::NeedChunk(ordered[index + 1].0));
            }
        }
        assert_eq!(request.params(), &[param]);
    }

    #[test]
    fn hash_mismatch_is_rejected() {
        let (first_hash, blocks) = chain(b"payload");
        let mut start = vec![HOST_START];
        start.extend_from_slice(&first_hash);
        let (mut request, _) = Request::start(&start).unwrap();
        let mut reply = vec![HOST_GET_CHUNK_SUCCESS];
        reply.extend_from_slice(&blocks[0].1);
        let last = reply.len() - 1;
        reply[last] ^= 0xFF;
        assert_eq!(request.receive(&reply), Err(BlockError::Integrity));
    }

    #[test]
    fn too_many_params_are_rejected() {
        let mut start = vec![HOST_START];
        start.extend_from_slice(&[0u8; HASH_LEN * (MAX_PARAMS + 1)]);
        assert_eq!(Request::start(&start).err(), Some(BlockError::BadLen));
    }
}
