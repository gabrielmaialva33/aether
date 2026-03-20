/// Æther Live Demo — generates realistic CSI-like embeddings
import aether
import aether/core/types.{Zone}
import aether/orchestrator
import aether/perception.{Activity, Pose, Presence, Vitals}
import aether/sensor
import aether/signal.{Signal, WifiCsi}
import gleam/bit_array
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list

pub fn main() {
  io.println("")
  io.println("  Starting Æther live demo...")
  io.println("")

  let assert Ok(hub) =
    aether.space("casa-gabriel")
    |> aether.add_zone(Zone("sala", "Sala", #(0.0, 0.0, 5.0, 4.0), 0.0, 3.0))
    |> aether.add_zone(Zone("quarto", "Quarto", #(5.0, 0.0, 9.0, 4.0), 0.0, 3.0))
    |> aether.add_sensor(sensor.wifi_csi(
      host: "127.0.0.1",
      port: 5000,
      antennas: 3,
      subcarriers: 56,
      sample_rate: 100,
    ))
    |> aether.with_api(9090)
    |> aether.start()

  io.println("")
  io.println("  Simulating CSI embeddings...")
  io.println("")

  // Generate frames with float64-encoded embeddings (not raw bytes)
  simulate_frames(hub.orchestrator, 10, 0)

  io.println("")
  io.println("  Done. Continuous simulation running.")
  io.println("  Dashboard: http://localhost:9090/")
  io.println("")

  // Continue generating frames in background
  continuous_sim(hub.orchestrator, 10)
}

fn simulate_frames(orch, count: Int, i: Int) -> Nil {
  case i >= count {
    True -> Nil
    False -> {
      let payload = generate_csi_embedding(i)
      orchestrator.ingest(
        orch,
        Signal(
          source: "sim-esp32",
          kind: WifiCsi(subcarriers: 32, antennas: 1, bandwidth: 20),
          timestamp: i * 10_000,
          payload: payload,
          metadata: [],
        ),
      )
      process.sleep(50)
      simulate_frames(orch, count, i + 1)
    }
  }
}

fn continuous_sim(orch, frame: Int) -> Nil {
  let payload = generate_csi_embedding(frame)
  orchestrator.ingest(
    orch,
    Signal(
      source: "sim-esp32",
      kind: WifiCsi(subcarriers: 32, antennas: 1, bandwidth: 20),
      timestamp: frame * 10_000,
      payload: payload,
      metadata: [],
    ),
  )
  process.sleep(200)
  continuous_sim(orch, frame + 1)
}

/// Generate float64-encoded CSI embedding that produces realistic perceptions.
/// 64 float64 values (512 bytes) simulating subcarrier amplitudes with
/// sinusoidal variation (mimics human breathing/movement in CSI).
fn generate_csi_embedding(frame: Int) -> BitArray {
  build_embedding(0, 64, frame, <<>>)
}

fn build_embedding(i: Int, n: Int, frame: Int, acc: BitArray) -> BitArray {
  case i >= n {
    True -> acc
    False -> {
      let fi = int_to_float(i)
      let ff = int_to_float(frame)
      // Simulate CSI: base + breathing modulation + movement + noise
      let base = 0.3
      let breathing = 0.25 *. float_sin(fi /. 5.0 +. ff /. 8.0)
      let movement = 0.15 *. float_cos(fi /. 3.0 +. ff /. 12.0)
      let drift = 0.1 *. float_sin(ff /. 20.0)
      let val = base +. breathing +. movement +. drift
      build_embedding(i + 1, n, frame, <<acc:bits, val:float-size(64)>>)
    }
  }
}

@external(erlang, "math", "sin")
fn float_sin(x: Float) -> Float

@external(erlang, "math", "cos")
fn float_cos(x: Float) -> Float

@external(erlang, "erlang", "float")
fn int_to_float(n: Int) -> Float
