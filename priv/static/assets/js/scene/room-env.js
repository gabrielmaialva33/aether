// Aether Observatory — Room Environment (Layer 3)
// Wireframe walls, floor grid, ESP32 node markers, floor heatmap

import * as THREE from 'three';
import { ROOM, NODES, THEME } from '../config.js';
import { floorHeatmapVertexShader, floorHeatmapFragmentShader } from '../shaders/floor-heatmap.js';
import { beamVertexShader, beamFragmentShader } from '../shaders/beam-line.js';

export class RoomEnvironment {
  constructor(scene) {
    this.scene = scene;
    this.group = new THREE.Group();
    this.nodeMarkers = [];
    this.beamLines = [];
    this.heatmapMaterial = null;
    this.heatmapTexture = null;
    this._targetPos = new THREE.Vector3(ROOM.width / 2, 1.0, ROOM.depth / 2);
    this._lastHeatmapUpdate = 0;
    this._heatmapUpdateInterval = 150; // ms

    this._build();
    scene.add(this.group);
  }

  _build() {
    this._buildGrid();
    this._buildWalls();
    this._buildNodeMarkers();
    this._buildFloorHeatmap();
    this._buildBeamLines();
  }

  _buildGrid() {
    const grid = new THREE.GridHelper(
      Math.max(ROOM.width, ROOM.depth),
      Math.max(ROOM.width, ROOM.depth) * 2,
      0x1a1a1a,
      0x0d0d0d
    );
    grid.position.set(ROOM.width / 2, 0, ROOM.depth / 2);
    this.group.add(grid);
  }

  _buildWalls() {
    const mat = new THREE.LineBasicMaterial({
      color: 0x1a0810,
      transparent: true,
      opacity: 0.4,
    });

    const w = ROOM.width, h = ROOM.height, d = ROOM.depth;
    const corners = [
      [0,0,0], [w,0,0], [w,0,d], [0,0,d], // bottom
      [0,h,0], [w,h,0], [w,h,d], [0,h,d], // top
    ];

    // Bottom edges
    const edges = [
      [0,1],[1,2],[2,3],[3,0], // bottom
      [4,5],[5,6],[6,7],[7,4], // top
      [0,4],[1,5],[2,6],[3,7], // verticals
    ];

    for (const [a, b] of edges) {
      const geo = new THREE.BufferGeometry().setFromPoints([
        new THREE.Vector3(...corners[a]),
        new THREE.Vector3(...corners[b]),
      ]);
      this.group.add(new THREE.LineSegments(geo, mat));
    }
  }

  _buildNodeMarkers() {
    for (const node of NODES) {
      // Glowing icosahedron
      const geo = new THREE.IcosahedronGeometry(0.12, 1);
      const mat = new THREE.MeshBasicMaterial({
        color: node.color,
        transparent: true,
        opacity: 0.8,
        wireframe: true,
      });
      const mesh = new THREE.Mesh(geo, mat);
      mesh.position.set(...node.pos);
      this.group.add(mesh);

      // Outer glow sphere
      const glowGeo = new THREE.SphereGeometry(0.25, 16, 16);
      const glowMat = new THREE.MeshBasicMaterial({
        color: node.color,
        transparent: true,
        opacity: 0.08,
      });
      const glow = new THREE.Mesh(glowGeo, glowMat);
      glow.position.set(...node.pos);
      this.group.add(glow);

      // Point light
      const light = new THREE.PointLight(node.color, 0.2, 2.5);
      light.position.set(...node.pos);
      this.group.add(light);

      // Label sprite
      const label = this._createLabel(node.label, node.color);
      label.position.set(node.pos[0], node.pos[1] + 0.35, node.pos[2]);
      this.group.add(label);

      this.nodeMarkers.push({ mesh, glow, light, node });
    }
  }

  _createLabel(text, color) {
    const canvas = document.createElement('canvas');
    canvas.width = 64;
    canvas.height = 32;
    const ctx = canvas.getContext('2d');
    ctx.font = 'bold 18px JetBrains Mono';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillStyle = `#${color.toString(16).padStart(6, '0')}`;
    ctx.fillText(text, 32, 16);

    const tex = new THREE.CanvasTexture(canvas);
    const mat = new THREE.SpriteMaterial({ map: tex, transparent: true, opacity: 0.7 });
    const sprite = new THREE.Sprite(mat);
    sprite.scale.set(0.5, 0.25, 1);
    return sprite;
  }

  _buildFloorHeatmap() {
    // Data texture for CSI heatmap (updated each frame)
    const size = 64;
    const data = new Uint8Array(size * size);
    this.heatmapTexture = new THREE.DataTexture(
      data, size, size, THREE.RedFormat, THREE.UnsignedByteType
    );
    this.heatmapTexture.needsUpdate = true;

    this.heatmapMaterial = new THREE.ShaderMaterial({
      vertexShader: floorHeatmapVertexShader,
      fragmentShader: floorHeatmapFragmentShader,
      uniforms: {
        uHeatmap: { value: this.heatmapTexture },
        uTime: { value: 0 },
        uRoomSize: { value: new THREE.Vector2(ROOM.width, ROOM.depth) },
      },
      transparent: true,
      depthWrite: false,
      side: THREE.DoubleSide,
    });

    const plane = new THREE.PlaneGeometry(ROOM.width, ROOM.depth);
    const mesh = new THREE.Mesh(plane, this.heatmapMaterial);
    mesh.rotation.x = -Math.PI / 2;
    mesh.position.set(ROOM.width / 2, 0.01, ROOM.depth / 2);
    this.group.add(mesh);
  }

  _buildBeamLines() {
    for (const node of NODES) {
      const points = 32;
      const positions = new Float32Array(points * 3);
      const progress = new Float32Array(points);

      for (let i = 0; i < points; i++) {
        progress[i] = i / (points - 1);
      }

      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
      geo.setAttribute('aProgress', new THREE.BufferAttribute(progress, 1));

      const mat = new THREE.ShaderMaterial({
        vertexShader: beamVertexShader,
        fragmentShader: beamFragmentShader,
        uniforms: {
          uColor: { value: new THREE.Color(node.color) },
          uTime: { value: 0 },
          uIntensity: { value: 0.5 },
        },
        transparent: true,
        depthWrite: false,
        blending: THREE.AdditiveBlending,
      });

      const line = new THREE.Line(geo, mat);
      this.group.add(line);
      this.beamLines.push({ line, geo, mat, nodePos: node.pos });
    }
  }

  // ── Update ────────────────────────────────────────────────────────────

  update(time, dataBridge) {
    // Animate node markers
    for (const m of this.nodeMarkers) {
      m.mesh.rotation.y = time * 0.5;
      m.mesh.rotation.x = Math.sin(time * 0.3) * 0.2;
      m.glow.scale.setScalar(1.0 + Math.sin(time * 2) * 0.15);
    }

    // Update floor heatmap from CSI (throttled)
    if (this.heatmapMaterial) {
      this.heatmapMaterial.uniforms.uTime.value = time;
      const now = performance.now();
      if (now - this._lastHeatmapUpdate > this._heatmapUpdateInterval) {
        this._lastHeatmapUpdate = now;
        this._updateHeatmapTexture(dataBridge);
      }
    }

    // Update target position from location data
    if (dataBridge.location.x !== 0 || dataBridge.location.z !== 0) {
      this._targetPos.set(
        dataBridge.location.x,
        dataBridge.location.y || 1.0,
        dataBridge.location.z
      );
    }

    // Update beam lines
    for (const beam of this.beamLines) {
      beam.mat.uniforms.uTime.value = time;
      this._updateBeamPositions(beam);
    }
  }

  _updateHeatmapTexture(dataBridge) {
    if (!dataBridge.csiAmplitudes) return;
    const size = 64;
    const data = this.heatmapTexture.image.data;
    const amps = dataBridge.csiAmplitudes;
    const nNodes = NODES.length;
    const ampsPerNode = Math.floor(amps.length / nNodes) || 1;

    // Pre-compute per-node averages
    const nodeAvg = new Float32Array(nNodes);
    for (let n = 0; n < nNodes; n++) {
      let sum = 0;
      const start = n * ampsPerNode;
      const end = Math.min(start + ampsPerNode, amps.length);
      for (let s = start; s < end; s++) sum += amps[s];
      nodeAvg[n] = sum / ((end - start) || 1);
    }

    const sizeM1 = size - 1;
    for (let iy = 0; iy < size; iy++) {
      const wz = (iy / sizeM1) * ROOM.depth;
      for (let ix = 0; ix < size; ix++) {
        const wx = (ix / sizeM1) * ROOM.width;
        let value = 0, totalWeight = 0;
        for (let n = 0; n < nNodes; n++) {
          const dx = wx - NODES[n].pos[0], dz = wz - NODES[n].pos[2];
          const weight = 1.0 / (1.0 + dx * dx + dz * dz);
          value += nodeAvg[n] * weight;
          totalWeight += weight;
        }
        data[iy * size + ix] = Math.min(255, (value / totalWeight) * 255);
      }
    }
    this.heatmapTexture.needsUpdate = true;
  }

  _updateBeamPositions(beam) {
    const posAttr = beam.geo.getAttribute('position');
    const count = posAttr.count;
    const src = beam.nodePos;
    const dst = this._targetPos;

    for (let i = 0; i < count; i++) {
      const t = i / (count - 1);
      posAttr.setXYZ(i,
        src[0] + (dst.x - src[0]) * t,
        src[1] + (dst.y - src[1]) * t,
        src[2] + (dst.z - src[2]) * t
      );
    }
    posAttr.needsUpdate = true;
  }

  setTargetPosition(x, y, z) {
    this._targetPos.set(x, y, z);
  }

  dispose() {
    this.group.traverse(obj => {
      if (obj.geometry) obj.geometry.dispose();
      if (obj.material) {
        if (obj.material.map) obj.material.map.dispose();
        obj.material.dispose();
      }
    });
    this.scene.remove(this.group);
  }
}
