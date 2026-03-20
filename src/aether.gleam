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
import aether/sensor.{type SensorConfig, Udp}
import aether/sensor/actor as sensor_actor
import aether/sensor/udp as sensor_udp
import aether/serve/api
import aether/signal
import aether/space.{type SpaceConfig}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/list

/// Running Æther hub.
pub type Hub {
  Hub(
    config: SpaceConfig,
    orchestrator: Subject(OrchestratorMsg),
    sensor_actors: List(Subject(sensor_actor.SensorMsg)),
  )
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
/// Boots: orchestrator → sensor actors (with UDP listeners) → HTTP API.
/// Signals flow automatically: UDP → sensor actor → orchestrator → perceptions.
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
          // 2. Start sensor actors — each one auto-forwards signals to orchestrator
          let sensor_actors = start_sensor_actors(sensors, orch)

          // 3. Start API server
          let _ = api.start(config.api_port, orch)

          io.println(
            "╔══════════════════════════════════════╗\n"
            <> "║   Æther v0.1.0 — perceiving.         ║\n"
            <> "╚══════════════════════════════════════╝\n"
            <> "  sensors: "
            <> int.to_string(list.length(sensors))
            <> " ("
            <> int.to_string(list.length(sensor_actors))
            <> " active)\n"
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

          Ok(Hub(
            config: config,
            orchestrator: orch,
            sensor_actors: sensor_actors,
          ))
        }
      }
    }
  }
}

/// Get current perceptions from the hub.
pub fn perceive(hub: Hub) -> List(Perception) {
  orchestrator.get_perceptions(hub.orchestrator)
}

/// Send a signal to the hub for processing (manual ingestion).
pub fn ingest(hub: Hub, signal signal: signal.Signal) -> Nil {
  orchestrator.ingest(hub.orchestrator, signal)
}

/// Subscribe to real-time perception updates.
pub fn on_perception(hub: Hub, callback: fn(List(Perception)) -> Nil) -> Nil {
  let sub = process.new_subject()
  orchestrator.subscribe(hub.orchestrator, sub)
  do_spawn_listener(sub, callback)
}

// ─── Internal: sensor actor wiring ──────────────────────────────────────────

/// Start a sensor actor for each SensorConfig.
/// Each sensor's signals are automatically forwarded to the orchestrator.
fn start_sensor_actors(
  sensors: List(SensorConfig),
  orch: Subject(OrchestratorMsg),
) -> List(Subject(sensor_actor.SensorMsg)) {
  list.filter_map(sensors, fn(sensor_config) {
    start_one_sensor(sensor_config, orch)
  })
}

fn start_one_sensor(
  config: SensorConfig,
  orch: Subject(OrchestratorMsg),
) -> Result(Subject(sensor_actor.SensorMsg), Nil) {
  // Create a bridge subject: sensor actor → orchestrator
  let bridge = process.new_subject()

  // Spawn bridge forwarder: receives Signals, sends to orchestrator
  spawn_bridge(bridge, orch)

  // Start the sensor actor with bridge as subscriber
  let test_config =
    sensor_actor.TestConfig(
      id: config.id,
      kind: config.kind,
      subscriber: bridge,
    )

  case sensor_actor.start_test(test_config) {
    Ok(actor_subject) -> {
      // If transport is UDP, start the UDP listener
      case config.transport {
        Udp(_host, port) -> {
          let _ = sensor_udp.start_listener(port, actor_subject)
          Nil
        }
        _ -> Nil
      }
      Ok(actor_subject)
    }
    Error(_) -> Error(Nil)
  }
}

/// Spawn a process that forwards Signals from sensor actor to orchestrator.
@external(erlang, "aether_bridge_ffi", "spawn_bridge")
fn spawn_bridge(
  from: Subject(signal.Signal),
  to: Subject(OrchestratorMsg),
) -> Nil

@external(erlang, "aether_listener_ffi", "spawn_listener")
fn do_spawn_listener(
  sub: Subject(List(Perception)),
  callback: fn(List(Perception)) -> Nil,
) -> Nil
