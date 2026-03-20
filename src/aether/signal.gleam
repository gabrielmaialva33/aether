import aether/core/types.{type RfidBand, type SensorId}

pub type Signal {
  Signal(
    source: SensorId,
    kind: SignalKind,
    timestamp: Int,
    payload: BitArray,
    metadata: List(#(String, String)),
  )
}

pub type SignalKind {
  WifiCsi(subcarriers: Int, antennas: Int, bandwidth: Int)
  BleRssi(channels: Int)
  Uwb(bandwidth_mhz: Int)
  MmWave(freq_ghz: Float, chirps: Int)
  FmcwRadar(range_bins: Int, doppler_bins: Int)
  Rfid(frequency: RfidBand)
  UserDefinedSignal(name: String, schema: List(#(String, String)))
}

/// Signal age in microseconds relative to a reference time
pub fn signal_age_us(signal: Signal, now now: Int) -> Int {
  now - signal.timestamp
}
