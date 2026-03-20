import aether/core/error.{type AetherError}
import aether/fusion/sync
import aether/signal.{type Signal}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor

pub type FusionMsg {
  IngestSignal(Signal)
  Flush(reply: Subject(Result(List(Signal), AetherError)))
}

pub type FusionState {
  FusionState(buffer: Dict(String, Signal), window_us: Int, tolerance_us: Int)
}

pub fn start(
  window_us window: Int,
  tolerance_us tolerance: Int,
) -> Result(Subject(FusionMsg), actor.StartError) {
  let state =
    FusionState(buffer: dict.new(), window_us: window, tolerance_us: tolerance)
  let result =
    actor.new(state)
    |> actor.on_message(handle_message)
    |> actor.start()
  case result {
    Ok(started) -> Ok(started.data)
    Error(e) -> Error(e)
  }
}

pub fn ingest(engine: Subject(FusionMsg), signal: Signal) -> Nil {
  actor.send(engine, IngestSignal(signal))
}

pub fn flush(engine: Subject(FusionMsg)) -> Result(List(Signal), AetherError) {
  actor.call(engine, 1000, Flush)
}

fn handle_message(
  state: FusionState,
  msg: FusionMsg,
) -> actor.Next(FusionState, FusionMsg) {
  case msg {
    IngestSignal(signal) -> {
      let new_buffer = dict.insert(state.buffer, signal.source, signal)
      actor.continue(FusionState(..state, buffer: new_buffer))
    }
    Flush(reply) -> {
      let signals = dict.values(state.buffer)
      let result = sync.align_signals(signals, tolerance_us: state.tolerance_us)
      process.send(reply, result)
      actor.continue(FusionState(..state, buffer: dict.new()))
    }
  }
}
