import aether/core/types.{type HealthConfig, type SensorId, HealthConfig}
import aether/signal.{type SignalKind, WifiCsi}
import gleam/int

pub type SensorConfig {
  SensorConfig(
    id: SensorId,
    kind: SignalKind,
    transport: Transport,
    sample_rate_hz: Int,
    sync: SyncProtocol,
    health: HealthConfig,
  )
}

pub type Transport {
  Udp(host: String, port: Int)
  Serial(path: String, baud: Int)
  Tcp(host: String, port: Int)
  CallbackTransport(handler_module: String)
}

pub type SyncProtocol {
  Gptp
  Ntp
  FreeRunning
}

/// Convenience: create a WiFi CSI sensor config
pub fn wifi_csi(
  host host: String,
  port port: Int,
  antennas antennas: Int,
  subcarriers subcarriers: Int,
  sample_rate sample_rate: Int,
) -> SensorConfig {
  SensorConfig(
    id: host <> ":" <> int.to_string(port),
    kind: WifiCsi(subcarriers: subcarriers, antennas: antennas, bandwidth: 20),
    transport: Udp(host, port),
    sample_rate_hz: sample_rate,
    sync: FreeRunning,
    health: HealthConfig(
      timeout_ms: 5000,
      max_packet_loss_pct: 5.0,
      drift_tolerance_ms: 10.0,
    ),
  )
}

/// Convenience: create a mmWave sensor config
pub fn mmwave(
  host host: String,
  port port: Int,
  freq_ghz freq: Float,
  chirps chirps: Int,
  sample_rate sample_rate: Int,
) -> SensorConfig {
  SensorConfig(
    id: host <> ":" <> int.to_string(port),
    kind: signal.MmWave(freq_ghz: freq, chirps: chirps),
    transport: Udp(host, port),
    sample_rate_hz: sample_rate,
    sync: FreeRunning,
    health: HealthConfig(
      timeout_ms: 5000,
      max_packet_loss_pct: 5.0,
      drift_tolerance_ms: 10.0,
    ),
  )
}
