// Motion helpers. All closed-form functions of time.
import { step, type SpringConfig } from "../kit/spring";

export const clamp01 = (v: number) => Math.min(1, Math.max(0, v));
export const lerp = (a: number, b: number, u: number) => a + (b - a) * u;
export const prog = (t: number, a: number, len: number) => clamp01((t - a) / len);
export const easeOut = (u: number) => 1 - Math.pow(1 - clamp01(u), 3);
export const easeIn = (u: number) => Math.pow(clamp01(u), 3);
export const easeInOut = (u: number) => {
  u = clamp01(u);
  return u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2;
};
export const expoOut = (u: number) => (u >= 1 ? 1 : 1 - Math.pow(2, -10 * clamp01(u)));
export const expoIn = (u: number) => (u <= 0 ? 0 : Math.pow(2, 10 * clamp01(u) - 10));
export const backOut = (u: number, s = 1.7) => {
  u = clamp01(u) - 1;
  return u * u * ((s + 1) * u + s) + 1;
};

export const POP: SpringConfig = { stiffness: 520, damping: 20 };
export const SNAP: SpringConfig = { stiffness: 700, damping: 30 };
export const SOFT: SpringConfig = { stiffness: 170, damping: 22 };
export const WOBBLE: SpringConfig = { stiffness: 380, damping: 11 };
export const HEAVY: SpringConfig = { stiffness: 140, damping: 26, mass: 1.2 };

/** 0 -> 1 spring starting at `at` (overshoots with POP). */
export const sp = (t: number, at: number, cfg: SpringConfig = POP) => step(t - at, cfg);

/** Landing squash: returns [scaleX, scaleY], a decaying wobble after impact. */
export function squash(t: number, at: number, amount = 0.28, freq = 16, decay = 7): [number, number] {
  const d = t - at;
  if (d < 0) return [1, 1];
  const w = amount * Math.exp(-d * decay) * Math.cos(d * freq);
  return [1 + w, 1 - w];
}

/** Anticipation stretch on the way in (before `at`), for drops. */
export function stretchIn(t: number, at: number, len = 0.12, amount = 0.25): [number, number] {
  const u = clamp01((t - (at - len)) / len);
  if (t >= at || u <= 0) return [1, 1];
  const w = amount * Math.sin(u * Math.PI * 0.5);
  return [1 - w * 0.5, 1 + w];
}

const rnd = (n: number) => {
  const x = Math.sin(n * 91.345 + 12.9898) * 43758.5453;
  return x - Math.floor(x);
};

/** Screen shake: sum of damped oscillations, one per impulse. */
export function shake(t: number, hits: readonly [number, number][]) {
  let x = 0, y = 0, r = 0;
  hits.forEach(([at, amp], i) => {
    const d = t - at;
    if (d < 0 || d > 0.6) return;
    const e = amp * Math.exp(-d * 9);
    x += e * Math.sin(d * 55 + rnd(i) * 6);
    y += e * Math.sin(d * 47 + rnd(i + 9) * 6);
    r += e * 0.03 * Math.sin(d * 38 + rnd(i + 3) * 6);
  });
  return { x, y, r };
}

/** A short flash 1 -> 0 after `at`. */
export const flash = (t: number, at: number, len = 0.18) => (t < at ? 0 : Math.max(0, 1 - (t - at) / len));

export const rand = rnd;
