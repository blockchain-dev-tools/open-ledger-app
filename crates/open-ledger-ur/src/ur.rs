//! UR 编码：把已经规范化（dCBOR）的字节编成 Keystone 主机能扫的帧。

use bc_ur::prelude::*;
use open_ledger_biz::errors::{ChainError, Result};

/// 单帧与多帧的分界：二维码版本越高越难扫，60 个字符是 Keystone 的常用值。
pub const DEFAULT_FRAGMENT_LEN: usize = 60;

fn ur_error(message: String) -> ChainError {
    ChainError::ParseError(message)
}

/// 把 dCBOR 字节包成 `ur:<type>` 帧。
///
/// `fragment_len == 0` 时返回单帧字符串；否则按该长度切出一轮纯分片，调用方循环播放。
/// **不输出 fountain 组合帧**：参考解码器能用，但 OKX 插件会把 `seq > total` 的帧
/// 丢弃/中断，导致进度永远停在 99%。
/// 非规范化 CBOR 会在这里被 `CBOR::try_from_data` 拒绝——主机只接受 dCBOR。
pub fn encode_frames(ur_type: &str, cbor: &[u8], fragment_len: usize) -> Result<Vec<String>> {
    let cbor = CBOR::try_from_data(cbor).map_err(|e| ur_error(format!("dCBOR: {e}")))?;
    let ur = UR::new(ur_type, cbor).map_err(|e| ur_error(format!("UR type: {e}")))?;
    if fragment_len == 0 {
        return Ok(vec![ur.string()]);
    }
    let mut encoder =
        MultipartEncoder::new(&ur, fragment_len).map_err(|e| ur_error(format!("UR encode: {e}")))?;
    let count = encoder.parts_count();
    let mut frames = Vec::with_capacity(count);
    for _ in 0..count {
        frames.push(
            encoder
                .next_part()
                .map_err(|e| ur_error(format!("UR frame: {e}")))?,
        );
    }
    Ok(frames)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_non_canonical_cbor() {
        // Map keys out of canonical order (1 then 0) must be refused by dCBOR.
        let bad = [0xa2, 0x01, 0x01, 0x00, 0x01];
        assert!(encode_frames("test", &bad, 0).is_err());
    }

    #[test]
    fn single_frame_has_no_indices() {
        let frames = encode_frames("eth-signature", &[0xa0], 0).unwrap();
        assert_eq!(frames.len(), 1);
        assert!(frames[0].starts_with("ur:eth-signature/"));
        assert!(!frames[0].contains("/1-1/"));
    }

    #[test]
    fn multipart_frames_round_trip() {
        // 11-byte CBOR map; a 4-byte fragment budget forces three parts.
        let cbor = [
            0xa2, 0x01, 0x18, 0x2a, 0x02, 0x45, b'h', b'e', b'l', b'l', b'o',
        ];
        let frames = encode_frames("test", &cbor, 4).unwrap();
        assert!(frames.len() > 1);
        assert!(frames[0].contains("/1-"));

        let mut decoder = MultipartDecoder::new();
        for frame in &frames {
            decoder.receive(frame).unwrap();
        }
        assert!(decoder.is_complete());
        let message = decoder.message().unwrap().expect("complete message");
        assert_eq!(message.cbor().to_cbor_data(), cbor);
    }

    /// `ur:<type>/<seq>-<total>/<data>` → (seq, total)
    fn seq_total(frame: &str) -> (usize, usize) {
        let header = frame.split('/').nth(1).expect("header");
        let (seq, total) = header.split_once('-').expect("seq-total");
        (seq.parse().unwrap(), total.parse().unwrap())
    }

    #[test]
    fn only_pure_parts_are_emitted() {
        let cbor = [
            0xa2, 0x01, 0x18, 0x2a, 0x02, 0x45, b'h', b'e', b'l', b'l', b'o',
        ];
        let frames = encode_frames("test", &cbor, 4).unwrap();
        let (_, total) = seq_total(&frames[0]);
        assert_eq!(frames.len(), total);
        for (offset, frame) in frames.iter().enumerate() {
            let (seq, frame_total) = seq_total(frame);
            assert_eq!(seq, offset + 1);
            assert_eq!(frame_total, total);
        }

        // 少一帧就解不出来——这是有意的取舍（OKX 不认组合帧）。
        let mut decoder = MultipartDecoder::new();
        for frame in frames.iter().skip(1) {
            decoder.receive(frame).unwrap();
        }
        assert!(!decoder.is_complete());
    }
}
