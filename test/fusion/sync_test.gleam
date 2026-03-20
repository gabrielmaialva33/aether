import aether/fusion/sync.{align_signals}
import aether/signal.{BleRssi, Signal, WifiCsi}
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn align_within_tolerance_test() {
  let s1 =
    Signal(
      source: "wifi",
      kind: WifiCsi(56, 3, 20),
      timestamp: 1000,
      payload: <<>>,
      metadata: [],
    )
  let s2 =
    Signal(
      source: "ble",
      kind: BleRssi(3),
      timestamp: 1005,
      payload: <<>>,
      metadata: [],
    )

  let result = align_signals([s1, s2], tolerance_us: 10)
  result |> should.be_ok()
  let assert Ok(aligned) = result
  aligned |> list.length() |> should.equal(2)
}

pub fn reject_out_of_tolerance_test() {
  let s1 =
    Signal(
      source: "wifi",
      kind: WifiCsi(56, 3, 20),
      timestamp: 1000,
      payload: <<>>,
      metadata: [],
    )
  let s2 =
    Signal(
      source: "ble",
      kind: BleRssi(3),
      timestamp: 2000,
      payload: <<>>,
      metadata: [],
    )

  let result = align_signals([s1, s2], tolerance_us: 10)
  let assert Ok(aligned) = result
  aligned |> list.length() |> should.equal(1)
}

pub fn empty_signals_error_test() {
  let result = align_signals([], tolerance_us: 10)
  result |> should.be_error()
}
