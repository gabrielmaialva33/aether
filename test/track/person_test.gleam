import aether/core/types.{Vec3}
import aether/track/person
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn new_person_has_initial_position_test() {
  let p = person.new_person("p1", Vec3(1.0, 2.0, 3.0), 0)
  let pos = person.position(p)
  pos.x |> should.equal(1.0)
  pos.y |> should.equal(2.0)
  pos.z |> should.equal(3.0)
}

pub fn kalman_smooths_noisy_measurements_test() {
  let p = person.new_person("p1", Vec3(0.0, 0.0, 0.0), 0)

  // Feed noisy measurements around x=1.0
  let p = person.update(p, Vec3(1.2, 0.0, 0.0), 10_000)
  let p = person.update(p, Vec3(0.8, 0.0, 0.0), 20_000)
  let p = person.update(p, Vec3(1.1, 0.0, 0.0), 30_000)
  let p = person.update(p, Vec3(0.9, 0.0, 0.0), 40_000)
  let p = person.update(p, Vec3(1.0, 0.0, 0.0), 50_000)

  // Kalman-filtered position should be close to 1.0
  let pos = person.position(p)
  let diff = case pos.x -. 1.0 {
    d if d <. 0.0 -> 0.0 -. d
    d -> d
  }
  { diff <. 0.5 } |> should.be_true()
}

pub fn kalman_estimates_velocity_test() {
  let p = person.new_person("p1", Vec3(0.0, 0.0, 0.0), 0)

  // Move consistently in x direction: 0 → 1 → 2 → 3
  let p = person.update(p, Vec3(1.0, 0.0, 0.0), 1_000_000)
  let p = person.update(p, Vec3(2.0, 0.0, 0.0), 2_000_000)
  let p = person.update(p, Vec3(3.0, 0.0, 0.0), 3_000_000)

  // Velocity should be positive in x direction
  let vel = person.velocity(p)
  { vel.x >. 0.0 } |> should.be_true()
}

pub fn predict_position_uses_velocity_test() {
  let p = person.new_person("p1", Vec3(0.0, 0.0, 0.0), 0)
  let p = person.update(p, Vec3(1.0, 0.0, 0.0), 1_000_000)
  let p = person.update(p, Vec3(2.0, 0.0, 0.0), 2_000_000)

  // Predict 1 second into the future
  let predicted = person.predict_position(p, 1.0)
  // Should be ahead of current position
  let current = person.position(p)
  { predicted.x >. current.x } |> should.be_true()
}

pub fn stale_detection_test() {
  let p = person.new_person("p1", Vec3(0.0, 0.0, 0.0), 1_000_000)
  // 5 seconds later, with 3 second timeout
  person.is_stale(p, 6_000_000, 3_000_000) |> should.be_true()
  // 2 seconds later, not stale yet
  person.is_stale(p, 3_000_000, 3_000_000) |> should.be_false()
}
