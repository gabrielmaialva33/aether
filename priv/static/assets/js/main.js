// Aether Observatory — Main Entry Point
// Three.js scene init, render loop, controls, layer toggling

import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { ROOM, CAMERA, THEME } from './config.js';
import { DataBridge } from './data-bridge.js';
import { RoomEnvironment } from './scene/room-env.js';
import { GhostBody } from './scene/ghost-body.js';
import { RFVolume } from './scene/rf-volume.js';
import { PostFX } from './scene/post-fx.js';
import { HudController } from './hud/hud-controller.js';

class AetherObservatory {
  constructor() {
    this.clock = new THREE.Clock();
    this.layers = { room: true, ghost: true, volume: true };
    this._frameTimes = [];
    this._qualityHigh = true;

    this._init();
  }

  _init() {
    // Renderer
    const canvas = document.getElementById('viewport');
    this.renderer = new THREE.WebGLRenderer({
      canvas,
      antialias: true,
      alpha: false,
      powerPreference: 'high-performance',
    });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.renderer.setSize(window.innerWidth, window.innerHeight);
    this.renderer.setClearColor(THEME.void, 1);
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.2;

    // Scene
    this.scene = new THREE.Scene();
    this.scene.fog = new THREE.FogExp2(THEME.void, 0.04);

    // Camera
    this.camera = new THREE.PerspectiveCamera(
      CAMERA.fov,
      window.innerWidth / window.innerHeight,
      CAMERA.near,
      CAMERA.far
    );
    this.camera.position.set(...CAMERA.position);

    // Controls
    this.controls = new OrbitControls(this.camera, canvas);
    this.controls.target.set(...CAMERA.target);
    this.controls.enableDamping = true;
    this.controls.dampingFactor = 0.08;
    this.controls.maxPolarAngle = Math.PI * 0.85;
    this.controls.minDistance = 2;
    this.controls.maxDistance = 25;
    this.controls.update();

    // Ambient light
    const ambient = new THREE.AmbientLight(0x111111, 0.5);
    this.scene.add(ambient);

    // Data bridge
    this.dataBridge = new DataBridge();
    this.dataBridge.connect();
    // Polling fallback
    this._pollInterval = setInterval(() => this.dataBridge.poll(), 400);

    // Scene layers
    this.roomEnv = new RoomEnvironment(this.scene);
    this.ghostBody = new GhostBody(this.scene);
    this.rfVolume = new RFVolume(this.scene);

    // Post processing
    this.postFX = new PostFX(this.renderer, this.scene, this.camera);

    // HUD controller
    this.hud = new HudController(this.dataBridge);

    // Events
    window.addEventListener('resize', () => this._onResize());
    window.addEventListener('keydown', (e) => this._onKey(e));

    // Camera presets
    this._cameraPresets = {
      orbit: { pos: [8, 5, 8], target: [3, 1.2, 2.5] },
      top: { pos: [3, 12, 2.5], target: [3, 0, 2.5] },
      front: { pos: [3, 1.5, -3], target: [3, 1.2, 2.5] },
    };
    this._currentPreset = 'orbit';

    // Render FPS counter (independent of WS data rate)
    this._renderFrames = 0;
    this._renderFps = 0;
    setInterval(() => {
      this._renderFps = this._renderFrames;
      this._renderFrames = 0;
      const fv = document.getElementById('fv');
      if (fv) fv.textContent = this._renderFps;
    }, 1000);

    // Start
    this._animate();
  }

  _animate() {
    requestAnimationFrame(() => this._animate());

    const time = this.clock.getElapsedTime();
    const frameStart = performance.now();

    // Update controls
    this.controls.update();

    // Update scene layers
    if (this.layers.room) this.roomEnv.update(time, this.dataBridge);
    if (this.layers.ghost) this.ghostBody.update(time, this.dataBridge);
    if (this.layers.volume) this.rfVolume.update(time, this.dataBridge);

    // Update HUD (throttled to ~30fps for DOM perf)
    if (Math.floor(time * 30) !== Math.floor((time - 0.033) * 30)) {
      this.hud.update();
    }

    // Render with post-processing
    this.postFX.render(time);
    this._renderFrames++;
  }

  _onResize() {
    const w = window.innerWidth;
    const h = window.innerHeight;

    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(w, h);
    this.postFX.resize(w, h);
  }

  _onKey(e) {
    switch (e.key) {
      case '1':
        this.layers.room = !this.layers.room;
        this.roomEnv.group.visible = this.layers.room;
        break;
      case '2':
        this.layers.ghost = !this.layers.ghost;
        this.ghostBody.setVisible(this.layers.ghost);
        break;
      case '3':
        this.layers.volume = !this.layers.volume;
        this.rfVolume.setVisible(this.layers.volume);
        break;
      case 'f':
      case 'F':
        if (!document.fullscreenElement) {
          document.documentElement.requestFullscreen();
        } else {
          document.exitFullscreen();
        }
        break;
      case 'c':
      case 'C':
        this._cycleCamera();
        break;
    }
  }

  _cycleCamera() {
    const presets = Object.keys(this._cameraPresets);
    const idx = (presets.indexOf(this._currentPreset) + 1) % presets.length;
    this._currentPreset = presets[idx];
    const preset = this._cameraPresets[this._currentPreset];
    this.camera.position.set(...preset.pos);
    this.controls.target.set(...preset.target);
  }

  _setQuality(high) {
    this._qualityHigh = high;
    this.rfVolume.setQuality(high);
    this.postFX.setQuality(high);
  }

  dispose() {
    this.dataBridge.destroy();
    this.roomEnv.dispose();
    this.ghostBody.dispose();
    this.rfVolume.dispose();
    this.postFX.dispose();
    this.hud.dispose();
    clearInterval(this._pollInterval);
    this.renderer.dispose();
  }
}

// ── Boot ──────────────────────────────────────────────────────────────────
window.addEventListener('DOMContentLoaded', () => {
  window.aether = new AetherObservatory();
});
