// Aether Observatory — Volume Ray March Shader
// Ray marches through Data3DTexture of CSI amplitudes with FBM noise

export const volumeVertexShader = /* glsl */`
varying vec3 vOrigin;
varying vec3 vDirection;

void main() {
  vec4 mvPosition = modelViewMatrix * vec4(position, 1.0);
  // Transform camera position to local (0-1) box space
  mat4 invModel = inverse(modelMatrix);
  vOrigin = (invModel * vec4(cameraPosition, 1.0)).xyz;
  vDirection = position - vOrigin;
  gl_Position = projectionMatrix * mvPosition;
}
`;

export const volumeFragmentShader = /* glsl */`
precision highp float;
precision highp sampler3D;

varying vec3 vOrigin;
varying vec3 vDirection;

uniform sampler3D uVolume;
uniform float uTime;
uniform float uBreathPhase;
uniform float uDensity;
uniform float uOpacity;
uniform int uSteps;
uniform vec3 uRoomSize; // normalized box is 0-1, this maps to room

// FBM noise for organic movement
float hash(vec3 p) {
  p = fract(p * 0.3183099 + 0.1);
  p *= 17.0;
  return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3D(vec3 p) {
  vec3 i = floor(p);
  vec3 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x),
        mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
    mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x),
        mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y),
    f.z
  );
}

float fbm(vec3 p) {
  float v = 0.0;
  float a = 0.5;
  vec3 shift = vec3(100.0);
  for (int i = 0; i < 4; i++) {
    v += a * noise3D(p);
    p = p * 2.0 + shift;
    a *= 0.5;
  }
  return v;
}

// Transfer function: deep purple → teal → orange → white (subtle)
vec4 transferFunction(float val) {
  vec3 color;
  float alpha;

  if (val < 0.3) {
    float t = val / 0.3;
    color = mix(vec3(0.04, 0.01, 0.08), vec3(0.12, 0.0, 0.25), t);
    alpha = t * 0.15;
  } else if (val < 0.55) {
    float t = (val - 0.3) / 0.25;
    color = mix(vec3(0.12, 0.0, 0.25), vec3(0.0, 0.4, 0.25), t);
    alpha = 0.15 + t * 0.2;
  } else if (val < 0.8) {
    float t = (val - 0.55) / 0.25;
    color = mix(vec3(0.0, 0.4, 0.25), vec3(0.6, 0.1, 0.12), t);
    alpha = 0.35 + t * 0.15;
  } else {
    float t = (val - 0.8) / 0.2;
    color = mix(vec3(0.6, 0.1, 0.12), vec3(0.9, 0.7, 0.6), t);
    alpha = 0.5 + t * 0.15;
  }

  return vec4(color, alpha);
}

vec2 intersectBox(vec3 orig, vec3 dir) {
  vec3 invDir = 1.0 / dir;
  vec3 t0 = (vec3(0.0) - orig) * invDir;
  vec3 t1 = (vec3(1.0) - orig) * invDir;
  vec3 tmin = min(t0, t1);
  vec3 tmax = max(t0, t1);
  float tnear = max(max(tmin.x, tmin.y), tmin.z);
  float tfar = min(min(tmax.x, tmax.y), tmax.z);
  return vec2(tnear, tfar);
}

void main() {
  vec3 rayDir = normalize(vDirection);
  vec2 bounds = intersectBox(vOrigin, rayDir);

  if (bounds.x > bounds.y) discard;

  bounds.x = max(bounds.x, 0.0);

  vec3 p = vOrigin + bounds.x * rayDir;
  vec3 step = rayDir * (bounds.y - bounds.x) / float(uSteps);
  float stepLength = length(step);

  vec4 accum = vec4(0.0);

  for (int i = 0; i < 128; i++) {
    if (i >= uSteps) break;

    // Sample CSI volume
    float csiVal = texture(uVolume, p).r;

    // Add FBM noise for organic movement
    float noiseVal = fbm(p * 4.0 + uTime * 0.15) * 0.3;
    float val = csiVal + noiseVal;

    // Height fade: denser at body height (0.3-0.6 in normalized, ~1m-1.8m)
    float heightFade = smoothstep(0.1, 0.3, p.y) * smoothstep(0.8, 0.6, p.y);
    val *= mix(0.3, 1.0, heightFade);

    // Breath modulation
    val *= 1.0 + sin(uBreathPhase * 6.283) * 0.1;

    // Apply transfer function
    vec4 sampleColor = transferFunction(clamp(val, 0.0, 1.0));
    sampleColor.a *= uOpacity * stepLength * uDensity;

    // Front-to-back compositing (pre-multiplied alpha)
    sampleColor.rgb *= sampleColor.a;
    accum += sampleColor * (1.0 - accum.a);

    // Early termination
    if (accum.a > 0.95) break;

    p += step;
  }

  gl_FragColor = accum;
}
`;
