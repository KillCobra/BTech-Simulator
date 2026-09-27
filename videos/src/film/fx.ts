import { step, type SpringConfig } from "../kit/spring";
import { clamp01 } from "../kit/time";

// Springs. Bunk Master's own UI pops (style pops scale 1.4 -> 1 in 0.18 s), so overshoot is on brand.
export const POP: SpringConfig = { stiffness: 520, damping: 17 };
export const SNAP: SpringConfig = { stiffness: 700, damping: 30 };
export const SOFT: SpringConfig = { stiffness: 160, damping: 22 };
export const HEAVY: SpringConfig = { stiffness: 260, damping: 26 };
export const JELLY: SpringConfig = { stiffness: 380, damping: 11 };

export const sp = (t: number, start: number, cfg: SpringConfig = POP) => step(t - start, cfg);

export const lerp = (a: number, b: number, u: number) => a + (b - a) * u;
export const outExpo = (u: number) => (u >= 1 ? 1 : 1 - Math.pow(2, -10 * clamp01(u)));
export const inExpo = (u: number) => (u <= 0 ? 0 : Math.pow(2, 10 * (clamp01(u) - 1)));
export const outCubic = (u: number) => 1 - Math.pow(1 - clamp01(u), 3);
export const inCubic = (u: number) => Math.pow(clamp01(u), 3);
export const inOutCubic = (u: number) => {
  const x = clamp01(u);
  return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2;
};
export const outBack = (u: number, s = 1.9) => {
  const x = clamp01(u) - 1;
  return 1 + (s + 1) * x * x * x + s * x * x;
};
/** 0 -> 1 over [start, start + len] with the given easing. */
export const ease = (t: number, start: number, len: number, fn: (u: number) => number = outExpo) =>
  fn(clamp01((t - start) / len));

/** A decaying kick: 1 at `at`, gone after ~`decay * 4` s. Sum of these = bumps on beats. */
export const impulse = (t: number, at: number, decay = 0.09) => (t < at ? 0 : Math.exp(-(t - at) / decay));
export const pulses = (t: number, times: readonly number[], decay = 0.09) =>
  times.reduce((sum, at) => sum + impulse(t, at, decay), 0);

/** Deterministic hash noise in [-1, 1]. */
export const hash = (n: number) => {
  const x = Math.sin(n * 127.1 + 311.7) * 43758.5453;
  return (x - Math.floor(x)) * 2 - 1;
};
/** Smooth value noise in [-1, 1]. */
export const noise1 = (x: number, seed = 0) => {
  const i = Math.floor(x);
  const f = x - i;
  const u = f * f * (3 - 2 * f);
  return lerp(hash(i + seed * 57), hash(i + 1 + seed * 57), u);
};

/** Camera shake: a trauma value that decays from each hit, driving smooth noise. */
export function shake(t: number, hits: readonly (readonly [number, number])[], freq = 22) {
  let trauma = 0;
  for (const [at, amount] of hits) if (t >= at) trauma += amount * Math.exp(-(t - at) / 0.22);
  trauma = Math.min(trauma, 1.4);
  const k = trauma * trauma;
  return {
    x: noise1(t * freq, 1) * 26 * k,
    y: noise1(t * freq, 2) * 20 * k,
    r: noise1(t * freq, 3) * 1.6 * k,
  };
}

/** Squash and stretch for a landing: returns [sx, sy]. */
export const squash = (t: number, at: number, amount = 0.28) => {
  if (t < at) return [1, 1] as const;
  const d = t - at;
  const w = Math.exp(-d / 0.09) * Math.cos(d * 38);
  return [1 + amount * w, 1 - amount * w] as const;
};

export const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));
export { clamp01 };
