import aether/core/error.{type AetherError}
import aether/signal.{type Signal}
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
    Augment(_), Inference -> Ok(signal)
    PhaseCalibrate(_), _ -> Ok(signal)
    Denoise(_), _ -> Ok(signal)
    Stabilize(_), _ -> Ok(signal)
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
