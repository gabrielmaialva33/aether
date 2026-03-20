/// Sensor OTP Actor — receives raw RF frames, parses, emits Signals.
///
/// Instead of a raw Subject(Signal), the sensor accepts an `on_signal`
/// callback that is called with each parsed Signal. This eliminates
/// the need for bridge processes with raw erlang:send.
import aether/sensor/parser
import aether/signal.{type Signal, type SignalKind, Signal}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor

pub type SensorMsg {
  RawFrame(data: BitArray)
  GetStats(reply: Subject(SensorStats))
  Shutdown
}

pub type SensorState {
  SensorState(
    id: String,
    kind: SignalKind,
    on_signal: fn(Signal) -> Nil,
    frames_received: Int,
    parse_errors: Int,
  )
}

pub type SensorStats {
  SensorStats(frames_received: Int, parse_errors: Int)
}

/// Configuration for starting a sensor actor.
/// `on_signal` is called for each successfully parsed Signal.
pub type SensorStartConfig {
  SensorStartConfig(id: String, kind: SignalKind, on_signal: fn(Signal) -> Nil)
}

/// Start a sensor actor with a signal callback.
pub fn start(
  config: SensorStartConfig,
) -> Result(Subject(SensorMsg), actor.StartError) {
  let state =
    SensorState(
      id: config.id,
      kind: config.kind,
      on_signal: config.on_signal,
      frames_received: 0,
      parse_errors: 0,
    )
  let result =
    actor.new(state)
    |> actor.on_message(handle_message)
    |> actor.start()
  case result {
    Ok(started) -> Ok(started.data)
    Error(e) -> Error(e)
  }
}

/// Convenience: start with a Subject(Signal) subscriber (for tests).
pub fn start_with_subject(
  id: String,
  kind: SignalKind,
  subscriber: Subject(Signal),
) -> Result(Subject(SensorMsg), actor.StartError) {
  start(
    SensorStartConfig(id: id, kind: kind, on_signal: fn(signal) {
      process.send(subscriber, signal)
    }),
  )
}

/// Inject a raw frame for processing (used by UDP listener and tests).
pub fn inject_frame(sensor: Subject(SensorMsg), frame: BitArray) -> Nil {
  actor.send(sensor, RawFrame(frame))
}

/// Get sensor statistics.
pub fn get_stats(sensor: Subject(SensorMsg)) -> SensorStats {
  actor.call(sensor, 1000, GetStats)
}

fn handle_message(
  state: SensorState,
  msg: SensorMsg,
) -> actor.Next(SensorState, SensorMsg) {
  case msg {
    RawFrame(data) -> {
      case parser.parse_csi_frame(data, state.kind) {
        Ok(frame) -> {
          let signal =
            Signal(
              source: state.id,
              kind: state.kind,
              timestamp: monotonic_time_us(),
              payload: frame.data,
              metadata: [],
            )
          state.on_signal(signal)
          actor.continue(
            SensorState(..state, frames_received: state.frames_received + 1),
          )
        }
        Error(_) ->
          actor.continue(
            SensorState(..state, parse_errors: state.parse_errors + 1),
          )
      }
    }
    GetStats(reply) -> {
      process.send(
        reply,
        SensorStats(state.frames_received, state.parse_errors),
      )
      actor.continue(state)
    }
    Shutdown -> actor.stop()
  }
}

@external(erlang, "aether_time_ffi", "monotonic_us")
fn monotonic_time_us() -> Int
