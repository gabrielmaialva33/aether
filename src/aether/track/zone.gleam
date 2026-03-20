import aether/core/error.{type AetherError, ZoneNotFound}
import aether/core/types.{type Vec3, type Zone, type ZoneId, zone_contains}
import gleam/list

pub fn assign(zones: List(Zone), point: Vec3) -> Result(ZoneId, AetherError) {
  case list.find(zones, fn(z) { zone_contains(z, point) }) {
    Ok(zone) -> Ok(zone.id)
    Error(_) -> Error(ZoneNotFound("no zone contains point"))
  }
}
