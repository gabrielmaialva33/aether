import aether/signal.{Signal, WifiCsi, signal_age_us}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn create_wifi_csi_signal_test() {
  let sig =
    Signal(
      source: "esp32-sala",
      kind: WifiCsi(subcarriers: 56, antennas: 3, bandwidth: 20),
      timestamp: 1_000_000,
      payload: <<0, 1, 2, 3>>,
      metadata: [],
    )
  sig.source |> should.equal("esp32-sala")
}

pub fn signal_age_test() {
  let sig =
    Signal(
      source: "test",
      kind: WifiCsi(subcarriers: 56, antennas: 3, bandwidth: 20),
      timestamp: 100,
      payload: <<>>,
      metadata: [],
    )
  signal_age_us(sig, now: 350) |> should.equal(250)
}
