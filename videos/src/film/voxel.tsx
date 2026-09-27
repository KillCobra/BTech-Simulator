// The game's icon/splash diorama (art/make_art.py) rebuilt block by block, so every voxel can move.
// Same isometric projection and face shading as Voxels.render in make_art.py.
import React from "react";
import vox from "./voxels.json";

type V = [number, number, number, string, string];
export type VoxelAnim = (x: number, y: number, z: number, i: number) => { dy?: number; dx?: number; s?: number; o?: number } | null;

const rgb = (h: string) => {
  const n = parseInt(h.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
};
const shade = (h: string, k: number) => {
  const [r, g, b] = rgb(h).map((v) => Math.max(0, Math.min(255, Math.round(v * k))));
  return `rgb(${r},${g},${b})`;
};

type Prepared = { x: number; y: number; z: number; top: string; left: string; right: string };

function prepare(list: V[]): Prepared[] {
  const set = new Set(list.map(([x, y, z]) => `${x},${y},${z}`));
  const has = (x: number, y: number, z: number) => set.has(`${x},${y},${z}`);
  return [...list]
    .sort((a, b) => a[0] + a[1] + a[2] - (b[0] + b[1] + b[2]) || a[2] - b[2])
    .map(([x, y, z, top, front]) => {
      const occ = [[1, 0], [-1, 0], [0, 1], [0, -1]].filter(([dx, dy]) => has(x + dx, y + dy, z + 1)).length;
      return { x, y, z, top: shade(top, 1 - 0.06 * occ), left: shade(front, 0.86), right: shade(top, 0.7) };
    });
}

const SCENES = { hero: prepare(vox.hero as V[]), icon: prepare(vox.icon as V[]) };

export function voxelBounds(scene: keyof typeof SCENES, a: number) {
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  for (const v of SCENES[scene]) {
    const cx = (v.x - v.y) * a, cy = ((v.x + v.y) * a) / 2 - v.z * a;
    x0 = Math.min(x0, cx - a); x1 = Math.max(x1, cx + a);
    y0 = Math.min(y0, cy - a / 2); y1 = Math.max(y1, cy + a * 1.5);
  }
  return { x0, y0, x1, y1, w: x1 - x0, h: y1 - y0 };
}

/** Renders the scene centred in a `width` x `height` box. `anim` moves each block (screen px). */
export const Voxels: React.FC<{ scene: keyof typeof SCENES; a: number; width: number; height: number; anim?: VoxelAnim; style?: React.CSSProperties }> = ({
  scene, a, width, height, anim, style,
}) => {
  const bb = voxelBounds(scene, a);
  const ox = width / 2 - (bb.x0 + bb.x1) / 2;
  const oy = height / 2 - (bb.y0 + bb.y1) / 2;
  const polys: React.ReactNode[] = [];
  SCENES[scene].forEach((v, i) => {
    const m = anim ? anim(v.x, v.y, v.z, i) : {};
    if (m === null || (m.o ?? 1) <= 0) return;
    const s = m.s ?? 1;
    const cx = ox + (v.x - v.y) * a + (m.dx ?? 0);
    const cy = oy + ((v.x + v.y) * a) / 2 - v.z * a + (m.dy ?? 0);
    const e = a * s;
    // centre of the cube in screen space sits at (cx, cy + a/2); scale about it
    const my = cy + a / 2;
    const P = (px: number, py: number) => `${cx + px * s},${my + py * s}`;
    const o = m.o ?? 1;
    polys.push(
      <g key={i} opacity={o < 1 ? o : undefined}>
        <polygon points={`${P(0, -a)} ${P(a, -a / 2)} ${P(0, 0)} ${P(-a, -a / 2)}`} fill={v.top} stroke={v.top} strokeWidth={0.6} />
        <polygon points={`${P(-a, -a / 2)} ${P(0, 0)} ${P(0, a)} ${P(-a, a / 2)}`} fill={v.left} stroke={v.left} strokeWidth={0.6} />
        <polygon points={`${P(0, 0)} ${P(a, -a / 2)} ${P(a, a / 2)} ${P(0, a)}`} fill={v.right} stroke={v.right} strokeWidth={0.6} />
      </g>,
    );
    void e;
  });
  return (
    <svg width={width} height={height} style={{ overflow: "visible", ...style }}>
      {polys}
    </svg>
  );
};

/** One loose voxel cube (for bursts and clouds), centred at 0,0. */
export const Cube: React.FC<{ a: number; color: string; x?: number; y?: number; rot?: number; o?: number }> = ({ a, color, x = 0, y = 0, rot = 0, o = 1 }) => (
  <g transform={`translate(${x} ${y}) rotate(${rot})`} opacity={o}>
    <polygon points={`0,${-a} ${a},${-a / 2} 0,0 ${-a},${-a / 2}`} fill={color} />
    <polygon points={`${-a},${-a / 2} 0,0 0,${a} ${-a},${a / 2}`} fill={shade(color, 0.86)} />
    <polygon points={`0,0 ${a},${-a / 2} ${a},${a / 2} 0,${a}`} fill={shade(color, 0.7)} />
  </g>
);

/** A voxel cloud like make_art.cloud(): a 2-deep slab with a narrower slab on top. */
export const Cloud: React.FC<{ a: number; w: number; x: number; y: number; o?: number }> = ({ a, w, x, y, o = 1 }) => {
  const cells: [number, number, number][] = [];
  for (let i = 0; i <= w; i++) for (let j = 0; j <= 1; j++) cells.push([i, j, 0]);
  for (let i = 1; i <= w - 1; i++) for (let j = 0; j <= 1; j++) cells.push([i, j, 1]);
  cells.sort((p, q) => p[0] + p[1] + p[2] - (q[0] + q[1] + q[2]) || p[2] - q[2]);
  return (
    <g transform={`translate(${x} ${y})`} opacity={o}>
      {cells.map(([i, j, k], n) => (
        <Cube key={n} a={a} color="#ffffff" x={(i - j) * a} y={((i + j) * a) / 2 - k * a} />
      ))}
    </g>
  );
};
