import aether/core/error.{
  ModelNotLoaded, NoSensorsAvailable, SensorOffline,
  to_string as error_to_string,
}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn sensor_offline_to_string_test() {
  SensorOffline("esp32-sala", "connection refused")
  |> error_to_string()
  |> should.equal("[sensor:esp32-sala] offline: connection refused")
}

pub fn model_not_loaded_to_string_test() {
  ModelNotLoaded
  |> error_to_string()
  |> should.equal("[model] not loaded")
}

pub fn no_sensors_to_string_test() {
  NoSensorsAvailable
  |> error_to_string()
  |> should.equal("[space] no sensors available")
}
