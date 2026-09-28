// Steam trailer grid: 128 BPM, 31 bars, 58.125 s. Every moment is b(bar, beat). No literal frame numbers.
// Each act works in its own LOCAL bars (ACTS) and is shifted onto the film by OFFSET (global = local + offset),
// so an act can grow without moving the code of the acts after it.
import timeline from "./timeline.json";

export const BPM = timeline.bpm;
export const BEAT = 60 / BPM; // 0.46875 s
export const BAR = BEAT * 4; // 1.875 s
export const DURATION = timeline.bars * BAR; // 58.125 s (the whole film)
export const b = (bar: number, beat = 0) => (bar * 4 + beat) * BEAT;

/** Act windows in LOCAL time: [start, end) seconds. Each act renders only inside its window. */
export const ACTS = {
  open: [b(0), b(6)],
  dodge: [b(6), b(12)],
  chaos: [b(10), b(16)],
  crew: [b(14), b(19)],
  finale: [b(18), b(26) + 0.01],
} as const;
export type ActName = keyof typeof ACTS;
/** Bars each act is shifted by on the film (timeline.json offsets). */
export const OFFSET = timeline.offsets as Record<ActName, number>;
/** The last local second of the finale (its end card runs to here). */
export const FINALE_END = b(26);
export const within = (t: number, a: readonly [number, number]) => t >= a[0] && t < a[1];
