import aether/core/types.{type PersonId, type ZoneId}
import aether/perception.{type Event, PersonEntered, PersonLeft}

/// Detect zone transition events by comparing previous and current zone
pub fn detect_zone_transition(
  person: PersonId,
  previous_zone: Result(ZoneId, Nil),
  current_zone: Result(ZoneId, Nil),
) -> List(Event) {
  case previous_zone, current_zone {
    Ok(prev), Ok(curr) if prev != curr -> [
      PersonLeft(person, prev),
      PersonEntered(person, curr),
    ]
    Error(_), Ok(curr) -> [PersonEntered(person, curr)]
    Ok(prev), Error(_) -> [PersonLeft(person, prev)]
    _, _ -> []
  }
}
