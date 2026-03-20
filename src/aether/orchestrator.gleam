/// Æther Orchestrator — connects sensor → pipeline → fusion → brain → perception.
///
/// This is the heart of the data flow. It receives Signals from sensor actors,
/// processes them through the stateful conditioning pipeline (with ring buffer
/// for AveCSI), runs foundation model inference, parses real JSON results,
/// and emits Perceptions to subscribers.
import aether/condition/pipeline.{type Conditioner, type PipelineMode, Inference}
import aether/condition/ring_buffer.{type RingBuffer}
import aether/core/types.{Vec3}
import aether/nif/brain.{type ModelRef}
import aether/nif/signal as signal_nif
import aether/perception.{
  type Event, type Keypoint, type Perception, Activity, Coco17, Keypoint,
  Location, Pose, Presence, Vitals,
}
import aether/signal.{type Signal}
import gleam/dynamic
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/result

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
    model: ModelRef,
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
  let model = brain.load_model(config.model_path, config.device)

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
  model: ModelRef,
  embedding: List(Float),
  tasks: List(String),
) -> List(Perception) {
  case embedding {
    [] -> []
    _ -> {
      let json_str = brain.foundation_infer(model, embedding, tasks)
      parse_brain_json(json_str)
    }
  }
}

/// Parse the JSON array returned by aether_brain NIF.
/// Format: [{"task":"pose","data":{...},"confidence":0.9}, ...]
/// Uses gleam_json + gleam/dynamic/decode for proper parsing.
fn parse_brain_json(json_str: String) -> List(Perception) {
  case json.parse(json_str, decode.list(inference_result_decoder())) {
    Ok(results) -> list.filter_map(results, result_to_perception)
    Error(_) -> []
  }
}

/// Decoded inference result from brain NIF.
type InferResult {
  InferResult(task: String, data: dynamic.Dynamic, confidence: Float)
}

fn inference_result_decoder() -> decode.Decoder(InferResult) {
  use task <- decode.field("task", decode.string)
  use data <- decode.field("data", decode.dynamic)
  use confidence <- decode.field("confidence", decode.float)
  decode.success(InferResult(task:, data:, confidence:))
}

/// Convert a decoded InferResult into a typed Perception.
fn result_to_perception(result: InferResult) -> Result(Perception, Nil) {
  case result.task {
    "pose" -> {
      let keypoints = decode_keypoints(result.data)
      Ok(Pose(keypoints:, skeleton: Coco17, confidence: result.confidence))
    }
    "vitals" -> {
      let decoder = {
        use heart <- decode.field("heart_bpm", decode.float)
        use breath <- decode.field("breath_bpm", decode.float)
        use hrv <- decode.optional_field("hrv", 0.0, decode.float)
        decode.success(#(heart, breath, hrv))
      }
      case decode.run(result.data, decoder) {
        Ok(#(heart, breath, hrv)) ->
          Ok(Vitals(
            heart_bpm: heart,
            breath_bpm: breath,
            hrv: Some(hrv),
            confidence: result.confidence,
          ))
        Error(_) -> Error(Nil)
      }
    }
    "presence" -> {
      let decoder = {
        use count <- decode.optional_field("occupant_count", 0, decode.int)
        use occupied <- decode.optional_field("occupied", False, decode.bool)
        decode.success(#(count, occupied))
      }
      case decode.run(result.data, decoder) {
        Ok(#(count, occupied)) ->
          Ok(
            Presence(zones: [], total_occupants: case occupied {
              True -> int.max(count, 1)
              False -> 0
            }),
          )
        Error(_) -> Ok(Presence(zones: [], total_occupants: 0))
      }
    }
    "activity" -> {
      let decoder = {
        use label <- decode.field("label", decode.string)
        decode.success(label)
      }
      case decode.run(result.data, decoder) {
        Ok(label) ->
          Ok(Activity(label:, confidence: result.confidence, duration_ms: 0))
        Error(_) -> Error(Nil)
      }
    }
    "location" -> {
      let decoder = {
        use x <- decode.field("x", decode.float)
        use y <- decode.field("y", decode.float)
        use z <- decode.field("z", decode.float)
        use acc <- decode.optional_field("accuracy_m", 5.0, decode.float)
        decode.success(#(x, y, z, acc))
      }
      case decode.run(result.data, decoder) {
        Ok(#(x, y, z, acc)) ->
          Ok(Location(position: Vec3(x, y, z), accuracy_m: acc, velocity: None))
        Error(_) -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

/// Decode keypoints from the "data" field of a pose result.
fn decode_keypoints(data: dynamic.Dynamic) -> List(Keypoint) {
  let kp_decoder = {
    use id <- decode.field("id", decode.int)
    use name <- decode.field("name", decode.string)
    use x <- decode.field("x", decode.float)
    use y <- decode.field("y", decode.float)
    use z <- decode.field("z", decode.float)
    use conf <- decode.field("confidence", decode.float)
    decode.success(Keypoint(
      id:,
      name:,
      x:,
      y:,
      z:,
      confidence: conf,
      velocity: None,
    ))
  }
  let decoder =
    decode.field("keypoints", decode.list(kp_decoder), fn(kps) {
      decode.success(kps)
    })
  case decode.run(data, decoder) {
    Ok(kps) -> kps
    Error(_) -> []
  }
}
