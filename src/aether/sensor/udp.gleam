/// Real UDP listener for sensor actors.
/// Binds to a port, receives CSI frames, forwards to sensor actor.
import aether/sensor/actor.{type SensorMsg}
import gleam/erlang/process.{type Subject}

pub type UdpSocket

/// Open a UDP socket on the given port and forward all incoming
/// packets as RawFrame messages to the sensor actor.
pub fn start_listener(
  port: Int,
  sensor: Subject(SensorMsg),
) -> Result(UdpSocket, String) {
  case udp_open(port) {
    Ok(socket) -> {
      // Spawn a linked process for the receive loop
      spawn_receiver(socket, sensor)
      Ok(socket)
    }
    Error(reason) -> Error(reason)
  }
}

// --- Erlang FFI ---

@external(erlang, "aether_udp_ffi", "open")
fn udp_open(port: Int) -> Result(UdpSocket, String)

@external(erlang, "aether_udp_ffi", "recv")
pub fn udp_recv(socket: UdpSocket, timeout_ms: Int) -> Result(BitArray, String)

@external(erlang, "aether_udp_ffi", "close")
pub fn close(socket: UdpSocket) -> Nil

@external(erlang, "aether_udp_ffi", "spawn_receiver")
fn spawn_receiver(socket: UdpSocket, sensor: Subject(SensorMsg)) -> Nil
