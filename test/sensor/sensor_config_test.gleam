import aether/sensor.{FreeRunning, Udp, mmwave, wifi_csi}
import aether/signal.{MmWave, WifiCsi}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn wifi_csi_constructor_test() {
  let config =
    wifi_csi(
      host: "192.168.1.50",
      port: 5000,
      antennas: 3,
      subcarriers: 56,
      sample_rate: 100,
    )

  config.id |> should.equal("192.168.1.50:5000")
  config.sample_rate_hz |> should.equal(100)
  config.sync |> should.equal(FreeRunning)

  case config.transport {
    Udp(host, port) -> {
      host |> should.equal("192.168.1.50")
      port |> should.equal(5000)
    }
    _ -> should.fail()
  }

  case config.kind {
    WifiCsi(subcarriers, antennas, bandwidth) -> {
      subcarriers |> should.equal(56)
      antennas |> should.equal(3)
      bandwidth |> should.equal(20)
    }
    _ -> should.fail()
  }
}

pub fn mmwave_constructor_test() {
  let config =
    mmwave(
      host: "192.168.1.60",
      port: 6000,
      freq_ghz: 60.0,
      chirps: 128,
      sample_rate: 50,
    )

  config.sample_rate_hz |> should.equal(50)
  string.contains(config.id, "6000") |> should.be_true()

  case config.kind {
    MmWave(freq_ghz, chirps) -> {
      chirps |> should.equal(128)
    }
    _ -> should.fail()
  }
}
