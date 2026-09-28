// Static voxel sets, from the game's builders (campus_builder.gd _bench / blackboard / add_cctv,
// trolley.gd, grounds.gd stall, palette.gd). Metres, y up. The classroom keeps the game's layout:
// the board is at +Z and seated students face +Z.
import { darkened, lightened, P, type Box, type V3 } from "./voxel";

const b = (list: Box[], c: V3, s: V3, col: string) => list.push({ c, s, col });

// Deterministic pseudo-random (no Math.random: every frame is a pure function of time).
export const hash = (n: number) => {
  const x = Math.sin(n * 127.1 + 311.7) * 43758.5453;
  return x - Math.floor(x);
};

export function bench(list: Box[], x: number, z: number) {
  const top = P.WOOD, frame = P.WOOD_DARK;
  b(list, [x, 0.76, z], [1.8, 0.06, 0.52], top);
  b(list, [x, 0.5, z + 0.24], [1.8, 0.46, 0.04], frame);
  b(list, [x, 0.58, z - 0.02], [1.72, 0.03, 0.44], frame);
  for (const sx of [-0.87, 0.87]) {
    b(list, [x + sx, 0.37, z], [0.06, 0.74, 0.5], frame);
    b(list, [x + sx, 0.22, z - 0.62], [0.06, 0.44, 0.3], frame);
  }
  b(list, [x, 0.46, z - 0.62], [1.8, 0.05, 0.32], top);
  b(list, [x, 0.78, z - 0.8], [1.8, 0.26, 0.04], top);
  b(list, [x - 0.87, 0.62, z - 0.8], [0.06, 0.34, 0.04], frame);
  b(list, [x + 0.87, 0.62, z - 0.8], [0.06, 0.34, 0.04], frame);
}

export const BENCHES: [number, number][] = [
  [-2.2, 1.6], [0.6, 1.6], [-2.2, -0.2], [0.6, -0.2], [-2.2, -2.0], [0.6, -2.0],
];
/** Seat positions (feet) for a bench, left and right. */
export const seat = (i: number, side: 0 | 1): V3 => [BENCHES[i][0] + (side ? 0.45 : -0.45), 0, BENCHES[i][1] - 0.66];

export function classroom(): Box[] {
  const L: Box[] = [];
  // Floor: checker tiles, like FLOOR_A / FLOOR_B.
  for (let x = -6; x < 6; x++)
    for (let z = -5; z < 5; z++) b(L, [x + 0.5, -0.05, z + 0.5], [1, 0.1, 1], (x + z) & 1 ? P.FLOOR_A : P.FLOOR_B);
  // Front wall (board side, +Z) and left wall with windows, dado green below 1 m.
  const W = 4.6, H = 3.4;
  b(L, [0, H / 2, W + 0.1], [12, H, 0.2], P.WALL);
  b(L, [0, 0.5, W - 0.01], [12, 1.0, 0.02], P.DADO_INSIDE);
  b(L, [-6.1, H / 2, 0], [0.2, H, 10], P.WALL);
  b(L, [-6.0, 0.5, 0], [0.02, 1.0, 10], P.DADO_INSIDE);
  for (const z of [-3, 0, 3]) {
    b(L, [-6.0, 1.9, z], [0.06, 1.3, 1.9], "#3f86a8");
    b(L, [-5.98, 1.9, z], [0.04, 1.14, 1.74], "#bfe8ff");
    b(L, [-5.97, 1.9, z], [0.03, 1.14, 0.05], "#3f86a8");
  }
  // Right wall with the door.
  b(L, [6.1, H / 2, -1.5], [0.2, H, 7], P.WALL);
  b(L, [6.1, H / 2, 4.2], [0.2, H, 0.8], P.WALL);
  b(L, [6.1, 2.95, 2.8], [0.2, 0.9, 2.0], P.WALL);
  b(L, [6.0, 0.5, -1.5], [0.02, 1.0, 7], P.DADO_INSIDE);
  b(L, [6.06, 1.25, 2.8], [0.1, 2.5, 1.2], "#c9703a");
  b(L, [6.0, 1.2, 2.4], [0.06, 0.06, 0.12], P.METAL);
  // Dais, blackboard, chalk, clock (campus_builder.gd:845).
  const back = W;
  b(L, [0, 0.045, back - 0.9], [9.5, 0.07, 1.5], P.WOOD_DARK);
  b(L, [0, 1.75, back - 0.03], [3.9, 1.5, 0.06], P.WOOD_DARK);
  b(L, [0, 1.75, back - 0.07], [3.7, 1.3, 0.03], P.BOARD);
  b(L, [0, 1.02, back - 0.1], [3.7, 0.05, 0.12], P.WOOD_DARK);
  for (let k = 0; k < 3; k++) b(L, [-1.2 + k * 0.3, 1.06, back - 0.1], [0.08, 0.025, 0.025], P.CHALK);
  b(L, [0, 2.9, back - 0.03], [0.46, 0.46, 0.05], "#2a2a30");
  b(L, [0, 2.9, back - 0.06], [0.38, 0.38, 0.02], "#ffffff");
  // Teacher's table with the register.
  const d = 0.08;
  b(L, [2.9, d + 0.76, back - 1.2], [1.7, 0.06, 0.8], P.WOOD);
  b(L, [2.9, d + 0.45, back - 1.58], [1.7, 0.6, 0.04], P.WOOD_DARK);
  for (const sx of [-0.8, 0.8]) b(L, [2.9 + sx, d + 0.37, back - 1.2], [0.06, 0.74, 0.76], P.WOOD_DARK);
  b(L, [2.9, d + 0.8, back - 1.15], [0.34, 0.04, 0.44], "#2f5fb0");
  b(L, [2.4, d + 0.86, back - 1.1], [0.24, 0.16, 0.32], "#e0524f");
  b(L, [3.5, d + 0.9, back - 1.15], [0.08, 0.22, 0.08], "#7fd0ea");
  for (let i = 0; i < BENCHES.length; i++) bench(L, BENCHES[i][0], BENCHES[i][1]);
  // Bags and books on desks.
  b(L, [-2.6, 0.83, 1.6], [0.3, 0.06, 0.22], "#4f86e0");
  b(L, [1.0, 0.83, -0.2], [0.3, 0.06, 0.22], "#e0524f");
  b(L, [-1.8, 0.83, -2.0], [0.3, 0.06, 0.22], "#48b06a");
  return L;
}

/** The hand-held chalk "Thermodynamics" line is drawn as a texture in World3D. */
export const BOARD_TEXT_POS: V3 = [0, 1.85, 4.6 - 0.09];

export function cctv(): { body: Box[]; led: Box[]; mount: Box[] } {
  const body: Box[] = [], led: Box[] = [], mount: Box[] = [];
  b(body, [0, 0, -0.12], [0.18, 0.16, 0.36], "#e8e6e0");
  b(body, [0, 0, -0.31], [0.12, 0.1, 0.04], "#22232b");
  b(body, [0, 0.1, -0.12], [0.22, 0.03, 0.42], "#c9c5bb");
  b(led, [0.06, 0.05, -0.3], [0.03, 0.03, 0.01], "#ff3030");
  b(mount, [0, 0.14, 0.04], [0.05, 0.14, 0.05], "#4a4f5a");
  b(mount, [0, 0.24, 0.1], [0.14, 0.06, 0.2], "#4a4f5a");
  return { body, led, mount };
}

export function corridor(): Box[] {
  const L: Box[] = [];
  for (let x = -10; x < 16; x++)
    for (let z = -3; z < 3; z++) b(L, [x + 0.5, -0.05, z + 0.5], [1, 0.1, 1], (x + z) & 1 ? P.FLOOR_A : P.FLOOR_B);
  b(L, [3, 1.7, 3.1], [26, 3.4, 0.2], P.WALL);
  b(L, [3, 0.5, 2.99], [26, 1.0, 0.02], P.DADO_INSIDE);
  // Lockers (campus_builder.gd locker_parts): body #5f8fb8, door lighter, louvres, class tag.
  for (let i = 0; i < 20; i++) {
    const x = -6 + i * 0.78 + (i >= 9 ? 4.2 : 0);
    b(L, [x, 0.95, 2.7], [0.74, 1.9, 0.56], "#5f8fb8");
    b(L, [x, 0.95, 2.41], [0.66, 1.8, 0.02], lightened("#5f8fb8", 0.1));
    for (const y of [1.45, 1.57, 1.69]) b(L, [x, y, 2.39], [0.4, 0.04, 0.01], "#2a3a4a");
    b(L, [x + 0.24, 1.0, 2.38], [0.04, 0.16, 0.03], P.METAL);
    b(L, [x, 1.25, 2.395], [0.14, 0.06, 0.01], P.CLASS[i % 4]);
  }
  // Notice board.
  b(L, [3.4, 1.6, 2.98], [2.2, 1.2, 0.05], P.WOOD_DARK);
  b(L, [3.4, 1.6, 2.95], [2.0, 1.0, 0.02], "#c9a26a");
  const notes = ["#fbf6e8", "#ffd24a", "#9fd8ff", "#f2b8c6", "#b9e6a0"];
  for (let i = 0; i < 6; i++) b(L, [2.7 + (i % 3) * 0.6, 1.8 - Math.floor(i / 3) * 0.45, 2.93], [0.4, 0.3, 0.01], notes[i % 5]);
  return L;
}

export function trolley(): Box[] {
  const L: Box[] = [];
  const steel = "#b8c0c8", dark = "#3a3d47";
  b(L, [0, 0.62, 0], [0.72, 0.05, 1.02], steel);
  b(L, [0, 0.28, 0], [0.7, 0.04, 1.0], darkened(steel, 0.15));
  for (const x of [-0.33, 0.33])
    for (const z of [-0.47, 0.47]) {
      b(L, [x, 0.4, z], [0.04, 0.5, 0.04], darkened(steel, 0.25));
      b(L, [x, 0.07, z], [0.08, 0.14, 0.14], dark);
    }
  b(L, [0, 0.9, 0.5], [0.7, 0.05, 0.05], "#e0524f");
  for (const x of [-0.33, 0.33]) b(L, [x, 0.78, 0.5], [0.04, 0.28, 0.04], darkened(steel, 0.25));
  b(L, [0.18, 0.72, 0.15], [0.16, 0.16, 0.16], "#f4f1e6");
  return L;
}

// world.gd samosa and paper ball.
export const SAMOSA: Box[] = [
  { c: [0, 0, 0], s: [0.18, 0.1, 0.18], col: "#e0a050" },
  { c: [0, 0.06, 0], s: [0.1, 0.05, 0.1], col: "#c9853a" },
];
export const PAPER_BALL: Box[] = [
  { c: [0, 0, 0], s: [0.12, 0.12, 0.12], col: "#fbf6e8" },
  { c: [0.03, 0.04, 0.02], s: [0.08, 0.06, 0.1], col: "#e8e0cc" },
];
export const CHAI_GLASS: Box[] = [
  { c: [0, -0.5, -0.1], s: [0.08, 0.11, 0.08], col: "#c68a5c" },
  { c: [0, -0.44, -0.1], s: [0.085, 0.02, 0.085], col: "#e8d2b0" },
];

export function tree(L: Box[], x: number, z: number, seed: number, scale = 1) {
  const h = (1.6 + hash(seed) * 1.2) * scale;
  b(L, [x, h / 2, z], [0.35 * scale, h, 0.35 * scale], P.TRUNK);
  const leaf = P.LEAVES[Math.floor(hash(seed + 1) * 4)];
  const w = (1.6 + hash(seed + 2) * 0.8) * scale;
  b(L, [x, h + w * 0.35, z], [w, w * 0.8, w], leaf);
  b(L, [x + 0.1 * scale, h + w * 0.85, z - 0.1 * scale], [w * 0.6, w * 0.5, w * 0.6], lightened(leaf, 0.08));
}

/** Outside: grass, the compound wall with the main gate, the road and the chai stall across it. */
export function outside(): Box[] {
  const L: Box[] = [];
  for (let x = -30; x < 30; x += 2)
    for (let z = -24; z < 16; z += 2) {
      if (z >= 4 && z < 10) continue; // road strip
      b(L, [x + 1, -0.1, z + 1], [2, 0.2, 2], ((x + z) / 2) & 1 ? P.GRASS : P.GRASS_DARK);
    }
  // Road, with dashes.
  b(L, [0, -0.08, 7], [60, 0.16, 6], P.ASPHALT);
  for (let x = -29; x < 30; x += 3) b(L, [x, 0.005, 7], [1.5, 0.02, 0.18], P.LINE);
  // Pavement.
  b(L, [0, -0.02, 3.6], [60, 0.14, 1.2], "#d9d0bf");
  // Compound wall (BRICK with BRICK_CAP) along z = 2.4, gate gap at x -2..2.
  for (const [x0, x1] of [[-30, -2.2], [2.2, 30]] as const) {
    const cx = (x0 + x1) / 2, w = x1 - x0;
    b(L, [cx, 1.1, 2.4], [w, 2.2, 0.4], P.BRICK);
    b(L, [cx, 2.26, 2.4], [w + 0.05, 0.12, 0.5], P.BRICK_CAP);
    for (let x = x0 + 1; x < x1; x += 2.5) b(L, [x, 1.1, 2.4], [0.5, 2.4, 0.55], darkened(P.BRICK, 0.08));
  }
  // Gate pillars and the open gate.
  for (const s of [-1, 1]) {
    b(L, [s * 2.5, 1.5, 2.4], [0.7, 3.0, 0.7], P.BRICK);
    b(L, [s * 2.5, 3.07, 2.4], [0.85, 0.15, 0.85], P.BRICK_CAP);
    b(L, [s * 3.2, 1.0, 1.5], [0.08, 1.8, 1.6], "#4a4f5a");
  }
  // Gate sign.
  b(L, [0, 3.35, 2.4], [5.6, 0.7, 0.2], "#24315e");
  // Guard booth.
  b(L, [4.6, 1.2, 0.6], [1.6, 2.4, 1.6], P.WALL);
  b(L, [4.6, 2.5, 0.6], [1.9, 0.2, 1.9], P.TRIM);
  b(L, [4.6, 1.5, -0.21], [1.0, 0.8, 0.04], "#bfe8ff");
  // Chai stall across the road (grounds.gd stall, First Day's yellow "CHAI · SUTTA · MAGGI").
  const sx = -7, sz = 12.5;
  b(L, [sx, 1.1, sz], [3.4, 2.2, 2.4], "#ffd24a");
  b(L, [sx, 0.55, sz - 1.35], [3.4, 1.1, 0.3], P.WOOD);
  b(L, [sx, 2.35, sz - 0.2], [3.8, 0.2, 3.0], "#e0524f");
  for (let i = 0; i < 6; i++) b(L, [sx - 1.6 + i * 0.64, 2.15, sz - 1.65], [0.32, 0.3, 0.05], i % 2 ? "#ffffff" : "#e0524f");
  b(L, [sx, 1.6, sz - 1.22], [2.6, 0.5, 0.05], "#24315e");
  // Trees inside the compound and across the road.
  const trees: [number, number][] = [[-9, -4], [-14, -8], [8, -5], [12, -10], [-20, -3], [18, -3], [-5, -12], [6, -14], [-12, 13], [2, 14], [9, 12.5], [-18, 12]];
  trees.forEach(([x, z], i) => tree(L, x, z, i + 3));
  // Bushes along the wall.
  for (let i = 0; i < 10; i++) {
    const x = -26 + i * 5.3 + hash(i) * 1.5;
    if (Math.abs(x) < 4) continue;
    b(L, [x, 0.35, 1.4], [1.1, 0.7, 0.9], P.LEAVES[i % 4]);
  }
  return L;
}

/** art/icon.png as voxels: grass slab on dirt, a brick wall with a sand cap, four flower cubes. */
export function island(): { ground: Box[]; wall: Box[]; flowers: Box[] } {
  const ground: Box[] = [], wall: Box[] = [], flowers: Box[] = [];
  const N = 6, s = 0.5;
  for (let i = 0; i < N; i++)
    for (let j = 0; j < N; j++) {
      const x = (i - (N - 1) / 2) * s, z = (j - (N - 1) / 2) * s;
      const g = hash(i * 7 + j * 13);
      b(ground, [x, -0.15 * 0 + 0.0, z], [s, 0.22, s], g < 0.33 ? "#86c95a" : g < 0.66 ? "#74b04e" : "#8cc45c");
      b(ground, [x, -0.36, z], [s, 0.2, s], g < 0.5 ? "#7a4a2a" : "#6b4028");
      b(ground, [x, -0.62, z], [s, 0.32, s], g < 0.5 ? "#5e3a22" : "#6b4028");
    }
  for (let i = 0; i < 5; i++) {
    const x = -0.75 + i * 0.5;
    for (let k = 0; k < 3; k++) {
      const c = hash(i * 3 + k) < 0.5 ? "#b95c43" : "#a9533e";
      b(wall, [x, 0.36 + k * 0.25, 0.25], [0.5, 0.25, 0.5], c);
    }
    b(wall, [x, 1.06, 0.25], [0.5, 0.15, 0.5], hash(i + 40) < 0.5 ? "#e2c9a6" : "#d9bf96");
  }
  b(flowers, [-1.0, 0.2, -0.9], [0.22, 0.2, 0.22], "#b07cff");
  b(flowers, [-0.7, 0.2, -1.15], [0.22, 0.2, 0.22], "#ff6b8a");
  b(flowers, [0.4, 0.2, -1.1], [0.22, 0.2, 0.22], "#ffd24a");
  b(flowers, [0.2, 0.2, -1.3], [0.22, 0.2, 0.22], "#ffd24a");
  return { ground, wall, flowers };
}

export function clouds(): Box[] {
  const L: Box[] = [];
  const spots: [number, number, number][] = [[-9, 7, -8], [8, 8.5, -10], [-3, 9.5, -16], [13, 6.5, -6], [-14, 5.5, -12], [3, 6, -20]];
  spots.forEach(([x, y, z], i) => {
    const w = 2 + hash(i) * 1.5;
    b(L, [x, y, z], [w, 0.5, w * 0.55], "#ffffff");
    b(L, [x + w * 0.2, y + 0.4, z], [w * 0.55, 0.4, w * 0.4], "#ffffff");
    b(L, [x - w * 0.3, y - 0.05, z + 0.3], [w * 0.45, 0.4, w * 0.35], "#f2f6fa");
  });
  return L;
}
