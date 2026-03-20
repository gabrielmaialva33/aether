import aether/condition/pipeline.{type Conditioner}
import aether/core/types.{type Zone}
import aether/sensor.{type SensorConfig}

pub type SpaceConfig {
  SpaceConfig(
    id: String,
    zones: List(Zone),
    sensors: List(SensorConfig),
    conditioners: List(Conditioner),
    api_port: Int,
    model_path: String,
    device: String,
    tasks: List(String),
  )
}

pub fn new(id: String) -> SpaceConfig {
  SpaceConfig(
    id: id,
    zones: [],
    sensors: [],
    conditioners: pipeline.default_wifi(),
    api_port: 8080,
    model_path: "models/aether-v1.pt",
    device: "cpu",
    tasks: ["pose", "vitals", "presence", "activity"],
  )
}

pub fn add_zone(config: SpaceConfig, zone: Zone) -> SpaceConfig {
  SpaceConfig(..config, zones: [zone, ..config.zones])
}

pub fn add_sensor(config: SpaceConfig, sensor: SensorConfig) -> SpaceConfig {
  SpaceConfig(..config, sensors: [sensor, ..config.sensors])
}

pub fn with_conditioners(
  config: SpaceConfig,
  conditioners: List(Conditioner),
) -> SpaceConfig {
  SpaceConfig(..config, conditioners: conditioners)
}

pub fn with_api_port(config: SpaceConfig, port: Int) -> SpaceConfig {
  SpaceConfig(..config, api_port: port)
}

pub fn with_model(
  config: SpaceConfig,
  path path: String,
  device device: String,
) -> SpaceConfig {
  SpaceConfig(..config, model_path: path, device: device)
}

pub fn with_tasks(config: SpaceConfig, tasks: List(String)) -> SpaceConfig {
  SpaceConfig(..config, tasks: tasks)
}
