import aether
import aether/core/types.{Zone}
import aether/sensor
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn build_space_config_test() {
  let config =
    aether.space("test-house")
    |> aether.add_zone(Zone("sala", "Sala", #(0.0, 0.0, 5.0, 4.0), 0.0, 3.0))
    |> aether.add_zone(Zone("quarto", "Quarto", #(5.0, 0.0, 9.0, 4.0), 0.0, 3.0))

  config.id |> should.equal("test-house")
  config.zones |> list.length() |> should.equal(2)
}

pub fn start_with_no_sensors_fails_test() {
  let result =
    aether.space("empty")
    |> aether.start()

  result |> should.be_error()
}

pub fn start_with_sensor_succeeds_test() {
  let result =
    aether.space("home")
    |> aether.add_sensor(sensor.wifi_csi(
      host: "192.168.1.50",
      port: 5000,
      antennas: 3,
      subcarriers: 56,
      sample_rate: 100,
    ))
    |> aether.start()

  result |> should.be_ok()
}
