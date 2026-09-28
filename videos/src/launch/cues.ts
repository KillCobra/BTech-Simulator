// The beat sheet as data. Every moment is b(bar, beat) on the 128 BPM grid of the score
// (audio/launch_music.py reads the same timeline.json). No literal frame numbers in scene code.
import timeline from "./timeline.json";

export const BPM = timeline.bpm;
export const BEAT = 60 / BPM; // 0.46875 s
export const BAR = BEAT * 4; // 1.875 s
export const DURATION = timeline.bars * BAR; // 30 s
export const b = (bar: number, beat = 0) => (bar * 4 + beat) * BEAT;

// Acts [start, end)
export const ACT = {
  classroom: [b(0), b(2)],
  plan: [b(2), b(4)],
  ruin: [b(4), b(5)],
  cctv: [b(5), b(6)],
  excuse: [b(6), b(7)],
  trolley: [b(7), b(7, 2)],
  paper: [b(7, 2), b(7, 3)],
  spray: [b(7, 3), b(8)],
  test: [b(8), b(9)],
  panic: [b(9), b(10)],
  chase: [b(10), b(11)],
  maps: [b(11), b(12)],
  escape: [b(12), b(13)],
  bell: [b(13), b(13, 3.5)],
  logo: [b(13, 2), DURATION + 1],
} as const;

export const inAct = (t: number, a: readonly [number, number]) => t >= a[0] && t < a[1];

/** Chapter stamps: the README's own pitch, "Make a plan, someone ruins it, improvise, panic, barely get out." */
export const CHAPTERS: { words: [string, number][]; out: number; accent?: string }[] = [
  { words: [["MAKE", b(2, 0)], ["A PLAN.", b(2, 1)]], out: b(2, 2) },
  { words: [["SOMEONE", b(4, 0)], ["RUINS IT.", b(4, 0.5)]], out: b(4, 1) },
  { words: [["IMPROVISE.", b(6, 0)]], out: b(6, 1) },
  { words: [["PANIC.", b(9, 0)]], out: b(9, 1.75), accent: "#ff4a4a" },
  { words: [["BARELY", b(12, 0)], ["GET OUT.", b(12, 1)]], out: b(12, 1.6) },
];

/** Screen shake impulses [time, strength px]. */
export const SHAKES: [number, number][] = [
  [b(0), 10], [b(2), 16], [b(2, 1), 10], [b(4), 18], [b(4, 2), 14], [b(5, 3), 22], [b(6), 16],
  [b(7), 34], [b(7, 3), 10], [b(8), 12], [b(9), 26], [b(9, 1), 8], [b(9, 2), 10], [b(9, 3), 12],
  [b(10), 40], [b(10, 2), 12], [b(11), 14], [b(12), 16], [b(12, 2), 18], [b(13), 10], [b(14), 42], [b(15), 10],
];
