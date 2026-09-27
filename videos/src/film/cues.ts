// The beat sheet as data. Same grid as audio/make_music.py: 128 BPM, 4/4, 16 bars = 30.0 s.
export const BPM = 128;
export const BEAT = 60 / BPM; // 0.46875 s
export const BAR = BEAT * 4; // 1.875 s
export const DURATION = 16 * BAR; // 30 s

/** Seconds at a 1-based bar and beat; frac is a share of one beat (0.5 = the "and"). */
export const b = (bar: number, beat = 1, frac = 0) => ((bar - 1) * 4 + (beat - 1) + frac) * BEAT;

export const ACTS = {
  bell: [0, b(3)], // clock + period card
  class: [b(3), b(5)], // classroom, stand up, suspicion, RUN!
  words: [b(5), b(6)], // SNEAK OUT OF CLASS. DON'T GET CAUGHT.
  minimap: [b(6), b(7)],
  style: [b(7), b(8)],
  phone: [b(8), b(9)],
  maps: [b(9), b(13)],
  canteen: [b(13), b(14)],
  ranks: [b(14), b(15)],
  logo: [b(15), DURATION],
} as const;

/** Every kick in the score (four on the floor in the drops) — the camera bumps on these. */
export const KICKS: number[] = (() => {
  const k: number[] = [b(3, 1), b(3, 3)];
  for (let beat = 1; beat <= 4; beat++) k.push(b(4, beat));
  for (let bar = 5; bar <= 12; bar++) for (let beat = 1; beat <= 4; beat++) k.push(b(bar, beat));
  k.push(b(13, 1), b(13, 3), b(14, 1), b(14, 3));
  for (let beat = 1; beat <= 4; beat++) k.push(b(15, beat));
  k.push(b(16, 1));
  return k;
})();
