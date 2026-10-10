//! 常量时间比较原语。
//!
//! 用于 PIN 哈希等敏感值的比较：运行时间只与输入长度有关，与内容无关，
//! 从而避免基于「首先在哪一字节不匹配」的时序侧信道。

/// 逐字节比较两个切片，**不短路**。
///
/// 返回 `true` 当且仅当 `a == b`。长度差异被折叠进累加结果而非提前返回，
/// 越界位置以 0 补齐，因此比较耗时只取决于 `max(a.len(), b.len())`，
/// 不泄漏「第几字节开始不同」。
pub fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    // 长度差异（用 usize 避免 `len as u8` 在长度差为 256 倍数时被截断为 0）。
    let mut diff: usize = a.len() ^ b.len();
    let len = a.len().max(b.len());
    for i in 0..len {
        // get() 越界时返回 0：短的那一侧补零继续比较，不提前退出。
        let x = a.get(i).copied().unwrap_or(0) as usize;
        let y = b.get(i).copied().unwrap_or(0) as usize;
        diff |= x ^ y;
    }
    diff == 0
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::hint::black_box;
    use std::time::{Duration, Instant};

    #[test]
    fn equal_returns_true() {
        assert!(constant_time_eq(b"same", b"same"));
        assert!(constant_time_eq(b"", b""));
        assert!(constant_time_eq(&[0u8; 32], &[0u8; 32]));
    }

    #[test]
    fn different_content_returns_false() {
        assert!(!constant_time_eq(b"same", b"diff"));
        // 仅最后一字节不同也要能检出（防止只比较首字节的错误实现）
        let mut a = [0u8; 32];
        let mut b = [0u8; 32];
        a[31] = 1;
        b[31] = 2;
        assert!(!constant_time_eq(&a, &b));
    }

    #[test]
    fn different_length_returns_false() {
        assert!(!constant_time_eq(b"short", b"much-longer"));
        // 前缀相同但长度不同，必须为 false
        assert!(!constant_time_eq(b"abc", b"abcd"));
        assert!(!constant_time_eq(b"abcd", b"abc"));
    }

    /// 抽查：耗时与「第几字节开始不同」无关。
    ///
    /// 若实现短路，前缀不匹配会远快于后缀不匹配（约 32 倍），此处用宽松的
    /// 10x 阈值即可稳定区分，不会因 CI 负载产生假阴性。
    #[test]
    fn timing_independent_of_content_spot_check() {
        let base = [0xabu8; 32];
        let mut early_diff = base;
        early_diff[0] ^= 0x01; // 第 0 字节即不同
        let mut late_diff = base;
        late_diff[31] ^= 0x01; // 最后一字节才不同

        const ITERS: u32 = 300_000;
        let measure = |other: &[u8]| -> Duration {
            let start = Instant::now();
            for _ in 0..ITERS {
                black_box(constant_time_eq(black_box(&base), black_box(other)));
            }
            start.elapsed()
        };

        let _ = measure(&early_diff); // warmup
        let _ = measure(&late_diff);
        let t_early = measure(&early_diff);
        let t_late = measure(&late_diff);

        let (fast, slow) = if t_early < t_late {
            (t_early, t_late)
        } else {
            (t_late, t_early)
        };
        // fast 可能为 0（理论下限），做保护后比较。
        let fast_ns = fast.as_nanos().max(1);
        let ratio = slow.as_nanos() as f64 / fast_ns as f64;
        assert!(
            ratio < 10.0,
            "timing gap too large ({t_early:?} vs {t_late:?}, ratio={ratio:.2}); \
             possible early-exit (non constant-time) comparison",
        );
    }
}
