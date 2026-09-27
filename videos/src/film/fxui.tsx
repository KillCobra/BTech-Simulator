// Shared motion pieces: pixel wipes, bursts of voxel cubes, shockwaves, rays, iris.
import React from "react";
import { clamp01 } from "../kit/time";
import { hash, outBack, outCubic, outExpo } from "./fx";
import { H, W } from "./tokens";
import { Cube } from "./voxel";

/**
 * A grid of squares that grow (cover) or shrink (reveal), staggered by distance from `origin`.
 * Pixel/voxel-flavoured transition, the game's own chunky look.
 */
export const PixelWipe: React.FC<{
  t: number;
  start: number;
  dur?: number;
  color: string;
  mode: "cover" | "reveal";
  cell?: number;
  origin?: [number, number];
}> = ({ t, start, dur = 0.45, color, mode, cell = 120, origin = [W / 2, H / 2] }) => {
  if (mode === "reveal" && t > start + dur + 0.05) return null;
  if (mode === "cover" && t < start) return null;
  const cols = Math.ceil(W / cell) + 1;
  const rows = Math.ceil(H / cell) + 1;
  const maxD = Math.hypot(W, H) * 0.6;
  const rects: React.ReactNode[] = [];
  for (let i = 0; i < cols; i++)
    for (let j = 0; j < rows; j++) {
      const cx = i * cell + cell / 2, cy = j * cell + cell / 2;
      const d = Math.hypot(cx - origin[0], cy - origin[1]) / maxD;
      const jitter = (hash(i * 31 + j * 17) + 1) * 0.06;
      const local = clamp01((t - start - (d * 0.6 + jitter) * dur) / (dur * 0.45));
      const s = mode === "cover" ? outCubic(local) : 1 - outCubic(local);
      if (s <= 0.001) continue;
      const size = cell * s * 1.02;
      rects.push(
        <rect key={`${i}-${j}`} x={cx - size / 2} y={cy - size / 2} width={size} height={size} fill={color} transform={`rotate(${(1 - s) * 45} ${cx} ${cy})`} />,
      );
    }
  return (
    <svg width={W} height={H} style={{ position: "absolute", inset: 0 }}>
      {rects}
    </svg>
  );
};

/** Voxel cubes bursting out of a point with gravity; deterministic per `seed`. */
export const Burst: React.FC<{ t: number; at: number; x: number; y: number; colors: string[]; n?: number; seed?: number; power?: number; size?: number }> = ({
  t, at, x, y, colors, n = 18, seed = 1, power = 900, size = 16,
}) => {
  const d = t - at;
  if (d < 0 || d > 1.4) return null;
  return (
    <svg width={W} height={H} style={{ position: "absolute", inset: 0, overflow: "visible", pointerEvents: "none" }}>
      {Array.from({ length: n }, (_, i) => {
        const a = (i / n) * Math.PI * 2 + hash(seed * 13 + i) * 0.5;
        const v = power * (0.55 + 0.45 * (hash(seed * 7 + i * 3) + 1) / 2);
        const px = x + Math.cos(a) * v * d * Math.exp(-d * 1.6);
        const py = y + Math.sin(a) * v * d * Math.exp(-d * 1.6) + 900 * d * d;
        const s = size * (0.6 + 0.5 * (hash(seed + i * 5) + 1) / 2) * (1 - clamp01((d - 0.5) / 0.7));
        return <Cube key={i} a={s} color={colors[i % colors.length]} x={px} y={py} rot={hash(i + seed) * 180 * d * 3} />;
      })}
    </svg>
  );
};

/** An expanding ring. */
export const Shockwave: React.FC<{ t: number; at: number; x: number; y: number; color?: string; r?: number; width?: number; dur?: number }> = ({
  t, at, x, y, color = "#ffffff", r = 700, width = 40, dur = 0.5,
}) => {
  const u = (t - at) / dur;
  if (u < 0 || u > 1) return null;
  const e = outExpo(u);
  return (
    <svg width={W} height={H} style={{ position: "absolute", inset: 0, pointerEvents: "none" }}>
      <circle cx={x} cy={y} r={r * e} fill="none" stroke={color} strokeWidth={width * (1 - u)} opacity={1 - u * 0.6} />
    </svg>
  );
};

/** Comic "speed" rays spinning slowly behind a hit. */
export const Rays: React.FC<{ t: number; x: number; y: number; color: string; n?: number; o?: number; spin?: number; r?: number }> = ({
  t, x, y, color, n = 18, o = 1, spin = 12, r = 1600,
}) => (
  <svg width={W} height={H} style={{ position: "absolute", inset: 0, opacity: o }}>
    <g transform={`translate(${x} ${y}) rotate(${t * spin})`}>
      {Array.from({ length: n }, (_, i) => {
        const a0 = (i / n) * Math.PI * 2, a1 = a0 + (Math.PI / n) * 0.9;
        return <polygon key={i} points={`0,0 ${Math.cos(a0) * r},${Math.sin(a0) * r} ${Math.cos(a1) * r},${Math.sin(a1) * r}`} fill={color} />;
      })}
    </g>
  </svg>
);

/** Full-screen flash that decays. */
export const Flash: React.FC<{ t: number; at: number; color?: string; dur?: number; peak?: number }> = ({ t, at, color = "#ffffff", dur = 0.22, peak = 1 }) => {
  const u = (t - at) / dur;
  if (u < 0 || u > 1) return null;
  return <div style={{ position: "absolute", inset: 0, background: color, opacity: peak * (1 - outCubic(u)) }} />;
};

/** A colour flood that grows as a circle from a point (a bar-change wipe). */
export const Iris: React.FC<{ t: number; at: number; x: number; y: number; color: string; dur?: number }> = ({ t, at, x, y, color, dur = 0.32 }) => {
  if (t < at) return null;
  const u = outCubic((t - at) / dur);
  const r = Math.hypot(W, H) * 1.05 * u;
  return (
    <svg width={W} height={H} style={{ position: "absolute", inset: 0 }}>
      <circle cx={x} cy={y} r={r} fill={color} />
    </svg>
  );
};

/** Scale for "slam" entries: from `from` down to 1 with overshoot. */
export const slam = (t: number, at: number, from = 2.4, len = 0.28) => {
  if (t < at) return 0;
  const u = clamp01((t - at) / len);
  return 1 + (from - 1) * (1 - outBack(u, 2.2));
};
