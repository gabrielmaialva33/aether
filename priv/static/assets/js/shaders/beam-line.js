// Aether Observatory — Beam Line Shader
// Signal propagation glow from ESP32 nodes to detected position

export const beamVertexShader = /* glsl */`
attribute float aProgress; // 0-1 along the line
varying float vProgress;
varying vec3 vWorldPos;

void main() {
  vProgress = aProgress;
  vec4 worldPos = modelMatrix * vec4(position, 1.0);
  vWorldPos = worldPos.xyz;
  gl_Position = projectionMatrix * viewMatrix * worldPos;
}
`;

export const beamFragmentShader = /* glsl */`
precision highp float;

varying float vProgress;
varying vec3 vWorldPos;

uniform vec3 uColor;
uniform float uTime;
uniform float uIntensity;

void main() {
  // Traveling pulse along the beam
  float pulse = sin(vProgress * 12.566 - uTime * 4.0) * 0.5 + 0.5;
  pulse = pow(pulse, 3.0);

  // Fade at endpoints
  float fade = smoothstep(0.0, 0.1, vProgress) * smoothstep(1.0, 0.9, vProgress);

  float alpha = (0.15 + pulse * 0.6) * fade * uIntensity;

  gl_FragColor = vec4(uColor * (0.5 + pulse * 0.5), alpha);
}
`;
