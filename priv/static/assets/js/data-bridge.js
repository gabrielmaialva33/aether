// Aether Observatory — WebSocket Data Bridge
// Manages WS connection, ring buffers, keypoint interpolation

import { NODES, VOLUME } from './config.js';

export class DataBridge {
  constructor() {
    this.ws = null;
    this.connected = false;
    this.frameCount = 0;
    this.fps = 0;
    this._fpsFrames = 0;
    this._lastFpsTime = performance.now();

    // Ring buffers
    this.perceptions = [];
    this.csiHistory = [];       // last 30 CSI frames
    this.rssiHistory = [];      // last 60 RSSI values
    this.csiAmplitudes = null;  // latest raw CSI amplitudes
    this.csiSubcarriers = 32;

    // Keypoint interpolation (ring buffer of 5 poses)
    this.poseBuffer = [];
    this.currentPose = null;    // interpolated pose for rendering
    this.prevPose = null;
    this.poseAlpha = 0;
    this.lastPoseTime = 0;
    this.poseInterval = 200;    // expected ms between WS frames

    // Latest data
    this.vitals = { heart_bpm: 0, breath_bpm: 0, hrv: 0, confidence: 0 };
    this.presence = { total: 0 };
    this.activity = { label: '--', confidence: 0 };
    this.location = { x: 0, y: 0, z: 0, accuracy: 0 };
    this.latency = { condition: 0, fusion: 0, brain: 0, total: 0 };

    // Simulated metrics
    this._simInterval = null;
    this._csiSimInterval = null;

    // Listeners
    this._listeners = {};
  }

  on(event, fn) {
    (this._listeners[event] ||= []).push(fn);
  }

  _emit(event, data) {
    (this._listeners[event] || []).forEach(fn => fn(data));
  }

  connect() {
    const h = location.hostname || 'localhost';
    const p = location.port || '9090';
    this.ws = new WebSocket(`ws://${h}:${p}/ws/stream`);

    this.ws.onopen = () => {
      this.connected = true;
      this._emit('status', { connected: true });
    };

    this.ws.onmessage = (e) => {
      const d = JSON.parse(e.data);
      if (d.perceptions) this._processPerceptions(d.perceptions);
      if (d.csi) this._processCSI(d.csi);
    };

    this.ws.onclose = () => {
      this.connected = false;
      this._emit('status', { connected: false });
      setTimeout(() => this.connect(), 2000);
    };

    this.ws.onerror = () => this.ws.close();

    // Start simulated metrics (RSSI, latency, CSI)
    this._startSimulation();

    // FPS counter
    setInterval(() => {
      this.fps = this._fpsFrames;
      this._fpsFrames = 0;
    }, 1000);
  }

  _processPerceptions(perceptions) {
    this.perceptions = perceptions;
    this.frameCount++;
    this._fpsFrames++;

    for (const p of perceptions) {
      switch (p.type) {
        case 'pose':
          this._pushPose(p.keypoints || []);
          break;
        case 'vitals':
          this.vitals = {
            heart_bpm: p.heart_bpm || 0,
            breath_bpm: p.breath_bpm || 0,
            hrv: p.hrv || 0,
            confidence: p.confidence || 0,
          };
          break;
        case 'presence':
          this.presence = { total: p.total_occupants || 0 };
          break;
        case 'activity':
          this.activity = {
            label: p.label || '--',
            confidence: p.confidence || 0,
          };
          break;
        case 'location':
          this.location = {
            x: p.x || 0, y: p.y || 0, z: p.z || 0,
            accuracy: p.accuracy_m || 0,
          };
          break;
      }
    }
    this._emit('data', perceptions);
  }

  _processCSI(csi) {
    this.csiAmplitudes = csi.amplitudes;
    this.csiSubcarriers = csi.subcarriers || 32;
    this.csiHistory.push([...csi.amplitudes]);
    if (this.csiHistory.length > 30) this.csiHistory.shift();
  }

  // ── Keypoint Interpolation ──────────────────────────────────────────

  _pushPose(keypoints) {
    if (!keypoints.length) return;
    this.prevPose = this.currentPose;
    this.currentPose = keypoints;
    this.poseBuffer.push(keypoints);
    if (this.poseBuffer.length > 5) this.poseBuffer.shift();
    this.lastPoseTime = performance.now();
    this.poseAlpha = 0;
  }

  // Call per render frame: returns interpolated keypoints for smooth 60fps
  getInterpolatedPose(now) {
    if (!this.currentPose) return null;
    if (!this.prevPose) return this.currentPose;

    const elapsed = now - this.lastPoseTime;
    const alpha = Math.min(1, elapsed / this.poseInterval);

    return this.currentPose.map((kp, i) => {
      const prev = this.prevPose[i];
      if (!prev) return kp;
      return {
        ...kp,
        x: prev.x + (kp.x - prev.x) * alpha,
        y: prev.y + (kp.y - prev.y) * alpha,
        z: prev.z + (kp.z - prev.z) * alpha,
        confidence: prev.confidence + (kp.confidence - prev.confidence) * alpha,
      };
    });
  }

  // ── CSI → Volume Interpolation ──────────────────────────────────────

  // RBF interpolation: CSI amplitudes from node positions → 3D volume
  // Writes into pre-allocated output buffer to avoid GC pressure
  interpolateToVolume(roomWidth, roomDepth, roomHeight, output) {
    const res = VOLUME.resolution;
    const amps = this.csiAmplitudes;
    if (!amps || amps.length === 0) { output.fill(0); return; }

    const nNodes = NODES.length;
    const ampsPerNode = Math.floor(amps.length / nNodes) || this.csiSubcarriers;

    // Pre-compute per-node average amplitude
    const nodeAvg = new Float32Array(nNodes);
    for (let n = 0; n < nNodes; n++) {
      let sum = 0;
      const start = n * ampsPerNode;
      const end = Math.min(start + ampsPerNode, amps.length);
      for (let s = start; s < end; s++) sum += amps[s];
      nodeAvg[n] = sum / ((end - start) || 1);
    }

    // Pre-compute node positions
    const nx = new Float32Array(nNodes);
    const ny = new Float32Array(nNodes);
    const nz = new Float32Array(nNodes);
    for (let n = 0; n < nNodes; n++) {
      nx[n] = NODES[n].pos[0];
      ny[n] = NODES[n].pos[1];
      nz[n] = NODES[n].pos[2];
    }

    const resM1 = res - 1;
    const scaleX = roomWidth / resM1;
    const scaleY = roomHeight / resM1;
    const scaleZ = roomDepth / resM1;

    let idx = 0;
    for (let iz = 0; iz < res; iz++) {
      const wz = iz * scaleZ;
      for (let iy = 0; iy < res; iy++) {
        const wy = iy * scaleY;
        for (let ix = 0; ix < res; ix++) {
          const wx = ix * scaleX;

          let value = 0, totalWeight = 0;
          for (let n = 0; n < nNodes; n++) {
            const dx = wx - nx[n], dy = wy - ny[n], dz = wz - nz[n];
            // falloff=2 → dist^2, skip sqrt entirely
            const dist2 = dx * dx + dy * dy + dz * dz;
            const weight = 1.0 / (1.0 + dist2);
            value += nodeAvg[n] * weight;
            totalWeight += weight;
          }

          output[idx++] = value / totalWeight;
        }
      }
    }
  }

  // ── Simulation (matches original index.html behavior) ───────────────

  _startSimulation() {
    this._simInterval = setInterval(() => {
      const cond = (0.1 + Math.random() * 0.15);
      const fuse = (0.02 + Math.random() * 0.03);
      const brain = (0.3 + Math.random() * 0.4);
      this.latency = {
        condition: cond,
        fusion: fuse,
        brain: brain,
        total: cond + fuse + brain,
      };

      const rssi = -44 + Math.random() * 8 - 4;
      this.rssiHistory.push(rssi);
      if (this.rssiHistory.length > 60) this.rssiHistory.shift();

      this._emit('metrics', this.latency);
    }, 500);

    this._csiSimInterval = setInterval(() => {
      const t = Date.now() / 1000;
      const frame = [];
      for (let i = 0; i < 32; i++) {
        frame.push(0.3 + 0.25 * Math.sin(i / 5 + t) + 0.1 * Math.cos(i / 3 + t * 1.3) + Math.random() * 0.08);
      }
      this.csiHistory.push(frame);
      if (this.csiHistory.length > 30) this.csiHistory.shift();
      // Also feed as raw amplitudes for volume
      if (!this.csiAmplitudes) this.csiAmplitudes = frame;
      this.csiAmplitudes = frame;
    }, 200);
  }

  // Polling fallback
  poll() {
    const h = location.hostname || 'localhost';
    const p = location.port || '9090';
    fetch(`http://${h}:${p}/api/perceptions`)
      .then(r => r.json())
      .then(d => { if (d.perceptions) this._processPerceptions(d.perceptions); })
      .catch(() => {});
  }

  destroy() {
    if (this.ws) this.ws.close();
    clearInterval(this._simInterval);
    clearInterval(this._csiSimInterval);
  }
}
