import aether/perception.{PersonEntered, PersonLeft}
import aether/track/event
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn detect_enter_event_test() {
  let events = event.detect_zone_transition("p1", Error(Nil), Ok("sala"))
  events |> should.equal([PersonEntered("p1", "sala")])
}

pub fn detect_leave_event_test() {
  let events = event.detect_zone_transition("p1", Ok("sala"), Error(Nil))
  events |> should.equal([PersonLeft("p1", "sala")])
}

pub fn detect_zone_change_test() {
  let events = event.detect_zone_transition("p1", Ok("sala"), Ok("quarto"))
  events
  |> should.equal([PersonLeft("p1", "sala"), PersonEntered("p1", "quarto")])
}

pub fn no_event_if_same_zone_test() {
  let events = event.detect_zone_transition("p1", Ok("sala"), Ok("sala"))
  events |> should.equal([])
}
