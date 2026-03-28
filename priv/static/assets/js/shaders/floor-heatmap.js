// Aether Observatory — Floor Heatmap Shader
// CSI projected on ground as 2D heatmap with grid overlay

export const floorHeatmapVertexShader = /* glsl */`
varying vec2 vUv;
varying vec3 vWorldPos;

void main() {
  vUv = uv;
  vec4 worldPos = modelMatrix * vec4(position, 1.0);
  vWorldPos = worldPos.xyz;
  gl_Position = projectionMatrix * viewMatrix * worldPos;
}
`;

export const floorHeatmapFragmentShader = /* glsl */`
precision highp float;

varying vec2 vUv;
varying vec3 vWorldPos;

uniform sampler2D uHeatmap;
uniform float uTime;
uniform vec2 uRoomSize;

// 4-stop color ramp matching void theme
vec3 heatColor(float v) {
  if (v < 0.25) {
    float t = v / 0.25;
    return mix(vec3(0.02, 0.01, 0.04), vec3(0.1, 0.0, 0.25), t);
  } else if (v < 0.5) {
    float t = (v - 0.25) / 0.25;
    return mix(vec3(0.1, 0.0, 0.25), vec3(0.0, 0.6, 0.25), t);
  } else if (v < 0.75) {
    float t = (v - 0.5) / 0.25;
    return mix(vec3(0.0, 0.6, 0.25), vec3(0.8, 0.12, 0.15), t);
  } else {
    float t = (v - 0.75) / 0.25;
    return mix(vec3(0.8, 0.12, 0.15), vec3(1.0, 0.95, 0.9), t);
  }
}

void main() {
  float val = texture2D(uHeatmap, vUv).r;

  // Grid overlay
  vec2 gridUv = vUv * 20.0;
  float gridLine = 1.0 - smoothstep(0.02, 0.04, min(fract(gridUv.x), fract(gridUv.y)));
  gridLine *= 0.15;

  // Edge fade
  float edgeFade = smoothstep(0.0, 0.05, vUv.x) * smoothstep(1.0, 0.95, vUv.x)
                 * smoothstep(0.0, 0.05, vUv.y) * smoothstep(1.0, 0.95, vUv.y);

  // Animated ripple from center
  float dist = length(vUv - 0.5) * 2.0;
  float ripple = sin(dist * 20.0 - uTime * 2.0) * 0.03;

  vec3 color = heatColor(clamp(val + ripple, 0.0, 1.0));
  color += vec3(gridLine);

  float alpha = (val * 0.6 + 0.05 + gridLine) * edgeFade;

  gl_FragColor = vec4(color, alpha * 0.8);
}
`;
