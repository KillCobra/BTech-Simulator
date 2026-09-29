// Advanced motion design utilities for showreel
// All frame-driven, deterministic, no randomness unless seeded

import { C, W, H } from "./tokens";

/** Spring physics - critically damped with optional overshoot */
export function spring(
  t: number,
  start: number,
  { stiffness = 300, damping = 20, mass = 1, overshoot = 0 }: { stiffness?: number; damping?: number; mass?: number; overshoot?: number } = {}
): number {
  const w0 = Math.sqrt(stiffness / mass);
  const zeta = damping / (2 * Math.sqrt(stiffness * mass));
  const dt = t;
  
  if (zeta >= 1) {
    // Overdamped
    const s1 = -w0 * zeta + w0 * Math.sqrt(zeta * zeta - 1);
    const s2 = -w0 * zeta - w0 * Math.sqrt(zeta * zeta - 1);
    return 1 - (s2 * Math.exp(s1 * dt) - s1 * Math.exp(s2 * dt)) / (s2 - s1);
  } else {
    // Underdamped (overshoot)
    const wd = w0 * Math.sqrt(1 - zeta * zeta);
    const amp = Math.exp(-w0 * zeta * dt);
    const phase = wd * dt;
    const cos = Math.cos(phase);
    const sin = Math.sin(phase);
    const base = 1 - amp * (cos + (zeta / Math.sqrt(1 - zeta * zeta)) * sin);
    return base + overshoot * amp * sin * 0.3;
  }
}

/** Jelly spring - bouncy, playful */
export const jelly = (t: number, start: number) => spring(t - start, 0, { stiffness: 420, damping: 16, overshoot: 0.4 });

/** Pop spring - quick, snappy */
export const pop = (t: number, start: number) => spring(t - start, 0, { stiffness: 600, damping: 22, overshoot: 0.2 });

/** Snap spring - fast, minimal overshoot */
export const snap = (t: number, start: number) => spring(t - start, 0, { stiffness: 800, damping: 30, overshoot: 0.1 });

/** Heavy spring - slow, deliberate */
export const heavy = (t: number, start: number) => spring(t - start, 0, { stiffness: 180, damping: 18, overshoot: 0 });

/** Elastic spring - very bouncy */
export const elastic = (t: number, start: number) => spring(t - start, 0, { stiffness: 350, damping: 8, overshoot: 0.6 });

/** Clamp 0-1 */
export const clamp01 = (v: number) => Math.max(0, Math.min(1, v));

/** Smoothstep */
export const smoothstep = (t: number) => t * t * (3 - 2 * t);

/** Smootherstep */
export const smootherstep = (t: number) => t * t * t * (t * (6 * t - 15) + 10);

/** Cubic bezier approximation */
export const cubicBezier = (t: number, x1: number, y1: number, x2: number, y2: number) => {
  // Simplified: use key splines
  const cx = 3 * x1;
  const bx = 3 * (x2 - x1) - cx;
  const ax = 1 - cx - bx;
  const cy = 3 * y1;
  const by = 3 * (y2 - y1) - cy;
  const ay = 1 - cy - by;
  return ((ay * t + by) * t + cy) * t;
};

/** Pulse on beats - returns 0-1 envelope */
export function pulse(t: number, beatTime: number, decay = 0.08): number {
  const dt = t - beatTime;
  if (dt < 0) return 0;
  return Math.exp(-dt / decay);
}

/** Multiple pulses summed */
export function pulses(t: number, beats: number[], decay = 0.08): number {
  return beats.reduce((sum, b) => sum + pulse(t, b, decay), 0);
}

/** Squash and stretch - returns [scaleX, scaleY] */
export function squash(t: number, impactTime: number, duration = 0.3): [number, number] {
  const dt = t - impactTime;
  if (dt < 0 || dt > duration) return [1, 1];
  const u = dt / duration;
  const squeeze = Math.sin(u * Math.PI) * 0.3;
  return [1 + squeeze, 1 - squeeze * 0.8];
}

/** Shake/trauma - returns { x, y, rotation } */
export function trauma(t: number, hits: [number, number][], decay = 0.12): { x: number; y: number; r: number } {
  let trauma = 0;
  for (const [hitTime, strength] of hits) {
    const dt = t - hitTime;
    if (dt >= 0) trauma += strength * Math.exp(-dt / decay);
  }
  trauma = Math.min(trauma, 1);
  const seed = t * 123.456;
  return {
    x: Math.sin(seed * 7.1) * trauma * 30,
    y: Math.cos(seed * 5.3) * trauma * 22,
    r: Math.sin(seed * 3.7) * trauma * 4,
  };
}

/** Noise helper */
export function noise1(t: number, seed = 0): number {
  const n = Math.sin(t * 12.9898 + seed * 78.233) * 43758.5453;
  return (n - Math.floor(n)) * 2 - 1;
}

/** 2D noise */
export function noise2(x: number, y: number): number {
  const n = Math.sin(x * 12.9898 + y * 78.233) * 43758.5453;
  return (n - Math.floor(n)) * 2 - 1;
}

/** Lerp */
export const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

/** Color lerp */
export function lerpColor(a: string, b: string, t: number): string {
  const parse = (c: string) => {
    const m = c.match(/^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i);
    if (!m) return [0, 0, 0];
    return [parseInt(m[1], 16), parseInt(m[2], 16), parseInt(m[3], 16)];
  };
  const [r1, g1, b1] = parse(a);
  const [r2, g2, b2] = parse(b);
  const r = Math.round(lerp(r1, r2, t));
  const g = Math.round(lerp(g1, g2, t));
  const b = Math.round(lerp(b1, b2, t));
  return `#${r.toString(16).padStart(2, "0")}${g.toString(16).padStart(2, "0")}${b.toString(16).padStart(2, "0")}`;
}

/** Flash - white overlay */
export function flash(t: number, at: number, dur: number, peak = 1): number {
  const dt = t - at;
  if (dt < 0 || dt > dur) return 0;
  const u = dt / dur;
  return peak * Math.sin(u * Math.PI);
}

/** Stagger delay for index */
export const stagger = (index: number, base = 0, step = 0.05) => base + index * step;

/** Wrap value */
export const wrap = (v: number, min: number, max: number) => {
  const range = max - min;
  return ((v - min) % range + range) % range + min;
};

/** Ease out elastic for entrances */
export const easeOutElastic = (t: number) => {
  const c4 = (2 * Math.PI) / 3;
  return t === 0 ? 0 : t === 1 ? 1 : Math.pow(2, -10 * t) * Math.sin((t * 10 - 0.75) * c4) + 1;
};

/** Ease in back for exits */
export const easeInBack = (t: number) => {
  const c1 = 1.70158;
  const c3 = c1 + 1;
  return c3 * t * t * t - c1 * t * t;
};

/** Ease out back for entrances */
export const easeOutBack = (t: number) => {
  const c1 = 1.70158;
  const c3 = c1 + 1;
  return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2);
};

/** Beat-synchronized scale bump */
export function beatBump(t: number, beats: number[], amount = 0.08, decay = 0.08): number {
  return 1 + amount * pulses(t, beats, decay);
}

/** Directional wipe */
export function wipe(t: number, start: number, dur: number, dir: "left" | "right" | "up" | "down" = "left"): number {
  const dt = t - start;
  if (dt < 0) return dir === "left" || dir === "up" ? 0 : 1;
  if (dt > dur) return dir === "left" || dir === "up" ? 1 : 0;
  return smoothstep(dt / dur);
}

/** Morph between two values with spring */
export function morph(t: number, start: number, from: number, to: number, springConfig = { stiffness: 400, damping: 20 }): number {
  const progress = spring(t - start, 0, springConfig);
  return lerp(from, to, clamp01(progress));
}

/** Orbit position */
export function orbit(t: number, radius: number, speed: number, offset = 0): { x: number; y: number } {
  const angle = (t * speed + offset) * Math.PI * 2;
  return { x: Math.cos(angle) * radius, y: Math.sin(angle) * radius };
}

/** Parallax offset */
export function parallax(t: number, depth: number, speed = 1): { x: number; y: number } {
  return {
    x: Math.sin(t * 0.7 * speed) * 50 * depth,
    y: Math.cos(t * 0.5 * speed) * 30 * depth,
  };
}

/** Glitch offset - random but deterministic */
export function glitch(t: number, intensity: number, seed = 0): { x: number; y: number; slice?: { y: number; h: number; x: number } } {
  const n = noise1(t * 60, seed);
  if (n > 0.95) {
    return {
      x: (noise1(t * 100, seed + 1) - 0.5) * intensity * 40,
      y: (noise1(t * 100, seed + 2) - 0.5) * intensity * 20,
      slice: n > 0.98 ? { y: Math.random() * H, h: 20 + Math.random() * 60, x: (Math.random() - 0.5) * 100 } : undefined,
    };
  }
  return { x: 0, y: 0 };
}

/** Text reveal - per character */
export function charReveal(t: number, start: number, index: number, total: number, staggerMs = 30): number {
  const charStart = start + (index / total) * staggerMs / 1000;
  const dt = t - charStart;
  if (dt < 0) return 0;
  return clamp01(spring(dt, 0, { stiffness: 500, damping: 25, overshoot: 0.15 }));
}

/** Counter number animation */
export function countNumber(t: number, start: number, end: number, duration: number, easeFn = smoothstep): number {
  const dt = t;
  if (dt < 0) return start;
  if (dt > duration) return end;
  return lerp(start, end, easeFn(dt / duration));
}

/** Path follow - returns position along path */
export function followPath(t: number, start: number, duration: number, path: { x: number; y: number }[]): { x: number; y: number } {
  const dt = t - start;
  if (dt <= 0) return path[0];
  if (dt >= duration) return path[path.length - 1];
  const u = dt / duration;
  const index = u * (path.length - 1);
  const i = Math.floor(index);
  const localU = index - i;
  if (i >= path.length - 1) return path[path.length - 1];
  return {
    x: lerp(path[i].x, path[i + 1].x, smoothstep(localU)),
    y: lerp(path[i].y, path[i + 1].y, smoothstep(localU)),
  };
}

/** Random but deterministic choice */
export function seededChoice<T>(arr: T[], seed: number): T {
  let x = Math.sin(seed * 123.456) * 43758.5453;
  x = x - Math.floor(x);
  return arr[Math.floor(x * arr.length)];
}

/** Deterministic random float */
export function seededRandom(seed: number, min = 0, max = 1): number {
  let x = Math.sin(seed * 12345.6789) * 98765.4321;
  x = x - Math.floor(x);
  return min + x * (max - min);
}

/** Deterministic random int */
export function seededRandomInt(seed: number, min: number, max: number): number {
  return Math.floor(seededRandom(seed, min, max + 1));
}