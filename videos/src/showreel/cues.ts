// Showreel beat sheet: 128 BPM, 30s, 16 bars. Same grid as launch trailer for music reuse.
export const BPM = 128;
export const BEAT = 60 / BPM; // 0.46875s
export const BAR = BEAT * 4; // 1.875s
export const DURATION = 16 * BAR; // 30s

export const b = (bar: number, beat = 1, frac = 0) => ((bar - 1) * 4 + (beat - 1) + frac) * BEAT;

// Act structure - each gets ~2 bars for rapid-fire showreel pacing
export const ACTS = {
  coldOpen: [0, b(2)],           // 0-3.75s: logo formation + title
  voxelParade: [b(2), b(4)],     // 3.75-7.5s: voxel chars with personality
  uiBreakdown: [b(4), b(6)],     // 7.5-11.25s: HUD components animated
  iconBurst: [b(6), b(8)],       // 11.25-15s: item icons explosion
  mapFlight: [b(8), b(11)],      // 15-20.625s: 3D map tour
  gameplayChaos: [b(11), b(13)], // 20.625-24.375s: multiplayer mayhem
  brandLockup: [b(13), b(15)],   // 24.375-28.125s: logo + tagline
  cta: [b(15), DURATION],        // 28.125-30s: platforms + coming soon
} as const;

// Every kick for camera bump
export const KICKS: number[] = [
  ...Array.from({ length: 16 }, (_, bar) => 
    Array.from({ length: 4 }, (_, beat) => b(bar + 1, beat + 1))
  ).flat(),
];

// Screen shake impulses [time, strength]
export const SHAKES: [number, number][] = [
  [b(1), 8], [b(2), 12], [b(3), 10], [b(4), 15], [b(5), 8],
  [b(6), 18], [b(7), 12], [b(8), 22], [b(9), 14], [b(10), 28],
  [b(11), 20], [b(12), 30], [b(13), 16], [b(14), 35], [b(15), 12],
];

// Chapter stamps for the "showreel narrative"
export const STAMPS = [
  { text: "MOTION", at: b(1, 1), out: b(1, 3) },
  { text: "DESIGN", at: b(1, 2), out: b(2, 1) },
  { text: "SHOWREEL", at: b(2, 1), out: b(2, 3) },
  { text: "BUNK MASTER", at: b(13, 1), out: b(14) },
  { text: "SNEAK OUT.", at: b(14, 1), out: b(14, 3) },
  { text: "DON'T GET CAUGHT.", at: b(14, 2), out: b(15) },
] as const;