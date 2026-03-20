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

/// Set the model checkpoint and device.
pub fn with_model(
  config: SpaceConfig,
  path path: String,
  device device: String,
) -> SpaceConfig {
  space.with_model(config, path: path, device: device)
}

/// Set inference tasks.
pub fn with_tasks(config: SpaceConfig, tasks: List(String)) -> SpaceConfig {
  space.with_tasks(config, tasks)
}

/// Start the Æther perception system.
/// Boots: orchestrator → sensor actors (with UDP listeners) → HTTP API.
/// Signals flow automatically: UDP → sensor actor → orchestrator → perceptions.
/// No bridge processes — sensors call orchestrator.ingest() directly via callback.
pub fn start(config: SpaceConfig) -> Result(Hub, String) {
  case config.sensors {
    [] -> Error("No sensors configured")
    sensors -> {
      // 1. Start orchestrator
      let orch_config =
        orchestrator.OrchestratorConfig(
          conditioners: config.conditioners,
          model_path: config.model_path,
          device: config.device,
          tasks: config.tasks,
        )
      case orchestrator.start(orch_config) {
        Error(e) -> Error("Orchestrator failed: " <> e)
        Ok(orch) -> {
          // 2. Start sensor actors — each calls orchestrator.ingest directly
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

// ─── Internal: sensor actor wiring (pure Gleam, no bridge FFI) ──────────────

/// Start a sensor actor for each SensorConfig.
/// Each sensor sends signals directly to the orchestrator via callback — no
/// intermediate bridge process, no raw erlang:send, fully type-safe.
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
  // The sensor actor calls orchestrator.ingest() directly when it parses a signal.
  // Pure Gleam — no Erlang bridge process, no raw message passing.
  let on_signal = fn(signal: signal.Signal) {
    orchestrator.ingest(orch, signal)
  }

  let sensor_config =
    sensor_actor.SensorStartConfig(
      id: config.id,
      kind: config.kind,
      on_signal: on_signal,
    )

  case sensor_actor.start(sensor_config) {
    Ok(actor_subject) -> {
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

@external(erlang, "aether_listener_ffi", "spawn_listener")
fn do_spawn_listener(
  sub: Subject(List(Perception)),
  callback: fn(List(Perception)) -> Nil,
) -> Nil
