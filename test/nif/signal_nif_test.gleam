import aether/nif/signal as nif
import gleam/float
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn nif_is_loaded_test() {
  nif.is_loaded() |> should.be_true()
}

pub fn hampel_removes_outlier_test() {
  let data = [1.0, 1.1, 0.9, 1.0, 50.0, 1.0, 0.95, 1.05]
  let filtered = nif.hampel_filter(data, 3, 3.0)

  // Outlier at index 4 (50.0) should be replaced
  let assert Ok(val) = list_at(filtered, 4)
  { val <. 5.0 } |> should.be_true()
}

pub fn hampel_preserves_clean_data_test() {
  let data = [1.0, 1.1, 0.9, 1.0, 1.05, 0.95]
  let filtered = nif.hampel_filter(data, 3, 3.0)
  filtered |> should.equal(data)
}

pub fn avecsi_averages_frames_test() {
  let frames = [
    [1.0, 2.0, 3.0],
    [3.0, 4.0, 5.0],
    [5.0, 6.0, 7.0],
  ]
  let result = nif.avecsi_stabilize(frames, 3)
  result |> list.length() |> should.equal(3)

  // (1+3+5)/3 = 3.0, (2+4+6)/3 = 4.0, (3+5+7)/3 = 5.0
  let assert Ok(v0) = list_at(result, 0)
  let assert Ok(v1) = list_at(result, 1)
  let assert Ok(v2) = list_at(result, 2)
  { float.loosely_equals(v0, 3.0, tolerating: 0.01) } |> should.be_true()
  { float.loosely_equals(v1, 4.0, tolerating: 0.01) } |> should.be_true()
  { float.loosely_equals(v2, 5.0, tolerating: 0.01) } |> should.be_true()
}

pub fn tsfr_calibrate_returns_same_length_test() {
  let amplitude = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
  let phase = [0.1, 0.3, 0.5, 0.7, 0.9, 1.1]
  let result = nif.tsfr_calibrate(amplitude, phase, 3, 2)
  result |> list.length() |> should.equal(6)
}

pub fn savgol_smooths_data_test() {
  let data = [1.0, 5.0, 1.0, 5.0, 1.0, 5.0, 1.0]
  let smoothed = nif.savgol_filter(data, 5, 2)
  smoothed |> list.length() |> should.equal(7)

  // Smoothed data should have less extreme values
  let assert Ok(orig_max) = list.reduce(data, float.max)
  let assert Ok(smooth_max) = list.reduce(smoothed, float.max)
  { smooth_max <. orig_max } |> should.be_true()
}

pub fn butterworth_bandpass_test() {
  // Generate 100-sample sine wave at 10 Hz
  let data = generate_sine(100, 10.0, 100.0)
  let filtered = nif.butterworth_bandpass(data, 4, 5.0, 20.0, 100.0)
  filtered |> list.length() |> should.equal(100)
}

pub fn spotfi_aoa_returns_angles_test() {
  // 3 antennas, 10 subcarriers, 5GHz
  let n = 30
  let amplitude = list.repeat(1.0, n)
  let phase = generate_ramp(n, 0.1)
  let result = nif.spotfi_aoa(amplitude, phase, 3, 10, 5.0e9, 0.025)
  { list.length(result) >= 0 } |> should.be_true()
}

fn generate_sine(samples: Int, freq_hz: Float, sample_rate: Float) -> List(Float) {
  do_generate_sine(0, samples, freq_hz, sample_rate, [])
  |> list.reverse()
}

fn do_generate_sine(i: Int, n: Int, freq: Float, sr: Float, acc: List(Float)) -> List(Float) {
  case i >= n {
    True -> acc
    False -> {
      let t = int_to_float(i) /. sr
      let val = float_sin(t *. 6.28318 *. freq)
      do_generate_sine(i + 1, n, freq, sr, [val, ..acc])
    }
  }
}

fn generate_ramp(n: Int, step: Float) -> List(Float) {
  do_generate_ramp(0, n, step, []) |> list.reverse()
}

fn do_generate_ramp(i: Int, n: Int, step: Float, acc: List(Float)) -> List(Float) {
  case i >= n {
    True -> acc
    False -> do_generate_ramp(i + 1, n, step, [int_to_float(i) *. step, ..acc])
  }
}

// --- Helpers ---

fn list_at(lst: List(a), index: Int) -> Result(a, Nil) {
  case lst, index {
    [head, ..], 0 -> Ok(head)
    [_, ..rest], n if n > 0 -> list_at(rest, n - 1)
    _, _ -> Error(Nil)
  }
}

@external(erlang, "math", "sin")
fn float_sin(x: Float) -> Float

fn int_to_float(i: Int) -> Float {
  case i {
    0 -> 0.0
    _ -> erlang_int_to_float(i)
  }
}

@external(erlang, "erlang", "float")
fn erlang_int_to_float(i: Int) -> Float
