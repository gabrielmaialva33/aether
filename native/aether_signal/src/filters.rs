//! Signal processing filters for CSI data.
//!
//! - Hampel: robust outlier detection via median absolute deviation
//! - Butterworth: IIR bandpass filter for frequency isolation
//! - Savitzky-Golay: polynomial smoothing preserving signal shape

use std::cmp::Ordering;

// ─── Hampel Filter ──────────────────────────────────────────────────────────

/// Hampel filter: replace outliers with local median.
/// Uses Median Absolute Deviation (MAD) as robust scale estimator.
/// Points where |x - median| > threshold * 1.4826 * MAD are replaced.
pub fn hampel(data: &[f64], window: usize, threshold: f64) -> Vec<f64> {
    let n = data.len();
    let mut result = data.to_vec();

    for i in 0..n {
        let start = i.saturating_sub(window);
        let end = (i + window + 1).min(n);

        let mut window_data: Vec<f64> = data[start..end].to_vec();
        sort_floats(&mut window_data);

        let median = window_data[window_data.len() / 2];

        let mut deviations: Vec<f64> = window_data.iter().map(|x| (x - median).abs()).collect();
        sort_floats(&mut deviations);

        let mad = 1.4826 * deviations[deviations.len() / 2];

        if mad > 1e-10 && (data[i] - median).abs() > threshold * mad {
            result[i] = median;
        }
    }

    result
}

// ─── Butterworth Bandpass ───────────────────────────────────────────────────

/// Second-order Butterworth bandpass filter via bilinear transform.
/// Cascades `order/2` biquad sections for numerical stability.
pub fn butterworth_bp(
    data: &[f64],
    order: usize,
    low_hz: f64,
    high_hz: f64,
    sample_rate: f64,
) -> Vec<f64> {
    let nyquist = sample_rate / 2.0;
    let low = low_hz / nyquist;
    let high = high_hz / nyquist;

    if low >= high || low <= 0.0 || high >= 1.0 {
        return data.to_vec();
    }

    // Pre-warp frequencies for bilinear transform
    let w_low = (std::f64::consts::PI * low).tan();
    let w_high = (std::f64::consts::PI * high).tan();
    let bw = w_high - w_low;
    let w0 = (w_low * w_high).sqrt();

    // Design biquad coefficients for 2nd-order bandpass
    let q = w0 / bw;
    let alpha = (0.5 / q).min(0.999);

    let b0 = alpha;
    let b1 = 0.0;
    let b2 = -alpha;
    let a0 = 1.0 + alpha;
    let a1 = -2.0 * (w0 * w0 - 1.0) / (1.0 + w0 * w0);
    let a2 = (1.0 - alpha) / a0;

    let b0 = b0 / a0;
    let b1 = b1 / a0;
    let b2 = b2 / a0;
    let a1 = a1 / a0;
    let a2_n = a2;

    // Apply biquad sections (cascade for higher orders)
    let sections = (order / 2).max(1);
    let mut output = data.to_vec();

    for _ in 0..sections {
        output = apply_biquad(&output, b0, b1, b2, a1, a2_n);
        // Zero-phase: apply in reverse direction too
        output.reverse();
        output = apply_biquad(&output, b0, b1, b2, a1, a2_n);
        output.reverse();
    }

    output
}

/// Apply a single biquad (second-order IIR) section.
/// Direct Form II Transposed for numerical stability.
fn apply_biquad(data: &[f64], b0: f64, b1: f64, b2: f64, a1: f64, a2: f64) -> Vec<f64> {
    let mut output = vec![0.0; data.len()];
    let mut z1 = 0.0; // delay line
    let mut z2 = 0.0;

    for i in 0..data.len() {
        let x = data[i];
        let y = b0 * x + z1;
        z1 = b1 * x - a1 * y + z2;
        z2 = b2 * x - a2 * y;
        output[i] = y;
    }

    output
}

// ─── Savitzky-Golay Filter ──────────────────────────────────────────────────

/// Savitzky-Golay smoothing filter.
/// Fits a polynomial of degree `poly_order` over a sliding window of size `window`.
/// Window must be odd; if even, it's incremented by 1.
pub fn savgol(data: &[f64], window: usize, poly_order: usize) -> Vec<f64> {
    let n = data.len();
    if n < 3 || window < 3 {
        return data.to_vec();
    }

    let w = if window % 2 == 0 { window + 1 } else { window };
    let w = w.min(n);
    let half = w / 2;
    let order = poly_order.min(w - 1);

    // Compute convolution coefficients for the center point
    let coeffs = savgol_coefficients(w, order);

    let mut result = vec![0.0; n];

    for i in 0..n {
        let mut val = 0.0;
        for j in 0..w {
            let idx = i as isize + j as isize - half as isize;
            let idx = idx.clamp(0, n as isize - 1) as usize;
            val += coeffs[j] * data[idx];
        }
        result[i] = val;
    }

    result
}

/// Compute Savitzky-Golay convolution coefficients.
/// Uses least-squares polynomial fitting approach.
fn savgol_coefficients(window: usize, order: usize) -> Vec<f64> {
    let half = window as isize / 2;
    let order = order.min(window - 1);

    // Build Vandermonde-like matrix and solve for center point weights
    // For smoothing (0th derivative), we need the first row of (J^T J)^-1 J^T
    let m = window;
    let k = order + 1;

    // J matrix: J[i][j] = (i - half)^j
    let mut jtj = vec![0.0; k * k];
    let mut jt_e0 = vec![0.0; k]; // J^T * e_center

    let center = half as usize;

    for i in 0..m {
        let x = i as f64 - half as f64;
        let mut powers = vec![1.0; k];
        for j in 1..k {
            powers[j] = powers[j - 1] * x;
        }

        for r in 0..k {
            for c in 0..k {
                jtj[r * k + c] += powers[r] * powers[c];
            }
            if i == center {
                jt_e0[r] = powers[r]; // we want center point
            }
        }
    }

    // For smoothing coefficients, we need (J^T J)^-1 applied to each column of J^T
    // Simplified: compute coefficients directly from the pseudo-inverse
    // Using the fact that for the center derivative order 0:
    // c_i = sum_j (J^T J)^-1[0][j] * x_i^j

    // Solve (J^T J) * a = e_0 (first unit vector) for the smoothing case
    // This gives us the 0th row of the pseudo-inverse
    let a = solve_symmetric(&jtj, &jt_e0, k);

    // Now compute the actual filter coefficients
    let mut coeffs = vec![0.0; m];
    for i in 0..m {
        let x = i as f64 - half as f64;
        let mut val = a[0];
        let mut xp = 1.0;
        for j in 1..k {
            xp *= x;
            val += a[j] * xp;
        }
        coeffs[i] = val;
    }

    coeffs
}

/// Solve a symmetric positive-definite system Ax = b using Cholesky decomposition.
fn solve_symmetric(a: &[f64], b: &[f64], n: usize) -> Vec<f64> {
    // Cholesky: A = L * L^T
    let mut l = vec![0.0; n * n];

    for i in 0..n {
        for j in 0..=i {
            let mut sum = 0.0;
            for k in 0..j {
                sum += l[i * n + k] * l[j * n + k];
            }
            if i == j {
                let val = a[i * n + i] - sum;
                l[i * n + j] = if val > 0.0 { val.sqrt() } else { 1e-10 };
            } else {
                let denom = l[j * n + j];
                l[i * n + j] = if denom.abs() > 1e-15 {
                    (a[i * n + j] - sum) / denom
                } else {
                    0.0
                };
            }
        }
    }

    // Forward substitution: L * y = b
    let mut y = vec![0.0; n];
    for i in 0..n {
        let mut sum = 0.0;
        for j in 0..i {
            sum += l[i * n + j] * y[j];
        }
        y[i] = (b[i] - sum) / l[i * n + i].max(1e-15);
    }

    // Backward substitution: L^T * x = y
    let mut x = vec![0.0; n];
    for i in (0..n).rev() {
        let mut sum = 0.0;
        for j in (i + 1)..n {
            sum += l[j * n + i] * x[j];
        }
        x[i] = (y[i] - sum) / l[i * n + i].max(1e-15);
    }

    x
}

// ─── Helpers ────────────────────────────────────────────────────────────────

fn sort_floats(v: &mut Vec<f64>) {
    v.sort_by(|a, b| a.partial_cmp(b).unwrap_or(Ordering::Equal));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hampel_removes_outliers() {
        let mut data = vec![1.0, 1.1, 0.9, 1.0, 50.0, 1.0, 0.95, 1.05];
        let filtered = hampel(&data, 3, 3.0);
        // The outlier at index 4 (50.0) should be replaced
        assert!(
            (filtered[4] - 50.0).abs() > 1.0,
            "outlier was not removed: {}",
            filtered[4]
        );
        assert!(filtered[4] < 5.0, "replacement too high: {}", filtered[4]);
    }

    #[test]
    fn test_hampel_preserves_clean_data() {
        let data = vec![1.0, 1.1, 0.9, 1.0, 1.05, 0.95];
        let filtered = hampel(&data, 3, 3.0);
        for (orig, filt) in data.iter().zip(filtered.iter()) {
            assert_eq!(orig, filt);
        }
    }

    #[test]
    fn test_butterworth_bandpass() {
        // Generate a signal with two frequencies
        let n = 1000;
        let sample_rate = 1000.0;
        let data: Vec<f64> = (0..n)
            .map(|i| {
                let t = i as f64 / sample_rate;
                // 10 Hz signal + 100 Hz noise
                (2.0 * std::f64::consts::PI * 10.0 * t).sin()
                    + 0.5 * (2.0 * std::f64::consts::PI * 100.0 * t).sin()
            })
            .collect();

        let filtered = butterworth_bp(&data, 4, 5.0, 20.0, sample_rate);
        assert_eq!(filtered.len(), n);

        // The 10 Hz component should be preserved, 100 Hz attenuated
        // Check energy in the filtered signal is less than original
        let orig_energy: f64 = data.iter().map(|x| x * x).sum();
        let filt_energy: f64 = filtered.iter().map(|x| x * x).sum();
        assert!(
            filt_energy < orig_energy,
            "filtered energy {} should be less than original {}",
            filt_energy,
            orig_energy
        );
    }

    #[test]
    fn test_savgol_smoothing() {
        // Noisy data with clear trend
        let data = vec![1.0, 1.5, 0.8, 2.0, 1.9, 2.5, 2.3, 3.0, 2.8, 3.5];
        let smoothed = savgol(&data, 5, 2);
        assert_eq!(smoothed.len(), data.len());

        // Smoothed data should have less variance
        let orig_var = variance(&data);
        let smooth_var = variance(&smoothed);
        assert!(
            smooth_var < orig_var,
            "smoothed variance {} should be < original {}",
            smooth_var,
            orig_var
        );
    }

    fn variance(data: &[f64]) -> f64 {
        let mean = data.iter().sum::<f64>() / data.len() as f64;
        data.iter().map(|x| (x - mean).powi(2)).sum::<f64>() / data.len() as f64
    }
}
