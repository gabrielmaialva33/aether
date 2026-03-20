/// Æther Supervision Tree
///
/// Pure Gleam — no bridge FFI. Sensors call orchestrator.ingest() directly.
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

/// Start the full Æther system.
pub fn start(
  sensors: List(SensorConfig),
  conditioners: List(Conditioner),
  _zones: List(Zone),
  api_port: Int,
  model_path: String,
  device: String,
  tasks: List(String),
) -> Result(Subject(orchestrator.OrchestratorMsg), String) {
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
      list.each(sensors, fn(config) { start_sensor(config, orch) })
      let _ = api.start(api_port, orch)
      Ok(orch)
    }
  }
}

fn start_sensor(
  config: SensorConfig,
  orch: Subject(orchestrator.OrchestratorMsg),
) -> Nil {
  let on_signal = fn(sig: signal.Signal) { orchestrator.ingest(orch, sig) }

  case
    sensor_actor.start(sensor_actor.SensorStartConfig(
      id: config.id,
      kind: config.kind,
      on_signal: on_signal,
    ))
  {
    Ok(actor_subject) ->
      case config.transport {
        Udp(_host, port) -> {
          let _ = sensor_udp.start_listener(port, actor_subject)
          Nil
        }
        _ -> Nil
      }
    Error(_) -> Nil
  }
}
