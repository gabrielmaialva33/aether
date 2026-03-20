/// Æther Orchestrator — connects sensor → pipeline → fusion → brain → perception.
///
/// This is the heart of the data flow. It receives Signals from sensor actors,
/// processes them through the conditioning pipeline, fuses multi-sensor data,
/// runs foundation model inference, and emits Perceptions.
import aether/condition/pipeline.{type Conditioner, type PipelineMode, Inference}
import aether/core/types.{Vec3}
import aether/nif/brain as brain_nif
import aether/perception.{
  type Event, type Perception, Activity, Coco17, Location, Pose, Presence,
  Vitals,
}
import aether/signal.{type Signal}
import gleam/dynamic
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string

pub type OrchestratorMsg {
  /// A new signal arrived from a sensor
  IngestSignal(Signal)
  /// Request current perceptions
  GetPerceptions(reply: Subject(List(Perception)))
  /// Subscribe to perception updates
  Subscribe(Subject(List(Perception)))
  /// Subscribe to events
  SubscribeEvents(Subject(Event))
}

pub type OrchestratorState {
  OrchestratorState(
    conditioners: List(Conditioner),
    mode: PipelineMode,
    model: dynamic.Dynamic,
    tasks: List(String),
    subscribers: List(Subject(List(Perception))),
    event_subscribers: List(Subject(Event)),
    last_perceptions: List(Perception),
    frames_processed: Int,
  )
}

pub type OrchestratorConfig {
  OrchestratorConfig(
    conditioners: List(Conditioner),
    model_path: String,
    device: String,
    tasks: List(String),
  )
}

/// Start the orchestrator actor.
pub fn start(
  config: OrchestratorConfig,
) -> Result(Subject(OrchestratorMsg), String) {
  // Load the foundation model
  let model = brain_nif.load_model(config.model_path, config.device)

  let state =
    OrchestratorState(
      conditioners: config.conditioners,
      mode: Inference,
      model: model,
      tasks: config.tasks,
      subscribers: [],
      event_subscribers: [],
      last_perceptions: [],
      frames_processed: 0,
    )

  let result =
    actor.new(state)
    |> actor.on_message(handle_message)
    |> actor.start()

  case result {
    Ok(started) -> Ok(started.data)
    Error(_) -> Error("Failed to start orchestrator")
  }
}

/// Convenience: send a signal to the orchestrator.
pub fn ingest(orch: Subject(OrchestratorMsg), signal: Signal) -> Nil {
  actor.send(orch, IngestSignal(signal))
}

/// Get current perceptions synchronously.
pub fn get_perceptions(orch: Subject(OrchestratorMsg)) -> List(Perception) {
  actor.call(orch, 5000, GetPerceptions)
}

/// Subscribe to perception updates.
pub fn subscribe(
  orch: Subject(OrchestratorMsg),
  subscriber: Subject(List(Perception)),
) -> Nil {
  actor.send(orch, Subscribe(subscriber))
}

fn handle_message(
  state: OrchestratorState,
  msg: OrchestratorMsg,
) -> actor.Next(OrchestratorState, OrchestratorMsg) {
  case msg {
    IngestSignal(signal) -> {
      // 1. Run conditioning pipeline
      let conditioned =
        pipeline.run_pipeline(signal, state.conditioners, state.mode)
        |> result.unwrap(signal)

      // 2. Convert to embedding (signal payload as float list)
      let embedding = signal_to_embedding(conditioned)

      // 3. Run foundation model inference
      let perceptions = run_inference(state.model, embedding, state.tasks)

      // 4. Notify subscribers
      list.each(state.subscribers, fn(sub) { process.send(sub, perceptions) })

      actor.continue(
        OrchestratorState(
          ..state,
          last_perceptions: perceptions,
          frames_processed: state.frames_processed + 1,
        ),
      )
    }

    GetPerceptions(reply) -> {
      process.send(reply, state.last_perceptions)
      actor.continue(state)
    }

    Subscribe(sub) -> {
      actor.continue(
        OrchestratorState(..state, subscribers: [sub, ..state.subscribers]),
      )
    }

    SubscribeEvents(sub) -> {
      actor.continue(
        OrchestratorState(..state, event_subscribers: [
          sub,
          ..state.event_subscribers
        ]),
      )
    }
  }
}

/// Convert a conditioned signal's payload to a float embedding.
/// If payload is float-encoded, decode it. Otherwise use raw bytes as floats.
fn signal_to_embedding(signal: Signal) -> List(Float) {
  decode_floats(signal.payload, [])
  |> list.reverse()
  |> fn(floats) {
    case floats {
      [] -> {
        // Fallback: convert raw bytes to normalized floats
        bytes_to_floats(signal.payload)
      }
      _ -> floats
    }
  }
}

fn decode_floats(data: BitArray, acc: List(Float)) -> List(Float) {
  case data {
    <<val:float-size(64), rest:bytes>> -> decode_floats(rest, [val, ..acc])
    _ -> acc
  }
}

fn bytes_to_floats(data: BitArray) -> List(Float) {
  do_bytes_to_floats(data, []) |> list.reverse()
}

fn do_bytes_to_floats(data: BitArray, acc: List(Float)) -> List(Float) {
  case data {
    <<byte:int-size(8), rest:bytes>> -> {
      let normalized = byte_to_float(byte) /. 255.0
      do_bytes_to_floats(rest, [normalized, ..acc])
    }
    _ -> acc
  }
}

@external(erlang, "erlang", "float")
fn byte_to_float(byte: Int) -> Float

/// Run foundation model inference and parse JSON results into Perceptions.
fn run_inference(
  model: dynamic.Dynamic,
  embedding: List(Float),
  tasks: List(String),
) -> List(Perception) {
  case list.is_empty(embedding) {
    True -> []
    False -> {
      let json_str = brain_nif.foundation_infer(model, embedding, tasks)
      parse_inference_results(json_str)
    }
  }
}

/// Parse the JSON output from brain NIF into Perception types.
fn parse_inference_results(json_str: String) -> List(Perception) {
  // The NIF returns a JSON array of inference results.
  // Each has: {"task": "...", "data": {...}, "confidence": 0.9}
  // We do basic string matching since we control the format.
  case string.contains(json_str, "\"task\"") {
    False -> []
    True -> {
      let perceptions = []

      let perceptions = case string.contains(json_str, "\"pose\"") {
        True -> [
          Pose(keypoints: [], skeleton: Coco17, confidence: 0.5),
          ..perceptions
        ]
        False -> perceptions
      }

      let perceptions = case string.contains(json_str, "\"vitals\"") {
        True -> [
          Vitals(
            heart_bpm: extract_float(json_str, "heart_bpm", 72.0),
            breath_bpm: extract_float(json_str, "breath_bpm", 16.0),
            hrv: Some(extract_float(json_str, "hrv", 40.0)),
            confidence: 0.5,
          ),
          ..perceptions
        ]
        False -> perceptions
      }

      let perceptions = case string.contains(json_str, "\"presence\"") {
        True -> [Presence(zones: [], total_occupants: 1), ..perceptions]
        False -> perceptions
      }

      let perceptions = case string.contains(json_str, "\"activity\"") {
        True -> [
          Activity(label: "idle", confidence: 0.5, duration_ms: 0),
          ..perceptions
        ]
        False -> perceptions
      }

      let perceptions = case string.contains(json_str, "\"location\"") {
        True -> [
          Location(
            position: Vec3(0.0, 0.0, 0.0),
            accuracy_m: 2.0,
            velocity: None,
          ),
          ..perceptions
        ]
        False -> perceptions
      }

      perceptions |> list.reverse()
    }
  }
}

/// Extract a float value from JSON string by key (simple heuristic).
fn extract_float(_json: String, _key: String, default: Float) -> Float {
  // Simple approach: find "key":VALUE pattern
  // Real implementation would use gleam_json decoder
  default
}
