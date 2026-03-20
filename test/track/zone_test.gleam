import aether/core/types.{Vec3, Zone}
import aether/track/zone as zone_tracker
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn assign_point_to_zone_test() {
  let zones = [
    Zone("sala", "Sala", #(0.0, 0.0, 5.0, 4.0), 0.0, 3.0),
    Zone("quarto", "Quarto", #(5.0, 0.0, 9.0, 4.0), 0.0, 3.0),
  ]
  let point = Vec3(2.5, 2.0, 1.0)

  zone_tracker.assign(zones, point) |> should.equal(Ok("sala"))
}

pub fn point_outside_all_zones_test() {
  let zones = [Zone("sala", "Sala", #(0.0, 0.0, 5.0, 4.0), 0.0, 3.0)]
  let point = Vec3(10.0, 10.0, 1.0)

  zone_tracker.assign(zones, point) |> should.be_error()
}
