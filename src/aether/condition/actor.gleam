/// Stateful conditioner pipeline actor.
/// Maintains a ring buffer of recent frames for AveCSI stabilization.
/// Receives Signals, processes through pipeline, emits conditioned Signals.
import aether/condition/pipeline.{
  type Conditioner, type PipelineMode, Inference, Stabilize,
}
import aether/condition/ring_buffer.{type RingBuffer}
import aether/core/error.{type AetherError}
import aether/nif/signal as nif
import aether/signal.{type Signal, Signal}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import gleam/result

pub type PipelineMsg {
  ProcessSignal(signal: Signal, reply: Subject(Result(Signal, AetherError)))
  ProcessSignalAsync(signal: Signal, subscriber: Subject(Signal))
  GetStats(reply: Subject(PipelineStats))
}

pub type PipelineStats {
  PipelineStats(frames_processed: Int, buffer_size: Int, buffer_drops: Int)
}

pub type PipelineState {
  PipelineState(
    stages: List(Conditioner),
    mode: PipelineMode,
    buffer: RingBuffer(List(Float)),
    frames_processed: Int,
    buffer_drops: Int,
  )
}

/// Start the pipeline actor with given stages and buffer capacity.
pub fn start(
  stages: List(Conditioner),
  buffer_capacity: Int,
) -> Result(Subject(PipelineMsg), actor.StartError) {
  let state =
    PipelineState(
      stages: stages,
      mode: Inference,
      buffer: ring_buffer.new(buffer_capacity),
      frames_processed: 0,
      buffer_drops: 0,
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

fn handle_message(
  state: PipelineState,
  msg: PipelineMsg,
) -> actor.Next(PipelineState, PipelineMsg) {
  case msg {
    ProcessSignal(signal, reply) -> {
      let #(result, new_state) = process_signal(state, signal)
      process.send(reply, result)
      actor.continue(new_state)
    }
    ProcessSignalAsync(signal, subscriber) -> {
      let #(result, new_state) = process_signal(state, signal)
      case result {
        Ok(conditioned) -> process.send(subscriber, conditioned)
        Error(_) -> Nil
      }
      actor.continue(new_state)
    }
    GetStats(reply) -> {
      process.send(
        reply,
        PipelineStats(
          frames_processed: state.frames_processed,
          buffer_size: ring_buffer.size(state.buffer),
          buffer_drops: state.buffer_drops,
        ),
      )
      actor.continue(state)
    }
  }
}

fn process_signal(
  state: PipelineState,
  signal: Signal,
) -> #(Result(Signal, AetherError), PipelineState) {
  // Run non-stateful stages first
  let non_stabilize_stages =
    list.filter(state.stages, fn(s) {
      case s {
        Stabilize(_) -> False
        _ -> True
      }
    })

  let intermediate =
    pipeline.run_pipeline(signal, non_stabilize_stages, state.mode)
    |> result.unwrap(signal)

  // Extract float data from payload for ring buffer
  let frame_data = payload_to_floats(intermediate.payload)

  // Push to ring buffer
  let was_full = ring_buffer.is_full(state.buffer)
  let new_buffer = ring_buffer.push(state.buffer, frame_data)
  let drops = case was_full {
    True -> state.buffer_drops + 1
    False -> state.buffer_drops
  }

  // Run AveCSI stabilization if we have a Stabilize stage
  let has_stabilize =
    list.any(state.stages, fn(s) {
      case s {
        Stabilize(_) -> True
        _ -> False
      }
    })

  let final_signal = case has_stabilize {
    True -> {
      // Get all frames from buffer as nested list for NIF
      let frames =
        ring_buffer.to_list(new_buffer)
        |> list.reverse()
      let window = ring_buffer.size(new_buffer)

      case list.is_empty(frames) || window == 0 {
        True -> intermediate
        False -> {
          let stabilized = nif.avecsi_stabilize(frames, window)
          Signal(..intermediate, payload: floats_to_payload(stabilized))
        }
      }
    }
    False -> intermediate
  }

  let new_state =
    PipelineState(
      ..state,
      buffer: new_buffer,
      frames_processed: state.frames_processed + 1,
      buffer_drops: drops,
    )

  #(Ok(final_signal), new_state)
}

// ─── Payload conversion ─────────────────────────────────────────────────────

fn payload_to_floats(payload: BitArray) -> List(Float) {
  decode_floats(payload, [])
  |> list.reverse()
  |> fn(floats) {
    case floats {
      [] -> bytes_to_floats(payload)
      _ -> floats
    }
  }
}

fn decode_floats(data: BitArray, acc: List(Float)) -> List(Float) {
  case data {
    <<val:float-size(64), rest:bytes>> -> decode_floats(rest, [val, ..acc])
    _ -> acc
  }
}

fn bytes_to_floats(data: BitArray) -> List(Float) {
  do_bytes(data, []) |> list.reverse()
}

fn do_bytes(data: BitArray, acc: List(Float)) -> List(Float) {
  case data {
    <<byte:int-size(8), rest:bytes>> -> {
      let val = byte_to_float(byte) /. 255.0
      do_bytes(rest, [val, ..acc])
    }
    _ -> acc
  }
}

@external(erlang, "erlang", "float")
fn byte_to_float(b: Int) -> Float

fn floats_to_payload(values: List(Float)) -> BitArray {
  list.fold(values, <<>>, fn(acc, val) { <<acc:bits, val:float-size(64)>> })
}
