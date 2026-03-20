/// Perception Aggregator — multi-person tracking with Kalman filtering.
///
/// Receives raw perceptions from the orchestrator and:
/// 1. Associates pose detections with tracked persons (nearest neighbor)
/// 2. Updates Kalman filter state per person
/// 3. Detects zone transition events
/// 4. Removes stale persons (not seen for > timeout)
import aether/core/types.{
  type PersonId, type Vec3, type Zone, Vec3, vec3_distance,
}
import aether/perception.{
  type Event, type Perception, FallDetected, Keypoint, Location, PersonEntered,
  PersonLeft, Pose,
}
import aether/track/event
import aether/track/person.{type PersonState}
import aether/track/zone as zone_tracker
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/int
import gleam/list
import gleam/order
import gleam/otp/actor

pub type AggregatorMsg {
  ProcessPerceptions(perceptions: List(Perception), timestamp_us: Int)
  GetTrackedPersons(reply: Subject(List(PersonState)))
  GetEvents(reply: Subject(List(Event)))
}

pub type AggregatorState {
  AggregatorState(
    persons: Dict(PersonId, PersonState),
    zones: List(Zone),
    events: List(Event),
    next_person_id: Int,
    stale_timeout_us: Int,
  )
}

/// Start the aggregator actor.
pub fn start(
  zones: List(Zone),
  stale_timeout_us: Int,
) -> Result(Subject(AggregatorMsg), actor.StartError) {
  let state =
    AggregatorState(
      persons: dict.new(),
      zones: zones,
      events: [],
      next_person_id: 1,
      stale_timeout_us: stale_timeout_us,
    )
  let result =
    actor.new(state)
    |> actor.on_message(handle_message)
    |> actor.start()
  case result {
    Ok(started) -> Ok(started.data)
    Error(e) -> Error(e)
  }
}

/// Get currently tracked persons.
pub fn get_tracked(agg: Subject(AggregatorMsg)) -> List(PersonState) {
  actor.call(agg, 1000, GetTrackedPersons)
}

/// Get and clear recent events.
pub fn get_events(agg: Subject(AggregatorMsg)) -> List(Event) {
  actor.call(agg, 1000, GetEvents)
}

fn handle_message(
  state: AggregatorState,
  msg: AggregatorMsg,
) -> actor.Next(AggregatorState, AggregatorMsg) {
  case msg {
    ProcessPerceptions(perceptions, timestamp) -> {
      let new_state = process_frame(state, perceptions, timestamp)
      actor.continue(new_state)
    }
    GetTrackedPersons(reply) -> {
      process.send(reply, dict.values(state.persons))
      actor.continue(state)
    }
    GetEvents(reply) -> {
      process.send(reply, state.events)
      // Clear events after reading
      actor.continue(AggregatorState(..state, events: []))
    }
  }
}

fn process_frame(
  state: AggregatorState,
  perceptions: List(Perception),
  timestamp: Int,
) -> AggregatorState {
  // Extract position from Location perception if available
  let positions = extract_positions(perceptions)

  // Associate each position with nearest tracked person or create new
  let #(updated_persons, new_events, next_id) =
    associate_positions(state, positions, timestamp)

  // Remove stale persons
  let #(active_persons, stale_events) =
    remove_stale(
      updated_persons,
      state.zones,
      timestamp,
      state.stale_timeout_us,
    )

  AggregatorState(
    ..state,
    persons: active_persons,
    events: list.flatten([stale_events, new_events, state.events]),
    next_person_id: next_id,
  )
}

/// Extract positions from perceptions (from Location or Pose).
fn extract_positions(perceptions: List(Perception)) -> List(Vec3) {
  list.filter_map(perceptions, fn(p) {
    case p {
      Location(position, _acc, _vel) -> Ok(position)
      Pose(keypoints, _skeleton, _conf) -> {
        // Use nose keypoint (index 0) as person position
        case keypoints {
          [Keypoint(_id, _name, x, y, z, _conf, _vel), ..] -> Ok(Vec3(x, y, z))
          _ -> Error(Nil)
        }
      }
      _ -> Error(Nil)
    }
  })
}

/// Associate detected positions with tracked persons.
fn associate_positions(
  state: AggregatorState,
  positions: List(Vec3),
  timestamp: Int,
) -> #(Dict(PersonId, PersonState), List(Event), Int) {
  let max_association_distance = 2.0
  // meters

  list.fold(positions, #(state.persons, [], state.next_person_id), fn(acc, pos) {
    let #(persons, events, next_id) = acc

    // Find nearest tracked person
    let nearest =
      dict.to_list(persons)
      |> list.map(fn(entry) {
        let #(id, ps) = entry
        let dist = vec3_distance(person.position(ps), pos)
        #(id, dist)
      })
      |> list.sort(fn(a, b) { float_compare(a.1, b.1) })
      |> list.first()

    case nearest {
      Ok(#(nearest_id, dist)) if dist <. max_association_distance -> {
        // Update existing person
        let assert Ok(ps) = dict.get(persons, nearest_id)
        let prev_zone =
          zone_tracker.assign(state.zones, person.position(ps))
          |> result_to_zone()
        let updated = person.update(ps, pos, timestamp)
        let curr_zone =
          zone_tracker.assign(state.zones, person.position(updated))
          |> result_to_zone()
        let zone_events =
          event.detect_zone_transition(nearest_id, prev_zone, curr_zone)
        let new_persons = dict.insert(persons, nearest_id, updated)
        #(new_persons, list.flatten([zone_events, events]), next_id)
      }
      _ -> {
        // Create new person
        let id = "p" <> int.to_string(next_id)
        let new_person = person.new_person(id, pos, timestamp)
        let new_persons = dict.insert(persons, id, new_person)
        let curr_zone =
          zone_tracker.assign(state.zones, pos) |> result_to_zone()
        let zone_events =
          event.detect_zone_transition(id, Error(Nil), curr_zone)
        #(new_persons, list.flatten([zone_events, events]), next_id + 1)
      }
    }
  })
}

/// Remove persons not seen for longer than the timeout.
fn remove_stale(
  persons: Dict(PersonId, PersonState),
  zones: List(Zone),
  now_us: Int,
  timeout_us: Int,
) -> #(Dict(PersonId, PersonState), List(Event)) {
  let entries = dict.to_list(persons)
  list.fold(entries, #(dict.new(), []), fn(acc, entry) {
    let #(active, events) = acc
    let #(id, ps) = entry
    case person.is_stale(ps, now_us, timeout_us) {
      True -> {
        let prev_zone =
          zone_tracker.assign(zones, person.position(ps)) |> result_to_zone()
        let leave_events =
          event.detect_zone_transition(id, prev_zone, Error(Nil))
        #(active, list.flatten([leave_events, events]))
      }
      False -> #(dict.insert(active, id, ps), events)
    }
  })
}

fn result_to_zone(r: Result(String, a)) -> Result(String, Nil) {
  case r {
    Ok(z) -> Ok(z)
    Error(_) -> Error(Nil)
  }
}

fn float_compare(a: Float, b: Float) -> order.Order {
  float.compare(a, b)
}
