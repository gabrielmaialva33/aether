import aether/core/types.{
  Vec3, Zone, vec3_add, vec3_distance, vec3_zero, zone_contains,
}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn vec3_add_test() {
  let a = Vec3(1.0, 2.0, 3.0)
  let b = Vec3(4.0, 5.0, 6.0)
  let result = vec3_add(a, b)
  result.x |> should.equal(5.0)
  result.y |> should.equal(7.0)
  result.z |> should.equal(9.0)
}

pub fn vec3_zero_test() {
  let z = vec3_zero()
  z.x |> should.equal(0.0)
  z.y |> should.equal(0.0)
  z.z |> should.equal(0.0)
}

pub fn vec3_distance_test() {
  let a = Vec3(0.0, 0.0, 0.0)
  let b = Vec3(3.0, 4.0, 0.0)
  vec3_distance(a, b) |> should.equal(5.0)
}

pub fn zone_contains_point_test() {
  let zone =
    Zone(
      id: "sala",
      name: "Sala de Estar",
      bounds: #(0.0, 0.0, 5.0, 4.0),
      floor: 0.0,
      ceiling: 3.0,
    )
  zone_contains(zone, Vec3(2.5, 2.0, 1.0)) |> should.be_true()
  zone_contains(zone, Vec3(6.0, 2.0, 1.0)) |> should.be_false()
}
