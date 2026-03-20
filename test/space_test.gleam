import aether/condition/pipeline
import aether/core/types.{Zone}
import aether/sensor
import aether/space
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn new_space_has_defaults_test() {
  let config = space.new("home")
  config.id |> should.equal("home")
  config.zones |> should.equal([])
  config.sensors |> should.equal([])
  config.api_port |> should.equal(8080)
  config.device |> should.equal("cpu")
  config.model_path |> should.equal("models/aether-v1.pt")
}

pub fn add_zone_test() {
  let config =
    space.new("home")
    |> space.add_zone(Zone("sala", "Sala", #(0.0, 0.0, 5.0, 4.0), 0.0, 3.0))
    |> space.add_zone(Zone("quarto", "Quarto", #(5.0, 0.0, 9.0, 4.0), 0.0, 3.0))

  config.zones |> list.length() |> should.equal(2)
}

pub fn add_sensor_test() {
  let config =
    space.new("home")
    |> space.add_sensor(sensor.wifi_csi(
      host: "10.0.0.1",
      port: 5000,
      antennas: 3,
      subcarriers: 56,
      sample_rate: 100,
    ))

  config.sensors |> list.length() |> should.equal(1)
}

pub fn with_model_test() {
  let config =
    space.new("home")
    |> space.with_model(path: "custom/model.pt", device: "cuda:0")

  config.model_path |> should.equal("custom/model.pt")
  config.device |> should.equal("cuda:0")
}

pub fn with_tasks_test() {
  let config =
    space.new("home")
    |> space.with_tasks(["pose", "vitals"])

  config.tasks |> should.equal(["pose", "vitals"])
}

pub fn with_conditioners_test() {
  let config =
    space.new("home")
    |> space.with_conditioners(pipeline.default_vitals())

  config.conditioners |> list.length() |> should.equal(4)
}
