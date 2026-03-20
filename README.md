# Æther

**Ambient RF perception system — sees without cameras.**

Æther transforms WiFi CSI, BLE, UWB, mmWave, and any RF signal into human perception: pose estimation, vital signs, presence detection, activity recognition, and 3D localization. Built in Gleam/OTP with Rust NIFs for signal processing and ML inference.

```gleam
import aether
import aether/core/types.{Zone}
import aether/sensor

let assert Ok(hub) =
  aether.space("home")
  |> aether.add_zone(Zone("sala", "Sala", #(0.0, 0.0, 5.0, 4.0), 0.0, 3.0))
  |> aether.add_sensor(sensor.wifi_csi(
    host: "192.168.1.50", port: 5000,
    antennas: 3, subcarriers: 56, sample_rate: 100,
  ))
  |> aether.with_api(8080)
  |> aether.start()
```

```bash
curl localhost:8080/api/perceptions
```

```json
{
  "perceptions": [
    {"type": "pose", "keypoints": [...], "skeleton": "coco17", "confidence": 0.92},
    {"type": "vitals", "heart_bpm": 72.3, "breath_bpm": 16.1, "hrv": 45.2},
    {"type": "presence", "total_occupants": 2},
    {"type": "activity", "label": "walking", "confidence": 0.85}
  ]
}
```

## Architecture

```
ESP32/Radar/BLE ──UDP──► Sensor Actor ──► Conditioner Pipeline ──► Orchestrator ──► Brain NIF ──► Perceptions
                          (OTP actor)     (Rust NIFs: TSFR,        (ring buffer,    (foundation    ──► HTTP API
                          parse CSI       Hampel, Butterworth,      AveCSI,          model,         ──► WebSocket
                          health check    SavGol, SpotFi)           fusion)          5 decoders)    ──► Subscribers
```

**OTP Supervision Tree:**
- Sensor crashes → only that sensor restarts
- Orchestrator crashes → restarts with fresh state, sensors reconnect
- Brain NIF crashes → dirty scheduler isolates, supervisor restarts

## Features

- **Sensor-agnostic**: WiFi CSI, BLE RSSI, UWB, mmWave, FMCW radar, RFID, or any custom RF source
- **Foundation model architecture**: one model, multiple decoder heads (pose, vitals, presence, activity, location)
- **Real-time**: UDP ingestion → Rust NIF processing → perception output in <15ms
- **Multi-person tracking**: Kalman filter per person per axis, nearest-neighbor association
- **Event detection**: zone enter/leave, fall detection, vitals alerts
- **API-first**: REST + WebSocket streaming, CORS enabled
- **OTP resilience**: supervision trees, graceful degradation when sensors go offline

## Signal Processing (Rust NIFs)

Algorithms validated in 2025-2026 research papers:

| NIF | Algorithm | Paper |
|-----|-----------|-------|
| `tsfr_calibrate` | Phase unwrap + linear detrend + Savitzky-Golay | TSFR (2023) |
| `hampel_filter` | Outlier detection via Median Absolute Deviation | Standard DSP |
| `butterworth_bandpass` | Zero-phase IIR cascaded biquads | Standard DSP |
| `savgol_filter` | Polynomial least-squares smoothing | Savitzky-Golay (1964) |
| `avecsi_stabilize` | Sliding window frame averaging | CSIPose (IEEE TMC 2025) |
| `spotfi_aoa` | MUSIC-based Angle of Arrival estimation | SpotFi (SIGCOMM 2015) |

## Foundation Model Decoders

| Decoder | Output | Inspired by |
|---------|--------|-------------|
| Pose | 17 COCO keypoints with velocity | GraphPose-Fi, VST-Pose |
| Vitals | Heart BPM, breathing BPM, HRV | PulseFi (2025) |
| Presence | Occupancy count, zone detection | AM-FM (2026) |
| Activity | Label + confidence (idle, walking, falling...) | X-Fi (2025) |
| Location | 3D position + accuracy | Geometry-Aware WiFi Sensing (2026) |

## Research Foundation

Built on state-of-the-art 2025-2026 papers:

- **AM-FM** (Feb 2026) — Foundation Model for Ambient Intelligence Through WiFi
- **X-Fi** (2025) — Cross-modal transformer, 24.8% MPJPE reduction
- **WiFlow** (Feb 2026) — Lightweight axial attention + TCN
- **CroSSL** (Mar 2026) — Station-wise masking for sensor robustness
- **GraphPose-Fi** — Per-antenna GCN + self-attention decoder
- **VST-Pose** — Velocity-Integrated Spatio-Temporal Attention
- **LatentCSI** — CSI to Stable Diffusion latent space mapping

## Quick Start

```bash
# Build
gleam build

# Build Rust NIFs
cd native/aether_signal && cargo build --release && cd ../..
cd native/aether_brain && cargo build --release && cd ../..

# Copy NIFs
make nif

# Test
gleam test
# 72 passed, no failures

# Run
gleam run
```

## API

### REST

```
GET  /api/health        → {"status": "ok", "version": "0.1.0"}
GET  /api/perceptions   → {"perceptions": [...], "count": 5}
GET  /api/sensors       → {"sensors": [...]}
```

### WebSocket

```
ws://localhost:8080/ws/stream → real-time perception push (JSON)
```

## Hardware

### Supported Sensors

| Sensor | Transport | CSI Support | Use Case |
|--------|-----------|-------------|----------|
| ESP32-S3 | UDP | Full CSI | Pose, vitals, presence |
| mmWave radar (IWR6843) | UDP | Range-Doppler | Micro-movements, vitals |
| BLE beacons | UDP | RSSI only | Coarse presence |
| UWB (DW3000) | UDP | CIR | Precise localization |
| Any WiFi device | UDP | RSSI degraded | Basic presence |

### ESP32 Firmware

Included in `firmware/esp32-csi-node/`. Requires ESP-IDF to build.

```bash
cd firmware/esp32-csi-node
idf.py menuconfig  # Set WiFi SSID, hub IP
idf.py build
idf.py -p /dev/ttyACM0 flash monitor
```

## Project Structure

```
aether/
├── src/aether.gleam              # Public API
├── src/aether/
│   ├── core/                     # Types, errors, math
│   ├── sensor/                   # OTP actors, UDP listener, CSI parser
│   ├── condition/                # Pipeline, ring buffer, NIF wiring
│   ├── fusion/                   # Temporal sync, cross-modal fusion
│   ├── orchestrator.gleam        # Heart of the data flow
│   ├── track/                    # Kalman filter, aggregator, events
│   ├── serve/                    # HTTP API, WebSocket, JSON codec
│   └── nif/                      # Gleam FFI to Rust NIFs
├── native/
│   ├── aether_signal/            # Rust NIF: signal processing (CPU)
│   └── aether_brain/             # Rust NIF: foundation model (CUDA)
├── test/                         # 72 tests
└── firmware/esp32-csi-node/      # ESP32-S3 CSI capture firmware
```

## Stats

- **5,800+ lines** of Gleam, Rust, Erlang, C
- **72 tests**, zero failures
- **6 signal processing NIFs** (Rust)
- **5 ML decoder heads** (Rust)
- **3 API endpoints** + WebSocket streaming
- **Kalman filter** multi-person tracking

## Tech Stack

- **Gleam 1.14** + OTP 28 — fault-tolerant actor system
- **Rust 1.94** — NIFs for signal processing + ML
- **Mist 5.x** — HTTP/WebSocket server
- **ESP-IDF** — ESP32 firmware

## License

MIT
