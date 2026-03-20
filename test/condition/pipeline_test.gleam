import aether/condition/pipeline.{
  Augment, Denoise, Inference, Stabilize, StationMasking, Training, run_pipeline,
}
import aether/signal.{Signal, WifiCsi}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn pipeline_runs_in_order_test() {
  let stages = [
    Stabilize(window_size: 5),
    Denoise(pipeline.Hampel(window: 3, threshold: 3.0)),
  ]

  let sig =
    Signal(
      source: "test",
      kind: WifiCsi(subcarriers: 4, antennas: 1, bandwidth: 20),
      timestamp: 100,
      payload: <<>>,
      metadata: [],
    )

  let result = run_pipeline(sig, stages, Inference)
  result |> should.be_ok()
}

pub fn pipeline_skips_augment_in_inference_test() {
  let stages = [Augment(StationMasking(prob: 0.3))]

  let sig =
    Signal(
      source: "test",
      kind: WifiCsi(subcarriers: 4, antennas: 1, bandwidth: 20),
      timestamp: 100,
      payload: <<1, 2, 3>>,
      metadata: [],
    )

  let assert Ok(result) = run_pipeline(sig, stages, Inference)
  result.payload |> should.equal(sig.payload)
}

pub fn pipeline_runs_augment_in_training_test() {
  let stages = [Augment(StationMasking(prob: 0.3))]

  let sig =
    Signal(
      source: "test",
      kind: WifiCsi(subcarriers: 4, antennas: 1, bandwidth: 20),
      timestamp: 100,
      payload: <<>>,
      metadata: [],
    )

  let result = run_pipeline(sig, stages, Training)
  result |> should.be_ok()
}
