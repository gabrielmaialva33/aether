// Aether Observatory — RF Volume (Layer 1)
// Ray-marched Data3DTexture of CSI amplitudes

import * as THREE from 'three';
import { ROOM, VOLUME, THEME } from '../config.js';
import { volumeVertexShader, volumeFragmentShader } from '../shaders/volume-raymarch.js';

export class RFVolume {
  constructor(scene) {
    this.scene = scene;
    this.mesh = null;
    this.material = null;
    this.volumeTexture = null;
    this._breathPhase = 0;
    this._res = VOLUME.resolution;
    this._lastVolumeUpdate = 0;
    this._volumeUpdateInterval = 100; // ms — update volume data at 10fps
    this._volumeBuffer = new Float32Array(VOLUME.resolution ** 3);

    this._build();
    scene.add(this.mesh);
  }

  _build() {
    const res = this._res;

    // Create 3D texture
    const data = new Float32Array(res * res * res);
    this.volumeTexture = new THREE.Data3DTexture(data, res, res, res);
    this.volumeTexture.format = THREE.RedFormat;
    this.volumeTexture.type = THREE.FloatType;
    this.volumeTexture.minFilter = THREE.LinearFilter;
    this.volumeTexture.magFilter = THREE.LinearFilter;
    this.volumeTexture.wrapS = THREE.ClampToEdgeWrapping;
    this.volumeTexture.wrapT = THREE.ClampToEdgeWrapping;
    this.volumeTexture.wrapR = THREE.ClampToEdgeWrapping;
    this.volumeTexture.needsUpdate = true;

    // Box covering the room, rendered from BackSide
    const geo = new THREE.BoxGeometry(1, 1, 1);

    this.material = new THREE.ShaderMaterial({
      vertexShader: volumeVertexShader,
      fragmentShader: volumeFragmentShader,
      uniforms: {
        uVolume: { value: this.volumeTexture },
        uTime: { value: 0 },
        uBreathPhase: { value: 0 },
        uDensity: { value: 1.0 },
        uOpacity: { value: 0.25 },
        uSteps: { value: VOLUME.raySteps },
        uRoomSize: { value: new THREE.Vector3(ROOM.width, ROOM.height, ROOM.depth) },
      },
      transparent: true,
      depthWrite: false,
      side: THREE.BackSide,
      blending: THREE.AdditiveBlending,
    });

    this.mesh = new THREE.Mesh(geo, this.material);
    // BoxGeometry(1,1,1) is -0.5..0.5; shift to 0..1 so ray march box test works
    this.mesh.geometry.translate(0.5, 0.5, 0.5);
    // Scale to room size so 0..1 in local space maps to room dimensions
    this.mesh.scale.set(ROOM.width, ROOM.height, ROOM.depth);
  }

  // ── Update ──────────────────────────────────────────────────────────

  update(time, dataBridge) {
    if (!this.material) return;

    this.material.uniforms.uTime.value = time;

    // Breath phase from vitals
    const breathRpm = dataBridge.vitals.breath_bpm || 15;
    this._breathPhase += (breathRpm / 60.0) / 60.0;
    if (this._breathPhase > 1) this._breathPhase -= 1;
    this.material.uniforms.uBreathPhase.value = this._breathPhase;

    // Update volume texture from CSI data (throttled — heavy CPU)
    const now = performance.now();
    if (now - this._lastVolumeUpdate > this._volumeUpdateInterval) {
      this._lastVolumeUpdate = now;
      this._updateVolume(dataBridge);
    }
  }

  _updateVolume(dataBridge) {
    dataBridge.interpolateToVolume(ROOM.width, ROOM.depth, ROOM.height, this._volumeBuffer);
    const texData = this.volumeTexture.image.data;

    for (let i = 0; i < this._volumeBuffer.length; i++) {
      texData[i] = this._volumeBuffer[i];
    }

    this.volumeTexture.needsUpdate = true;
  }

  // Quality adjustment
  setQuality(high) {
    if (high) {
      this.material.uniforms.uSteps.value = VOLUME.raySteps;
    } else {
      this.material.uniforms.uSteps.value = VOLUME.fallbackSteps;
    }
  }

  setVisible(v) {
    this.mesh.visible = v;
  }

  dispose() {
    if (this.mesh.geometry) this.mesh.geometry.dispose();
    if (this.material) this.material.dispose();
    if (this.volumeTexture) this.volumeTexture.dispose();
    this.scene.remove(this.mesh);
  }
}
