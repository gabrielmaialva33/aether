import aether/core/types.{type Zone}
import aether/sensor.{type SensorConfig}
import aether/space.{type SpaceConfig}
import gleam/int
import gleam/io
import gleam/list

/// Create a new Space configuration
pub fn space(id: String) -> SpaceConfig {
  space.new(id)
}

/// Add a zone to the space
pub fn add_zone(config: SpaceConfig, zone: Zone) -> SpaceConfig {
  space.add_zone(config, zone)
}

/// Add a sensor to the space
pub fn add_sensor(config: SpaceConfig, sensor: SensorConfig) -> SpaceConfig {
  space.add_sensor(config, sensor)
}

/// Start the Æther perception system
pub fn start(config: SpaceConfig) -> Result(SpaceConfig, String) {
  case config.sensors {
    [] -> Error("No sensors configured")
    sensors -> {
      io.println(
        "Æther started — "
        <> int.to_string(list.length(sensors))
        <> " sensors, "
        <> int.to_string(list.length(config.zones))
        <> " zones",
      )
      Ok(config)
    }
  }
}
