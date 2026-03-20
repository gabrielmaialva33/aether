import aether/core/error.{type AetherError}
import aether/nif/signal as nif
import aether/signal.{type Signal, Signal}
import gleam/bit_array
import gleam/list

pub type PipelineMode {
  Inference
  Training
}

pub type Conditioner {
  PhaseCalibrate(method: PhaseMethod)
  Denoise(method: DenoiseMethod)
  Stabilize(window_size: Int)
  Augment(method: AugmentMethod)
}

pub type PhaseMethod {
  Tsfr
  LinearFit
}

pub type DenoiseMethod {
  Hampel(window: Int, threshold: Float)
  Butterworth(order: Int, cutoff_hz: Float)
  SavitzkyGolay(window: Int, poly_order: Int)
}

pub type AugmentMethod {
  GaussianNoise(std: Float)
  Scaling(range: #(Float, Float))
  StationMasking(prob: Float)
}

pub type PipelineConfig {
  PipelineConfig(
    stages: List(Conditioner),
    mode: PipelineMode,
    buffer_size: Int,
    drop_stale_after_ms: Int,
  )
}

/// Run the conditioning pipeline as functional composition.
/// Augment stages are skipped in Inference mode.
/// When NIF is loaded, delegates to Rust for real signal processing.
pub fn run_pipeline(
  signal: Signal,
  stages: List(Conditioner),
  mode: PipelineMode,
) -> Result(Signal, AetherError) {
  list.try_fold(stages, signal, fn(sig, stage) { apply_stage(sig, stage, mode) })
}

fn apply_stage(
  signal: Signal,
  stage: Conditioner,
  mode: PipelineMode,
) -> Result(Signal, AetherError) {
  case stage, mode {
    // Skip augmentation in inference mode
    Augment(_), Inference -> Ok(signal)

    // Phase calibration via NIF
    PhaseCalibrate(Tsfr), _ -> {
      let data = payload_to_floats(signal.payload)
      let half = list.length(data) / 2
      let #(amplitude, phase) = list_split(data, half)
      let subs = half / 1
      // Default: treat as 1 antenna, N subcarriers
      let calibrated = nif.tsfr_calibrate(amplitude, phase, subs, 1)
      Ok(Signal(..signal, payload: floats_to_payload(calibrated)))
    }

    PhaseCalibrate(LinearFit), _ -> Ok(signal)

    // Denoising via NIF
    Denoise(Hampel(window, threshold)), _ -> {
      let data = payload_to_floats(signal.payload)
      let filtered = nif.hampel_filter(data, window, threshold)
      Ok(Signal(..signal, payload: floats_to_payload(filtered)))
    }

    Denoise(Butterworth(order, cutoff_hz)), _ -> {
      let data = payload_to_floats(signal.payload)
      // Bandpass: [0.1 Hz, cutoff_hz] at assumed 100Hz sample rate
      let filtered =
        nif.butterworth_bandpass(data, order, 0.1, cutoff_hz, 100.0)
      Ok(Signal(..signal, payload: floats_to_payload(filtered)))
    }

    Denoise(SavitzkyGolay(window, poly_order)), _ -> {
      let data = payload_to_floats(signal.payload)
      let smoothed = nif.savgol_filter(data, window, poly_order)
      Ok(Signal(..signal, payload: floats_to_payload(smoothed)))
    }

    // Stabilization — needs frame history (stateful), pass-through for now
    // Real implementation uses the pipeline actor's ring buffer
    Stabilize(_window), _ -> Ok(signal)

    // Augmentation in training mode — pass-through placeholder
    Augment(_), Training -> Ok(signal)
  }
}

/// Default pipeline for WiFi CSI
pub fn default_wifi() -> List(Conditioner) {
  [
    PhaseCalibrate(Tsfr),
    Denoise(Hampel(window: 5, threshold: 3.0)),
    Denoise(Butterworth(order: 4, cutoff_hz: 80.0)),
    Stabilize(window_size: 10),
  ]
}

/// Pipeline optimized for vital signs extraction
pub fn default_vitals() -> List(Conditioner) {
  [
    PhaseCalibrate(Tsfr),
    Denoise(Hampel(window: 3, threshold: 2.5)),
    Denoise(Butterworth(order: 6, cutoff_hz: 2.5)),
    Stabilize(window_size: 20),
  ]
}

// ─── Payload ↔ Float list conversion ────────────────────────────────────────

/// Convert BitArray payload to list of f64 values.
/// Assumes IEEE 754 double-precision (8 bytes each).
/// Falls back to empty list if payload is not float-encoded.
fn payload_to_floats(payload: BitArray) -> List(Float) {
  decode_floats(payload, []) |> list.reverse()
}

fn decode_floats(data: BitArray, acc: List(Float)) -> List(Float) {
  case data {
    <<val:float-size(64), rest:bytes>> -> decode_floats(rest, [val, ..acc])
    _ -> acc
  }
}

/// Convert list of f64 values back to BitArray payload.
fn floats_to_payload(values: List(Float)) -> BitArray {
  list.fold(values, <<>>, fn(acc, val) {
    bit_array.append(acc, <<val:float-size(64)>>)
  })
}

/// Split a list at index n.
fn list_split(lst: List(a), n: Int) -> #(List(a), List(a)) {
  list_split_acc(lst, n, [])
}

fn list_split_acc(lst: List(a), n: Int, acc: List(a)) -> #(List(a), List(a)) {
  case n <= 0 {
    True -> #(list.reverse(acc), lst)
    False ->
      case lst {
        [] -> #(list.reverse(acc), [])
        [head, ..rest] -> list_split_acc(rest, n - 1, [head, ..acc])
      }
  }
}
