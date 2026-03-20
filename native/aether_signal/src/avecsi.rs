//! AveCSI — CSI Frame Stabilization
//!
//! Sliding window average across CSI frames to reduce temporal noise.
//! Validated in CSIPose (IEEE TMC 2025) for through-wall pose estimation.
//!
//! The key insight: CSI frames have high-frequency noise from multipath,
//! but the signal component changes slowly (human movement ~1-10Hz).
//! Averaging over a window of frames preserves the signal while
//! suppressing noise by sqrt(N).

/// Compute stabilized CSI frame as sliding window average.
///
/// `frames`: list of CSI frames, each frame is a flat vec of subcarrier values.
/// `window`: number of most recent frames to average over.
///
/// Returns a single averaged frame.
pub fn stabilize(frames: &[Vec<f64>], window: usize) -> Vec<f64> {
    if frames.is_empty() {
        return vec![];
    }

    let frame_len = frames[0].len();
    if frame_len == 0 {
        return vec![];
    }

    let n = frames.len();
    let w = window.min(n);
    let start = n - w;

    let mut avg = vec![0.0; frame_len];
    let mut count = 0;

    for frame in &frames[start..] {
        let len = frame.len().min(frame_len);
        for i in 0..len {
            avg[i] += frame[i];
        }
        count += 1;
    }

    if count > 0 {
        let inv = 1.0 / count as f64;
        for val in &mut avg {
            *val *= inv;
        }
    }

    avg
}

/// Weighted AveCSI: exponential moving average with decay factor.
/// More recent frames contribute more to the average.
/// `alpha` in [0, 1]: higher = more weight on recent frames.
#[allow(dead_code)]
pub fn stabilize_ema(frames: &[Vec<f64>], alpha: f64) -> Vec<f64> {
    if frames.is_empty() {
        return vec![];
    }

    let frame_len = frames[0].len();
    let mut ema = frames[0].clone();

    for frame in &frames[1..] {
        let len = frame.len().min(frame_len);
        for i in 0..len {
            ema[i] = alpha * frame[i] + (1.0 - alpha) * ema[i];
        }
    }

    ema
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_stabilize_averages_correctly() {
        let frames = vec![
            vec![1.0, 2.0, 3.0],
            vec![3.0, 4.0, 5.0],
            vec![5.0, 6.0, 7.0],
        ];
        let result = stabilize(&frames, 3);
        assert_eq!(result.len(), 3);
        assert!((result[0] - 3.0).abs() < 1e-10); // (1+3+5)/3
        assert!((result[1] - 4.0).abs() < 1e-10); // (2+4+6)/3
        assert!((result[2] - 5.0).abs() < 1e-10); // (3+5+7)/3
    }

    #[test]
    fn test_stabilize_window_smaller_than_frames() {
        let frames = vec![
            vec![0.0, 0.0],
            vec![10.0, 10.0],
            vec![20.0, 20.0],
            vec![30.0, 30.0],
        ];
        // Window of 2: average last 2 frames only
        let result = stabilize(&frames, 2);
        assert!((result[0] - 25.0).abs() < 1e-10); // (20+30)/2
        assert!((result[1] - 25.0).abs() < 1e-10);
    }

    #[test]
    fn test_ema_weights_recent_more() {
        let frames = vec![
            vec![0.0],  // old
            vec![0.0],  // old
            vec![10.0], // recent
        ];
        let result = stabilize_ema(&frames, 0.9);
        // With alpha=0.9, the result should be close to 10.0
        assert!(result[0] > 5.0, "EMA should weight recent: {}", result[0]);
    }
}
