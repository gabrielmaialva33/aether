// Aether Observatory — Hologram Shader
// Fresnel rim glow, scanlines, heart pulse, breath modulation

export const hologramVertexShader = /* glsl */`
varying vec3 vNormal;
varying vec3 vViewDir;
varying vec3 vWorldPos;
varying vec2 vUv;

void main() {
  vec4 worldPos = modelMatrix * vec4(position, 1.0);
  vWorldPos = worldPos.xyz;
  vNormal = normalize(normalMatrix * normal);
  vViewDir = normalize(cameraPosition - worldPos.xyz);
  vUv = uv;
  gl_Position = projectionMatrix * viewMatrix * worldPos;
}
`;

export const hologramFragmentShader = /* glsl */`
precision highp float;

varying vec3 vNormal;
varying vec3 vViewDir;
varying vec3 vWorldPos;
varying vec2 vUv;

uniform vec3 uColor;
uniform vec3 uSecondaryColor;
uniform float uTime;
uniform float uHeartPhase;   // 0-1 cycling with heart rate
uniform float uBreathPhase;  // 0-1 cycling with breath rate
uniform float uConfidence;   // 0-1 global alpha modulation
uniform float uOpacity;

void main() {
  // Fresnel rim glow
  float fresnel = pow(1.0 - max(dot(vNormal, vViewDir), 0.0), 2.5);

  // Heart pulse: double-bump cardiac pattern
  float heartPulse = pow(max(sin(uHeartPhase * 6.283), 0.0), 3.0);
  float heartPulse2 = pow(max(sin(uHeartPhase * 6.283 + 1.2), 0.0), 5.0) * 0.4;
  float heart = heartPulse + heartPulse2;

  // Breath modulation — subtle body swell
  float breath = sin(uBreathPhase * 6.283) * 0.05;

  // Horizontal scanlines rolling upward
  float scanline = sin(vWorldPos.y * 120.0 - uTime * 0.8) * 0.5 + 0.5;
  scanline = smoothstep(0.3, 0.7, scanline);

  // Vertical flicker (subtle)
  float flicker = sin(vWorldPos.x * 40.0 + uTime * 3.0) * 0.03 + 1.0;

  // Mix primary and secondary color based on heart
  vec3 color = mix(uColor, uSecondaryColor, heart * 0.6);

  // Combine
  float intensity = fresnel * 0.7 + 0.3;
  intensity *= (0.6 + scanline * 0.4);
  intensity *= flicker;
  intensity *= (1.0 + heart * 0.5);
  intensity *= (1.0 + breath);

  float alpha = intensity * uConfidence * uOpacity;

  gl_FragColor = vec4(color * intensity, alpha);
}
`;
