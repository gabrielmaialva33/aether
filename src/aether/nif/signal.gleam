//! FFI bindings to aether_signal Rust NIF.
//! Signal processing functions for CSI data conditioning.

/// TSFR phase calibration: unwrap + linear detrend + Savitzky-Golay smoothing.
@external(erlang, "aether_signal_nif", "tsfr_calibrate")
pub fn tsfr_calibrate(
  amplitude: List(Float),
  phase: List(Float),
  subcarriers: Int,
  antennas: Int,
) -> List(Float)

/// Hampel outlier filter using Median Absolute Deviation.
@external(erlang, "aether_signal_nif", "hampel_filter")
pub fn hampel_filter(
  data: List(Float),
  window: Int,
  threshold: Float,
) -> List(Float)

/// Butterworth IIR bandpass filter (zero-phase, cascaded biquads).
@external(erlang, "aether_signal_nif", "butterworth_bandpass")
pub fn butterworth_bandpass(
  data: List(Float),
  order: Int,
  low_hz: Float,
  high_hz: Float,
  sample_rate: Float,
) -> List(Float)

/// Savitzky-Golay polynomial smoothing filter.
@external(erlang, "aether_signal_nif", "savgol_filter")
pub fn savgol_filter(
  data: List(Float),
  window: Int,
  poly_order: Int,
) -> List(Float)

/// AveCSI frame stabilization via sliding window average.
@external(erlang, "aether_signal_nif", "avecsi_stabilize")
pub fn avecsi_stabilize(frames: List(List(Float)), window: Int) -> List(Float)

/// SpotFi Angle of Arrival estimation (MUSIC-based).
@external(erlang, "aether_signal_nif", "spotfi_aoa")
pub fn spotfi_aoa(
  amplitude: List(Float),
  phase: List(Float),
  antennas: Int,
  subcarriers: Int,
  freq_hz: Float,
  antenna_spacing_m: Float,
) -> List(Float)

/// Check if the NIF is loaded.
@external(erlang, "aether_signal_nif", "is_loaded")
pub fn is_loaded() -> Bool
