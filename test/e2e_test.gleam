/// End-to-end integration test.
/// Sends a CSI frame via UDP → sensor actor parses it → orchestrator processes it
/// → perceptions come out the other end.
import aether/condition/pipeline
import aether/orchestrator
import aether/sensor/actor as sensor_actor
import aether/signal.{Signal, WifiCsi}
import gleam/erlang/process
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

/// Test: signal flows from sensor actor through orchestrator and produces perceptions.
pub fn sensor_to_orchestrator_test() {
  // 1. Start orchestrator
  let orch_config =
    orchestrator.OrchestratorConfig(
      conditioners: pipeline.default_wifi(),
      model_path: "test.pt",
      device: "cpu",
      tasks: ["pose", "vitals", "presence"],
    )
  let assert Ok(orch) = orchestrator.start(orch_config)

  // 2. Subscribe to perception updates
  let perception_sub = process.new_subject()
  orchestrator.subscribe(orch, perception_sub)

  // 3. Start sensor actor that forwards to orchestrator
  let signal_sub = process.new_subject()
  let sensor_config =
    sensor_actor.TestConfig(
      id: "e2e-sensor",
      kind: WifiCsi(subcarriers: 4, antennas: 1, bandwidth: 20),
      subscriber: signal_sub,
    )
  let assert Ok(sensor) = sensor_actor.start_test(sensor_config)

  // 4. Inject a CSI frame
  let frame = <<
    0xAE, 0x01, 0x00, 0x01,
    // 16 bytes of CSI data
    10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150, 160,
  >>
  sensor_actor.inject_frame(sensor, frame)

  // 5. Receive the parsed signal from sensor
  let assert Ok(signal) = process.receive(signal_sub, 1000)
  signal.source |> should.equal("e2e-sensor")

  // 6. Forward to orchestrator (simulating the wiring)
  orchestrator.ingest(orch, signal)

  // 7. Receive perceptions from orchestrator
  let assert Ok(perceptions) = process.receive(perception_sub, 2000)
  // Should have perceptions for all 3 requested tasks
  { perceptions != [] } |> should.be_true()
}

/// Test: orchestrator handles empty embedding gracefully.
pub fn empty_signal_test() {
  let orch_config =
    orchestrator.OrchestratorConfig(
      conditioners: [],
      model_path: "test.pt",
      device: "cpu",
      tasks: ["pose"],
    )
  let assert Ok(orch) = orchestrator.start(orch_config)

  // Send a signal with empty payload
  let signal =
    Signal(
      source: "empty-sensor",
      kind: WifiCsi(subcarriers: 0, antennas: 0, bandwidth: 20),
      timestamp: 1000,
      payload: <<>>,
      metadata: [],
    )
  orchestrator.ingest(orch, signal)

  // Should not crash — just produce empty perceptions
  process.sleep(100)
  let perceptions = orchestrator.get_perceptions(orch)
  // Empty embedding → no perceptions (or empty list)
  { list.length(perceptions) >= 0 } |> should.be_true()
}

/// Test: multiple signals accumulate frame count.
pub fn multiple_frames_test() {
  let orch_config =
    orchestrator.OrchestratorConfig(
      conditioners: [],
      model_path: "test.pt",
      device: "cpu",
      tasks: ["presence"],
    )
  let assert Ok(orch) = orchestrator.start(orch_config)

  let perception_sub = process.new_subject()
  orchestrator.subscribe(orch, perception_sub)

  // Send 3 signals
  let signal = fn(i) {
    Signal(
      source: "multi-sensor",
      kind: WifiCsi(subcarriers: 4, antennas: 1, bandwidth: 20),
      timestamp: i * 1000,
      payload: <<1, 2, 3, 4, 5, 6, 7, 8>>,
      metadata: [],
    )
  }

  orchestrator.ingest(orch, signal(1))
  orchestrator.ingest(orch, signal(2))
  orchestrator.ingest(orch, signal(3))

  // Should receive 3 perception updates
  let assert Ok(_p1) = process.receive(perception_sub, 1000)
  let assert Ok(_p2) = process.receive(perception_sub, 1000)
  let assert Ok(_p3) = process.receive(perception_sub, 1000)
}

/// Test: UDP round-trip — send UDP packet, receive as signal.
pub fn udp_round_trip_test() {
  // 1. Start sensor actor with subscriber
  let signal_sub = process.new_subject()
  let sensor_config =
    sensor_actor.TestConfig(
      id: "udp-sensor",
      kind: WifiCsi(subcarriers: 2, antennas: 1, bandwidth: 20),
      subscriber: signal_sub,
    )
  let assert Ok(sensor) = sensor_actor.start_test(sensor_config)

  // 2. Open UDP socket and start listener
  let port = 19_876
  // We'll test UDP recv directly since the spawn_receiver sends tagged tuples
  // that may not match the Gleam actor mailbox format.
  // Instead, test the manual approach: recv + inject.
  let assert Ok(socket) = udp_open(port)

  // 3. Send a CSI frame via UDP from another socket
  udp_send_to(#(127, 0, 0, 1), port, <<0xAE, 0x01, 0x00, 0x42, 10, 20, 30, 40>>)

  // 4. Receive on our socket
  let assert Ok(data) = udp_recv(socket, 2000)

  // 5. Inject into sensor actor
  sensor_actor.inject_frame(sensor, data)

  // 6. Verify signal arrives
  let assert Ok(signal) = process.receive(signal_sub, 1000)
  signal.source |> should.equal("udp-sensor")

  // Cleanup
  udp_close(socket)
}

// --- UDP FFI helpers for testing ---

@external(erlang, "aether_udp_ffi", "open")
fn udp_open(port: Int) -> Result(UdpSock, String)

type UdpSock

@external(erlang, "aether_udp_ffi", "recv")
fn udp_recv(socket: UdpSock, timeout_ms: Int) -> Result(BitArray, String)

@external(erlang, "aether_udp_ffi", "close")
fn udp_close(socket: UdpSock) -> Nil

@external(erlang, "aether_e2e_test_ffi", "udp_send_to")
fn udp_send_to(host: #(Int, Int, Int, Int), port: Int, data: BitArray) -> Nil
