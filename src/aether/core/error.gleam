import aether/core/types.{type SensorId}
import gleam/float
import gleam/int

pub type AetherError {
  SensorOffline(id: SensorId, reason: String)
  SensorTimeout(id: SensorId, last_seen_ms: Int)
  ParseError(sensor: SensorId, reason: String)
  CalibrationFailed(method: String, reason: String)
  InsufficientData(expected: Int, got: Int)
  SyncError(drift_ms: Float, tolerance_ms: Float)
  NoSensorsAvailable
  ModelNotLoaded
  InferenceError(reason: String)
  CheckpointNotFound(path: String)
  CudaError(code: Int, message: String)
  ZoneNotFound(id: String)
  SpaceNotConfigured(missing: String)
}

pub fn to_string(error: AetherError) -> String {
  case error {
    SensorOffline(id, reason) -> "[sensor:" <> id <> "] offline: " <> reason
    SensorTimeout(id, ms) ->
      "[sensor:" <> id <> "] timeout after " <> int.to_string(ms) <> "ms"
    ParseError(sensor, reason) ->
      "[sensor:" <> sensor <> "] parse error: " <> reason
    CalibrationFailed(method, reason) ->
      "[calibration:" <> method <> "] failed: " <> reason
    InsufficientData(expected, got) ->
      "[data] insufficient: expected "
      <> int.to_string(expected)
      <> " got "
      <> int.to_string(got)
    SyncError(drift, tolerance) ->
      "[sync] drift "
      <> float.to_string(drift)
      <> "ms exceeds tolerance "
      <> float.to_string(tolerance)
      <> "ms"
    NoSensorsAvailable -> "[space] no sensors available"
    ModelNotLoaded -> "[model] not loaded"
    InferenceError(reason) -> "[inference] error: " <> reason
    CheckpointNotFound(path) -> "[checkpoint] not found: " <> path
    CudaError(code, msg) -> "[cuda:" <> int.to_string(code) <> "] " <> msg
    ZoneNotFound(id) -> "[zone:" <> id <> "] not found"
    SpaceNotConfigured(missing) -> "[space] not configured: missing " <> missing
  }
}
