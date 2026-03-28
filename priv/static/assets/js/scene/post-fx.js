// Aether Observatory — Post Processing
// UnrealBloomPass + vignette/CRT shader pass

import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { THEME } from '../config.js';

// Vignette + CRT scanlines shader
const VignetteCRTShader = {
  uniforms: {
    tDiffuse: { value: null },
    uTime: { value: 0 },
    uVignetteStrength: { value: 0.4 },
    uScanlineIntensity: { value: 0.04 },
  },
  vertexShader: /* glsl */`
    varying vec2 vUv;
    void main() {
      vUv = uv;
      gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
    }
  `,
  fragmentShader: /* glsl */`
    uniform sampler2D tDiffuse;
    uniform float uTime;
    uniform float uVignetteStrength;
    uniform float uScanlineIntensity;
    varying vec2 vUv;

    void main() {
      vec4 color = texture2D(tDiffuse, vUv);

      // Vignette
      vec2 center = vUv - 0.5;
      float dist = length(center);
      float vignette = 1.0 - smoothstep(0.3, 0.85, dist) * uVignetteStrength;
      color.rgb *= vignette;

      // Subtle chromatic aberration
      float offset = 0.0006;
      float r = texture2D(tDiffuse, vUv + vec2(offset, 0.0)).r;
      float b = texture2D(tDiffuse, vUv - vec2(offset, 0.0)).b;
      color.r = mix(color.r, r, 0.2);
      color.b = mix(color.b, b, 0.2);

      gl_FragColor = color;
    }
  `,
};

export class PostFX {
  constructor(renderer, scene, camera) {
    this.renderer = renderer;
    this.composer = new EffectComposer(renderer);

    // Render pass
    const renderPass = new RenderPass(scene, camera);
    this.composer.addPass(renderPass);

    // Bloom (half resolution for performance)
    const bloomRes = new THREE.Vector2(
      Math.floor(renderer.domElement.width / 2),
      Math.floor(renderer.domElement.height / 2)
    );
    this.bloomPass = new UnrealBloomPass(
      bloomRes,
      THEME.bloomStrength,
      THEME.bloomRadius,
      THEME.bloomThreshold
    );
    this.composer.addPass(this.bloomPass);

    // Vignette + CRT
    this.vignettePass = new ShaderPass(VignetteCRTShader);
    this.composer.addPass(this.vignettePass);
  }

  render(time) {
    this.vignettePass.uniforms.uTime.value = time;
    this.composer.render();
  }

  resize(width, height) {
    this.composer.setSize(width, height);
    this.bloomPass.resolution.set(width, height);
  }

  // Quality fallback
  setQuality(high) {
    if (high) {
      this.bloomPass.strength = THEME.bloomStrength;
      this.bloomPass.resolution.set(
        this.renderer.domElement.width,
        this.renderer.domElement.height
      );
    } else {
      this.bloomPass.strength = THEME.bloomStrength * 0.7;
      this.bloomPass.resolution.set(
        this.renderer.domElement.width / 4,
        this.renderer.domElement.height / 4
      );
    }
  }

  dispose() {
    this.composer.dispose();
  }
}
