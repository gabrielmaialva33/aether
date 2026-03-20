/// Æther — Ambient RF Perception System
///
/// Usage:
///   let assert Ok(hub) =
///     aether.space("home")
///     |> aether.add_zone(Zone("sala", "Sala", #(0.0, 0.0, 5.0, 4.0), 0.0, 3.0))
///     |> aether.add_sensor(sensor.wifi_csi(host: "192.168.1.50", port: 5000, ...))
///     |> aether.with_api(8080)
///     |> aether.start()
import aether/core/types.{type Zone}
import aether/orchestrator.{type OrchestratorMsg}
import aether/perception.{type Perception}
import aether/sensor.{type SensorConfig}
import aether/serve/api
import aether/signal
import aether/space.{type SpaceConfig}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/list

/// Running Æther hub — holds orchestrator and config.
pub type Hub {
  Hub(config: SpaceConfig, orchestrator: Subject(OrchestratorMsg))
}

/// Create a new Space configuration.
pub fn space(id: String) -> SpaceConfig {
  space.new(id)
}

/// Add a zone to the space.
pub fn add_zone(config: SpaceConfig, zone: Zone) -> SpaceConfig {
  space.add_zone(config, zone)
}

/// Add a sensor to the space.
pub fn add_sensor(config: SpaceConfig, sensor: SensorConfig) -> SpaceConfig {
  space.add_sensor(config, sensor)
}

/// Set the API server port.
pub fn with_api(config: SpaceConfig, port: Int) -> SpaceConfig {
  space.with_api_port(config, port)
}

/// Start the Æther perception system.
/// Boots orchestrator, optionally starts HTTP/WS API server.
pub fn start(config: SpaceConfig) -> Result(Hub, String) {
  case config.sensors {
    [] -> Error("No sensors configured")
    sensors -> {
      // 1. Start orchestrator
      let orch_config =
        orchestrator.OrchestratorConfig(
          conditioners: config.conditioners,
          model_path: "models/aether-v1.pt",
          device: "cpu",
          tasks: ["pose", "vitals", "presence", "activity"],
        )
      case orchestrator.start(orch_config) {
        Error(e) -> Error("Orchestrator failed: " <> e)
        Ok(orch) -> {
          // 2. Start API server
          let _ = api.start(config.api_port, orch)

          io.println(
            "╔══════════════════════════════════════╗\n"
            <> "║   Æther v0.1.0 — perceiving.         ║\n"
            <> "╚══════════════════════════════════════╝\n"
            <> "  sensors: "
            <> int.to_string(list.length(sensors))
            <> "\n"
            <> "  zones:   "
            <> int.to_string(list.length(config.zones))
            <> "\n"
            <> "  API:     http://localhost:"
            <> int.to_string(config.api_port)
            <> "/api/health\n"
            <> "  WS:      ws://localhost:"
            <> int.to_string(config.api_port)
            <> "/ws/stream",
          )

          Ok(Hub(config: config, orchestrator: orch))
        }
      }
    }
  }
}

/// Get current perceptions from the hub.
pub fn perceive(hub: Hub) -> List(Perception) {
  orchestrator.get_perceptions(hub.orchestrator)
}

/// Send a signal to the hub for processing.
pub fn ingest(hub: Hub, signal signal: signal.Signal) -> Nil {
  orchestrator.ingest(hub.orchestrator, signal)
}

/// Subscribe to real-time perception updates.
pub fn on_perception(hub: Hub, callback: fn(List(Perception)) -> Nil) -> Nil {
  let sub = process.new_subject()
  orchestrator.subscribe(hub.orchestrator, sub)
  // Spawn a listener that calls the callback
  spawn_listener(sub, callback)
}

fn spawn_listener(
  sub: Subject(List(Perception)),
  callback: fn(List(Perception)) -> Nil,
) -> Nil {
  do_spawn_listener(sub, callback)
}

@external(erlang, "aether_listener_ffi", "spawn_listener")
fn do_spawn_listener(
  sub: Subject(List(Perception)),
  callback: fn(List(Perception)) -> Nil,
) -> Nil
