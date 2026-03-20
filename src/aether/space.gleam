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
  )
}

pub fn new(id: String) -> SpaceConfig {
  SpaceConfig(
    id: id,
    zones: [],
    sensors: [],
    conditioners: pipeline.default_wifi(),
    api_port: 8080,
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
