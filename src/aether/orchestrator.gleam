/// Æther Orchestrator — connects sensor → pipeline → fusion → brain → perception.
///
/// This is the heart of the data flow. It receives Signals from sensor actors,
/// processes them through the stateful conditioning pipeline (with ring buffer
/// for AveCSI), runs foundation model inference, parses real JSON results,
/// and emits Perceptions to subscribers.
import aether/condition/pipeline.{type Conditioner, type PipelineMode, Inference}
import aether/condition/ring_buffer.{type RingBuffer}
import aether/core/types.{Vec3}
import aether/nif/brain as brain_nif
import aether/nif/signal as signal_nif
import aether/perception.{
  type Event, type Keypoint, type Perception, Activity, Coco17, Keypoint,
  Location, Pose, Presence, Vitals,
}
import aether/signal.{type Signal}
import gleam/dynamic
import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string

pub type OrchestratorMsg {
  IngestSignal(Signal)
  GetPerceptions(reply: Subject(List(Perception)))
  Subscribe(Subject(List(Perception)))
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
    // Stateful ring buffer for AveCSI stabilization
    frame_buffer: RingBuffer(List(Float)),
    buffer_capacity: Int,
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

pub fn start(
  config: OrchestratorConfig,
) -> Result(Subject(OrchestratorMsg), String) {
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
      frame_buffer: ring_buffer.new(20),
      buffer_capacity: 20,
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

pub fn ingest(orch: Subject(OrchestratorMsg), signal: Signal) -> Nil {
  actor.send(orch, IngestSignal(signal))
}

pub fn get_perceptions(orch: Subject(OrchestratorMsg)) -> List(Perception) {
  actor.call(orch, 5000, GetPerceptions)
}

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
      // 1. Run non-stateful conditioning pipeline stages
      let conditioned =
        pipeline.run_pipeline(signal, state.conditioners, state.mode)
        |> result.unwrap(signal)

      // 2. Extract float embedding from payload
      let frame_floats = signal_to_floats(conditioned)

      // 3. Push into ring buffer for AveCSI stabilization
      let new_buffer = ring_buffer.push(state.frame_buffer, frame_floats)

      // 4. Run AveCSI stabilization over buffered frames
      let stabilized = case ring_buffer.size(new_buffer) > 1 {
        True -> {
          let frames = ring_buffer.to_list(new_buffer) |> list.reverse()
          let window = ring_buffer.size(new_buffer)
          signal_nif.avecsi_stabilize(frames, window)
        }
        False -> frame_floats
      }

      // 5. Run foundation model inference with stabilized embedding
      let perceptions = run_inference(state.model, stabilized, state.tasks)

      // 6. Notify subscribers
      list.each(state.subscribers, fn(sub) { process.send(sub, perceptions) })

      actor.continue(
        OrchestratorState(
          ..state,
          last_perceptions: perceptions,
          frames_processed: state.frames_processed + 1,
          frame_buffer: new_buffer,
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

// ─── Signal → Floats ────────────────────────────────────────────────────────

fn signal_to_floats(signal: Signal) -> List(Float) {
  let floats = decode_f64s(signal.payload, []) |> list.reverse()
  case floats {
    [] -> bytes_to_normalized(signal.payload)
    _ -> floats
  }
}

fn decode_f64s(data: BitArray, acc: List(Float)) -> List(Float) {
  case data {
    <<val:float-size(64), rest:bytes>> -> decode_f64s(rest, [val, ..acc])
    _ -> acc
  }
}

fn bytes_to_normalized(data: BitArray) -> List(Float) {
  do_bytes(data, []) |> list.reverse()
}

fn do_bytes(data: BitArray, acc: List(Float)) -> List(Float) {
  case data {
    <<byte:int-size(8), rest:bytes>> ->
      do_bytes(rest, [int_to_float(byte) /. 255.0, ..acc])
    _ -> acc
  }
}

@external(erlang, "erlang", "float")
fn int_to_float(n: Int) -> Float

// ─── Inference + JSON Parsing ───────────────────────────────────────────────

fn run_inference(
  model: dynamic.Dynamic,
  embedding: List(Float),
  tasks: List(String),
) -> List(Perception) {
  case embedding {
    [] -> []
    _ -> {
      let json_str = brain_nif.foundation_infer(model, embedding, tasks)
      parse_brain_json(json_str)
    }
  }
}

/// Parse the JSON array returned by aether_brain NIF.
/// Format: [{"task":"pose","data":{...},"confidence":0.9}, ...]
fn parse_brain_json(json_str: String) -> List(Perception) {
  // The entire JSON string contains all results — parse each task
  // by finding task markers in the full string
  let tasks_found = find_task_blocks(json_str)
  list.filter_map(tasks_found, fn(block) { parse_single_result(block) })
}

/// Find individual task JSON blocks within the array.
fn find_task_blocks(json: String) -> List(String) {
  // Split by "task":" to find each result block
  case string.split(json, "\"task\":\"") {
    [_prefix, ..blocks] ->
      list.map(blocks, fn(block) { "\"task\":\"" <> block })
    _ -> []
  }
}

fn parse_single_result(json_obj: String) -> Result(Perception, Nil) {
  let task = extract_string_value(json_obj, "task")
  let confidence = extract_number(json_obj, "confidence", 0.5)

  case task {
    "pose" -> {
      let keypoints = parse_keypoints(json_obj)
      Ok(Pose(keypoints: keypoints, skeleton: Coco17, confidence: confidence))
    }
    "vitals" -> {
      Ok(Vitals(
        heart_bpm: extract_number(json_obj, "heart_bpm", 0.0),
        breath_bpm: extract_number(json_obj, "breath_bpm", 0.0),
        hrv: case extract_number(json_obj, "hrv", -1.0) {
          val if val >=. 0.0 -> Some(val)
          _ -> None
        },
        confidence: confidence,
      ))
    }
    "presence" -> {
      let occupied = string.contains(json_obj, "\"occupied\":true")
      let count =
        extract_number(json_obj, "occupant_count", 0.0) |> float.round()
      Ok(
        Presence(zones: [], total_occupants: case occupied {
          True -> int.max(count, 1)
          False -> 0
        }),
      )
    }
    "activity" -> {
      let label = extract_string_value(json_obj, "label")
      Ok(Activity(label: label, confidence: confidence, duration_ms: 0))
    }
    "location" -> {
      let x = extract_number(json_obj, "\"x\"", 0.0)
      let y = extract_number(json_obj, "\"y\"", 0.0)
      let z = extract_number(json_obj, "\"z\"", 0.0)
      let acc = extract_number(json_obj, "accuracy_m", 5.0)
      Ok(Location(position: Vec3(x, y, z), accuracy_m: acc, velocity: None))
    }
    _ -> Error(Nil)
  }
}

fn parse_keypoints(json_obj: String) -> List(Keypoint) {
  // Extract individual keypoint objects from the keypoints array
  case string.split(json_obj, "\"name\":\"") {
    [_header, ..parts] ->
      list.filter_map(parts, fn(part) {
        case string.split(part, "\"") {
          [name, ..rest] -> {
            let rest_str = string.join(rest, "\"")
            Ok(Keypoint(
              id: 0,
              name: name,
              x: extract_number(rest_str, "\"x\"", 0.0),
              y: extract_number(rest_str, "\"y\"", 0.0),
              z: extract_number(rest_str, "\"z\"", 0.0),
              confidence: extract_number(rest_str, "confidence", 0.5),
              velocity: None,
            ))
          }
          _ -> Error(Nil)
        }
      })
    _ -> []
  }
}

// ─── JSON string helpers ────────────────────────────────────────────────────

/// Split a JSON array string into individual objects.
fn split_json_array(json: String) -> List(String) {
  // Remove outer brackets
  let trimmed = string.trim(json)
  let inner = case string.starts_with(trimmed, "[") {
    True ->
      trimmed
      |> string.drop_start(1)
      |> string.drop_end(1)
    False -> trimmed
  }

  // Split by "},{" and reconstruct
  case string.split(inner, "},{") {
    [single] -> [single]
    parts ->
      list.index_map(parts, fn(part, i) {
        case i == 0, i == list.length(parts) - 1 {
          True, _ -> part <> "}"
          _, True -> "{" <> part
          _, _ -> "{" <> part <> "}"
        }
      })
  }
}

/// Extract a string value for a given key from a JSON-like string.
/// Finds "key":"value" pattern.
fn extract_string_value(json: String, key: String) -> String {
  let pattern = "\"" <> key <> "\":\""
  case string.split(json, pattern) {
    [_, after, ..] ->
      case string.split(after, "\"") {
        [value, ..] -> value
        _ -> ""
      }
    _ -> ""
  }
}

/// Extract a numeric value for a given key from a JSON-like string.
/// Finds "key":NUMBER pattern.
fn extract_number(json: String, key: String, default: Float) -> Float {
  // Handle both "key": and key: patterns (key might already have quotes)
  let pattern = case string.starts_with(key, "\"") {
    True -> key <> ":"
    False -> "\"" <> key <> "\":"
  }
  case string.split(json, pattern) {
    [_, after, ..] -> {
      let num_str = take_number_chars(after)
      case float.parse(num_str) {
        Ok(val) -> val
        Error(_) ->
          case int.parse(num_str) {
            Ok(val) -> int_to_float(val)
            Error(_) -> default
          }
      }
    }
    _ -> default
  }
}

/// Take characters that form a number from the start of a string.
fn take_number_chars(s: String) -> String {
  let chars = string.to_graphemes(s)
  take_num_acc(chars, [])
  |> list.reverse()
  |> string.join("")
}

fn take_num_acc(chars: List(String), acc: List(String)) -> List(String) {
  case chars {
    [c, ..rest] ->
      case c == "-" || c == "." || is_digit(c) {
        True -> take_num_acc(rest, [c, ..acc])
        False -> acc
      }
    [] -> acc
  }
}

fn is_digit(c: String) -> Bool {
  c == "0"
  || c == "1"
  || c == "2"
  || c == "3"
  || c == "4"
  || c == "5"
  || c == "6"
  || c == "7"
  || c == "8"
  || c == "9"
}
