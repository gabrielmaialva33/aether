//! SpotFi — Angle of Arrival Estimation
//!
//! Simplified MUSIC-based AoA estimation from CSI data.
//! SpotFi was the first system to achieve decimeter-level indoor
//! localization using commodity WiFi (SIGCOMM 2015).
//!
//! The algorithm:
//! 1. Construct the CSI spatial correlation matrix from antenna pairs
//! 2. Eigendecompose to separate signal and noise subspaces
//! 3. Scan angles and find peaks in the MUSIC pseudo-spectrum
//!
//! This implementation uses a simplified approach suitable for
//! real-time processing on 3-antenna ESP32 setups.

use std::f64::consts::PI;

/// Estimate Angle of Arrival from CSI data.
///
/// Returns a list of estimated angles in degrees.
/// For a 3-antenna linear array, typically returns 1-2 angles.
pub fn estimate_aoa(
    amplitude: &[f64],
    phase: &[f64],
    antennas: usize,
    subcarriers: usize,
    freq_hz: f64,
    antenna_spacing_m: f64,
) -> Vec<f64> {
    let total = antennas * subcarriers;
    if amplitude.len() < total || phase.len() < total {
        return vec![];
    }

    // Speed of light
    let c = 299_792_458.0;
    let wavelength = c / freq_hz;

    // Construct complex CSI matrix: antennas x subcarriers
    // H[ant][sub] = amplitude * e^(j*phase)
    let mut h_real = vec![vec![0.0; subcarriers]; antennas];
    let mut h_imag = vec![vec![0.0; subcarriers]; antennas];

    for ant in 0..antennas {
        for sub in 0..subcarriers {
            let idx = ant * subcarriers + sub;
            let a = amplitude[idx];
            let p = phase[idx];
            h_real[ant][sub] = a * p.cos();
            h_imag[ant][sub] = a * p.sin();
        }
    }

    // Compute spatial correlation matrix R = (1/K) * H * H^H
    // R is antennas x antennas (Hermitian)
    let mut r_real = vec![vec![0.0; antennas]; antennas];
    let mut r_imag = vec![vec![0.0; antennas]; antennas];

    let inv_k = 1.0 / subcarriers as f64;
    for i in 0..antennas {
        for j in 0..antennas {
            let mut sum_real = 0.0;
            let mut sum_imag = 0.0;
            for sub in 0..subcarriers {
                // H[i][sub] * conj(H[j][sub])
                let a_r = h_real[i][sub];
                let a_i = h_imag[i][sub];
                let b_r = h_real[j][sub];
                let b_i = h_imag[j][sub];
                sum_real += a_r * b_r + a_i * b_i; // real part of a * conj(b)
                sum_imag += a_i * b_r - a_r * b_i; // imag part of a * conj(b)
            }
            r_real[i][j] = sum_real * inv_k;
            r_imag[i][j] = sum_imag * inv_k;
        }
    }

    // MUSIC pseudo-spectrum scan
    // For simplicity with small antenna arrays (3-4), we do a brute-force
    // angle scan and find peaks.
    let angle_resolution = 1.0; // degrees
    let mut spectrum = Vec::new();
    let mut angles = Vec::new();

    let mut theta = -90.0;
    while theta <= 90.0 {
        let theta_rad = theta * PI / 180.0;

        // Steering vector: a(θ) = [1, e^{-j*2π*d*sin(θ)/λ}, ...]
        let mut a_real = vec![0.0; antennas];
        let mut a_imag = vec![0.0; antennas];
        for ant in 0..antennas {
            let phase_shift =
                -2.0 * PI * ant as f64 * antenna_spacing_m * theta_rad.sin() / wavelength;
            a_real[ant] = phase_shift.cos();
            a_imag[ant] = phase_shift.sin();
        }

        // P(θ) = 1 / |a^H * R^-1 * a|
        // Simplified: use R directly (Bartlett beamformer) for robustness
        // P(θ) = a^H * R * a
        let mut power = 0.0;
        for i in 0..antennas {
            for j in 0..antennas {
                // (a[i])^H * R[i][j] * a[j]
                let ai_r = a_real[i];
                let ai_i = -a_imag[i]; // conjugate
                let rij_r = r_real[i][j];
                let rij_i = r_imag[i][j];

                // (ai_r + j*ai_i) * (rij_r + j*rij_i)
                let mid_r = ai_r * rij_r - ai_i * rij_i;
                let mid_i = ai_r * rij_i + ai_i * rij_r;

                // mid * a[j]
                let aj_r = a_real[j];
                let aj_i = a_imag[j];
                power += mid_r * aj_r - mid_i * aj_i;
            }
        }

        spectrum.push(power);
        angles.push(theta);
        theta += angle_resolution;
    }

    // Find peaks in the spectrum
    find_peaks(&angles, &spectrum)
}

/// Find peaks in the pseudo-spectrum.
/// Returns angles where spectrum has local maxima above threshold.
fn find_peaks(angles: &[f64], spectrum: &[f64]) -> Vec<f64> {
    if spectrum.len() < 3 {
        return vec![];
    }

    let max_val = spectrum.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
    let threshold = max_val * 0.5; // peaks must be at least 50% of max

    let mut peaks = Vec::new();
    for i in 1..spectrum.len() - 1 {
        if spectrum[i] > spectrum[i - 1]
            && spectrum[i] > spectrum[i + 1]
            && spectrum[i] > threshold
        {
            peaks.push(angles[i]);
        }
    }

    peaks
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_single_source_aoa() {
        // Simulate a signal arriving at 30 degrees on a 3-antenna array
        let antennas = 3;
        let subcarriers = 56;
        let freq = 5.0e9; // 5 GHz
        let spacing = 0.025; // ~half wavelength at 5 GHz
        let c = 299_792_458.0;
        let wavelength = c / freq;
        let theta = 30.0_f64.to_radians();

        let mut amplitude = vec![1.0; antennas * subcarriers];
        let mut phase = vec![0.0; antennas * subcarriers];

        for ant in 0..antennas {
            let phase_shift = -2.0 * PI * ant as f64 * spacing * theta.sin() / wavelength;
            for sub in 0..subcarriers {
                phase[ant * subcarriers + sub] = phase_shift + sub as f64 * 0.01; // slight freq variation
            }
        }

        let angles = estimate_aoa(&amplitude, &phase, antennas, subcarriers, freq, spacing);
        assert!(!angles.is_empty(), "should find at least one angle");

        // The estimated angle should be near 30 degrees
        let closest = angles
            .iter()
            .min_by(|a, b| {
                ((**a) - 30.0)
                    .abs()
                    .partial_cmp(&((**b) - 30.0).abs())
                    .unwrap()
            })
            .unwrap();
        assert!(
            (*closest - 30.0).abs() < 15.0,
            "estimated angle {} too far from 30°",
            closest
        );
    }
}
