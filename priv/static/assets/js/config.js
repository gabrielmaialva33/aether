// Aether Observatory — Configuration
// Room dimensions, ESP32 node positions, visual parameters

export const ROOM = {
  width: 6.0,   // meters (X)
  depth: 5.0,   // meters (Z)
  height: 3.0,  // meters (Y)
};

// ESP32 node positions in room space (meters)
export const NODES = [
  { id: 'esp32-a', pos: [0.0,  2.2, 0.0],  color: 0x00ff41, label: 'A' },
  { id: 'esp32-b', pos: [6.0,  2.2, 0.0],  color: 0x00d4ff, label: 'B' },
  { id: 'esp32-c', pos: [3.0,  2.2, 5.0],  color: 0xff8c00, label: 'C' },
];

// Volume texture resolution
export const VOLUME = {
  resolution: 32,   // 32^3 voxels
  fallbackRes: 16,   // low-end
  raySteps: 32,
  fallbackSteps: 16,
  rbfFalloff: 2.0,
};

// COCO17 bone definitions [from, to]
export const BONES = [
  [0,1],[0,2],[1,3],[2,4],       // head
  [5,6],[5,7],[7,9],[6,8],[8,10], // torso + arms
  [5,11],[6,12],[11,12],          // torso
  [11,13],[13,15],[12,14],[14,16] // legs
];

// Capsule radii per bone group (meters)
export const BONE_RADII = {
  head:  0.025,
  torso: 0.055,
  arms:  0.032,
  legs:  0.040,
};

// Which bones belong to which group
export const BONE_GROUPS = {
  head:  [[0,1],[0,2],[1,3],[2,4]],
  torso: [[5,6],[5,11],[6,12],[11,12]],
  arms:  [[5,7],[7,9],[6,8],[8,10]],
  legs:  [[11,13],[13,15],[12,14],[14,16]],
};

// Visual theme
export const THEME = {
  void: 0x050508,
  red: 0xc41e3a,
  redGlow: 0xff2040,
  green: 0x00ff41,
  greenGlow: 0x39ff14,
  orange: 0xff8c00,
  cyan: 0x00d4ff,
  ghostPrimary: 0x00d4ff,
  ghostSecondary: 0xff2040,
  bloomStrength: 0.6,
  bloomRadius: 0.4,
  bloomThreshold: 0.35,
};

// Camera defaults
export const CAMERA = {
  fov: 55,
  near: 0.1,
  far: 100,
  position: [8, 5, 8],
  target: [3, 1.2, 2.5],
};

// Activity icons
export const ACTIVITY_ICONS = {
  idle: '\u25A0',
  walking: '\u25B6',
  sitting_down: '\u25BC',
  standing_up: '\u25B2',
  waving: '\u25C6',
  falling: '\u26A0',
};
