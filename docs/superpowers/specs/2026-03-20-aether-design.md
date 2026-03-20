# Æther — Ambient RF Perception System

**Date:** 2026-03-20
**Author:** Gabriel Maia + Claude Opus 4.6
**Status:** Approved

---

## 1. Vision

Æther is a Gleam/OTP library that transforms any RF signal (WiFi CSI, BLE, UWB, mmWave, FMCW radar, RFID) into structured human perception: pose estimation, vital signs, presence detection, activity recognition, localization, and through-wall sensing.

It functions as a "nervous system for physical spaces" — a foundation-model-powered ambient intelligence platform that sees without cameras.

**Key differentiators over RuView:**
- Gleam/OTP for fault-tolerant, distributed, real-time orchestration
- Foundation model architecture (not task-specific models) — one model does everything
- Sensor-agnostic: any RF source, not just WiFi
- Leverages existing `viva_tensor` (67K+ lines, CUDA NIFs) for ML compute
- API-first, headless — integrates with Home Assistant, VIVA, anything
- Self-supervised pretraining — works with minimal labeled data

## 2. Scope

**First domain:** Smart home / personal spaces. Gabriel is the first user.

**Hardware target:** ESP32 nodes capture CSI → RTX 4090 hub processes via `viva_tensor` + CUDA. Architecture supports degraded mode (CPU-only) and future distribution across multiple hubs.

**Protocol:** UDP raw for sensing data (minimum latency), no broker.

## 3. Research Foundation (2025-2026 SOTA)

### Foundation Models for RF Sensing
- **AM-FM** (Feb 2026, arXiv 2602.11200) — Foundation Model for Ambient Intelligence Through WiFi. Pre-trains on WiFi for presence, activity, physiology with a single model.
- **X-Fi** (2025) — Cross-modal transformer accepting any modality combination. 24.8% MPJPE reduction on MM-Fi via "X-fusion" mechanism.
- **RF-GPT** (Feb 2026, arXiv 2602.14833) — LLM that natively understands RF signals.
- **Babel** — Scalable pre-trained model with Expandable Modality Alignment.
- **WiCo / WiCo-MG** — Wireless channel foundation models with few-shot adaptation.

### Pose Estimation
- **WiFlow** (Feb 2026) — Lightweight axial attention + TCN for spatio-temporal decoupling.
- **VST-Pose** (2025) — Velocity-Integrated Spatio-Temporal Attention. Models keypoint velocity explicitly. Code: github.com/CarmenQing/VST-Pose
- **GraphPose-Fi** — Per-antenna encoder + GCN + self-attention decoder.
- **Geometry-Aware WiFi Sensing** (Jan 2026) — Models RF propagation physics (alpha_k * e^{-j2*pi*f_m*tau_k}). Cross-layout 3D pose.
- **GenHPE** — Generative regularization with counterfactual RF signals. Loss: L_pe + lambda * L_cr.

### Diffusion Models for RF
- **LatentCSI** — Maps CSI amplitude into Stable Diffusion latent space. Code: github.com/nishio-laboratory/latentcsi
- **Diffusion2** (ICLR 2026) — 3D environments to RF heatmaps via diffusion.
- **AIGC for RF Sensing** — Diffusion-based data augmentation for RF.

### Self-Supervised Learning
- **CroSSL** (Mar 2026) — Station-wise Masking Augmentation (SMA) for robustness to missing sensors.
- **Topology-Constrained Decoding** — Contrastive temporal learning + masked reconstruction + GCN decoder.

### Vital Signs
- **PulseFi** (2025) — 5-step pipeline for heart rate from ESP32 CSI + LSTM.
- **RoSe** (Feb 2026) — Robust vital sign sensing under signal degradation.

### Signal Processing
- **TSFR** — Time Smoothing and Frequency Rebuild for phase calibration. Validated on 5 datasets, >90% accuracy.
- **SISO Bistatic** — Phase compensation via energy-adjusted reference CSI.
- **Complex-Valued Neural Networks** — Preserves native CSI phase information.
- **DF-CNN** — Decision Fusion CNN, processes channels separately.

### Datasets
| Dataset | Contents | Scale |
|---------|----------|-------|
| MM-Fi | WiFi CSI + 3D pose labels | Standard benchmark |
| CSI-Bench | In-the-wild, 26 environments, OOD splits | 461+ hours |
| CSRD2025 | Synthetic for pretraining | ~25M frames, 200TB |
| OPERAnet | WiFi CSI + PWR + UWB + Kinect | 8h, 6 participants |
| XRF55 | WiFi + mmWave + RFID + Kinect | Multi-modal |

## 4. Domain Model

### 4.0 Core Types (defined in `core/types.gleam`)

```gleam
/// Opaque reference to a loaded NIF model on GPU/CPU
pub opaque type NifModelRef {
  NifModelRef(ref: Dynamic)
}

/// Identifiers — newtypes for type safety
pub type SensorId = String
pub type PersonId = String
pub type ZoneId = String

/// 3D vector
pub type Vec3 {
  Vec3(x: Float, y: Float, z: Float)
}

/// RFID frequency bands
pub type RfidBand {
  Lf125Khz
  Hf13Mhz
  Uhf900Mhz
  Shf2400Mhz
}

/// Zone definition
pub type Zone {
  Zone(
    id: ZoneId,
    name: String,
    bounds: #(Float, Float, Float, Float),  // x_min, y_min, x_max, y_max
    floor: Float,   // z_min
    ceiling: Float, // z_max
  )
}

/// Zone occupancy snapshot
pub type ZoneOccupancy {
  ZoneOccupancy(zone: ZoneId, count: Int, person_ids: List(PersonId))
}

/// Through-wall detection target
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

/// Sensor health monitoring config
pub type HealthConfig {
  HealthConfig(
    timeout_ms: Int,            // sensor considered dead after this
    max_packet_loss_pct: Float, // alert threshold
    drift_tolerance_ms: Float,  // clock drift alert
  )
}

/// Doppler extraction config
pub type DopplerConfig {
  DopplerConfig(
    fft_size: Int,
    window_type: String,  // "hann", "hamming", "blackman"
    overlap: Float,
  )
}

/// Subcarrier selection method
pub type SelectionMethod {
  RemoveEdge(n: Int)           // remove n edge subcarriers
  VarianceThreshold(min: Float) // keep high-variance only
  ManualSelect(indices: List(Int))
}

/// Persistent RF field model for environment background
pub type FieldModel {
  FieldModel(
    background: BitArray,
    zone_calibrations: Dict(String, BitArray),
    last_updated: Int,
  )
}

/// Digital twin placeholder (future)
pub type DigitalTwin {
  DigitalTwin(geometry: Dynamic, rf_map: Dynamic)
}

/// Encoder configs
pub type PerAntennaConfig {
  PerAntennaConfig(conv_channels: List(Int), attention_heads: Int, dropout: Float)
}

pub type SpatioTemporalConfig {
  SpatioTemporalConfig(tcn_channels: List(Int), axial_attention_heads: Int, sequence_length: Int)
}

pub type VelocityConfig {
  VelocityConfig(velocity_branch: Bool, dst_blocks: Int, d_model: Int)
}

pub type ComplexConfig {
  ComplexConfig(preserve_phase: Bool, dual_branch: Bool, hidden_dim: Int)
}

/// Decoder configs
pub type GenConfig {
  GenConfig(lambda_cr: Float, gen_backbone: String)
}

pub type GeometryConfig {
  GeometryConfig(max_paths: Int, fresnel_zones: Bool)
}
```

### 4.1 Signal — Raw RF frame from any sensor

**Note:** `Signal.timestamp` uses BEAM monotonic time in microseconds (`erlang.system_time(Microsecond)`) adjusted by gPTP offset when available. Nanosecond precision is achievable via `Int` (Erlang arbitrary precision).

```gleam
pub type Signal {
  Signal(
    source: SensorId,
    kind: SignalKind,
    timestamp: Int,
    payload: BitArray,
    metadata: Dict(String, String),
  )
}

pub type SignalKind {
  WifiCsi(subcarriers: Int, antennas: Int, bandwidth: Int)
  BleRssi(channels: Int)
  Uwb(bandwidth_mhz: Int)
  MmWave(freq_ghz: Float, chirps: Int)
  FmcwRadar(range_bins: Int, doppler_bins: Int)
  Rfid(frequency: RfidBand)
  UserDefinedSignal(name: String, schema: Dict(String, String))
}
```

### 4.2 Sensor — OTP actor per physical device

```gleam
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

pub type SyncProtocol {
  Gptp
  Ntp
  FreeRunning
}

pub type Transport {
  Udp(host: String, port: Int)
  Serial(path: String, baud: Int)
  Tcp(host: String, port: Int)
  CallbackTransport(handler: fn() -> Nil)
}
```

### 4.3 Conditioner — Signal preprocessing pipeline (TSFR + AveCSI validated)

```gleam
pub type Conditioner {
  PhaseCalibrate(method: PhaseMethod)
  Denoise(method: DenoiseMethod)
  Stabilize(window_size: Int)
  DopplerExtract(config: DopplerConfig)
  Augment(method: AugmentMethod)       // training-only — skipped in inference mode
  SubcarrierSelect(method: SelectionMethod)
}

/// Pipeline mode determines which conditioners run
pub type PipelineMode {
  Inference   // skip Augment stages
  Training    // run all stages including Augment
}

/// The conditioner pipeline is a single OTP actor that folds over
/// the conditioner list with functional composition — no inter-actor hops.
/// Backpressure: maintains a bounded ring buffer of N latest frames.
/// When buffer is full, oldest frame is dropped (lossy but bounded).
pub type PipelineConfig {
  PipelineConfig(
    stages: List(Conditioner),
    mode: PipelineMode,
    buffer_size: Int,         // ring buffer capacity (default: 10)
    drop_stale_after_ms: Int, // drop frames older than this (default: 50)
  )
}

pub type PhaseMethod {
  Tsfr
  LinearFit
  SisoRecon
}

pub type DenoiseMethod {
  Hampel(window: Int, threshold: Float)
  Butterworth(order: Int, cutoff_hz: Float)
  SavitzkyGolay(window: Int, poly_order: Int)
}

pub type AugmentMethod {
  GaussianNoise(std: Float)
  Scaling(range: #(Float, Float))
  DiffusionSynthetic
  StationMasking(prob: Float)
}
```

### 4.4 Encoder — Feature extraction (per SOTA architectures)

```gleam
pub type Encoder {
  PerAntenna(config: PerAntennaConfig)
  SpatioTemporal(config: SpatioTemporalConfig)
  CrossModal(config: CrossModalConfig)
  VelocityAware(config: VelocityConfig)
  ComplexValued(config: ComplexConfig)
}

pub type CrossModalConfig {
  CrossModalConfig(
    d_model: Int,
    n_heads: Int,
    n_layers: Int,
    x_fusion: Bool,
    modality_embeddings: Bool,
  )
}
```

### 4.5 Decoder — Topology-aware output heads

```gleam
pub type Decoder {
  GraphPose(config: GraphPoseConfig)
  GenerativeRegularized(config: GenConfig)
  GeometryAware(config: GeometryConfig)
  DirectRegression(hidden_dims: List(Int))
}

pub type GraphPoseConfig {
  GraphPoseConfig(
    gcn_layers: Int,
    attention_heads: Int,
    skeleton_graph: SkeletonGraph,
    task_prompts: Bool,
  )
}

pub type SkeletonGraph {
  Coco17
  Halpe26
  CustomTopology(edges: List(#(Int, Int)), names: List(String))
}
```

### 4.6 Perception — Processed output

```gleam
pub type Perception {
  Pose(keypoints: List(Keypoint), skeleton: SkeletonGraph, confidence: Float)
  Vitals(heart_bpm: Float, breath_bpm: Float, hrv: Option(Float), confidence: Float)
  Presence(zones: List(ZoneOccupancy), total_occupants: Int)
  Location(position: Vec3, accuracy_m: Float, velocity: Option(Vec3))
  Activity(label: String, confidence: Float, duration_ms: Int)
  ThroughWall(targets: List(ThroughWallTarget))
  FreeformPerception(kind: String, data: Dynamic)
}

pub type Keypoint {
  Keypoint(
    id: Int, name: String,
    x: Float, y: Float, z: Float,
    confidence: Float,
    velocity: Option(Vec3),
  )
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

### 4.7 FoundationModel — The brain (AM-FM/X-Fi inspired)

```gleam
pub type FoundationModel {
  FoundationModel(
    encoder: Encoder,
    decoders: Dict(TaskType, Decoder),
    pretrain: PretrainStrategy,
    nif_ref: NifModelRef,
  )
}

pub type TaskType {
  PoseEstimation
  VitalSigns
  PresenceDetection
  ActivityRecognition
  Localization
  ThroughWallSensing
}

pub type PretrainStrategy {
  SelfSupervised(config: SslConfig)
  CrossModalDistill(teacher_modality: SignalKind)
  FrozenBackbone(checkpoint: String)
}

pub type SslConfig {
  SslConfig(
    masked_reconstruction: Bool,
    contrastive_temporal: Bool,
    station_masking_prob: Float,
    uniformity_regularization: Bool,
  )
}
```

### 4.8 Space — The monitored environment

```gleam
pub type Space {
  Space(
    id: String,
    name: String,
    sensors: List(SensorId),
    zones: List(Zone),
    conditioners: List(Conditioner),
    model: FoundationModel,
    field_model: Option(FieldModel),
    digital_twin: Option(DigitalTwin),
  )
}
```

### 4.9 OTP Supervision Tree

```
Space (Supervisor)
+-- SensorSupervisor
|   +-- Sensor("esp32-sala") — WiFi CSI actor
|   +-- Sensor("esp32-quarto") — WiFi CSI actor
|   +-- Sensor("radar-entrada") — mmWave actor
|   +-- Sensor("ble-mesh") — BLE RSSI actor
+-- ConditionerPipeline (single actor, functional composition over List(Conditioner))
|   (runs TSFR -> Hampel -> Butterworth -> AveCSI sequentially in one actor
|    to avoid inter-actor message passing overhead; training-only stages
|    like CroSSL SMA are skipped via pipeline mode flag)
+-- FusionEngine — cross-modal attention (X-Fi style)
|   +-- SyncCoordinator (gPTP alignment)
+-- InferenceEngine — foundation model via NIF
|   +-- PoseDecoder (GraphPose-Fi GCN)
|   +-- VitalsDecoder (PulseFi LSTM)
|   +-- PresenceDecoder
|   +-- ActivityDecoder
+-- PerceptionAggregator
|   +-- PersonTracker (Kalman + Hungarian assignment)
|   +-- ZoneManager
+-- FieldModelManager — learns RF background
+-- ApiServer — WebSocket/REST (Mist/Wisp)
```

## 5. Data Flow

### 5.1 Real-Time Inference

```
Sensor devices --UDP--> SensorActor --> ConditionerPipeline --> FusionEngine --> InferenceEngine --> PerceptionAggregator --> API
     ~1ms           parse+validate      ~200us                  ~50us           ~500us (NIF/GPU)     ~100us                  push
```

**Target latency: < 15ms end-to-end** (excluding network). Breakdown:
- Sensor parse + validate: ~1ms
- Conditioner pipeline: ~200us (single actor, functional composition)
- BEAM message passing overhead (5 stages): ~100us
- Fusion (NIF): ~200us
- Inference (NIF/GPU, dirty scheduler + kernel launch): ~5-8ms
- Aggregation: ~200us
- API push: ~100us

This achieves **60+ FPS** perception, sufficient for real-time pose tracking and vital sign monitoring. The 5ms stretch goal may be achievable with CUDA graphs and smaller models.

### 5.2 Training / Fine-Tuning

```
Datasets (MM-Fi, CSI-Bench, CSRD2025)
    |
    v
DataLoader (Gleam actor, streams batches)
    |
    +-- Augmenter (CroSSL SMA + Gaussian + DiffusionSynthetic)
    |
    v
Training Loop (NIF/CUDA via viva_tensor)
    |
    +-- Phase 1: Self-supervised pretrain (masked recon + contrastive)
    +-- Phase 2: Foundation model encoder (freeze after convergence)
    +-- Phase 3: Fine-tune decoder heads per task
    |
    v
Checkpoint (save to disk, versioned: aether-v{N}-{task}-{date}.pt)
```

**Training/Inference coexistence:**
- Training runs as a **separate OTP application** (`aether_trainer`) under its own supervision tree
- GPU resources: inference uses CUDA stream 0, training uses CUDA stream 1 — concurrent but isolated
- To prevent inference latency spikes during training, training batches yield GPU control via `cudaStreamSynchronize` between steps
- If GPU memory is insufficient for both, training is paused and inference takes priority

**Model hot-swapping:**
- New checkpoint is saved to disk with incremented version
- `InferenceEngine` receives `SwapModel(path)` message
- Loads new model into separate GPU memory, atomically swaps the `NifModelRef`
- Old model is freed after all in-flight inferences complete
- Zero-downtime model updates

**Checkpoint format:**
- Versioned: `aether-v{version}-{task}-{YYYY-MM-DD}.pt`
- Contains: encoder weights, decoder weights per task, optimizer state, training metadata (epochs, loss history, dataset info)
- Compatible with `viva_tensor` serialization format

### 5.3 Calibration (first boot or new environment)

1. `Space.new("minha_casa")` — create space
2. Sensors start capturing 60s of empty-room CSI
3. FieldModelManager computes background RF signature
4. User walks through space — system collects reference poses
5. Fine-tune decoder with few-shot environment data
6. Ready — inference mode activated

## 6. NIF Architecture

### 6.1 aether_signal (Rust, CPU)

Signal processing that needs performance but not GPU:

- `tsfr_calibrate` — Phase calibration (linear regression + Savitzky-Golay)
- `hampel_filter` — Outlier detection + replacement
- `butterworth_bandpass` — IIR filter design + apply
- `avecsi_stabilize` — Sliding window average
- `cir_reconstruct` — IFFT + CIR reconstruction (Doppler)
- `spotfi_aoa` — Angle of Arrival estimation

Build: `cd native/aether_signal && cargo build --release`
Copy: `cp target/release/libaether_signal.so ../../build/dev/erlang/aether/priv/aether_signal.so`

### 6.2 aether_brain (Rust + CUDA)

Foundation model inference and training. **Depends on `viva_tensor`.**

- `load_model` — Load checkpoint to GPU
- `foundation_infer` — Multi-task inference (dirty scheduler)
- `cross_modal_fuse` — Cross-modal attention fusion
- `train_step` — Forward + backward + optimizer step
- `ssl_pretrain_step` — CroSSL self-supervised step

Build: `cd native/aether_brain && cargo build --release`
Copy: `cp target/release/libaether_brain.so ../../build/dev/erlang/aether/priv/aether_brain.so`

**Scheduler policy:**
- `aether_signal` NIFs run on **normal BEAM schedulers** — each operation completes in <1ms on a single CSI frame, well within the safe threshold. No dirty scheduling needed.
- `aether_brain` NIFs run on **dirty CPU schedulers** (`schedule = "DirtyCpu"`) — GPU inference/training can take 1-10ms, which would block normal schedulers.

### 6.3 Erlang NIF Stubs

Every registered NIF must have a stub in `src/aether_signal_nif.erl` and `src/aether_brain_nif.erl` with `erlang:nif_error(not_loaded)` fallbacks.

## 7. API & Integration

### 7.1 Gleam Library API

```gleam
let assert Ok(hub) =
  space.new("minha_casa")
  |> space.add_zone(zone("sala", bounds: #(0.0, 0.0, 5.0, 4.0)))
  |> space.add_sensor(sensor.wifi_csi("192.168.1.50", port: 5000, ...))
  |> space.add_sensor(sensor.mmwave("192.168.1.60", port: 6000, ...))
  |> space.with_model(config.foundation_model(checkpoint: "models/aether-v1.pt", device: "cuda:0", ...))
  |> space.with_conditioner(config.default_wifi_pipeline())
  |> space.with_fusion(config.cross_modal_attention(window_ms: 50))
  |> space.with_api(config.websocket(port: 8080))
  |> aether.start()

aether.on_event(hub, fn(event) { ... })
let perceptions = aether.perceive(hub, space: "sala")
```

### 7.2 WebSocket API

```
ws://host:8080/stream    — continuous perception push (JSON)
ws://host:8080/events    — event push (fall, enter, leave, alert)
GET /api/spaces           — list spaces
GET /api/spaces/:id/perceptions
POST /api/spaces/:id/calibrate
GET /api/health
```

### 7.3 Integration Points

- **Home Assistant:** Custom component consuming WebSocket
- **VIVA:** Direct Gleam import — `import aether` — VIVA gains physical senses
- **Any system:** REST/WebSocket API

## 8. Project Structure

```
aether/
+-- gleam.toml
+-- Makefile
+-- src/
|   +-- aether.gleam                     # Public API
|   +-- aether/
|   |   +-- space.gleam                  # Space management
|   |   +-- sensor.gleam                 # Sensor configs & actors
|   |   +-- signal.gleam                 # Signal types
|   |   +-- perception.gleam             # Perception types & events
|   |   +-- config.gleam                 # Builder patterns
|   |   +-- condition/                   # Signal conditioning
|   |   |   +-- pipeline.gleam
|   |   |   +-- phase.gleam
|   |   |   +-- denoise.gleam
|   |   |   +-- stabilize.gleam
|   |   |   +-- augment.gleam
|   |   +-- fusion/                      # Multi-modal fusion
|   |   |   +-- engine.gleam
|   |   |   +-- attention.gleam
|   |   |   +-- kalman.gleam
|   |   |   +-- sync.gleam
|   |   +-- model/                       # Foundation model
|   |   |   +-- foundation.gleam
|   |   |   +-- encoder.gleam
|   |   |   +-- decoder.gleam
|   |   |   +-- pretrain.gleam
|   |   |   +-- checkpoint.gleam
|   |   +-- track/                       # Multi-person tracking
|   |   |   +-- aggregator.gleam
|   |   |   +-- person.gleam
|   |   |   +-- zone.gleam
|   |   |   +-- event.gleam
|   |   +-- serve/                       # API layer
|   |   |   +-- api.gleam
|   |   |   +-- ws.gleam
|   |   |   +-- codec.gleam
|   |   +-- nif/                         # NIF FFI wrappers
|   |   |   +-- signal.gleam
|   |   |   +-- brain.gleam
|   |   +-- core/                        # Shared types
|   |       +-- error.gleam
|   |       +-- types.gleam
|   |       +-- math.gleam
|   +-- aether_signal_nif.erl
|   +-- aether_brain_nif.erl
+-- native/
|   +-- aether_signal/                   # Rust NIF (CPU)
|   +-- aether_brain/                    # Rust NIF (CUDA)
+-- test/
+-- models/
+-- firmware/
|   +-- esp32-csi-node/
+-- docs/
```

## 9. Dependencies

```toml
[dependencies]
gleam_stdlib = ">= 0.44.0 and < 2.0.0"
gleam_erlang = ">= 0.34.0 and < 1.0.0"
gleam_otp = ">= 0.14.0 and < 1.0.0"
gleam_json = ">= 3.0.0 and < 4.0.0"
gleam_http = ">= 3.0.0 and < 4.0.0"
mist = ">= 4.0.0 and < 5.0.0"
wisp = ">= 1.0.0 and < 2.0.0"
gleam_crypto = ">= 1.0.0 and < 2.0.0"
viva_telemetry = ">= 1.0.0 and < 2.0.0"

[dev-dependencies]
gleeunit = ">= 1.0.0 and < 2.0.0"
gleamy_bench = ">= 0.6.0 and < 1.0.0"
```

**Rust-level dependency:** `aether_brain` Cargo.toml depends on `viva_tensor`'s native crate for CUDA tensor ops. This is a Cargo path/git dependency, not a Gleam dependency — `viva_tensor` types are used at the NIF boundary, not in Gleam application code.

## 10. Error Handling & Resilience

### Centralized Error Type

```gleam
pub type AetherError {
  SensorOffline(id: SensorId, reason: String)
  SensorTimeout(id: SensorId, last_seen_ms: Int)
  ParseError(sensor: SensorId, reason: String)
  CalibrationFailed(method: String, reason: String)
  InsufficientData(expected: Int, got: Int)
  SyncError(drift_ms: Float, tolerance_ms: Float)
  NoSensorsAvailable
  ModelNotLoaded
  InferenceError(reason: String)
  CheckpointNotFound(path: String)
  CudaError(code: Int, message: String)
  ZoneNotFound(id: String)
  SpaceNotConfigured(missing: String)
}
```

### OTP Resilience

- **Sensor dies** -> supervisor restarts actor, CroSSL SMA ensures model works without it
- **NIF crashes** -> dirty scheduler isolates crash, supervisor restarts inference engine
- **GPU OOM** -> NIF returns error, Gleam falls back to CPU inference
- **Network partition** -> each hub continues locally, reconciles on reconnect

## 11. Telemetry & Observability

Æther integrates with `viva_telemetry` for metrics and tracing:

**Per-actor metrics:**
- `aether.sensor.{id}.frames_received` — counter
- `aether.sensor.{id}.packet_loss_pct` — gauge
- `aether.sensor.{id}.clock_drift_us` — gauge
- `aether.conditioner.latency_us` — histogram
- `aether.fusion.latency_us` — histogram
- `aether.inference.latency_us` — histogram
- `aether.inference.gpu_utilization_pct` — gauge
- `aether.aggregator.persons_tracked` — gauge
- `aether.aggregator.events_emitted` — counter
- `aether.pipeline.buffer_drops` — counter (backpressure indicator)

**Per-NIF metrics (reported from Rust):**
- `aether.nif.signal.{op}.latency_us` — per signal processing op
- `aether.nif.brain.inference_latency_us`
- `aether.nif.brain.gpu_memory_used_mb`

**Health endpoint:** `GET /api/health` returns all metrics as JSON.

## 12a. Deployment

### Single Hub (default)

```bash
# Build
gleam build
cd native/aether_signal && cargo build --release
cd native/aether_brain && cargo build --release
# Copy NIFs
cp native/aether_signal/target/release/libaether_signal.so build/dev/erlang/aether/priv/aether_signal.so
cp native/aether_brain/target/release/libaether_brain.so build/dev/erlang/aether/priv/aether_brain.so
# Run
gleam run
```

### Distributed (future)

OTP distribution via `gleam_erlang` — connect multiple BEAM nodes, actors migrate across hubs automatically.

## 13. Success Criteria

- [ ] Single WiFi CSI sensor producing Signals at 100Hz
- [ ] Conditioner pipeline processing in < 500us (single actor)
- [ ] Foundation model inference in < 8ms on RTX 4090
- [ ] End-to-end latency < 15ms (60+ FPS)
- [ ] 17-keypoint pose estimation with MPJPE < 50mm (on MM-Fi)
- [ ] Heart rate estimation within +/- 3 BPM
- [ ] Presence detection accuracy > 98%
- [ ] Graceful degradation when sensors go offline (CroSSL SMA)
- [ ] WebSocket API streaming at 60+ FPS
- [ ] Running in Gabriel's house with 3+ ESP32 nodes
- [ ] Pipeline backpressure: zero OOM under sustained load
- [ ] Model hot-swap without inference interruption
- [ ] Telemetry dashboard showing all actor/NIF metrics

**Stretch goals:**
- [ ] End-to-end latency < 5ms with CUDA graphs
- [ ] Through-wall pose estimation at 2+ walls
- [ ] Multi-hub OTP distribution across 2+ BEAM nodes
- [ ] 5+ simultaneous person tracking
