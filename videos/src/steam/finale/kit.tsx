// Finale helpers: time warp (speed ramps), 3D labels, voxel confetti and dust, 2D speed lines, shake.
// Everything is a pure function of t.
import ADVANCES from "../jersey-advances.json";
import React, { useMemo } from "react";
import * as THREE from "three";
import { G, Voxels } from "../../launch/three";
import type { Box, V3 } from "../../launch/voxel";

export const PI = Math.PI;
export const clamp01 = (v: number) => Math.min(1, Math.max(0, v));
export const lerp = (a: number, b: number, u: number) => a + (b - a) * u;
export const smooth = (u: number) => {
  const x = clamp01(u);
  return x * x * (3 - 2 * x);
};
export const outCubic = (u: number) => 1 - Math.pow(1 - clamp01(u), 3);
export const inCubic = (u: number) => Math.pow(clamp01(u), 3);
export const outExpo = (u: number) => (u >= 1 ? 1 : 1 - Math.pow(2, -10 * clamp01(u)));
export const inExpo = (u: number) => (u <= 0 ? 0 : Math.pow(2, 10 * clamp01(u) - 10));
export const lerp3 = (a: V3, c: V3, u: number): V3 => [lerp(a[0], c[0], u), lerp(a[1], c[1], u), lerp(a[2], c[2], u)];

/** Deterministic hash in [0, 1). */
export const rnd = (n: number) => {
  const x = Math.sin(n * 127.1 + 311.7) * 43758.5453;
  return x - Math.floor(x);
};

function erf(x: number) {
  const s = Math.sign(x);
  const a = Math.abs(x);
  const k = 1 / (1 + 0.3275911 * a);
  const y = 1 - ((((1.061405429 * k - 1.453152027) * k + 1.421413741) * k - 0.284496736) * k + 0.254829592) * k * Math.exp(-a * a);
  return s * y;
}

/**
 * Speed ramp: clock time since `t0` where the rate dips to (1 - k) around `c` (gaussian, width w).
 * Closed form, so every frame is still a pure function of t.
 */
export const warp = (t: number, t0: number, c: number, k: number, w: number) =>
  t - t0 - k * w * (Math.sqrt(PI) / 2) * (erf((t - c) / w) - erf((t0 - c) / w));

/** Screen shake (px, deg) from impulses [time, amount]; smooth noise so it reads at 60 fps. */
const n1 = (x: number, seed: number) => {
  const i = Math.floor(x);
  const f = x - i;
  const u = f * f * (3 - 2 * f);
  return lerp(rnd(i + seed * 57) * 2 - 1, rnd(i + 1 + seed * 57) * 2 - 1, u);
};
export function shake(t: number, hits: readonly (readonly [number, number])[], freq = 24) {
  let trauma = 0;
  for (const [at, amount] of hits) if (t >= at) trauma += amount * Math.exp(-(t - at) / 0.2);
  trauma = Math.min(trauma, 1.5);
  const k = trauma * trauma;
  return { x: n1(t * freq, 1) * 34 * k, y: n1(t * freq, 2) * 26 * k, r: n1(t * freq, 3) * 1.8 * k };
}

export function textTexture(text: string, opts: { w: number; h: number; size: number; color: string; bg?: string }) {
  const c = document.createElement("canvas");
  c.width = opts.w;
  c.height = opts.h;
  const g = c.getContext("2d")!;
  if (opts.bg) {
    g.fillStyle = opts.bg;
    g.fillRect(0, 0, opts.w, opts.h);
  }
  g.fillStyle = opts.color;
  g.font = `${opts.size}px Jersey10`;
  g.textAlign = "center";
  g.textBaseline = "middle";
  g.fillText(text, opts.w / 2, opts.h / 2 + opts.size * 0.05);
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 8;
  return tex;
}

/** A flat text sign in the world (gate sign, stall board). */
export const Label: React.FC<{ text: string; p: V3; w: number; h: number; yaw?: number; color: string; bg?: string; px?: number }> = ({ text, p, w, h, yaw = 0, color, bg, px = 140 }) => {
  const tex = useMemo(() => textTexture(text, { w: Math.round(w * 200), h: Math.round(h * 200), size: px, color, bg }), [text, w, h, color, bg, px]);
  return (
    <mesh position={p} rotation={[0, yaw, 0]}>
      <planeGeometry args={[w, h]} />
      <meshBasicMaterial map={tex} transparent toneMapped={false} />
    </mesh>
  );
};

const CONFETTI_COLS = ["#e0524f", "#4f86e0", "#48b06a", "#9a62d6", "#ffd24a", "#ffffff", "#ff9a3c"];
const confettiBoxes: Box[][] = Array.from({ length: 90 }, (_, i) => [{ c: [0, 0, 0], s: [0.16, 0.16, 0.05], col: CONFETTI_COLS[i % CONFETTI_COLS.length] }]);

/** Voxel confetti: a burst of flat cubes with drag and slow fall, tumbling. */
export const Confetti: React.FC<{ t: number; at: number; origin: V3; n?: number; power?: number; seed?: number; up?: number }> = ({ t, at, origin, n = 80, power = 1, seed = 0, up = 1 }) => {
  const d = t - at;
  if (d < 0 || d > 3.2) return null;
  return (
    <>
      {confettiBoxes.slice(0, n).map((bx, i) => {
        const a = rnd(i + seed) * PI * 2, v = (3 + rnd(i + 3 + seed) * 6) * power;
        const vx = Math.cos(a) * v * 0.8, vz = Math.sin(a) * v * 0.6, vy = (6 + rnd(i + 7 + seed) * 7) * up;
        const drag = (1 - Math.exp(-d * 2.4)) / 2.4;
        const y = origin[1] + vy * drag - 1.6 * d * d;
        if (y < 0) return null;
        const flutter = Math.sin(d * 9 + i) * 0.25 * clamp01(d - 0.4);
        return (
          <G key={i} p={[origin[0] + vx * drag + flutter, y, origin[2] + vz * drag]} r={[d * (5 + rnd(i) * 9), d * 6 + i, d * 4]}>
            <Voxels boxes={bx} shadow={false} />
          </G>
        );
      })}
    </>
  );
};

const dustBox: Box[] = [{ c: [0, 0, 0], s: [0.22, 0.22, 0.22], col: "#f4f1e6" }];
/** Little voxel dust puffs where a foot (or a face) hits the ground. */
export const Dust: React.FC<{ t: number; at: number; p: V3; n?: number; spread?: number; seed?: number }> = ({ t, at, p, n = 8, spread = 1, seed = 0 }) => {
  const d = t - at;
  if (d < 0 || d > 0.7) return null;
  const e = 1 - Math.exp(-d * 7);
  const s = Math.max(0.001, (1 - d / 0.7) * 1.3);
  return (
    <>
      {Array.from({ length: n }, (_, i) => {
        const a = (i / n) * PI * 2 + rnd(i + seed) * 0.6;
        const r = (0.5 + rnd(i + 11 + seed) * 0.7) * spread * e;
        return (
          <G key={i} p={[p[0] + Math.cos(a) * r, p[1] + 0.12 + e * (0.25 + rnd(i + seed) * 0.35), p[2] + Math.sin(a) * r]} s={s * (0.6 + rnd(i + 5) * 0.6)} r={[d * 3, i, 0]}>
            <Voxels boxes={dustBox} shadow={false} />
          </G>
        );
      })}
    </>
  );
};

/** Streaks flying across the frame (horizontal): direction -1 = streaks move left. */
export const SpeedLines: React.FC<{ t: number; t0: number; o?: number; dir?: 1 | -1; n?: number; seed?: number; color?: string }> = ({ t, t0, o = 1, dir = -1, n = 26, seed = 0, color = "#ffffff" }) => {
  if (o <= 0.01) return null;
  return (
    <svg width={1920} height={1080} style={{ position: "absolute", inset: 0, pointerEvents: "none", opacity: o }}>
      {Array.from({ length: n }, (_, i) => {
        const y = 30 + rnd(i * 3 + seed) * 1020;
        const speed = 3200 + rnd(i + 1 + seed) * 2600;
        const len = 220 + rnd(i + 2 + seed) * 520;
        const h = 4 + rnd(i + 4 + seed) * 7;
        const run = ((t - t0) * speed + rnd(i + 3 + seed) * 3600) % 3600;
        const x = dir < 0 ? 2300 - run : -700 + run;
        return <rect key={i} x={x} y={y} width={len} height={h} rx={h / 2} fill={color} opacity={0.5 + rnd(i + 9) * 0.4} />;
      })}
    </svg>
  );
};

/** Radial zoom lines (manga focus lines) around a point, rushing outward. */
export const ZoomLines: React.FC<{ t: number; x?: number; y?: number; o?: number; n?: number; inner?: number; color?: string }> = ({ t, x = 960, y = 540, o = 1, n = 48, inner = 380, color = "#ffffff" }) => {
  if (o <= 0.01) return null;
  return (
    <svg width={1920} height={1080} style={{ position: "absolute", inset: 0, pointerEvents: "none", opacity: o }}>
      {Array.from({ length: n }, (_, i) => {
        const a = (i / n) * PI * 2 + rnd(i) * 0.12;
        const cyc = (t * (2.2 + rnd(i + 5) * 1.6) + rnd(i + 2)) % 1;
        const r0 = inner + rnd(i + 7) * 220 + cyc * 600;
        const r1 = r0 + 260 + rnd(i + 3) * 400;
        const w = 3 + rnd(i + 8) * 9;
        const px = Math.cos(a + PI / 2) * w, py = Math.sin(a + PI / 2) * w;
        const ax = x + Math.cos(a) * r0, ay = y + Math.sin(a) * r0 * 0.9;
        const bx = x + Math.cos(a) * r1, by = y + Math.sin(a) * r1 * 0.9;
        return <polygon key={i} points={`${ax},${ay} ${bx + px},${by + py} ${bx - px},${by - py}`} fill={color} opacity={0.35 + 0.4 * (1 - cyc)} />;
      })}
    </svg>
  );
};

/** Full-frame flash that decays. */
export const Flash: React.FC<{ t: number; at: number; color?: string; dur?: number; peak?: number }> = ({ t, at, color = "#ffffff", dur = 0.2, peak = 1 }) => {
  const u = (t - at) / dur;
  if (u < 0 || u > 1) return null;
  return <div style={{ position: "absolute", inset: 0, background: color, opacity: peak * (1 - outCubic(u)), pointerEvents: "none" }} />;
};

/**
 * Title text the way Godot draws the logo (main.gd): fill over a round-joined outline (SVG stroke with
 * linejoin round, painted under the fill) and a hard drop shadow. CSS text-stroke would give mitred boxes.
 * `w` is the box width (the text is centred in it); `line` the box height.
 */
const ADV = ADVANCES.advance as Record<string, number>;

export const InkText: React.FC<{
  text: string; size: number; w?: number; color?: string; ink?: string; stroke?: number; shadow?: number; shadowColor?: string; spacing?: number; style?: React.CSSProperties;
}> = ({ text, size, w: wIn, color = "#ffc93c", ink = "#2a1a0e", stroke = 0.1, shadow = 0.1, shadowColor = "rgba(0,0,0,0.45)", spacing = 0, style }) => {
  const h = size * 1.0;
  const w = wIn ?? measure(text, size, spacing) + size * stroke * 2;
  const sw = size * stroke * 2;
  const common = { x: w / 2, y: h * 0.55, textAnchor: "middle" as const, dominantBaseline: "middle" as const, fontFamily: "Jersey10", fontSize: size, letterSpacing: spacing };
  return (
    <svg width={w} height={h} style={{ display: "block", overflow: "visible", ...style }}>
      {shadow > 0 ? (
        <text {...common} y={common.y + size * shadow} fill={shadowColor} stroke={shadowColor} strokeWidth={sw} strokeLinejoin="round">{text}</text>
      ) : null}
      <text {...common} fill={color} stroke={ink} strokeWidth={sw} strokeLinejoin="round" paintOrder="stroke">{text}</text>
    </svg>
  );
};

/**
 * Width of a line of Jersey10 from the font file's own advance widths (src/steam/jersey-advances.json,
 * extracted with fontTools). Deliberately not canvas measureText: in long renders the browser sometimes
 * measured with a fallback font on a few frames, shifting centred words and leaving ghosts after motion blur.
 */
export function measure(text: string, size: number, spacing = 0) {
  let w = 0;
  for (const ch of text) w += (ADV[ch] ?? 0.5) * size;
  return w + spacing * text.length;
}
