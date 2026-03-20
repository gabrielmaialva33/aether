/// End-to-end integration test.
/// Tests the full data flow: CSI frame → sensor actor → orchestrator → perceptions.
/// Uses the new callback-based sensor actor — no bridge FFI.
import aether/condition/pipeline
import aether/orchestrator
import aether/sensor/actor as sensor_actor
import aether/signal.{Signal, WifiCsi}
import gleam/erlang/process
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

/// Test: sensor actor with orchestrator callback — full type-safe wiring.
pub fn sensor_to_orchestrator_test() {
  let assert Ok(orch) =
    orchestrator.start(
      orchestrator.OrchestratorConfig(
        conditioners: pipeline.default_wifi(),
        model_path: "test.pt",
        device: "cpu",
        tasks: ["pose", "vitals", "presence"],
      ),
    )

  let perception_sub = process.new_subject()
  orchestrator.subscribe(orch, perception_sub)
  process.sleep(50)

  // Start sensor with on_signal callback that calls orchestrator.ingest directly
  let assert Ok(sensor) =
    sensor_actor.start(
      sensor_actor.SensorStartConfig(
        id: "e2e-sensor",
        kind: WifiCsi(subcarriers: 4, antennas: 1, bandwidth: 20),
        on_signal: fn(signal) { orchestrator.ingest(orch, signal) },
      ),
    )

  // Inject CSI frame — it flows: sensor → orchestrator → perceptions
  sensor_actor.inject_frame(sensor, <<
    0xAE, 0x01, 0x00, 0x01, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120,
    130, 140, 150, 160,
  >>)

  let assert Ok(perceptions) = process.receive(perception_sub, 2000)
  { perceptions != [] } |> should.be_true()
}

/// Test: orchestrator handles empty embedding gracefully.
pub fn empty_signal_test() {
  let assert Ok(orch) =
    orchestrator.start(
      orchestrator.OrchestratorConfig(
        conditioners: [],
        model_path: "test.pt",
        device: "cpu",
        tasks: ["pose"],
      ),
    )

  orchestrator.ingest(
    orch,
    Signal(
      source: "empty-sensor",
      kind: WifiCsi(subcarriers: 0, antennas: 0, bandwidth: 20),
      timestamp: 1000,
      payload: <<>>,
      metadata: [],
    ),
  )

  process.sleep(100)
  let perceptions = orchestrator.get_perceptions(orch)
  { perceptions == [] } |> should.be_true()
}

/// Test: multiple signals produce multiple perception updates.
pub fn multiple_frames_test() {
  let assert Ok(orch) =
    orchestrator.start(
      orchestrator.OrchestratorConfig(
        conditioners: [],
        model_path: "test.pt",
        device: "cpu",
        tasks: ["presence"],
      ),
    )

  let perception_sub = process.new_subject()
  orchestrator.subscribe(orch, perception_sub)
  process.sleep(50)

  let make_signal = fn(i) {
    Signal(
      source: "multi-sensor",
      kind: WifiCsi(subcarriers: 4, antennas: 1, bandwidth: 20),
      timestamp: i * 1000,
      payload: <<1, 2, 3, 4, 5, 6, 7, 8>>,
      metadata: [],
    )
  }

  orchestrator.ingest(orch, make_signal(1))
  orchestrator.ingest(orch, make_signal(2))
  orchestrator.ingest(orch, make_signal(3))

  let assert Ok(_p1) = process.receive(perception_sub, 1000)
  let assert Ok(_p2) = process.receive(perception_sub, 1000)
  let assert Ok(_p3) = process.receive(perception_sub, 1000)
}

/// Test: UDP round-trip — send UDP packet, receive it, inject into sensor.
pub fn udp_round_trip_test() {
  let signal_sub = process.new_subject()
  let assert Ok(sensor) =
    sensor_actor.start_with_subject(
      "udp-sensor",
      WifiCsi(subcarriers: 2, antennas: 1, bandwidth: 20),
      signal_sub,
    )

  let port = 19_876
  let assert Ok(socket) = udp_open(port)

  udp_send_to(#(127, 0, 0, 1), port, <<0xAE, 0x01, 0x00, 0x42, 10, 20, 30, 40>>)

  let assert Ok(data) = udp_recv(socket, 2000)
  sensor_actor.inject_frame(sensor, data)

  let assert Ok(signal) = process.receive(signal_sub, 1000)
  signal.source |> should.equal("udp-sensor")

  udp_close(socket)
}

// --- UDP FFI helpers ---

@external(erlang, "aether_udp_ffi", "open")
fn udp_open(port: Int) -> Result(UdpSock, String)

type UdpSock

@external(erlang, "aether_udp_ffi", "recv")
fn udp_recv(socket: UdpSock, timeout_ms: Int) -> Result(BitArray, String)

@external(erlang, "aether_udp_ffi", "close")
fn udp_close(socket: UdpSock) -> Nil

fn udp_send_to(host: #(Int, Int, Int, Int), port: Int, data: BitArray) -> Nil {
  udp_send_raw(host, port, data, Nil)
}

@external(erlang, "aether_udp_ffi", "send_to")
fn udp_send_raw(
  host: #(Int, Int, Int, Int),
  port: Int,
  data: BitArray,
  opts: Nil,
) -> Nil
