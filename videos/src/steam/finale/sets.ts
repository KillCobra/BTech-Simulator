// The campus edge for the finale: a copy of launch/sets.ts outside() (grass, compound wall, main gate, road,
// chai stall) with the trees moved off the chase line and the camera paths.
import { darkened, P, type Box, type V3 } from "../../launch/voxel";
import { hash, tree } from "../../launch/sets";

const b = (list: Box[], c: V3, s: V3, col: string) => list.push({ c, s, col });

/** Outside: grass, the compound wall with the main gate, the road and the chai stall across it. */
export function campus(): Box[] {
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
  const trees: [number, number][] = [[-9, -5], [-14, -8], [8, -17], [14, -21], [-20, -3], [23, -19], [-5, -12], [6, -16], [-12, 13], [2, 14], [9, 12.5], [-18, 12], [16, 16], [-26, 14]];
  trees.forEach(([x, z], i) => tree(L, x, z, i + 3));
  // Bushes along the wall.
  for (let i = 0; i < 10; i++) {
    const x = -26 + i * 5.3 + hash(i) * 1.5;
    if (Math.abs(x) < 4) continue;
    b(L, [x, 0.35, 1.4], [1.1, 0.7, 0.9], P.LEAVES[i % 4]);
  }
  return L;
}

