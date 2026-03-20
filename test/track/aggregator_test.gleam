import aether/core/types.{Vec3, Zone}
import aether/perception.{Location}
import aether/track/aggregator
import gleam/erlang/process
import gleam/list
import gleam/option.{None}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn aggregator_creates_person_from_location_test() {
  let zones = [Zone("sala", "Sala", #(0.0, 0.0, 5.0, 4.0), 0.0, 3.0)]
  let assert Ok(agg) = aggregator.start(zones, 5_000_000)

  // Send a Location perception
  let perceptions = [Location(Vec3(2.5, 2.0, 1.0), 0.5, None)]
  actor_send(agg, aggregator.ProcessPerceptions(perceptions, 1_000_000))

  process.sleep(100)

  let persons = aggregator.get_tracked(agg)
  { persons != [] } |> should.be_true()
}

pub fn aggregator_tracks_movement_test() {
  let zones = [Zone("sala", "Sala", #(0.0, 0.0, 5.0, 4.0), 0.0, 3.0)]
  let assert Ok(agg) = aggregator.start(zones, 5_000_000)

  // First detection
  actor_send(
    agg,
    aggregator.ProcessPerceptions(
      [Location(Vec3(1.0, 1.0, 1.0), 0.5, None)],
      1_000_000,
    ),
  )
  process.sleep(50)

  // Same person moves slightly
  actor_send(
    agg,
    aggregator.ProcessPerceptions(
      [Location(Vec3(1.2, 1.1, 1.0), 0.5, None)],
      2_000_000,
    ),
  )
  process.sleep(50)

  let persons = aggregator.get_tracked(agg)
  // Should still be 1 person (associated with existing)
  list.length(persons) |> should.equal(1)
}

pub fn aggregator_detects_zone_entry_test() {
  let zones = [Zone("sala", "Sala", #(0.0, 0.0, 5.0, 4.0), 0.0, 3.0)]
  let assert Ok(agg) = aggregator.start(zones, 5_000_000)

  // Person enters a zone
  actor_send(
    agg,
    aggregator.ProcessPerceptions(
      [Location(Vec3(2.5, 2.0, 1.0), 0.5, None)],
      1_000_000,
    ),
  )
  process.sleep(100)

  let events = aggregator.get_events(agg)
  // Should have a PersonEntered event
  let has_enter =
    list.any(events, fn(e) {
      case e {
        perception.PersonEntered(_, _) -> True
        _ -> False
      }
    })
  has_enter |> should.be_true()
}

// Helper to send messages to aggregator
fn actor_send(
  agg: process.Subject(aggregator.AggregatorMsg),
  msg: aggregator.AggregatorMsg,
) -> Nil {
  process.send(agg, msg)
}
