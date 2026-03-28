/// Æther Orchestrator — connects sensor → pipeline → fusion → brain → perception.
///
/// Per-node state pipeline: each ESP32 node gets independent frame history,
/// AveCSI stabilization, and raw amplitudes. Aggregate perceptions are merged
/// across all active nodes. Presence count uses hysteresis to prevent flicker.
/// Nodes are marked offline after 5s without frames.
import aether/condition/pipeline.{type Conditioner, type PipelineMode, Inference}
import aether/condition/ring_buffer.{type RingBuffer}
import aether/core/types.{type SensorId, Vec3}
import aether/nif/brain.{type ModelRef}
import aether/nif/signal as signal_nif
import aether/perception.{
  type Event, type Keypoint, type Perception, Activity, Coco17, Keypoint,
  Location, Pose, Presence, SensorOffline, SensorRecovered, Vitals,
}
import aether/signal.{type Signal}
import gleam/dict.{type Dict}
import gleam/dynamic
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/otp/actor
import gleam/result

// ─── Per-Node State ─────────────────────────────────────────────────────────

/// Independent state for each ESP32 sensor node.
pub type NodeState {
  NodeState(
    sensor_id: SensorId,
    frame_buffer: RingBuffer(List(Float)),
    last_amplitudes: List(Float),
    last_perceptions: List(Perception),
    frames_processed: Int,
    last_seen_ms: Int,
    is_online: Bool,
  )
}

fn new_node_state(sensor_id: SensorId) -> NodeState {
  NodeState(
    sensor_id:,
    frame_buffer: ring_buffer.new(20),
    last_amplitudes: [],
    last_perceptions: [],
    frames_processed: 0,
    last_seen_ms: now_ms(),
    is_online: True,
  )
}

// ─── Presence Hysteresis ────────────────────────────────────────────────────

/// Debounce state for presence count — requires N consistent readings to change.
pub type PresenceHysteresis {
  PresenceHysteresis(
    confirmed_count: Int,
    candidate_count: Int,
    streak: Int,
    threshold: Int,
  )
}

fn new_hysteresis() -> PresenceHysteresis {
  PresenceHysteresis(
    confirmed_count: 0,
    candidate_count: 0,
    streak: 0,
    threshold: 3,
  )
}

fn update_hysteresis(h: PresenceHysteresis, raw_count: Int) -> PresenceHysteresis {
  case raw_count == h.candidate_count {
    True -> {
      let new_streak = h.streak + 1
      case new_streak >= h.threshold {
        True ->
          PresenceHysteresis(..h, confirmed_count: raw_count, streak: new_streak)
        False -> PresenceHysteresis(..h, streak: new_streak)
      }
    }
    False ->
      PresenceHysteresis(..h, candidate_count: raw_count, streak: 1)
  }
}

// ─── CSI Snapshot ───────────────────────────────────────────────────────────

pub type CsiSnapshot {
  CsiSnapshot(amplitudes: List(Float), source: String, subcarriers: Int)
}

// ─── Node Health (for WS broadcast) ────────────────────────────────────────

pub type NodeHealth {
  NodeHealth(sensor_id: SensorId, is_online: Bool, frames_processed: Int)
}

// ─── Messages ──────────────────────────────────────────────────────────────

pub type OrchestratorMsg {
  IngestSignal(Signal)
  GetPerceptions(reply: Subject(List(Perception)))
  GetCsiRaw(reply: Subject(CsiSnapshot))
  GetNodeHealth(reply: Subject(List(NodeHealth)))
  Subscribe(Subject(List(Perception)))
  SubscribeEvents(Subject(Event))
  CheckOfflineNodes
}

// ─── State ─────────────────────────────────────────────────────────────────

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
    buffer_capacity: Int,
    // Per-node state pipeline (replaces single shared buffer)
    node_states: Dict(SensorId, NodeState),
    // Presence hysteresis
    presence: PresenceHysteresis,
    // Node offline detection timeout (ms)
    offline_timeout_ms: Int,
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

// ─── Public API ────────────────────────────────────────────────────────────

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
      buffer_capacity: 20,
      node_states: dict.new(),
      presence: new_hysteresis(),
      offline_timeout_ms: 5000,
    )

  let result =
    actor.new(state)
    |> actor.on_message(handle_message)
    |> actor.start()

  case result {
    Ok(started) -> {
      // Start offline check timer (every 2s)
      start_offline_timer(started.data)
      Ok(started.data)
    }
    Error(_) -> Error("Failed to start orchestrator")
  }
}

pub fn ingest(orch: Subject(OrchestratorMsg), signal: Signal) -> Nil {
  actor.send(orch, IngestSignal(signal))
}

pub fn get_perceptions(orch: Subject(OrchestratorMsg)) -> List(Perception) {
  actor.call(orch, 5000, GetPerceptions)
}

pub fn get_csi_raw(orch: Subject(OrchestratorMsg)) -> CsiSnapshot {
  actor.call(orch, 5000, GetCsiRaw)
}

pub fn get_node_health(orch: Subject(OrchestratorMsg)) -> List(NodeHealth) {
  actor.call(orch, 5000, GetNodeHealth)
}

pub fn subscribe(
  orch: Subject(OrchestratorMsg),
  subscriber: Subject(List(Perception)),
) -> Nil {
  actor.send(orch, Subscribe(subscriber))
}

// ─── Message Handler ───────────────────────────────────────────────────────

fn handle_message(
  state: OrchestratorState,
  msg: OrchestratorMsg,
) -> actor.Next(OrchestratorState, OrchestratorMsg) {
  case msg {
    IngestSignal(signal) -> handle_ingest(state, signal)

    GetPerceptions(reply) -> {
      process.send(reply, state.last_perceptions)
      actor.continue(state)
    }

    GetCsiRaw(reply) -> {
      // Aggregate amplitudes from all online nodes
      let all_amps =
        dict.values(state.node_states)
        |> list.filter(fn(ns) { ns.is_online })
        |> list.flat_map(fn(ns) { ns.last_amplitudes })
      let source =
        dict.keys(state.node_states)
        |> list.first()
        |> result.unwrap("unknown")
      process.send(
        reply,
        CsiSnapshot(amplitudes: all_amps, source:, subcarriers: 32),
      )
      actor.continue(state)
    }

    GetNodeHealth(reply) -> {
      let health =
        dict.values(state.node_states)
        |> list.map(fn(ns) {
          NodeHealth(
            sensor_id: ns.sensor_id,
            is_online: ns.is_online,
            frames_processed: ns.frames_processed,
          )
        })
      process.send(reply, health)
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

    CheckOfflineNodes -> handle_offline_check(state)
  }
}

// ─── Ingest Handler (per-node pipeline) ────────────────────────────────────

fn handle_ingest(
  state: OrchestratorState,
  signal: Signal,
) -> actor.Next(OrchestratorState, OrchestratorMsg) {
  let node_id = signal.source

  // 1. Get or create node state
  let node =
    dict.get(state.node_states, node_id)
    |> result.unwrap(new_node_state(node_id))

  // If node was offline, emit recovery event
  let was_offline = !node.is_online
  let state = case was_offline {
    True -> {
      emit_event(state, SensorRecovered(node_id))
      state
    }
    False -> state
  }

  // 2. Run conditioning pipeline
  let conditioned =
    pipeline.run_pipeline(signal, state.conditioners, state.mode)
    |> result.unwrap(signal)

  // 3. Extract float embedding
  let frame_floats = signal_to_floats(conditioned)

  // 4. Push into per-node ring buffer
  let new_buffer = ring_buffer.push(node.frame_buffer, frame_floats)

  // 5. AveCSI stabilization on per-node buffer
  let stabilized = case ring_buffer.size(new_buffer) > 1 {
    True -> {
      let frames = ring_buffer.to_list(new_buffer) |> list.reverse()
      let window = ring_buffer.size(new_buffer)
      signal_nif.avecsi_stabilize(frames, window)
    }
    False -> frame_floats
  }

  // 6. Run inference on this node's stabilized data
  let node_perceptions = run_inference(state.model, stabilized, state.tasks)

  // 7. Update node state
  let updated_node =
    NodeState(
      ..node,
      frame_buffer: new_buffer,
      last_amplitudes: frame_floats,
      last_perceptions: node_perceptions,
      frames_processed: node.frames_processed + 1,
      last_seen_ms: now_ms(),
      is_online: True,
    )

  let new_node_states = dict.insert(state.node_states, node_id, updated_node)

  // 8. Aggregate perceptions across all online nodes
  let aggregated = aggregate_perceptions(new_node_states)

  // 9. Apply presence hysteresis
  let raw_presence = extract_presence_count(aggregated)
  let new_hysteresis = update_hysteresis(state.presence, raw_presence)
  let final_perceptions =
    apply_hysteresis_to_perceptions(aggregated, new_hysteresis.confirmed_count)

  // 10. Notify subscribers
  list.each(state.subscribers, fn(sub) {
    process.send(sub, final_perceptions)
  })

  actor.continue(
    OrchestratorState(
      ..state,
      node_states: new_node_states,
      last_perceptions: final_perceptions,
      frames_processed: state.frames_processed + 1,
      presence: new_hysteresis,
    ),
  )
}

// ─── Offline Detection ─────────────────────────────────────────────────────

fn handle_offline_check(
  state: OrchestratorState,
) -> actor.Next(OrchestratorState, OrchestratorMsg) {
  let current = now_ms()
  let timeout = state.offline_timeout_ms

  let #(new_nodes, events) =
    dict.fold(state.node_states, #(dict.new(), []), fn(acc, id, node) {
      let #(nodes, evts) = acc
      let elapsed = current - node.last_seen_ms
      case elapsed > timeout && node.is_online {
        True -> {
          let offline_node = NodeState(..node, is_online: False)
          #(
            dict.insert(nodes, id, offline_node),
            [SensorOffline(id), ..evts],
          )
        }
        False -> #(dict.insert(nodes, id, node), evts)
      }
    })

  // Emit offline events
  list.each(events, fn(evt) { emit_event(state, evt) })

  actor.continue(OrchestratorState(..state, node_states: new_nodes))
}

fn start_offline_timer(orch: Subject(OrchestratorMsg)) -> Nil {
  spawn_offline_checker(orch)
}

@external(erlang, "aether_time_ffi", "spawn_offline_checker")
fn spawn_offline_checker(orch: Subject(OrchestratorMsg)) -> Nil

// ─── Aggregation ───────────────────────────────────────────────────────────

/// Merge perceptions from all online nodes.
/// Strategy: take the highest-confidence version of each perception type.
fn aggregate_perceptions(
  node_states: Dict(SensorId, NodeState),
) -> List(Perception) {
  let all =
    dict.values(node_states)
    |> list.filter(fn(ns) { ns.is_online })
    |> list.flat_map(fn(ns) { ns.last_perceptions })

  // Group by type and pick best
  let best_pose = pick_best_by_type(all, is_pose)
  let best_vitals = pick_best_by_type(all, is_vitals)
  let best_presence = pick_best_by_type(all, is_presence)
  let best_activity = pick_best_by_type(all, is_activity)
  let best_location = pick_best_by_type(all, is_location)

  [best_pose, best_vitals, best_presence, best_activity, best_location]
  |> list.filter_map(fn(x) { x })
}

fn pick_best_by_type(
  perceptions: List(Perception),
  predicate: fn(Perception) -> Bool,
) -> Result(Perception, Nil) {
  perceptions
  |> list.filter(predicate)
  |> list.sort(fn(a, b) {
    float_compare(perception_confidence(b), perception_confidence(a))
  })
  |> list.first()
}

fn perception_confidence(p: Perception) -> Float {
  case p {
    Pose(_, _, c) -> c
    Vitals(_, _, _, c) -> c
    Activity(_, c, _) -> c
    Presence(_, count) -> int_to_float(count)
    Location(_, acc, _) -> 1.0 /. { acc +. 0.01 }
    _ -> 0.0
  }
}

fn is_pose(p: Perception) -> Bool {
  case p {
    Pose(_, _, _) -> True
    _ -> False
  }
}

fn is_vitals(p: Perception) -> Bool {
  case p {
    Vitals(_, _, _, _) -> True
    _ -> False
  }
}

fn is_presence(p: Perception) -> Bool {
  case p {
    Presence(_, _) -> True
    _ -> False
  }
}

fn is_activity(p: Perception) -> Bool {
  case p {
    Activity(_, _, _) -> True
    _ -> False
  }
}

fn is_location(p: Perception) -> Bool {
  case p {
    Location(_, _, _) -> True
    _ -> False
  }
}

// ─── Hysteresis Helpers ────────────────────────────────────────────────────

fn extract_presence_count(perceptions: List(Perception)) -> Int {
  list.fold(perceptions, 0, fn(acc, p) {
    case p {
      Presence(_, count) -> int.max(acc, count)
      _ -> acc
    }
  })
}

fn apply_hysteresis_to_perceptions(
  perceptions: List(Perception),
  confirmed: Int,
) -> List(Perception) {
  list.map(perceptions, fn(p) {
    case p {
      Presence(zones, _) -> Presence(zones:, total_occupants: confirmed)
      other -> other
    }
  })
}

// ─── Event Emission ────────────────────────────────────────────────────────

fn emit_event(state: OrchestratorState, event: Event) -> Nil {
  list.each(state.event_subscribers, fn(sub) { process.send(sub, event) })
}

// ─── Signal → Floats ───────────────────────────────────────────────────────

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

// ─── Inference + JSON Parsing ──────────────────────────────────────────────

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

fn parse_brain_json(json_str: String) -> List(Perception) {
  case json.parse(json_str, decode.list(inference_result_decoder())) {
    Ok(results) -> list.filter_map(results, result_to_perception)
    Error(_) -> []
  }
}

type InferResult {
  InferResult(task: String, data: dynamic.Dynamic, confidence: Float)
}

fn inference_result_decoder() -> decode.Decoder(InferResult) {
  use task <- decode.field("task", decode.string)
  use data <- decode.field("data", decode.dynamic)
  use confidence <- decode.field("confidence", decode.float)
  decode.success(InferResult(task:, data:, confidence:))
}

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

// ─── Erlang helpers ────────────────────────────────────────────────────────

@external(erlang, "aether_time_ffi", "now_ms")
fn now_ms() -> Int

fn float_compare(a: Float, b: Float) -> order.Order {
  case a <. b {
    True -> order.Lt
    False ->
      case a >. b {
        True -> order.Gt
        False -> order.Eq
      }
  }
}
