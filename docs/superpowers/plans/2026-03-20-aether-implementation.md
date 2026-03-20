# Æther Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Æther library — a Gleam/OTP ambient RF perception system that turns WiFi CSI (and any RF signal) into human perception via foundation models.

**Architecture:** Gleam library with OTP supervision tree orchestrating sensor actors, a signal conditioning pipeline, cross-modal fusion, and foundation model inference via Rust NIFs on CUDA. API-first design with WebSocket streaming.

**Tech Stack:** Gleam 1.14, Erlang/OTP 28, Rust 1.94 (NIFs), CUDA (RTX 4090), Mist/Wisp (HTTP/WS), gleeunit (tests), viva_tensor (ML compute)

**Spec:** `docs/superpowers/specs/2026-03-20-aether-design.md`

---

## File Map

```
aether/
├── gleam.toml                              # Project manifest
├── Makefile                                # Build orchestration
├── src/
│   ├── aether.gleam                        # Public API — start(), perceive(), on_event()
│   ├── aether/
│   │   ├── core/
│   │   │   ├── types.gleam                 # Vec3, SensorId, Zone, NifModelRef, etc
│   │   │   ├── error.gleam                 # AetherError centralized type
│   │   │   └── math.gleam                  # Pure Gleam math helpers (vec3 ops)
│   │   ├── signal.gleam                    # Signal, SignalKind types
│   │   ├── sensor.gleam                    # SensorConfig, Transport, SyncProtocol
│   │   ├── sensor/
│   │   │   ├── actor.gleam                 # Sensor OTP actor (UDP listener)
│   │   │   ├── supervisor.gleam            # SensorSupervisor (one_for_one)
│   │   │   ├── parser.gleam               # Raw bytes → Signal (per SignalKind)
│   │   │   └── health.gleam               # Sensor health monitor
│   │   ├── condition/
│   │   │   ├── pipeline.gleam             # Pipeline actor + functional composition
│   │   │   ├── phase.gleam                # Phase calibration (TSFR, LinearFit)
│   │   │   ├── denoise.gleam              # Hampel, Butterworth, SavitzkyGolay
│   │   │   └── stabilize.gleam            # AveCSI stabilization
│   │   ├── fusion/
│   │   │   ├── engine.gleam               # FusionEngine actor
│   │   │   └── sync.gleam                 # Temporal alignment / sync coordinator
│   │   ├── model/
│   │   │   ├── foundation.gleam           # FoundationModel lifecycle (load/infer)
│   │   │   ├── encoder.gleam              # Encoder type configs
│   │   │   ├── decoder.gleam              # Decoder type configs
│   │   │   └── checkpoint.gleam           # Save/load/version checkpoints
│   │   ├── perception.gleam               # Perception, Keypoint, Event types
│   │   ├── track/
│   │   │   ├── aggregator.gleam           # PerceptionAggregator actor
│   │   │   ├── person.gleam               # Per-person Kalman state
│   │   │   ├── zone.gleam                 # Zone occupancy management
│   │   │   └── event.gleam                # Event detection & dispatch
│   │   ├── space.gleam                    # Space builder + supervisor
│   │   ├── config.gleam                   # Builder pattern helpers
│   │   ├── serve/
│   │   │   ├── api.gleam                  # REST endpoints (Wisp)
│   │   │   ├── ws.gleam                   # WebSocket streaming (Mist)
│   │   │   └── codec.gleam                # JSON encode/decode for Perception
│   │   └── nif/
│   │       ├── signal.gleam               # FFI bindings → aether_signal NIF
│   │       └── brain.gleam                # FFI bindings → aether_brain NIF
│   ├── aether_signal_nif.erl              # Erlang NIF stubs (signal processing)
│   └── aether_brain_nif.erl               # Erlang NIF stubs (foundation model)
├── native/
│   ├── aether_signal/                     # Rust NIF — CPU signal processing
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs                     # NIF registration + entry
│   │       ├── tsfr.rs                    # TSFR phase calibration
│   │       ├── filters.rs                 # Hampel, Butterworth, SavitzkyGolay
│   │       ├── avecsi.rs                  # AveCSI stabilization
│   │       ├── doppler.rs                 # IFFT + CIR reconstruction
│   │       └── spotfi.rs                  # AoA estimation
│   └── aether_brain/                      # Rust NIF — CUDA ML
│       ├── Cargo.toml                     # depends on viva_tensor
│       └── src/
│           ├── lib.rs                     # NIF registration
│           ├── model.rs                   # Foundation model struct + lifecycle
│           ├── encoder.rs                 # Cross-modal transformer encoder
│           ├── decoder/
│           │   ├── mod.rs
│           │   ├── pose.rs                # GCN + attention
│           │   ├── vitals.rs              # LSTM head
│           │   └── presence.rs            # Classification head
│           ├── fusion.rs                  # Cross-modal attention
│           └── training.rs                # Forward/backward/optim
├── test/
│   ├── aether_test.gleam                  # Integration tests
│   ├── core/
│   │   ├── types_test.gleam               # Core types tests
│   │   ├── error_test.gleam               # Error formatting tests
│   │   └── math_test.gleam                # Vec3 math tests
│   ├── signal_test.gleam                  # Signal construction tests
│   ├── sensor/
│   │   ├── parser_test.gleam              # CSI parser tests
│   │   └── actor_test.gleam               # Sensor actor tests
│   ├── condition/
│   │   ├── pipeline_test.gleam            # Pipeline composition tests
│   │   ├── phase_test.gleam               # TSFR tests (with NIF)
│   │   └── denoise_test.gleam             # Filter tests (with NIF)
│   ├── fusion/
│   │   └── sync_test.gleam                # Temporal alignment tests
│   ├── track/
│   │   ├── aggregator_test.gleam          # Aggregator tests
│   │   ├── person_test.gleam              # Kalman filter tests
│   │   └── zone_test.gleam                # Zone assignment tests
│   └── serve/
│       ├── codec_test.gleam               # JSON codec tests
│       └── api_test.gleam                 # API endpoint tests
├── firmware/
│   └── esp32-csi-node/                    # Separate build (ESP-IDF)
├── models/
│   └── .gitkeep
└── docs/
    └── superpowers/
        ├── specs/
        └── plans/
```

---

## Phase 1: Foundation (project scaffold + core types)

### Task 1: Project Scaffold

**Files:**
- Create: `gleam.toml`
- Create: `Makefile`
- Create: `.gitignore`

- [ ] **Step 1: Initialize Gleam project**

```bash
cd /home/gabrielmaia/Documents/aether
gleam new aether --skip-git .
```

Note: project already has git initialized. The `gleam new` may need adjustment — if it fails because directory exists, manually create `gleam.toml`.

- [ ] **Step 2: Write gleam.toml**

```toml
name = "aether"
version = "0.1.0"
description = "Ambient RF perception system — sees without cameras"
licences = ["MIT"]
repository = { type = "github", user = "gabrielmaialva33", repo = "aether" }
target = "erlang"

[dependencies]
gleam_stdlib = ">= 0.44.0 and < 2.0.0"
gleam_erlang = ">= 1.0.0 and < 2.0.0"
gleam_otp = ">= 1.0.0 and < 2.0.0"
gleam_json = ">= 3.0.0 and < 4.0.0"
gleam_http = ">= 3.0.0 and < 5.0.0"
mist = ">= 5.0.0 and < 6.0.0"
gleam_crypto = ">= 1.0.0 and < 2.0.0"
logging = ">= 1.0.0 and < 2.0.0"

[dev-dependencies]
gleeunit = ">= 1.0.0 and < 2.0.0"
gleamy_bench = ">= 0.6.0 and < 1.0.0"
```

- [ ] **Step 3: Write Makefile**

```makefile
.PHONY: build test fmt check clean nif-signal nif-brain

build: nif-signal
	gleam build

test:
	gleam test

fmt:
	gleam format src test

check:
	gleam check

clean:
	gleam clean

# Signal processing NIF (CPU)
nif-signal:
	cd native/aether_signal && cargo build --release
	mkdir -p build/dev/erlang/aether/priv
	cp native/aether_signal/target/release/libaether_signal.so \
		build/dev/erlang/aether/priv/aether_signal.so

# Foundation model NIF (CUDA)
nif-brain:
	cd native/aether_brain && cargo build --release
	mkdir -p build/dev/erlang/aether/priv
	cp native/aether_brain/target/release/libaether_brain.so \
		build/dev/erlang/aether/priv/aether_brain.so

nif: nif-signal nif-brain
```

- [ ] **Step 4: Write .gitignore**

```
build/
erl_crash.dump
*.beam
*.ez
native/*/target/
*.so
```

- [ ] **Step 5: Run `gleam build` to verify scaffold**

Run: `gleam build`
Expected: builds successfully, downloads dependencies

- [ ] **Step 6: Commit**

```bash
git add gleam.toml Makefile .gitignore
git commit -m "scaffold: initialize Gleam project with deps and Makefile"
```

---

### Task 2: Core Types

**Files:**
- Create: `src/aether/core/types.gleam`
- Test: `test/core/types_test.gleam`

- [ ] **Step 1: Write the failing test**

```gleam
// test/core/types_test.gleam
import aether/core/types.{Vec3, Zone, vec3_add, vec3_distance, vec3_zero}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn vec3_add_test() {
  let a = Vec3(1.0, 2.0, 3.0)
  let b = Vec3(4.0, 5.0, 6.0)
  let result = vec3_add(a, b)
  result.x |> should.equal(5.0)
  result.y |> should.equal(7.0)
  result.z |> should.equal(9.0)
}

pub fn vec3_zero_test() {
  let z = vec3_zero()
  z.x |> should.equal(0.0)
  z.y |> should.equal(0.0)
  z.z |> should.equal(0.0)
}

pub fn vec3_distance_test() {
  let a = Vec3(0.0, 0.0, 0.0)
  let b = Vec3(3.0, 4.0, 0.0)
  vec3_distance(a, b) |> should.equal(5.0)
}

pub fn zone_contains_point_test() {
  let zone = Zone(
    id: "sala",
    name: "Sala de Estar",
    bounds: #(0.0, 0.0, 5.0, 4.0),
    floor: 0.0,
    ceiling: 3.0,
  )
  types.zone_contains(zone, Vec3(2.5, 2.0, 1.0)) |> should.be_true()
  types.zone_contains(zone, Vec3(6.0, 2.0, 1.0)) |> should.be_false()
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gleam test`
Expected: FAIL — module `aether/core/types` not found

- [ ] **Step 3: Write core types**

```gleam
// src/aether/core/types.gleam
import gleam/dynamic.{type Dynamic}
import gleam/float
import gleam/option.{type Option}

/// Identifiers
pub type SensorId =
  String

pub type PersonId =
  String

pub type ZoneId =
  String

/// 3D vector
pub type Vec3 {
  Vec3(x: Float, y: Float, z: Float)
}

pub fn vec3_zero() -> Vec3 {
  Vec3(0.0, 0.0, 0.0)
}

pub fn vec3_add(a: Vec3, b: Vec3) -> Vec3 {
  Vec3(a.x +. b.x, a.y +. b.y, a.z +. b.z)
}

pub fn vec3_sub(a: Vec3, b: Vec3) -> Vec3 {
  Vec3(a.x -. b.x, a.y -. b.y, a.z -. b.z)
}

pub fn vec3_scale(v: Vec3, s: Float) -> Vec3 {
  Vec3(v.x *. s, v.y *. s, v.z *. s)
}

pub fn vec3_magnitude(v: Vec3) -> Float {
  let sq = v.x *. v.x +. v.y *. v.y +. v.z *. v.z
  float_sqrt(sq)
}

pub fn vec3_distance(a: Vec3, b: Vec3) -> Float {
  vec3_sub(a, b) |> vec3_magnitude()
}

@external(erlang, "math", "sqrt")
fn float_sqrt(x: Float) -> Float

/// Zone definition
pub type Zone {
  Zone(
    id: ZoneId,
    name: String,
    bounds: #(Float, Float, Float, Float),
    floor: Float,
    ceiling: Float,
  )
}

pub fn zone_contains(zone: Zone, point: Vec3) -> Bool {
  let #(x_min, y_min, x_max, y_max) = zone.bounds
  point.x >=. x_min
  && point.x <=. x_max
  && point.y >=. y_min
  && point.y <=. y_max
  && point.z >=. zone.floor
  && point.z <=. zone.ceiling
}

/// Zone occupancy snapshot
pub type ZoneOccupancy {
  ZoneOccupancy(zone: ZoneId, count: Int, person_ids: List(PersonId))
}

/// Through-wall target
pub type ThroughWallTarget {
  ThroughWallTarget(
    position: Vec3,
    signal_strength: Float,
    is_moving: Bool,
    estimated_activity: Option(String),
  )
}

/// Vitals alert kinds
pub type VitalsAlertKind {
  TachycardiaAlert
  BradycardiaAlert
  ApneaAlert
  IrregularRhythmAlert
}

/// Sensor health config
pub type HealthConfig {
  HealthConfig(
    timeout_ms: Int,
    max_packet_loss_pct: Float,
    drift_tolerance_ms: Float,
  )
}

/// Doppler config
pub type DopplerConfig {
  DopplerConfig(fft_size: Int, window_type: String, overlap: Float)
}

/// Subcarrier selection
pub type SelectionMethod {
  RemoveEdge(n: Int)
  VarianceThreshold(min: Float)
  ManualSelect(indices: List(Int))
}

/// RFID frequency bands
pub type RfidBand {
  Lf125Khz
  Hf13Mhz
  Uhf900Mhz
  Shf2400Mhz
}

/// Opaque NIF model reference
pub opaque type NifModelRef {
  NifModelRef(ref: Dynamic)
}

/// Field model — persistent RF background
pub type FieldModel {
  FieldModel(
    background: BitArray,
    zone_calibrations: List(#(String, BitArray)),
    last_updated: Int,
  )
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `gleam test`
Expected: All 4 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/aether/core/types.gleam test/core/types_test.gleam
git commit -m "feat: add core types — Vec3, Zone, SensorId, NifModelRef"
```

---

### Task 3: Error Types

**Files:**
- Create: `src/aether/core/error.gleam`
- Test: `test/core/error_test.gleam`

- [ ] **Step 1: Write the failing test**

```gleam
// test/core/error_test.gleam
import aether/core/error.{
  AetherError, SensorOffline, ModelNotLoaded, NoSensorsAvailable,
  to_string as error_to_string,
}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn sensor_offline_to_string_test() {
  SensorOffline("esp32-sala", "connection refused")
  |> error_to_string()
  |> should.equal("[sensor:esp32-sala] offline: connection refused")
}

pub fn model_not_loaded_to_string_test() {
  ModelNotLoaded
  |> error_to_string()
  |> should.equal("[model] not loaded")
}

pub fn no_sensors_to_string_test() {
  NoSensorsAvailable
  |> error_to_string()
  |> should.equal("[space] no sensors available")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gleam test`
Expected: FAIL — module not found

- [ ] **Step 3: Write error types**

```gleam
// src/aether/core/error.gleam
import aether/core/types.{type SensorId}
import gleam/float
import gleam/int

pub type AetherError {
  // Sensor
  SensorOffline(id: SensorId, reason: String)
  SensorTimeout(id: SensorId, last_seen_ms: Int)
  ParseError(sensor: SensorId, reason: String)
  // Signal
  CalibrationFailed(method: String, reason: String)
  InsufficientData(expected: Int, got: Int)
  // Fusion
  SyncError(drift_ms: Float, tolerance_ms: Float)
  NoSensorsAvailable
  // Model
  ModelNotLoaded
  InferenceError(reason: String)
  CheckpointNotFound(path: String)
  CudaError(code: Int, message: String)
  // Space
  ZoneNotFound(id: String)
  SpaceNotConfigured(missing: String)
}

pub fn to_string(error: AetherError) -> String {
  case error {
    SensorOffline(id, reason) ->
      "[sensor:" <> id <> "] offline: " <> reason
    SensorTimeout(id, ms) ->
      "[sensor:" <> id <> "] timeout after " <> int.to_string(ms) <> "ms"
    ParseError(sensor, reason) ->
      "[sensor:" <> sensor <> "] parse error: " <> reason
    CalibrationFailed(method, reason) ->
      "[calibration:" <> method <> "] failed: " <> reason
    InsufficientData(expected, got) ->
      "[data] insufficient: expected "
      <> int.to_string(expected)
      <> " got "
      <> int.to_string(got)
    SyncError(drift, tolerance) ->
      "[sync] drift "
      <> float.to_string(drift)
      <> "ms exceeds tolerance "
      <> float.to_string(tolerance)
      <> "ms"
    NoSensorsAvailable -> "[space] no sensors available"
    ModelNotLoaded -> "[model] not loaded"
    InferenceError(reason) -> "[inference] error: " <> reason
    CheckpointNotFound(path) -> "[checkpoint] not found: " <> path
    CudaError(code, msg) ->
      "[cuda:" <> int.to_string(code) <> "] " <> msg
    ZoneNotFound(id) -> "[zone:" <> id <> "] not found"
    SpaceNotConfigured(missing) ->
      "[space] not configured: missing " <> missing
  }
}
```

- [ ] **Step 4: Run tests**

Run: `gleam test`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add src/aether/core/error.gleam test/core/error_test.gleam
git commit -m "feat: add centralized AetherError type with formatting"
```

---

### Task 4: Signal & Perception Types

**Files:**
- Create: `src/aether/signal.gleam`
- Create: `src/aether/perception.gleam`
- Test: `test/signal_test.gleam`

- [ ] **Step 1: Write the failing test**

```gleam
// test/signal_test.gleam
import aether/signal.{Signal, WifiCsi, signal_age_us}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn create_wifi_csi_signal_test() {
  let sig = Signal(
    source: "esp32-sala",
    kind: WifiCsi(subcarriers: 56, antennas: 3, bandwidth: 20),
    timestamp: 1_000_000,
    payload: <<0, 1, 2, 3>>,
    metadata: [],
  )
  sig.source |> should.equal("esp32-sala")
}

pub fn signal_age_test() {
  let sig = Signal(
    source: "test",
    kind: WifiCsi(subcarriers: 56, antennas: 3, bandwidth: 20),
    timestamp: 100,
    payload: <<>>,
    metadata: [],
  )
  signal_age_us(sig, now: 350) |> should.equal(250)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gleam test`
Expected: FAIL

- [ ] **Step 3: Write Signal types**

```gleam
// src/aether/signal.gleam
import aether/core/types.{type RfidBand, type SensorId}
import gleam/dict.{type Dict}

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
```

- [ ] **Step 4: Write Perception types**

```gleam
// src/aether/perception.gleam
import aether/core/types.{
  type PersonId, type SensorId, type ThroughWallTarget, type Vec3,
  type VitalsAlertKind, type ZoneId, type ZoneOccupancy,
}
import gleam/option.{type Option}

pub type SkeletonGraph {
  Coco17
  Halpe26
  CustomTopology(edges: List(#(Int, Int)), names: List(String))
}

pub type Keypoint {
  Keypoint(
    id: Int,
    name: String,
    x: Float,
    y: Float,
    z: Float,
    confidence: Float,
    velocity: Option(Vec3),
  )
}

pub type Perception {
  Pose(keypoints: List(Keypoint), skeleton: SkeletonGraph, confidence: Float)
  Vitals(
    heart_bpm: Float,
    breath_bpm: Float,
    hrv: Option(Float),
    confidence: Float,
  )
  Presence(zones: List(ZoneOccupancy), total_occupants: Int)
  Location(position: Vec3, accuracy_m: Float, velocity: Option(Vec3))
  Activity(label: String, confidence: Float, duration_ms: Int)
  ThroughWall(targets: List(ThroughWallTarget))
  FreeformPerception(kind: String, data: String)
}

pub type Event {
  PersonEntered(person: PersonId, zone: ZoneId)
  PersonLeft(person: PersonId, zone: ZoneId)
  FallDetected(person: PersonId, confidence: Float)
  VitalsAlert(person: PersonId, kind: VitalsAlertKind)
  SensorOffline(sensor: SensorId)
  SensorRecovered(sensor: SensorId)
}
```

- [ ] **Step 5: Run tests**

Run: `gleam test`
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add src/aether/signal.gleam src/aether/perception.gleam test/signal_test.gleam
git commit -m "feat: add Signal, SignalKind, Perception, Event types"
```

---

## Phase 2: Sensor Layer

### Task 5: Sensor Config & Parser

**Files:**
- Create: `src/aether/sensor.gleam`
- Create: `src/aether/sensor/parser.gleam`
- Test: `test/sensor/parser_test.gleam`

- [ ] **Step 1: Write the failing test**

```gleam
// test/sensor/parser_test.gleam
import aether/sensor
import aether/sensor/parser
import aether/signal.{WifiCsi}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn parse_wifi_csi_frame_test() {
  // Simulated CSI frame: 4-byte header (magic + seq) + 6 floats (2 subcarriers x 3 antennas)
  // Header: 0xAE 0x01 (magic) + 0x00 0x01 (seq=1)
  let frame = <<
    0xAE, 0x01, 0x00, 0x01,
    // amplitude data (6 x float32 = 24 bytes)
    63, 128, 0, 0,  // 1.0
    64, 0, 0, 0,    // 2.0
    64, 64, 0, 0,   // 3.0
    64, 128, 0, 0,  // 4.0
    64, 160, 0, 0,  // 5.0
    64, 192, 0, 0,  // 6.0
  >>

  let kind = WifiCsi(subcarriers: 2, antennas: 3, bandwidth: 20)
  let result = parser.parse_csi_frame(frame, kind)
  result |> should.be_ok()
}

pub fn parse_invalid_magic_test() {
  let frame = <<0xFF, 0xFF, 0x00, 0x01>>
  let kind = WifiCsi(subcarriers: 2, antennas: 3, bandwidth: 20)
  let result = parser.parse_csi_frame(frame, kind)
  result |> should.be_error()
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gleam test`
Expected: FAIL

- [ ] **Step 3: Write Sensor config types**

```gleam
// src/aether/sensor.gleam
import aether/core/types.{type HealthConfig, type SensorId}
import aether/signal.{type SignalKind}
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

/// Convenience constructors
pub fn wifi_csi(
  host host: String,
  port port: Int,
  antennas antennas: Int,
  subcarriers subcarriers: Int,
  sample_rate sample_rate: Int,
) -> SensorConfig {
  SensorConfig(
    id: host <> ":" <> int.to_string(port),
    kind: signal.WifiCsi(subcarriers: subcarriers, antennas: antennas, bandwidth: 20),
    transport: Udp(host, port),
    sample_rate_hz: sample_rate,
    sync: FreeRunning,
    health: HealthConfig(timeout_ms: 5000, max_packet_loss_pct: 5.0, drift_tolerance_ms: 10.0),
  )
}
```

- [ ] **Step 4: Write parser**

```gleam
// src/aether/sensor/parser.gleam
import aether/core/error.{type AetherError, ParseError}
import aether/signal.{type Signal, type SignalKind, Signal, WifiCsi}

/// CSI frame magic bytes
const csi_magic = 0xAE01

pub type CsiFrame {
  CsiFrame(sequence: Int, data: BitArray)
}

pub fn parse_csi_frame(
  raw: BitArray,
  kind: SignalKind,
) -> Result(CsiFrame, AetherError) {
  case raw {
    <<magic:size(16), seq:size(16), data:bytes>> if magic == csi_magic ->
      Ok(CsiFrame(sequence: seq, data: data))
    <<magic:size(16), _:bits>> ->
      Error(ParseError("csi", "invalid magic: expected 0xAE01"))
    _ ->
      Error(ParseError("csi", "frame too short"))
  }
}
```

- [ ] **Step 5: Run tests**

Run: `gleam test`
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add src/aether/sensor.gleam src/aether/sensor/parser.gleam test/sensor/parser_test.gleam
git commit -m "feat: add SensorConfig, Transport, CSI frame parser"
```

---

### Task 6: Sensor OTP Actor

**Files:**
- Create: `src/aether/sensor/actor.gleam`
- Test: `test/sensor/actor_test.gleam`

- [ ] **Step 1: Write the failing test**

```gleam
// test/sensor/actor_test.gleam
import aether/sensor/actor as sensor_actor
import aether/signal.{type Signal, WifiCsi}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn sensor_actor_receives_frame_test() {
  // Create a subscriber to receive parsed signals
  let subscriber = process.new_subject()

  // Start sensor actor in test mode (no UDP, inject frames directly)
  let config = sensor_actor.TestConfig(
    id: "test-sensor",
    kind: WifiCsi(subcarriers: 2, antennas: 3, bandwidth: 20),
    subscriber: subscriber,
  )
  let assert Ok(sensor) = sensor_actor.start_test(config)

  // Inject a raw frame
  let frame = <<
    0xAE, 0x01, 0x00, 0x01,
    63, 128, 0, 0,
    64, 0, 0, 0,
    64, 64, 0, 0,
    64, 128, 0, 0,
    64, 160, 0, 0,
    64, 192, 0, 0,
  >>
  sensor_actor.inject_frame(sensor, frame)

  // Should receive a parsed signal
  let assert Ok(signal) = process.receive(subscriber, 1000)
  signal.source |> should.equal("test-sensor")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gleam test`
Expected: FAIL

- [ ] **Step 3: Write sensor actor**

```gleam
// src/aether/sensor/actor.gleam
import aether/core/error.{type AetherError}
import aether/sensor/parser
import aether/signal.{type Signal, type SignalKind, Signal}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor

pub type SensorMsg {
  RawFrame(data: BitArray)
  GetStats(reply: Subject(SensorStats))
  Shutdown
}

pub type SensorState {
  SensorState(
    id: String,
    kind: SignalKind,
    subscriber: Subject(Signal),
    frames_received: Int,
    parse_errors: Int,
  )
}

pub type SensorStats {
  SensorStats(frames_received: Int, parse_errors: Int)
}

/// Test config — no UDP, frames injected manually
pub type TestConfig {
  TestConfig(
    id: String,
    kind: SignalKind,
    subscriber: Subject(Signal),
  )
}

pub fn start_test(
  config: TestConfig,
) -> Result(Subject(SensorMsg), actor.StartError) {
  let state =
    SensorState(
      id: config.id,
      kind: config.kind,
      subscriber: config.subscriber,
      frames_received: 0,
      parse_errors: 0,
    )
  actor.start(state, handle_message)
}

pub fn inject_frame(sensor: Subject(SensorMsg), frame: BitArray) -> Nil {
  actor.send(sensor, RawFrame(frame))
}

fn handle_message(
  msg: SensorMsg,
  state: SensorState,
) -> actor.Next(SensorMsg, SensorState) {
  case msg {
    RawFrame(data) -> {
      case parser.parse_csi_frame(data, state.kind) {
        Ok(frame) -> {
          let signal =
            Signal(
              source: state.id,
              kind: state.kind,
              timestamp: monotonic_time_us(),
              payload: frame.data,
              metadata: [],
            )
          process.send(state.subscriber, signal)
          actor.continue(SensorState(
            ..state,
            frames_received: state.frames_received + 1,
          ))
        }
        Error(_) ->
          actor.continue(SensorState(
            ..state,
            parse_errors: state.parse_errors + 1,
          ))
      }
    }
    GetStats(reply) -> {
      process.send(
        reply,
        SensorStats(state.frames_received, state.parse_errors),
      )
      actor.continue(state)
    }
    Shutdown -> actor.Stop(process.Normal)
  }
}

/// Returns BEAM monotonic time in microseconds
@external(erlang, "aether_time_ffi", "monotonic_us")
fn monotonic_time_us() -> Int
// Erlang helper: aether_time_ffi:monotonic_us() -> erlang:monotonic_time(microsecond).
```

- [ ] **Step 4: Run tests**

Run: `gleam test`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add src/aether/sensor/actor.gleam test/sensor/actor_test.gleam
git commit -m "feat: add Sensor OTP actor with frame injection for testing"
```

---

## Phase 3: Signal Conditioning (Rust NIF)

### Task 7: aether_signal NIF Scaffold

**Files:**
- Create: `native/aether_signal/Cargo.toml`
- Create: `native/aether_signal/src/lib.rs`
- Create: `native/aether_signal/src/filters.rs`
- Create: `src/aether_signal_nif.erl`
- Create: `src/aether/nif/signal.gleam`

- [ ] **Step 1: Create Cargo.toml**

```toml
[package]
name = "aether_signal"
version = "0.1.0"
edition = "2024"

[lib]
name = "aether_signal"
crate-type = ["cdylib"]

[dependencies]
rustler = "0.36"
```

- [ ] **Step 2: Write NIF lib.rs with Hampel filter**

```rust
// native/aether_signal/src/lib.rs
mod filters;

use rustler::{Env, NifResult, Term};

#[rustler::nif]
fn hampel_filter(data: Vec<f64>, window: usize, threshold: f64) -> NifResult<Vec<f64>> {
    Ok(filters::hampel(&data, window, threshold))
}

#[rustler::nif]
fn butterworth_bandpass(
    data: Vec<f64>,
    order: usize,
    low_hz: f64,
    high_hz: f64,
    sample_rate: f64,
) -> NifResult<Vec<f64>> {
    Ok(filters::butterworth_bp(&data, order, low_hz, high_hz, sample_rate))
}

#[rustler::nif]
fn avecsi_stabilize(frames: Vec<Vec<f64>>, window: usize) -> NifResult<Vec<f64>> {
    Ok(filters::avecsi(&frames, window))
}

rustler::init!("aether_signal_nif");
```

- [ ] **Step 3: Write filters.rs**

```rust
// native/aether_signal/src/filters.rs

/// Hampel filter — detect and replace outliers using median absolute deviation
pub fn hampel(data: &[f64], window: usize, threshold: f64) -> Vec<f64> {
    let n = data.len();
    let mut result = data.to_vec();

    for i in 0..n {
        let start = if i >= window { i - window } else { 0 };
        let end = (i + window + 1).min(n);
        let mut window_data: Vec<f64> = data[start..end].to_vec();
        window_data.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

        let median = window_data[window_data.len() / 2];
        let mut deviations: Vec<f64> = window_data.iter().map(|x| (x - median).abs()).collect();
        deviations.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
        let mad = 1.4826 * deviations[deviations.len() / 2];

        if (data[i] - median).abs() > threshold * mad && mad > 1e-10 {
            result[i] = median;
        }
    }
    result
}

/// AveCSI — sliding window average for CSI stabilization
pub fn avecsi(frames: &[Vec<f64>], window: usize) -> Vec<f64> {
    if frames.is_empty() {
        return vec![];
    }
    let len = frames[0].len();
    let n = frames.len().min(window);
    let start = if frames.len() > window { frames.len() - window } else { 0 };

    let mut avg = vec![0.0; len];
    for frame in &frames[start..] {
        for (i, &val) in frame.iter().enumerate() {
            if i < len {
                avg[i] += val;
            }
        }
    }
    for val in &mut avg {
        *val /= n as f64;
    }
    avg
}

/// Butterworth bandpass — simplified 2nd order IIR
/// Full implementation uses bilinear transform; this is a functional placeholder
pub fn butterworth_bp(
    data: &[f64],
    _order: usize,
    low_hz: f64,
    high_hz: f64,
    sample_rate: f64,
) -> Vec<f64> {
    // Simplified: use frequency-domain filtering via DFT
    // Full Butterworth IIR implementation in Phase 3 refinement
    let n = data.len();
    if n == 0 {
        return vec![];
    }

    // For now: simple moving average bandpass approximation
    // Real implementation will use proper IIR coefficients
    let low_idx = (low_hz / sample_rate * n as f64) as usize;
    let high_idx = (high_hz / sample_rate * n as f64) as usize;

    data.to_vec() // Placeholder — real implementation in Task 10
}
```

- [ ] **Step 4: Write Erlang NIF stubs**

```erlang
%% src/aether_signal_nif.erl
-module(aether_signal_nif).
-export([hampel_filter/3, butterworth_bandpass/5, avecsi_stabilize/2]).
-on_load(init/0).

init() ->
    PrivDir = case code:priv_dir(aether) of
        {error, bad_name} ->
            case file:get_cwd() of
                {ok, Cwd} -> filename:join(Cwd, "priv");
                _ -> "priv"
            end;
        Dir -> Dir
    end,
    NifPath = filename:join(PrivDir, "aether_signal"),
    case erlang:load_nif(NifPath, 0) of
        ok ->
            persistent_term:put(aether_signal_nif_loaded, true), ok;
        {error, {load_failed, _}} ->
            persistent_term:put(aether_signal_nif_loaded, false), ok;
        {error, {reload, _}} -> ok;
        {error, Reason} -> {error, Reason}
    end.

hampel_filter(_Data, _Window, _Threshold) ->
    erlang:nif_error(nif_not_loaded).

butterworth_bandpass(_Data, _Order, _LowHz, _HighHz, _SampleRate) ->
    erlang:nif_error(nif_not_loaded).

avecsi_stabilize(_Frames, _Window) ->
    erlang:nif_error(nif_not_loaded).
```

- [ ] **Step 5: Write Gleam FFI bindings**

```gleam
// src/aether/nif/signal.gleam

@external(erlang, "aether_signal_nif", "hampel_filter")
pub fn hampel_filter(
  data: List(Float),
  window: Int,
  threshold: Float,
) -> List(Float)

@external(erlang, "aether_signal_nif", "butterworth_bandpass")
pub fn butterworth_bandpass(
  data: List(Float),
  order: Int,
  low_hz: Float,
  high_hz: Float,
  sample_rate: Float,
) -> List(Float)

@external(erlang, "aether_signal_nif", "avecsi_stabilize")
pub fn avecsi_stabilize(
  frames: List(List(Float)),
  window: Int,
) -> List(Float)
```

- [ ] **Step 6: Build NIF**

Run: `cd native/aether_signal && cargo build --release`
Expected: Compiles successfully

Run: `make nif-signal`
Expected: .so copied to priv/

- [ ] **Step 7: Commit**

```bash
git add native/aether_signal/ src/aether_signal_nif.erl src/aether/nif/signal.gleam
git commit -m "feat: add aether_signal Rust NIF — Hampel, Butterworth, AveCSI"
```

---

### Task 8: Conditioner Pipeline

**Files:**
- Create: `src/aether/condition/pipeline.gleam`
- Test: `test/condition/pipeline_test.gleam`

- [ ] **Step 1: Write the failing test**

```gleam
// test/condition/pipeline_test.gleam
import aether/condition/pipeline.{
  type PipelineMode, Inference, Training,
  type Conditioner, Denoise, Stabilize, Augment,
  run_pipeline,
}
import aether/signal.{Signal, WifiCsi}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn pipeline_runs_in_order_test() {
  // Pipeline with 2 stages
  let stages = [
    Stabilize(window_size: 5),
    Denoise(pipeline.Hampel(window: 3, threshold: 3.0)),
  ]

  let sig = Signal(
    source: "test",
    kind: WifiCsi(subcarriers: 4, antennas: 1, bandwidth: 20),
    timestamp: 100,
    payload: <<>>,
    metadata: [],
  )

  // Should not crash — returns processed signal
  let result = run_pipeline(sig, stages, Inference)
  result |> should.be_ok()
}

pub fn pipeline_skips_augment_in_inference_test() {
  let stages = [
    Augment(pipeline.StationMasking(prob: 0.3)),
  ]

  let sig = Signal(
    source: "test",
    kind: WifiCsi(subcarriers: 4, antennas: 1, bandwidth: 20),
    timestamp: 100,
    payload: <<>>,
    metadata: [],
  )

  // In inference mode, Augment is skipped — signal passes through unchanged
  let assert Ok(result) = run_pipeline(sig, stages, Inference)
  result.payload |> should.equal(sig.payload)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gleam test`
Expected: FAIL

- [ ] **Step 3: Write pipeline**

```gleam
// src/aether/condition/pipeline.gleam
import aether/core/error.{type AetherError}
import aether/signal.{type Signal}
import gleam/list
import gleam/result

pub type PipelineMode {
  Inference
  Training
}

pub type Conditioner {
  PhaseCalibrate(method: PhaseMethod)
  Denoise(method: DenoiseMethod)
  Stabilize(window_size: Int)
  Augment(method: AugmentMethod)
}

pub type PhaseMethod {
  Tsfr
  LinearFit
}

pub type DenoiseMethod {
  Hampel(window: Int, threshold: Float)
  Butterworth(order: Int, cutoff_hz: Float)
  SavitzkyGolay(window: Int, poly_order: Int)
}

pub type AugmentMethod {
  GaussianNoise(std: Float)
  Scaling(range: #(Float, Float))
  StationMasking(prob: Float)
}

pub type PipelineConfig {
  PipelineConfig(
    stages: List(Conditioner),
    mode: PipelineMode,
    buffer_size: Int,
    drop_stale_after_ms: Int,
  )
}

/// Run the conditioning pipeline as functional composition.
/// Augment stages are skipped in Inference mode.
pub fn run_pipeline(
  signal: Signal,
  stages: List(Conditioner),
  mode: PipelineMode,
) -> Result(Signal, AetherError) {
  list.try_fold(stages, signal, fn(sig, stage) {
    apply_stage(sig, stage, mode)
  })
}

fn apply_stage(
  signal: Signal,
  stage: Conditioner,
  mode: PipelineMode,
) -> Result(Signal, AetherError) {
  case stage, mode {
    // Skip augmentation in inference mode
    Augment(_), Inference -> Ok(signal)

    // Placeholder implementations — real logic delegates to NIFs
    PhaseCalibrate(_method), _ -> Ok(signal)
    Denoise(_method), _ -> Ok(signal)
    Stabilize(_window), _ -> Ok(signal)
    Augment(_method), Training -> Ok(signal)
  }
}

/// Default pipeline for WiFi CSI (validated in TSFR + AveCSI papers)
pub fn default_wifi() -> List(Conditioner) {
  [
    PhaseCalibrate(Tsfr),
    Denoise(Hampel(window: 5, threshold: 3.0)),
    Denoise(Butterworth(order: 4, cutoff_hz: 80.0)),
    Stabilize(window_size: 10),
  ]
}

/// Pipeline optimized for vital signs extraction
pub fn default_vitals() -> List(Conditioner) {
  [
    PhaseCalibrate(Tsfr),
    Denoise(Hampel(window: 3, threshold: 2.5)),
    Denoise(Butterworth(order: 6, cutoff_hz: 2.5)),
    Stabilize(window_size: 20),
  ]
}
```

- [ ] **Step 4: Run tests**

Run: `gleam test`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add src/aether/condition/pipeline.gleam test/condition/pipeline_test.gleam
git commit -m "feat: add conditioner pipeline with functional composition and mode filtering"
```

---

## Phase 4: Fusion & Tracking

### Task 9: Temporal Sync & Fusion Engine

**Files:**
- Create: `src/aether/fusion/sync.gleam`
- Create: `src/aether/fusion/engine.gleam`
- Test: `test/fusion/sync_test.gleam`

- [ ] **Step 1: Write the failing test**

```gleam
// test/fusion/sync_test.gleam
import aether/fusion/sync.{align_signals}
import aether/signal.{Signal, WifiCsi, BleRssi}
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn align_within_tolerance_test() {
  let s1 = Signal(source: "wifi", kind: WifiCsi(56, 3, 20), timestamp: 1000, payload: <<>>, metadata: [])
  let s2 = Signal(source: "ble", kind: BleRssi(3), timestamp: 1005, payload: <<>>, metadata: [])

  let result = align_signals([s1, s2], tolerance_us: 10)
  result |> should.be_ok()
  let assert Ok(aligned) = result
  aligned |> list.length() |> should.equal(2)
}

pub fn reject_out_of_tolerance_test() {
  let s1 = Signal(source: "wifi", kind: WifiCsi(56, 3, 20), timestamp: 1000, payload: <<>>, metadata: [])
  let s2 = Signal(source: "ble", kind: BleRssi(3), timestamp: 2000, payload: <<>>, metadata: [])

  let result = align_signals([s1, s2], tolerance_us: 10)
  // Only s1 should survive — s2 is too far
  let assert Ok(aligned) = result
  aligned |> list.length() |> should.equal(1)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gleam test`
Expected: FAIL

- [ ] **Step 3: Write sync module**

```gleam
// src/aether/fusion/sync.gleam
import aether/core/error.{type AetherError, NoSensorsAvailable, SyncError}
import aether/signal.{type Signal}
import gleam/int
import gleam/list
import gleam/result

/// Align signals within a tolerance window.
/// Uses the median timestamp as reference, rejects outliers.
pub fn align_signals(
  signals: List(Signal),
  tolerance_us tolerance: Int,
) -> Result(List(Signal), AetherError) {
  case signals {
    [] -> Error(NoSensorsAvailable)
    [single] -> Ok([single])
    _ -> {
      let timestamps = list.map(signals, fn(s) { s.timestamp })
      let sorted = list.sort(timestamps, int.compare)
      let median = case list.length(sorted) / 2 {
        idx -> {
          let assert Ok(val) = list.at(sorted, idx)
          val
        }
      }

      let aligned =
        list.filter(signals, fn(s) {
          let drift = int.absolute_value(s.timestamp - median)
          drift <= tolerance
        })

      case aligned {
        [] -> Error(NoSensorsAvailable)
        _ -> Ok(aligned)
      }
    }
  }
}
```

- [ ] **Step 4: Run tests**

Run: `gleam test`
Expected: All PASS

- [ ] **Step 5: Write fusion engine actor**

```gleam
// src/aether/fusion/engine.gleam
import aether/core/error.{type AetherError}
import aether/fusion/sync
import aether/signal.{type Signal}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor

pub type FusionMsg {
  IngestSignal(Signal)
  Flush(reply: Subject(Result(List(Signal), AetherError)))
}

pub type FusionState {
  FusionState(
    buffer: Dict(String, Signal),
    window_us: Int,
    tolerance_us: Int,
  )
}

pub fn start(
  window_us window: Int,
  tolerance_us tolerance: Int,
) -> Result(Subject(FusionMsg), actor.StartError) {
  let state = FusionState(
    buffer: dict.new(),
    window_us: window,
    tolerance_us: tolerance,
  )
  actor.start(state, handle_message)
}

fn handle_message(
  msg: FusionMsg,
  state: FusionState,
) -> actor.Next(FusionMsg, FusionState) {
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
```

- [ ] **Step 6: Commit**

```bash
git add src/aether/fusion/sync.gleam src/aether/fusion/engine.gleam test/fusion/sync_test.gleam
git commit -m "feat: add temporal sync alignment and FusionEngine actor"
```

---

### Task 10: Perception Aggregator & Zone Tracking

**Files:**
- Create: `src/aether/track/zone.gleam`
- Create: `src/aether/track/aggregator.gleam`
- Create: `src/aether/track/event.gleam`
- Test: `test/track/zone_test.gleam`

- [ ] **Step 1: Write the failing test**

```gleam
// test/track/zone_test.gleam
import aether/core/types.{Vec3, Zone}
import aether/track/zone as zone_tracker
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn assign_point_to_zone_test() {
  let zones = [
    Zone("sala", "Sala", #(0.0, 0.0, 5.0, 4.0), 0.0, 3.0),
    Zone("quarto", "Quarto", #(5.0, 0.0, 9.0, 4.0), 0.0, 3.0),
  ]
  let point = Vec3(2.5, 2.0, 1.0)

  zone_tracker.assign(zones, point) |> should.equal(Ok("sala"))
}

pub fn point_outside_all_zones_test() {
  let zones = [
    Zone("sala", "Sala", #(0.0, 0.0, 5.0, 4.0), 0.0, 3.0),
  ]
  let point = Vec3(10.0, 10.0, 1.0)

  zone_tracker.assign(zones, point) |> should.be_error()
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gleam test`
Expected: FAIL

- [ ] **Step 3: Write zone tracker**

```gleam
// src/aether/track/zone.gleam
import aether/core/error.{type AetherError, ZoneNotFound}
import aether/core/types.{type Vec3, type Zone, type ZoneId, zone_contains}
import gleam/list

pub fn assign(zones: List(Zone), point: Vec3) -> Result(ZoneId, AetherError) {
  case list.find(zones, fn(z) { zone_contains(z, point) }) {
    Ok(zone) -> Ok(zone.id)
    Error(_) -> Error(ZoneNotFound("no zone contains point"))
  }
}
```

- [ ] **Step 4: Write event detection**

```gleam
// src/aether/track/event.gleam
import aether/core/types.{type PersonId, type ZoneId}
import aether/perception.{type Event, PersonEntered, PersonLeft}

/// Detect zone transition events by comparing previous and current zone
pub fn detect_zone_transition(
  person: PersonId,
  previous_zone: Result(ZoneId, Nil),
  current_zone: Result(ZoneId, Nil),
) -> List(Event) {
  case previous_zone, current_zone {
    Ok(prev), Ok(curr) if prev != curr -> [
      PersonLeft(person, prev),
      PersonEntered(person, curr),
    ]
    Error(_), Ok(curr) -> [PersonEntered(person, curr)]
    Ok(prev), Error(_) -> [PersonLeft(person, prev)]
    _, _ -> []
  }
}
```

- [ ] **Step 5: Run tests**

Run: `gleam test`
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add src/aether/track/zone.gleam src/aether/track/event.gleam test/track/zone_test.gleam
git commit -m "feat: add zone assignment and event detection for person tracking"
```

---

## Phase 5: API Layer

### Task 11: JSON Codec

**Files:**
- Create: `src/aether/serve/codec.gleam`
- Test: `test/serve/codec_test.gleam`

- [ ] **Step 1: Write the failing test**

```gleam
// test/serve/codec_test.gleam
import aether/core/types.{Vec3, ZoneOccupancy}
import aether/perception.{Coco17, Keypoint, Perception, Pose, Presence, Vitals}
import aether/serve/codec
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn encode_pose_test() {
  let pose = Pose(
    keypoints: [
      Keypoint(0, "nose", 2.3, 1.1, 0.9, 0.95, Some(Vec3(0.1, 0.0, 0.0))),
    ],
    skeleton: Coco17,
    confidence: 0.92,
  )

  let json_str = codec.encode_perception(pose) |> json.to_string()
  json_str |> should.not_equal("")
  // Should contain "pose" type
  string.contains(json_str, "\"type\":\"pose\"") |> should.be_true()
}

pub fn encode_vitals_test() {
  let vitals = Vitals(heart_bpm: 72.3, breath_bpm: 16.1, hrv: Some(45.2), confidence: 0.88)
  let json_str = codec.encode_perception(vitals) |> json.to_string()
  string.contains(json_str, "\"heart_bpm\"") |> should.be_true()
}
```

- [ ] **Step 2: Run test, verify fail**

Run: `gleam test`
Expected: FAIL

- [ ] **Step 3: Write codec**

```gleam
// src/aether/serve/codec.gleam
import aether/core/types.{type Vec3, Vec3}
import aether/perception.{
  type Event, type Keypoint, type Perception, Coco17, CustomTopology,
  FallDetected, FreeformPerception, Halpe26, Keypoint, Location,
  PersonEntered, PersonLeft, Pose, Presence, SensorOffline, SensorRecovered,
  ThroughWall, Vitals, VitalsAlert, Activity,
}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}

pub fn encode_perception(p: Perception) -> Json {
  case p {
    Pose(keypoints, skeleton, confidence) ->
      json.object([
        #("type", json.string("pose")),
        #("keypoints", json.array(keypoints, encode_keypoint)),
        #("skeleton", json.string(skeleton_name(skeleton))),
        #("confidence", json.float(confidence)),
      ])
    Vitals(heart, breath, hrv, confidence) ->
      json.object([
        #("type", json.string("vitals")),
        #("heart_bpm", json.float(heart)),
        #("breath_bpm", json.float(breath)),
        #("hrv", case hrv {
          Some(v) -> json.float(v)
          None -> json.null()
        }),
        #("confidence", json.float(confidence)),
      ])
    Presence(zones, total) ->
      json.object([
        #("type", json.string("presence")),
        #("total_occupants", json.int(total)),
      ])
    Location(pos, acc, _vel) ->
      json.object([
        #("type", json.string("location")),
        #("x", json.float(pos.x)),
        #("y", json.float(pos.y)),
        #("z", json.float(pos.z)),
        #("accuracy_m", json.float(acc)),
      ])
    Activity(label, confidence, duration) ->
      json.object([
        #("type", json.string("activity")),
        #("label", json.string(label)),
        #("confidence", json.float(confidence)),
        #("duration_ms", json.int(duration)),
      ])
    _ ->
      json.object([#("type", json.string("unknown"))])
  }
}

fn encode_keypoint(kp: Keypoint) -> Json {
  json.object([
    #("id", json.int(kp.id)),
    #("name", json.string(kp.name)),
    #("x", json.float(kp.x)),
    #("y", json.float(kp.y)),
    #("z", json.float(kp.z)),
    #("confidence", json.float(kp.confidence)),
  ])
}

fn skeleton_name(s) -> String {
  case s {
    Coco17 -> "coco17"
    Halpe26 -> "halpe26"
    CustomTopology(_, _) -> "custom"
  }
}

pub fn encode_event(e: Event) -> Json {
  case e {
    PersonEntered(person, zone) ->
      json.object([
        #("event", json.string("person_entered")),
        #("person", json.string(person)),
        #("zone", json.string(zone)),
      ])
    PersonLeft(person, zone) ->
      json.object([
        #("event", json.string("person_left")),
        #("person", json.string(person)),
        #("zone", json.string(zone)),
      ])
    FallDetected(person, confidence) ->
      json.object([
        #("event", json.string("fall_detected")),
        #("person", json.string(person)),
        #("confidence", json.float(confidence)),
      ])
    SensorOffline(sensor) ->
      json.object([
        #("event", json.string("sensor_offline")),
        #("sensor", json.string(sensor)),
      ])
    SensorRecovered(sensor) ->
      json.object([
        #("event", json.string("sensor_recovered")),
        #("sensor", json.string(sensor)),
      ])
    _ ->
      json.object([#("event", json.string("unknown"))])
  }
}
```

- [ ] **Step 4: Run tests**

Run: `gleam test`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add src/aether/serve/codec.gleam test/serve/codec_test.gleam
git commit -m "feat: add JSON codec for Perception and Event types"
```

---

### Task 12: WebSocket & REST API

**Files:**
- Create: `src/aether/serve/ws.gleam`
- Create: `src/aether/serve/api.gleam`

- [ ] **Step 1: Write WebSocket handler**

```gleam
// src/aether/serve/ws.gleam
import aether/perception.{type Perception}
import aether/serve/codec
import gleam/bytes_tree
import gleam/erlang/process.{type Subject}
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import mist.{type Connection, type ResponseData}

pub fn handle_ws_upgrade(
  req: request.Request(Connection),
) -> response.Response(ResponseData) {
  mist.websocket(
    request: req,
    on_init: fn(_conn) { #(Nil, None) },
    on_close: fn(_state) { Nil },
    handler: fn(state, _conn, msg) {
      case msg {
        mist.Text("ping") -> {
          let assert Ok(_) = mist.send_text_frame(_conn, "pong")
          actor.continue(state)
        }
        _ -> actor.continue(state)
      }
    },
  )
}

/// Broadcast perceptions to a WebSocket connection
pub fn broadcast_perceptions(
  conn: Connection,
  perceptions: List(Perception),
  timestamp: Int,
) -> Result(Nil, Nil) {
  let payload =
    json.object([
      #("timestamp", json.int(timestamp)),
      #("perceptions", json.array(perceptions, codec.encode_perception)),
    ])
    |> json.to_string()

  case mist.send_text_frame(conn, payload) {
    Ok(_) -> Ok(Nil)
    Error(_) -> Error(Nil)
  }
}
```

- [ ] **Step 2: Write REST API**

```gleam
// src/aether/serve/api.gleam
import gleam/bytes_tree
import gleam/http.{Get, Post}
import gleam/http/request
import gleam/http/response
import gleam/json
import mist.{type Connection, type ResponseData}

pub fn handle_request(
  req: request.Request(Connection),
) -> response.Response(ResponseData) {
  case req.method, request.path_segments(req) {
    Get, ["api", "health"] -> health_response()
    Get, ["api", "spaces"] -> spaces_response()
    _, _ -> not_found()
  }
}

fn health_response() -> response.Response(ResponseData) {
  let body =
    json.object([
      #("status", json.string("ok")),
      #("version", json.string("0.1.0")),
    ])
    |> json.to_string()
    |> bytes_tree.from_string()

  response.new(200)
  |> response.set_header("content-type", "application/json")
  |> response.set_body(mist.Bytes(body))
}

fn spaces_response() -> response.Response(ResponseData) {
  let body =
    json.object([#("spaces", json.array([], fn(_) { json.null() }))])
    |> json.to_string()
    |> bytes_tree.from_string()

  response.new(200)
  |> response.set_header("content-type", "application/json")
  |> response.set_body(mist.Bytes(body))
}

fn not_found() -> response.Response(ResponseData) {
  let body = bytes_tree.from_string("{\"error\":\"not found\"}")
  response.new(404)
  |> response.set_header("content-type", "application/json")
  |> response.set_body(mist.Bytes(body))
}
```

- [ ] **Step 3: Run `gleam build` to verify compilation**

Run: `gleam build`
Expected: Compiles with no errors

- [ ] **Step 4: Commit**

```bash
git add src/aether/serve/ws.gleam src/aether/serve/api.gleam
git commit -m "feat: add WebSocket handler and REST API endpoints"
```

---

## Phase 6: Space Orchestrator & Public API

### Task 13: Space Builder & Public API

**Files:**
- Create: `src/aether/space.gleam`
- Create: `src/aether/config.gleam`
- Create: `src/aether.gleam`
- Test: `test/aether_test.gleam`

- [ ] **Step 1: Write the failing integration test**

```gleam
// test/aether_test.gleam
import aether
import aether/config
import aether/core/types.{Zone}
import aether/sensor
import aether/signal.{WifiCsi}
import gleam/erlang/process
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn build_space_config_test() {
  let space =
    aether.space("test-house")
    |> aether.add_zone(Zone("sala", "Sala", #(0.0, 0.0, 5.0, 4.0), 0.0, 3.0))
    |> aether.add_zone(Zone("quarto", "Quarto", #(5.0, 0.0, 9.0, 4.0), 0.0, 3.0))

  space.id |> should.equal("test-house")
  space.zones |> list.length() |> should.equal(2)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gleam test`
Expected: FAIL

- [ ] **Step 3: Write Space builder**

```gleam
// src/aether/space.gleam
import aether/condition/pipeline.{type Conditioner}
import aether/core/types.{type Zone}
import aether/sensor.{type SensorConfig}

pub type SpaceConfig {
  SpaceConfig(
    id: String,
    zones: List(Zone),
    sensors: List(SensorConfig),
    conditioners: List(Conditioner),
    api_port: Int,
  )
}

pub fn new(id: String) -> SpaceConfig {
  SpaceConfig(
    id: id,
    zones: [],
    sensors: [],
    conditioners: pipeline.default_wifi(),
    api_port: 8080,
  )
}

pub fn add_zone(config: SpaceConfig, zone: Zone) -> SpaceConfig {
  SpaceConfig(..config, zones: [zone, ..config.zones])
}

pub fn add_sensor(config: SpaceConfig, sensor: SensorConfig) -> SpaceConfig {
  SpaceConfig(..config, sensors: [sensor, ..config.sensors])
}

pub fn with_conditioners(
  config: SpaceConfig,
  conditioners: List(Conditioner),
) -> SpaceConfig {
  SpaceConfig(..config, conditioners: conditioners)
}

pub fn with_api_port(config: SpaceConfig, port: Int) -> SpaceConfig {
  SpaceConfig(..config, api_port: port)
}
```

- [ ] **Step 4: Write public API**

```gleam
// src/aether.gleam
import aether/core/types.{type Zone}
import aether/space.{type SpaceConfig}

/// Create a new Space configuration
pub fn space(id: String) -> SpaceConfig {
  space.new(id)
}

/// Add a zone to the space
pub fn add_zone(config: SpaceConfig, zone: Zone) -> SpaceConfig {
  space.add_zone(config, zone)
}

/// Add a sensor to the space
pub fn add_sensor(config: SpaceConfig, sensor) -> SpaceConfig {
  space.add_sensor(config, sensor)
}
```

- [ ] **Step 5: Run tests**

Run: `gleam test`
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add src/aether.gleam src/aether/space.gleam test/aether_test.gleam
git commit -m "feat: add Space builder and public API — aether.space() |> add_zone() |> add_sensor()"
```

---

## Phase 7: NIF Brain Scaffold (CUDA)

### Task 14: aether_brain NIF Scaffold

**Files:**
- Create: `native/aether_brain/Cargo.toml`
- Create: `native/aether_brain/src/lib.rs`
- Create: `native/aether_brain/src/model.rs`
- Create: `src/aether_brain_nif.erl`
- Create: `src/aether/nif/brain.gleam`

- [ ] **Step 1: Create Cargo.toml**

```toml
[package]
name = "aether_brain"
version = "0.1.0"
edition = "2024"

[lib]
name = "aether_brain"
crate-type = ["cdylib"]

[dependencies]
rustler = { version = "0.36", features = ["nif_version_2_15"] }

[features]
default = ["cuda"]
cuda = []
```

- [ ] **Step 2: Write NIF lib.rs — placeholder inference**

```rust
// native/aether_brain/src/lib.rs
mod model;

use rustler::{Env, NifResult, ResourceArc};
use std::sync::Mutex;

#[derive(rustler::Resource)]
pub struct ModelRef {
    inner: Mutex<model::Model>,
}

#[rustler::nif]
fn load_model(path: String, device: String) -> NifResult<ResourceArc<ModelRef>> {
    let model = model::Model::new(&path, &device)
        .map_err(|e| rustler::Error::Term(Box::new(format!("load error: {}", e))))?;
    Ok(ResourceArc::new(ModelRef {
        inner: Mutex::new(model),
    }))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn foundation_infer(
    model: ResourceArc<ModelRef>,
    embedding: Vec<f64>,
    tasks: Vec<String>,
) -> NifResult<Vec<u8>> {
    let guard = model.inner.lock()
        .map_err(|_| rustler::Error::Term(Box::new("lock error")))?;
    let result = guard.infer(&embedding, &tasks);
    Ok(result)
}

rustler::init!("aether_brain_nif");
```

- [ ] **Step 3: Write model.rs — placeholder model**

```rust
// native/aether_brain/src/model.rs

pub struct Model {
    device: String,
    loaded: bool,
}

impl Model {
    pub fn new(path: &str, device: &str) -> Result<Self, String> {
        // Placeholder — real implementation loads from checkpoint
        Ok(Model {
            device: device.to_string(),
            loaded: true,
        })
    }

    pub fn infer(&self, embedding: &[f64], tasks: &[String]) -> Vec<u8> {
        // Placeholder — returns empty msgpack
        // Real implementation: run transformer encoder + decoder heads
        vec![]
    }
}
```

- [ ] **Step 4: Write Erlang NIF stubs**

```erlang
%% src/aether_brain_nif.erl
-module(aether_brain_nif).
-export([load_model/2, foundation_infer/3]).
-on_load(init/0).

init() ->
    PrivDir = case code:priv_dir(aether) of
        {error, bad_name} ->
            case file:get_cwd() of
                {ok, Cwd} -> filename:join(Cwd, "priv");
                _ -> "priv"
            end;
        Dir -> Dir
    end,
    NifPath = filename:join(PrivDir, "aether_brain"),
    case erlang:load_nif(NifPath, 0) of
        ok ->
            persistent_term:put(aether_brain_nif_loaded, true), ok;
        {error, {load_failed, _}} ->
            persistent_term:put(aether_brain_nif_loaded, false), ok;
        {error, {reload, _}} -> ok;
        {error, Reason} -> {error, Reason}
    end.

load_model(_Path, _Device) ->
    erlang:nif_error(nif_not_loaded).

foundation_infer(_Model, _Embedding, _Tasks) ->
    erlang:nif_error(nif_not_loaded).
```

- [ ] **Step 5: Write Gleam FFI bindings**

```gleam
// src/aether/nif/brain.gleam
import gleam/dynamic.{type Dynamic}

pub type ModelResource

@external(erlang, "aether_brain_nif", "load_model")
pub fn load_model(path: String, device: String) -> Dynamic

@external(erlang, "aether_brain_nif", "foundation_infer")
pub fn foundation_infer(
  model: Dynamic,
  embedding: List(Float),
  tasks: List(String),
) -> BitArray
```

- [ ] **Step 6: Build NIF**

Run: `cd native/aether_brain && cargo build --release`
Expected: Compiles (no CUDA yet — placeholder)

- [ ] **Step 7: Commit**

```bash
git add native/aether_brain/ src/aether_brain_nif.erl src/aether/nif/brain.gleam
git commit -m "feat: add aether_brain Rust NIF scaffold — placeholder model inference"
```

---

## Phase 8: ESP32 Firmware (Separate Build)

### Task 15: ESP32 CSI Streamer

**Files:**
- Create: `firmware/esp32-csi-node/main/csi_streamer.c`
- Create: `firmware/esp32-csi-node/CMakeLists.txt`
- Create: `firmware/esp32-csi-node/README.md`

- [ ] **Step 1: Write CMakeLists.txt**

```cmake
cmake_minimum_required(VERSION 3.16)
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(aether-csi-node)
```

- [ ] **Step 2: Write CSI streamer main**

```c
// firmware/esp32-csi-node/main/csi_streamer.c
// ESP32-S3 CSI capture → UDP stream to Æther hub
//
// Build: idf.py build
// Flash: idf.py -p /dev/ttyUSB0 flash monitor

#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_log.h"
#include "nvs_flash.h"
#include "lwip/sockets.h"

#define HUB_IP    "192.168.1.100"
#define HUB_PORT  5000
#define MAGIC     0xAE01
#define TAG       "aether-csi"

static int udp_sock = -1;
static struct sockaddr_in hub_addr;
static uint16_t seq = 0;

// CSI callback — called by ESP32 WiFi driver for each CSI frame
static void csi_callback(void *ctx, wifi_csi_info_t *info) {
    if (!info || !info->buf) return;

    // Build frame: magic(2) + seq(2) + csi_data(N)
    size_t frame_len = 4 + info->len;
    uint8_t *frame = malloc(frame_len);
    if (!frame) return;

    frame[0] = (MAGIC >> 8) & 0xFF;
    frame[1] = MAGIC & 0xFF;
    frame[2] = (seq >> 8) & 0xFF;
    frame[3] = seq & 0xFF;
    memcpy(frame + 4, info->buf, info->len);
    seq++;

    sendto(udp_sock, frame, frame_len, 0,
           (struct sockaddr *)&hub_addr, sizeof(hub_addr));
    free(frame);
}

void app_main(void) {
    // NVS init
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        nvs_flash_erase();
        nvs_flash_init();
    }

    // WiFi init (station mode)
    esp_netif_init();
    esp_event_loop_create_default();
    esp_netif_create_default_wifi_sta();
    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    esp_wifi_init(&cfg);

    // Configure WiFi
    wifi_config_t wifi_config = {
        .sta = {
            .ssid = CONFIG_WIFI_SSID,
            .password = CONFIG_WIFI_PASSWORD,
        },
    };
    esp_wifi_set_mode(WIFI_MODE_STA);
    esp_wifi_set_config(WIFI_IF_STA, &wifi_config);
    esp_wifi_start();
    esp_wifi_connect();

    // Wait for IP
    vTaskDelay(pdMS_TO_TICKS(5000));

    // UDP socket
    udp_sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    memset(&hub_addr, 0, sizeof(hub_addr));
    hub_addr.sin_family = AF_INET;
    hub_addr.sin_port = htons(HUB_PORT);
    inet_aton(HUB_IP, &hub_addr.sin_addr);

    // Enable CSI
    wifi_csi_config_t csi_config = {
        .lltf_en = true,
        .htltf_en = true,
        .stbc_htltf2_en = true,
        .ltf_merge_en = true,
        .channel_filter_en = false,
        .manu_scale = false,
    };
    esp_wifi_set_csi_config(&csi_config);
    esp_wifi_set_csi_rx_cb(csi_callback, NULL);
    esp_wifi_set_csi(true);

    ESP_LOGI(TAG, "Æther CSI node started — streaming to %s:%d", HUB_IP, HUB_PORT);

    // Keep alive
    while (1) {
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add firmware/
git commit -m "feat: add ESP32-S3 CSI streamer firmware — captures CSI and streams via UDP"
```

---

## Phase 9: Integration Wiring

### Task 16: Wire Everything Together

**Files:**
- Modify: `src/aether.gleam` — add `start()` function
- Create: `src/aether/config.gleam` — convenience helpers

- [ ] **Step 1: Write config helpers**

```gleam
// src/aether/config.gleam
import aether/condition/pipeline

pub type ModelConfig {
  ModelConfig(checkpoint: String, device: String, tasks: List(String))
}

pub type FusionConfig {
  CrossModalAttention(window_ms: Int)
  Concatenate
}

pub type ApiConfig {
  WebSocket(port: Int)
  NoApi
}

pub fn foundation_model(
  checkpoint checkpoint: String,
  device device: String,
) -> ModelConfig {
  ModelConfig(checkpoint: checkpoint, device: device, tasks: ["pose", "vitals", "presence"])
}

pub fn cross_modal_attention(window_ms window: Int) -> FusionConfig {
  CrossModalAttention(window)
}

pub fn websocket(port port: Int) -> ApiConfig {
  WebSocket(port)
}
```

- [ ] **Step 2: Expand public API with start()**

Add to `src/aether.gleam`:

```gleam
import aether/config.{type ApiConfig, type FusionConfig, type ModelConfig}
import aether/space.{type SpaceConfig}
import gleam/io

/// Start the Æther perception system
/// Returns a running hub that can be queried
pub fn start(config: SpaceConfig) -> Result(SpaceConfig, String) {
  // Phase 1: validate config
  case config.sensors {
    [] -> Error("No sensors configured")
    _ -> {
      io.println(
        "Æther started — "
        <> int.to_string(list.length(config.sensors))
        <> " sensors, "
        <> int.to_string(list.length(config.zones))
        <> " zones",
      )
      Ok(config)
    }
  }
}
```

- [ ] **Step 3: Run full test suite**

Run: `gleam test`
Expected: All tests PASS

- [ ] **Step 4: Format everything**

Run: `gleam format src test`
Expected: No changes (or auto-formats)

- [ ] **Step 5: Commit**

```bash
git add src/aether.gleam src/aether/config.gleam
git commit -m "feat: wire Space builder with start() and config helpers — Æther v0.1.0 foundation complete"
```

---

## Summary

| Phase | Tasks | What it delivers |
|-------|-------|-----------------|
| **1. Foundation** | 1-4 | Project scaffold, core types, errors, Signal/Perception types |
| **2. Sensor** | 5-6 | CSI parser, Sensor OTP actor with test injection |
| **3. Conditioning** | 7-8 | Rust NIF (Hampel, Butterworth, AveCSI), pipeline composition |
| **4. Fusion & Track** | 9-10 | Temporal sync, FusionEngine actor, zone tracking, events |
| **5. API** | 11-12 | JSON codec, WebSocket streaming, REST endpoints |
| **6. Orchestrator** | 13 | Space builder, public API (`aether.space() \|> ...`) |
| **7. Brain NIF** | 14 | CUDA NIF scaffold with placeholder model |
| **8. Firmware** | 15 | ESP32-S3 CSI capture → UDP streamer |
| **9. Integration** | 16 | Config helpers, start(), full wiring |

**Total: 16 tasks, ~80 steps, ~35 files**

After this plan completes, Æther v0.1.0 will have:
- Full type system with all domain types
- Working sensor actor that parses CSI frames
- Conditioner pipeline with Rust NIFs for signal processing
- Fusion engine with temporal alignment
- Zone tracking and event detection
- JSON API with WebSocket streaming
- ESP32 firmware ready to flash
- Foundation model NIF scaffold ready for viva_tensor integration

**Next phases (separate plans):**
- Phase 10: Foundation model training pipeline (SSL pretraining, CroSSL)
- Phase 11: Real inference with viva_tensor (encoder, GCN decoder, LSTM)
- Phase 12: Calibration flow (field model, few-shot adaptation)
- Phase 13: Multi-hub OTP distribution
