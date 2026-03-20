/// Per-person Kalman filter state for multi-person tracking.
///
/// Tracks position and velocity of each detected person across frames.
/// Uses a simplified 1D Kalman filter per axis (x, y, z) for real-time
/// smoothing and prediction.
import aether/core/types.{type PersonId, type Vec3, Vec3}

/// Kalman filter state for one axis.
pub type KalmanState1D {
  KalmanState1D(
    x: Float,
    // state estimate
    v: Float,
    // velocity estimate
    p_x: Float,
    // position uncertainty
    p_v: Float,
    // velocity uncertainty
    q: Float,
    // process noise
    r: Float,
    // measurement noise
  )
}

/// Full 3D tracked person state.
pub type PersonState {
  PersonState(
    id: PersonId,
    kf_x: KalmanState1D,
    kf_y: KalmanState1D,
    kf_z: KalmanState1D,
    last_seen_us: Int,
    frames_tracked: Int,
  )
}

/// Create a new Kalman filter for one axis.
pub fn new_kf1d(
  initial: Float,
  process_noise: Float,
  measurement_noise: Float,
) -> KalmanState1D {
  KalmanState1D(
    x: initial,
    v: 0.0,
    p_x: 1.0,
    p_v: 1.0,
    q: process_noise,
    r: measurement_noise,
  )
}

/// Create a new tracked person at an initial position.
pub fn new_person(
  id: PersonId,
  position: Vec3,
  timestamp_us: Int,
) -> PersonState {
  let q = 0.1
  // process noise — how much we expect movement
  let r = 0.5
  // measurement noise — how noisy the sensor is
  PersonState(
    id: id,
    kf_x: new_kf1d(position.x, q, r),
    kf_y: new_kf1d(position.y, q, r),
    kf_z: new_kf1d(position.z, q, r),
    last_seen_us: timestamp_us,
    frames_tracked: 1,
  )
}

/// Update the person's position with a new measurement.
/// Returns the smoothed (filtered) position.
pub fn update(
  person: PersonState,
  measurement: Vec3,
  timestamp_us: Int,
) -> PersonState {
  let dt = case timestamp_us - person.last_seen_us {
    diff if diff > 0 -> int_to_float(diff) /. 1_000_000.0
    // seconds
    _ -> 0.01
  }

  PersonState(
    ..person,
    kf_x: update_kf1d(person.kf_x, measurement.x, dt),
    kf_y: update_kf1d(person.kf_y, measurement.y, dt),
    kf_z: update_kf1d(person.kf_z, measurement.z, dt),
    last_seen_us: timestamp_us,
    frames_tracked: person.frames_tracked + 1,
  )
}

/// Get the current smoothed position.
pub fn position(person: PersonState) -> Vec3 {
  Vec3(x: person.kf_x.x, y: person.kf_y.x, z: person.kf_z.x)
}

/// Get the current estimated velocity.
pub fn velocity(person: PersonState) -> Vec3 {
  Vec3(x: person.kf_x.v, y: person.kf_y.v, z: person.kf_z.v)
}

/// Predict where the person will be after dt seconds (without measurement).
pub fn predict_position(person: PersonState, dt: Float) -> Vec3 {
  Vec3(
    x: person.kf_x.x +. person.kf_x.v *. dt,
    y: person.kf_y.x +. person.kf_y.v *. dt,
    z: person.kf_z.x +. person.kf_z.v *. dt,
  )
}

/// Check if the person hasn't been seen for too long (stale).
pub fn is_stale(person: PersonState, now_us: Int, timeout_us: Int) -> Bool {
  now_us - person.last_seen_us > timeout_us
}

// ─── Kalman filter update ───────────────────────────────────────────────────

/// 1D Kalman filter predict + update step.
fn update_kf1d(
  kf: KalmanState1D,
  measurement: Float,
  dt: Float,
) -> KalmanState1D {
  // Predict step
  let x_pred = kf.x +. kf.v *. dt
  let v_pred = kf.v
  let p_x_pred = kf.p_x +. dt *. dt *. kf.p_v +. kf.q
  let p_v_pred = kf.p_v +. kf.q

  // Update step (measurement of position only)
  let innovation = measurement -. x_pred
  let s = p_x_pred +. kf.r
  // innovation covariance
  let k_x = p_x_pred /. s
  // Kalman gain for position
  let k_v = { dt *. kf.p_v } /. s
  // Kalman gain for velocity

  KalmanState1D(
    x: x_pred +. k_x *. innovation,
    v: v_pred +. k_v *. innovation,
    p_x: { 1.0 -. k_x } *. p_x_pred,
    p_v: { 1.0 -. k_v *. dt } *. p_v_pred,
    q: kf.q,
    r: kf.r,
  )
}

@external(erlang, "erlang", "float")
fn int_to_float(n: Int) -> Float
