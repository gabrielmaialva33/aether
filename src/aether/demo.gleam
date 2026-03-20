/// Æther Live Demo
///
/// Starts the full system and simulates ESP32 sensor data.
/// Hit http://localhost:8080/api/perceptions to see real output.
import aether
import aether/core/types.{Zone}
import aether/orchestrator
import aether/perception.{Activity, Pose, Presence, Vitals}
import aether/sensor
import aether/signal.{Signal, WifiCsi}
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list

pub fn main() {
  io.println("")
  io.println("  Starting Æther live demo...")
  io.println("")

  // 1. Configure the space
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
    |> aether.with_api(8080)
    |> aether.start()

  io.println("")
  io.println("  Simulating CSI frames...")
  io.println("")

  // 2. Simulate CSI data (as if ESP32 was sending it)
  simulate_frames(hub.orchestrator, 10, 0)

  io.println("")
  io.println("  ✓ 10 frames processed")
  io.println("")

  // 3. Show perceptions
  let perceptions = aether.perceive(hub)
  io.println(
    "  Perceptions: " <> int.to_string(list.length(perceptions)) <> " active",
  )
  list.each(perceptions, fn(p) { io.println("    → " <> perception_summary(p)) })

  io.println("")
  io.println("  API ready at http://localhost:8080/api/perceptions")
  io.println("  Press Ctrl+C to stop.")
  io.println("")

  // 4. Keep alive — serve API
  process.sleep_forever()
}

fn simulate_frames(orch, count: Int, i: Int) -> Nil {
  case i >= count {
    True -> Nil
    False -> {
      // Generate slightly varying CSI-like data per frame
      let base = i * 7
      let payload = <<
        { base + 10 }:int,
        { base + 20 }:int,
        { base + 30 }:int,
        { base + 40 }:int,
        { base + 50 }:int,
        { base + 60 }:int,
        { base + 70 }:int,
        { base + 80 }:int,
        { base + 15 }:int,
        { base + 25 }:int,
        { base + 35 }:int,
        { base + 45 }:int,
        { base + 55 }:int,
        { base + 65 }:int,
        { base + 75 }:int,
        { base + 85 }:int,
      >>

      let signal =
        Signal(
          source: "sim-esp32",
          kind: WifiCsi(subcarriers: 8, antennas: 1, bandwidth: 20),
          timestamp: i * 10_000,
          payload: payload,
          metadata: [],
        )

      orchestrator.ingest(orch, signal)
      process.sleep(50)
      simulate_frames(orch, count, i + 1)
    }
  }
}

fn perception_summary(p) -> String {
  case p {
    Pose(keypoints, _, confidence) ->
      "Pose: "
      <> int.to_string(list.length(keypoints))
      <> " keypoints (conf: "
      <> float_str(confidence)
      <> ")"
    Vitals(heart, breath, _, confidence) ->
      "Vitals: heart "
      <> float_str(heart)
      <> " bpm, breath "
      <> float_str(breath)
      <> " bpm (conf: "
      <> float_str(confidence)
      <> ")"
    Presence(_, count) -> "Presence: " <> int.to_string(count) <> " occupant(s)"
    Activity(label, confidence, _) ->
      "Activity: " <> label <> " (conf: " <> float_str(confidence) <> ")"
    _ -> "Other perception"
  }
}

@external(erlang, "aether_demo_ffi", "float_str")
fn float_str(f: Float) -> String
