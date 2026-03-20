//! Æther Signal Processing NIFs
//!
//! CPU-bound signal processing for RF sensing data.
//! These run on normal BEAM schedulers (< 1ms per call).
//!
//! Algorithms validated in 2025-2026 papers:
//! - TSFR phase calibration (Time Smoothing + Frequency Rebuild)
//! - Hampel outlier filter (median absolute deviation)
//! - Butterworth IIR bandpass filter
//! - AveCSI frame stabilization (sliding window average)
//! - SpotFi AoA estimation (MUSIC-based)

mod avecsi;
mod filters;
mod spotfi;
mod tsfr;

use rustler::NifResult;

// --- Phase Calibration ---

/// TSFR phase calibration: linear regression on unwrapped phase + Savitzky-Golay smoothing.
/// Returns calibrated phase values.
#[rustler::nif]
fn tsfr_calibrate(
    amplitude: Vec<f64>,
    phase: Vec<f64>,
    subcarriers: usize,
    antennas: usize,
) -> NifResult<Vec<f64>> {
    if phase.is_empty() || subcarriers == 0 || antennas == 0 {
        return Ok(vec![]);
    }
    Ok(tsfr::calibrate(&amplitude, &phase, subcarriers, antennas))
}

// --- Denoising Filters ---

/// Hampel filter: detect and replace outliers using median absolute deviation.
/// threshold is typically 3.0 (3 sigma).
#[rustler::nif]
fn hampel_filter(data: Vec<f64>, window: usize, threshold: f64) -> NifResult<Vec<f64>> {
    if data.is_empty() || window == 0 {
        return Ok(data);
    }
    Ok(filters::hampel(&data, window, threshold))
}

/// Butterworth IIR bandpass filter.
/// Isolates frequency band [low_hz, high_hz] at given sample_rate.
#[rustler::nif]
fn butterworth_bandpass(
    data: Vec<f64>,
    order: usize,
    low_hz: f64,
    high_hz: f64,
    sample_rate: f64,
) -> NifResult<Vec<f64>> {
    if data.is_empty() || order == 0 || sample_rate <= 0.0 {
        return Ok(data);
    }
    Ok(filters::butterworth_bp(&data, order, low_hz, high_hz, sample_rate))
}

/// Savitzky-Golay smoothing filter.
/// Polynomial least-squares fit over sliding window.
#[rustler::nif]
fn savgol_filter(data: Vec<f64>, window: usize, poly_order: usize) -> NifResult<Vec<f64>> {
    if data.is_empty() || window < 3 {
        return Ok(data);
    }
    Ok(filters::savgol(&data, window, poly_order))
}

// --- Stabilization ---

/// AveCSI: sliding window average across CSI frames for stabilization.
/// Each frame is a flat vec of subcarrier amplitudes.
#[rustler::nif]
fn avecsi_stabilize(frames: Vec<Vec<f64>>, window: usize) -> NifResult<Vec<f64>> {
    if frames.is_empty() {
        return Ok(vec![]);
    }
    Ok(avecsi::stabilize(&frames, window))
}

// --- Spatial ---

/// SpotFi Angle of Arrival estimation using MUSIC algorithm.
/// Returns estimated angles in degrees.
#[rustler::nif]
fn spotfi_aoa(
    csi_amplitude: Vec<f64>,
    csi_phase: Vec<f64>,
    antennas: usize,
    subcarriers: usize,
    freq_hz: f64,
    antenna_spacing_m: f64,
) -> NifResult<Vec<f64>> {
    if antennas < 2 || subcarriers == 0 {
        return Ok(vec![]);
    }
    Ok(spotfi::estimate_aoa(
        &csi_amplitude,
        &csi_phase,
        antennas,
        subcarriers,
        freq_hz,
        antenna_spacing_m,
    ))
}

rustler::init!("aether_signal_nif");
