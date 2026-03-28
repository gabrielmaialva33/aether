// Aether Observatory — Ghost Body (Layer 2)
// Holographic human capsule skeleton with COCO17 keypoints

import * as THREE from 'three';
import { BONES, BONE_GROUPS, BONE_RADII, THEME } from '../config.js';
import { hologramVertexShader, hologramFragmentShader } from '../shaders/hologram.js';

const _tmpA = new THREE.Vector3();
const _tmpB = new THREE.Vector3();
const _tmpDir = new THREE.Vector3();
const _up = new THREE.Vector3(0, 1, 0);

export class GhostBody {
  constructor(scene) {
    this.scene = scene;
    this.group = new THREE.Group();
    this.bones = [];
    this.joints = [];
    this.material = null;
    this.visible = false;
    this._heartPhase = 0;
    this._breathPhase = 0;

    this._build();
    scene.add(this.group);
    this.group.visible = false;
  }

  _build() {
    // Shared hologram material
    this.material = new THREE.ShaderMaterial({
      vertexShader: hologramVertexShader,
      fragmentShader: hologramFragmentShader,
      uniforms: {
        uColor: { value: new THREE.Color(THEME.ghostPrimary) },
        uSecondaryColor: { value: new THREE.Color(THEME.ghostSecondary) },
        uTime: { value: 0 },
        uHeartPhase: { value: 0 },
        uBreathPhase: { value: 0 },
        uConfidence: { value: 1.0 },
        uOpacity: { value: 0.85 },
      },
      transparent: true,
      depthWrite: false,
      side: THREE.DoubleSide,
      blending: THREE.AdditiveBlending,
    });

    // Shared geometries (created ONCE, reused)
    this._jointGeo = new THREE.SphereGeometry(0.04, 8, 8);

    // Create joint spheres (17 COCO keypoints)
    for (let i = 0; i < 17; i++) {
      const mesh = new THREE.Mesh(this._jointGeo, this.material);
      mesh.visible = false;
      this.group.add(mesh);
      this.joints.push(mesh);
    }

    // Create bone cylinders (fixed geometry, scaled per-frame via transform)
    // Using CylinderGeometry(1, 1, 1) as unit — scale to fit
    this._boneGeo = new THREE.CylinderGeometry(1, 1, 1, 6, 1);
    for (const [a, b] of BONES) {
      const mesh = new THREE.Mesh(this._boneGeo, this.material);
      mesh.visible = false;
      this.group.add(mesh);
      this.bones.push({ mesh, from: a, to: b, radius: this._getBoneRadius(a, b) });
    }
  }

  _getBoneRadius(a, b) {
    for (const [group, bones] of Object.entries(BONE_GROUPS)) {
      if (bones.some(([i, j]) => (i === a && j === b) || (i === b && j === a))) {
        return BONE_RADII[group];
      }
    }
    return 0.03;
  }

  update(time, dataBridge) {
    const pose = dataBridge.getInterpolatedPose(performance.now());

    if (!pose || pose.length < 5) {
      this.group.visible = false;
      this.visible = false;
      return;
    }

    this.group.visible = true;
    this.visible = true;

    // Update uniforms
    this.material.uniforms.uTime.value = time;

    const heartBpm = dataBridge.vitals.heart_bpm || 72;
    this._heartPhase += (heartBpm / 60.0) / 60.0;
    if (this._heartPhase > 1) this._heartPhase -= 1;
    this.material.uniforms.uHeartPhase.value = this._heartPhase;

    const breathRpm = dataBridge.vitals.breath_bpm || 15;
    this._breathPhase += (breathRpm / 60.0) / 60.0;
    if (this._breathPhase > 1) this._breathPhase -= 1;
    this.material.uniforms.uBreathPhase.value = this._breathPhase;

    const avgConf = pose.reduce((s, k) => s + (k.confidence || 0), 0) / pose.length;
    this.material.uniforms.uConfidence.value = avgConf;

    // Map keypoints to room space
    const loc = dataBridge.location;
    const anchorX = loc.x || 3.0;
    const anchorZ = loc.z || 2.5;

    let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
    for (const kp of pose) {
      if (kp.x < minX) minX = kp.x;
      if (kp.x > maxX) maxX = kp.x;
      if (kp.y < minY) minY = kp.y;
      if (kp.y > maxY) maxY = kp.y;
    }
    const rangeX = maxX - minX || 1;
    const rangeY = maxY - minY || 1;
    const scale = 1.7 / rangeY;
    const cx = minX + rangeX / 2;

    // Update joints
    const len = Math.min(pose.length, this.joints.length);
    for (let i = 0; i < len; i++) {
      const kp = pose[i];
      const joint = this.joints[i];
      joint.position.set(
        anchorX + (kp.x - cx) * scale,
        (maxY - kp.y) * scale,
        anchorZ + (kp.z || 0) * scale * 0.5
      );
      joint.visible = kp.confidence > 0.2;
    }

    // Update bones — just transform, no geometry recreation
    for (const bone of this.bones) {
      const jA = this.joints[bone.from];
      const jB = this.joints[bone.to];

      if (!jA.visible || !jB.visible) {
        bone.mesh.visible = false;
        continue;
      }

      bone.mesh.visible = true;

      _tmpA.copy(jA.position);
      _tmpB.copy(jB.position);
      _tmpDir.subVectors(_tmpB, _tmpA);
      const length = _tmpDir.length();

      // Position at midpoint
      bone.mesh.position.lerpVectors(jA.position, jB.position, 0.5);

      // Scale: radius on X/Z, length on Y
      bone.mesh.scale.set(bone.radius, length, bone.radius);

      // Align Y axis to bone direction
      if (length > 0.001) {
        bone.mesh.quaternion.setFromUnitVectors(_up, _tmpDir.divideScalar(length));
      }
    }
  }

  setVisible(v) {
    this.group.visible = v;
  }

  dispose() {
    this._jointGeo.dispose();
    this._boneGeo.dispose();
    if (this.material) this.material.dispose();
    this.scene.remove(this.group);
  }
}
