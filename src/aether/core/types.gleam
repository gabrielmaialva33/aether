import gleam/option.{type Option}

/// Identifiers
pub type SensorId =
  String

pub type PersonId =
  String

pub type ZoneId =
  String

/// 3D vector
pub type Vec3 {
  Vec3(x: Float, y: Float, z: Float)
}

pub fn vec3_zero() -> Vec3 {
  Vec3(0.0, 0.0, 0.0)
}

pub fn vec3_add(a: Vec3, b: Vec3) -> Vec3 {
  Vec3(a.x +. b.x, a.y +. b.y, a.z +. b.z)
}

pub fn vec3_sub(a: Vec3, b: Vec3) -> Vec3 {
  Vec3(a.x -. b.x, a.y -. b.y, a.z -. b.z)
}

pub fn vec3_scale(v: Vec3, s: Float) -> Vec3 {
  Vec3(v.x *. s, v.y *. s, v.z *. s)
}

pub fn vec3_magnitude(v: Vec3) -> Float {
  let sq = v.x *. v.x +. v.y *. v.y +. v.z *. v.z
  float_sqrt(sq)
}

pub fn vec3_distance(a: Vec3, b: Vec3) -> Float {
  vec3_sub(a, b) |> vec3_magnitude()
}

@external(erlang, "math", "sqrt")
fn float_sqrt(x: Float) -> Float

/// Zone definition
pub type Zone {
  Zone(
    id: ZoneId,
    name: String,
    bounds: #(Float, Float, Float, Float),
    floor: Float,
    ceiling: Float,
  )
}

pub fn zone_contains(zone: Zone, point: Vec3) -> Bool {
  let #(x_min, y_min, x_max, y_max) = zone.bounds
  point.x >=. x_min
  && point.x <=. x_max
  && point.y >=. y_min
  && point.y <=. y_max
  && point.z >=. zone.floor
  && point.z <=. zone.ceiling
}

/// Zone occupancy snapshot
pub type ZoneOccupancy {
  ZoneOccupancy(zone: ZoneId, count: Int, person_ids: List(PersonId))
}

/// Through-wall target
pub type ThroughWallTarget {
  ThroughWallTarget(
    position: Vec3,
    signal_strength: Float,
    is_moving: Bool,
    estimated_activity: Option(String),
  )
}

/// Vitals alert kinds
pub type VitalsAlertKind {
  TachycardiaAlert
  BradycardiaAlert
  ApneaAlert
  IrregularRhythmAlert
}

/// Sensor health config
pub type HealthConfig {
  HealthConfig(
    timeout_ms: Int,
    max_packet_loss_pct: Float,
    drift_tolerance_ms: Float,
  )
}

/// Doppler config
pub type DopplerConfig {
  DopplerConfig(fft_size: Int, window_type: String, overlap: Float)
}

/// Subcarrier selection
pub type SelectionMethod {
  RemoveEdge(n: Int)
  VarianceThreshold(min: Float)
  ManualSelect(indices: List(Int))
}

/// RFID frequency bands
pub type RfidBand {
  Lf125Khz
  Hf13Mhz
  Uhf900Mhz
  Shf2400Mhz
}

/// NIF model reference — wraps an opaque Erlang resource
pub type NifModelRef {
  NifModelRef(ref: BitArray)
}

/// Field model — persistent RF background
pub type FieldModel {
  FieldModel(
    background: BitArray,
    zone_calibrations: List(#(String, BitArray)),
    last_updated: Int,
  )
}
