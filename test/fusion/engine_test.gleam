import aether/fusion/engine
import aether/signal.{BleRssi, Signal, WifiCsi}
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn engine_buffers_and_flushes_test() {
  let assert Ok(eng) = engine.start(window_us: 50_000, tolerance_us: 10_000)

  let s1 =
    Signal(
      source: "wifi",
      kind: WifiCsi(56, 3, 20),
      timestamp: 1000,
      payload: <<1, 2, 3>>,
      metadata: [],
    )
  let s2 =
    Signal(
      source: "ble",
      kind: BleRssi(3),
      timestamp: 1005,
      payload: <<4, 5, 6>>,
      metadata: [],
    )

  engine.ingest(eng, s1)
  engine.ingest(eng, s2)

  let assert Ok(aligned) = engine.flush(eng)
  aligned |> list.length() |> should.equal(2)
}

pub fn engine_flush_empty_returns_error_test() {
  let assert Ok(eng) = engine.start(window_us: 50_000, tolerance_us: 10_000)
  let result = engine.flush(eng)
  result |> should.be_error()
}

pub fn engine_overwrites_same_source_test() {
  let assert Ok(eng) = engine.start(window_us: 50_000, tolerance_us: 10_000)

  engine.ingest(
    eng,
    Signal(
      source: "wifi",
      kind: WifiCsi(56, 3, 20),
      timestamp: 1000,
      payload: <<1>>,
      metadata: [],
    ),
  )
  engine.ingest(
    eng,
    Signal(
      source: "wifi",
      kind: WifiCsi(56, 3, 20),
      timestamp: 2000,
      payload: <<2>>,
      metadata: [],
    ),
  )

  let assert Ok(aligned) = engine.flush(eng)
  // Same source → overwritten, only 1 signal
  aligned |> list.length() |> should.equal(1)
}
