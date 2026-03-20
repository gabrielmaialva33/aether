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
    subscriber: Subject(Signal),
    frames_received: Int,
    parse_errors: Int,
  )
}

pub type SensorStats {
  SensorStats(frames_received: Int, parse_errors: Int)
}

pub type TestConfig {
  TestConfig(id: String, kind: SignalKind, subscriber: Subject(Signal))
}

pub fn start_test(
  config: TestConfig,
) -> Result(Subject(SensorMsg), actor.StartError) {
  let state =
    SensorState(
      id: config.id,
      kind: config.kind,
      subscriber: config.subscriber,
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

pub fn inject_frame(sensor: Subject(SensorMsg), frame: BitArray) -> Nil {
  actor.send(sensor, RawFrame(frame))
}

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
          process.send(state.subscriber, signal)
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
