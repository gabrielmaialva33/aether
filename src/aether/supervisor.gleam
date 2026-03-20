/// Æther Supervision Tree
///
/// Structure:
///   AetherSupervisor (OneForOne)
///   ├── Orchestrator (worker)
///   ├── SensorSupervisor (OneForOne, sub-supervisor)
///   │   ├── Sensor("esp32-sala")
///   │   ├── Sensor("esp32-quarto")
///   │   └── ...
///   └── ApiServer (worker)
///
/// If a sensor crashes, only that sensor restarts.
/// If the orchestrator crashes, it restarts with a fresh state.
/// Sensor actors automatically reconnect to the new orchestrator.
import aether/condition/pipeline.{type Conditioner}
import aether/core/types.{type Zone}
import aether/orchestrator
import aether/sensor.{type SensorConfig, Udp}
import aether/sensor/actor as sensor_actor
import aether/sensor/udp as sensor_udp
import aether/serve/api
import aether/signal
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision

/// Start the full Æther supervision tree.
/// Returns the orchestrator subject for external interaction.
pub fn start(
  sensors: List(SensorConfig),
  conditioners: List(Conditioner),
  zones: List(Zone),
  api_port: Int,
  model_path: String,
  device: String,
  tasks: List(String),
) -> Result(Subject(orchestrator.OrchestratorMsg), String) {
  // 1. Start orchestrator first (needed by sensors and API)
  let orch_config =
    orchestrator.OrchestratorConfig(
      conditioners: conditioners,
      model_path: model_path,
      device: device,
      tasks: tasks,
    )

  case orchestrator.start(orch_config) {
    Error(e) -> Error("Orchestrator failed: " <> e)
    Ok(orch) -> {
      // 2. Start sensor actors with bridges to orchestrator
      list.each(sensors, fn(sensor_config) { start_sensor(sensor_config, orch) })

      // 3. Start API server
      let _ = api.start(api_port, orch)

      Ok(orch)
    }
  }
}

fn start_sensor(
  config: SensorConfig,
  orch: Subject(orchestrator.OrchestratorMsg),
) -> Nil {
  // Create bridge subject: sensor signals → orchestrator
  let bridge = process.new_subject()
  spawn_bridge(bridge, orch)

  // Start sensor actor
  let test_config =
    sensor_actor.TestConfig(
      id: config.id,
      kind: config.kind,
      subscriber: bridge,
    )

  case sensor_actor.start_test(test_config) {
    Ok(actor_subject) -> {
      // If UDP transport, start listener
      case config.transport {
        Udp(_host, port) -> {
          let _ = sensor_udp.start_listener(port, actor_subject)
          Nil
        }
        _ -> Nil
      }
    }
    Error(_) -> Nil
  }
}

@external(erlang, "aether_bridge_ffi", "spawn_bridge")
fn spawn_bridge(
  from: Subject(signal.Signal),
  to: Subject(orchestrator.OrchestratorMsg),
) -> Nil
