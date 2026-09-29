// A reel is plain JSON: scenes measured in beats of the game's 128 BPM score. The dashboard edits it,
// the model writes it, Remotion renders it. Nothing here imports React so the server can use it too.

export const BPM = 128; // the trailer score's tempo; custom music can use any BPM per reel
export const BEAT = 60 / BPM;
export const FPS = 30;
export const beatOf = (spec: { bpm: number }) => 60 / spec.bpm;

export const FORMATS = {
  "9:16": { width: 1080, height: 1920, label: "Reels / TikTok / Shorts" },
  "1:1": { width: 1080, height: 1080, label: "Square feed" },
  "16:9": { width: 1920, height: 1080, label: "YouTube / X" },
} as const;
export type Format = keyof typeof FORMATS;

export const THEMES = {
  sunny: { label: "Sunny", bg: "#8fd3f0", bg2: "#bfe9ff", fg: "#2a1a0e", accent: "#ffc93c", stripe: "#ffffff" },
  night: { label: "Night", bg: "#14141f", bg2: "#262640", fg: "#ffffff", accent: "#ffc93c", stripe: "#ffffff" },
  alarm: { label: "Alarm", bg: "#e0524f", bg2: "#ff7a6f", fg: "#ffffff", accent: "#ffd24a", stripe: "#ffffff" },
  grass: { label: "Grass", bg: "#7cbf5a", bg2: "#a8dc84", fg: "#2a1a0e", accent: "#ffc93c", stripe: "#ffffff" },
  dusk: { label: "Dusk", bg: "#6b3fa0", bg2: "#b07cff", fg: "#ffffff", accent: "#ffd24a", stripe: "#ffffff" },
} as const;
export type Theme = keyof typeof THEMES;

// Game screenshots in public/plates. Each has a one-line description for the model and the picker.
export const PLATES: Record<string, string> = {
  menu: "Main menu with the logo and diorama",
  class0: "Inside a classroom, students at desks",
  fp0: "First-person view, sneaking down a corridor",
  c_low1: "Low camera in the school grounds",
  c_air0: "Aerial view of the campus, map A",
  c_air1: "Aerial view of the campus, map B",
  c_air2: "Aerial view, another campus",
  c_air3: "Aerial view, sports field side",
  c_air4: "Aerial view, far wall and gate",
};

// Item art from scripts/icons.gd.
export const ITEMS: Record<string, string> = {
  hall_pass: "Hall Pass",
  samosa: "Samosa",
  medical_note: "Medical Note",
  canteen_key: "Canteen Key",
  library_book: "Library Book",
  detention_ticket: "Detention Ticket",
};

export type SceneKind = "title" | "words" | "plate" | "voxel" | "icons" | "alert" | "cta" | "stat";

export const KINDS: Record<SceneKind, { label: string; hint: string; fields: string }> = {
  title: { label: "Title", hint: "Big outlined headline that slams in", fields: "text (use \\n for lines), sub" },
  words: { label: "Punch words", hint: "One huge word per beat, hard cuts", fields: "items = list of words" },
  plate: { label: "Gameplay shot", hint: "Real screenshot in a frame, slow push-in, caption", fields: "plate id, text, sub" },
  voxel: { label: "Voxel diorama", hint: "The school builds itself block by block", fields: "variant hero|icon, text" },
  icons: { label: "Item burst", hint: "Game items pop in one by one", fields: "items = item ids, text" },
  alert: { label: "Alert", hint: "Red RUN! banner, suspicion bar fills", fields: "text (the banner), sub" },
  cta: { label: "Logo + CTA", hint: "Logo, tagline, platform chips, Coming soon", fields: "text (tagline), items = chips" },
  stat: { label: "Big number", hint: "One huge number or word with a label", fields: "text (the number/word), sub (label)" },
};

export const TRANSITIONS = { flash: "Flash", cut: "Hard cut", slide: "Slide in", zoom: "Zoom in" } as const;
export type Transition = keyof typeof TRANSITIONS;

export type Overlay = {
  id: string;
  text: string;
  at: number; // beat the overlay appears
  beats: number;
  x: number; // centre, % of width
  y: number; // centre, % of height
  size: number; // 0.5 .. 3
  color: "gold" | "white" | "red" | "green" | "blue" | "ink";
  style: "sticker" | "caption" | "plain";
};
export const OVERLAY_COLORS = { gold: "#ffc93c", white: "#ffffff", red: "#ff4a4a", green: "#7fe0a0", blue: "#9fd8ff", ink: "#2a1a0e" } as const;

// ---- music: a small pattern synth (see synth.ts). 16 steps per bar, looped over a chord progression.
export const SCALES = {
  minor: [0, 2, 3, 5, 7, 8, 10],
  major: [0, 2, 4, 5, 7, 9, 11],
  phrygian: [0, 1, 3, 5, 7, 8, 10],
  pentatonic: [0, 3, 5, 7, 10],
} as const;
export type ScaleName = keyof typeof SCALES;
export const KITS = { punch: "Punchy", hard: "Hard 808", "8bit": "8-bit", lofi: "Lo-fi" } as const;
export type Kit = keyof typeof KITS;
export const LANES = ["kick", "snare", "clap", "hat", "perc"] as const;
export type Lane = (typeof LANES)[number];
export const KEYS = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];

export type Track = {
  key: number;
  scale: ScaleName;
  kit: Kit;
  swing: number; // 0 .. 0.3
  prog: number[]; // scale degree per bar, cycles
  dropBar: number; // bars before this are a stripped-back build (hats, perc, pad), then everything hits
  fill: boolean; // snare roll into every 4th bar
  riser: boolean; // noise sweep in the bar before the drop
  drums: Record<Lane, number[]>; // 16 steps: 0 off, 1 hit, 2 accent
  bass: (number | null)[]; // 16 steps: scale degree or null
  lead: (number | null)[];
  chords: "off" | "pad" | "stab";
  mix: { drums: number; bass: number; lead: number; chords: number };
  syncCuts: boolean; // add an impact on every scene cut, ticks on punch words, a riser into alerts
};

const steps = (str: string) => [...str.replace(/\s/g, "")].slice(0, 16).map((c) => (c === "X" ? 2 : c === "x" ? 1 : 0));
const notes = (str: string) => str.trim().split(/\s+/).slice(0, 16).map((t) => (t === "." ? null : Number(t)));
const pad16 = <T,>(a: T[], fill: T) => Array.from({ length: 16 }, (_, i) => (i < a.length ? a[i] : fill));

export const TRACK_PRESETS: Record<string, { label: string; bpm: number; track: Track }> = {
  hype: {
    // Modelled on audio/make_music.py: D minor, chords Dm-Bb-F-C, sneaky intro, drums + riser, drop on bar 5
    label: "Trailer score", bpm: 128,
    track: { key: 2, scale: "minor", kit: "punch", swing: 0, prog: [0, 5, 2, 6], dropBar: 4, fill: true, riser: true, chords: "stab", syncCuts: true,
      drums: { kick: steps("X...x...x...x..."), snare: steps("................"), clap: steps("....x.......x..."), hat: steps("..x...x...x...x."), perc: steps("x.....x.x.....x.") },
      bass: notes("0 . 0 . 0 . 0 . 0 . 0 . 0 . 0 ."), lead: notes("7 . . 9 11 . 10 . 9 . 8 9 7 . . ."), mix: { drums: 0.9, bass: 0.7, lead: 0.5, chords: 0.5 } },
  },
  trap: {
    label: "Trap", bpm: 140,
    track: { key: 0, scale: "minor", kit: "hard", swing: 0, prog: [0, 0, 5, 3], dropBar: 1, fill: true, riser: false, chords: "off", syncCuts: true,
      drums: { kick: steps("X.....x...x....."), snare: steps("........X......."), clap: steps("........x......."), hat: steps("x.x.x.xxx.x.x.xx"), perc: steps("...............x") },
      bass: notes("0 . . . . . 0 . . . 2 . . . . ."), lead: notes(". . . . . . . . 4 . . 2 . . . ."), mix: { drums: 0.9, bass: 0.9, lead: 0.4, chords: 0.4 } },
  },
  house: {
    label: "House", bpm: 124,
    track: { key: 7, scale: "minor", kit: "punch", swing: 0.04, prog: [0, 3, 5, 4], dropBar: 2, fill: true, riser: true, chords: "stab", syncCuts: true,
      drums: { kick: steps("x...x...x...x..."), snare: steps("................"), clap: steps("....x.......x..."), hat: steps(".x...x...x...x.."), perc: steps("..x...x...x...x.") },
      bass: notes(". 0 . . 0 . . 0 . 0 . . 0 . . 0"), lead: notes(". . . . . . . . . . . . . . . ."), mix: { drums: 0.85, bass: 0.75, lead: 0.4, chords: 0.55 } },
  },
  chase: {
    label: "8-bit chase", bpm: 150,
    track: { key: 4, scale: "minor", kit: "8bit", swing: 0, prog: [0, 0, 5, 6], dropBar: 0, fill: true, riser: false, chords: "off", syncCuts: true,
      drums: { kick: steps("x..x..x.x..x..x."), snare: steps("....x.......x..."), clap: steps("................"), hat: steps("x.x.x.x.x.x.x.x."), perc: steps("................") },
      bass: notes("0 . 0 . 0 . 0 . 3 . 3 . 4 . 4 ."), lead: notes("0 2 4 2 0 2 4 7 0 2 4 2 7 4 2 0"), mix: { drums: 0.8, bass: 0.7, lead: 0.55, chords: 0.3 } },
  },
  lofi: {
    label: "Lo-fi", bpm: 85,
    track: { key: 3, scale: "major", kit: "lofi", swing: 0.18, prog: [0, 3, 4, 2], dropBar: 0, fill: false, riser: false, chords: "pad", syncCuts: true,
      drums: { kick: steps("x.....x..x......"), snare: steps("....x.......x..."), clap: steps("................"), hat: steps("x.x.x.x.x.x.x.x."), perc: steps("...........x....") },
      bass: notes("0 . . . . . -1 . . . 2 . . . . ."), lead: notes(". . . . . . 4 . . . . . 2 . . ."), mix: { drums: 0.7, bass: 0.7, lead: 0.4, chords: 0.7 } },
  },
};

const clampNum = (v: unknown, lo: number, hi: number, d: number) => {
  const n = Number(v);
  return Number.isFinite(n) ? Math.min(hi, Math.max(lo, n)) : d;
};
const pickNote = (v: unknown): number | null => (v === null || v === undefined || !Number.isFinite(Number(v)) ? null : Math.max(-21, Math.min(21, Math.round(Number(v)))));

export function sanitizeTrack(raw: any): Track {
  const d = TRACK_PRESETS.hype.track;
  const drums = {} as Record<Lane, number[]>;
  // models sometimes answer with compact strings ("x...x...", "0 . 2 .") instead of arrays
  const asSteps = (v: any) => (typeof v === "string" ? steps(v) : v);
  const asNotes = (v: any) => (typeof v === "string" ? notes(v) : v);
  for (const l of LANES) drums[l] = pad16(Array.isArray(asSteps(raw?.drums?.[l])) ? asSteps(raw.drums[l]).map((x: any) => clampNum(x, 0, 2, 0) | 0) : d.drums[l], 0).slice(0, 16);
  const line = (v: any, dv: (number | null)[]) => pad16(Array.isArray(v) ? v.map(pickNote) : dv, null).slice(0, 16);
  const prog = Array.isArray(raw?.prog) && raw.prog.length ? raw.prog.slice(0, 8).map((x: any) => Math.round(clampNum(x, -7, 14, 0))) : d.prog;
  return {
    key: Math.round(clampNum(raw?.key, 0, 11, d.key)),
    scale: raw?.scale in SCALES ? raw.scale : d.scale,
    kit: raw?.kit in KITS ? raw.kit : d.kit,
    swing: clampNum(raw?.swing, 0, 0.3, 0),
    prog,
    dropBar: Math.round(clampNum(raw?.dropBar, 0, 16, 0)),
    fill: raw?.fill !== false,
    riser: !!raw?.riser,
    drums,
    bass: line(asNotes(raw?.bass), d.bass),
    lead: line(asNotes(raw?.lead), d.lead),
    chords: raw?.chords === "off" || raw?.chords === "stab" ? raw.chords : "pad",
    syncCuts: raw?.syncCuts !== false,
    mix: {
      drums: clampNum(raw?.mix?.drums, 0, 1, 0.85), bass: clampNum(raw?.mix?.bass, 0, 1, 0.75),
      lead: clampNum(raw?.mix?.lead, 0, 1, 0.5), chords: clampNum(raw?.mix?.chords, 0, 1, 0.5),
    },
  };
}

export type Scene = {
  id: string;
  kind: SceneKind;
  beats: number;
  text?: string;
  sub?: string;
  items?: string[];
  plate?: string;
  variant?: "hero" | "icon";
  theme?: Theme; // overrides the reel theme for this scene
  transition?: Transition;
};

export type ReelSpec = {
  title: string;
  format: Format;
  theme: Theme;
  bpm: number; // scene lengths are in beats of this tempo (the trailer score is fixed at 128)
  music: "trailer" | "custom" | "none";
  musicStartBar: number; // trailer score only: 0-based bar of the 16-bar score to start from
  track?: Track; // the custom music
  scenes: Scene[];
  overlays: Overlay[];
};

export const MAX_BEATS = 64; // the trailer score is 30 s
export const maxBeats = (spec: { music: string }) => (spec.music === "trailer" ? MAX_BEATS : 160);

export const totalBeats = (spec: ReelSpec) => spec.scenes.reduce((n, s) => n + s.beats, 0);
export const durationFrames = (spec: ReelSpec) => Math.max(1, Math.round(totalBeats(spec) * beatOf(spec) * FPS));
export const durationSeconds = (spec: ReelSpec) => totalBeats(spec) * beatOf(spec);
/** Start frame of every scene (rounded on the running total so cuts never drift off the beat). */
export function sceneFrames(spec: ReelSpec) {
  let beats = 0;
  return spec.scenes.map((s) => {
    const from = Math.round(beats * beatOf(spec) * FPS);
    beats += s.beats;
    return { from, frames: Math.max(1, Math.round(beats * beatOf(spec) * FPS) - from) };
  });
}

let counter = 0;
export const newId = () => `s${Date.now().toString(36)}${(counter++).toString(36)}`;

export const DEFAULT_SCENE: Record<SceneKind, Omit<Scene, "id">> = {
  title: { kind: "title", beats: 4, text: "SNEAK OUT\nOF CLASS", sub: "up to 8 players" },
  words: { kind: "words", beats: 4, items: ["PLAN", "PANIC", "IMPROVISE", "ESCAPE"] },
  plate: { kind: "plate", beats: 4, plate: "fp0", text: "Staff hear how loud you are", sub: "PROXIMITY VOICE" },
  voxel: { kind: "voxel", beats: 4, variant: "hero", text: "Big maps. Bigger plans." },
  icons: { kind: "icons", beats: 4, items: ["hall_pass", "samosa", "medical_note"], text: "Trade. Bluff. Survive." },
  alert: { kind: "alert", beats: 4, text: "RUN!", sub: "The teacher saw you" },
  cta: { kind: "cta", beats: 4, text: "Sneak out of class. Don't get caught.", items: ["Windows", "Mac"] },
  stat: { kind: "stat", beats: 4, text: "8", sub: "PLAYERS" },
};

export const DEFAULT_OVERLAY: Omit<Overlay, "id"> = { text: "NEW!", at: 0, beats: 4, x: 50, y: 20, size: 1, color: "gold", style: "sticker" };

export const SAMPLE: ReelSpec = {
  title: "Sneak out with friends",
  format: "9:16",
  theme: "sunny",
  bpm: 128,
  overlays: [],
  music: "trailer",
  musicStartBar: 0,
  scenes: [
    { id: "a1", kind: "title", beats: 4, text: "SNEAK OUT\nOF CLASS", sub: "up to 8 players" },
    { id: "a2", kind: "plate", beats: 4, plate: "fp0", text: "Make a plan", sub: "CO-OP" },
    { id: "a3", kind: "alert", beats: 4, text: "RUN!", sub: "Someone ruined it" },
    { id: "a4", kind: "words", beats: 4, items: ["PLAN", "PANIC", "IMPROVISE", "ESCAPE"] },
    { id: "a5", kind: "cta", beats: 8, text: "Sneak out of class. Don't get caught.", items: ["Windows", "Mac"] },
  ],
};

const clampInt = (v: unknown, lo: number, hi: number, d: number) => {
  const n = Math.round(Number(v));
  return Number.isFinite(n) ? Math.min(hi, Math.max(lo, n)) : d;
};
const str = (v: unknown, max: number) => (typeof v === "string" ? v.slice(0, max) : undefined);

/** Coerces anything (model output, old files) into a spec that always renders. */
export function sanitize(raw: any): ReelSpec {
  const kinds = Object.keys(KINDS) as SceneKind[];
  let scenes: Scene[] = (Array.isArray(raw?.scenes) ? raw.scenes : [])
    .filter((s: any) => kinds.includes(s?.kind))
    .slice(0, 24)
    .map((s: any): Scene => {
      const kind = s.kind as SceneKind;
      const d = DEFAULT_SCENE[kind];
      const out: Scene = { id: str(s.id, 24) || newId(), kind, beats: clampInt(s.beats, 1, 32, d.beats) };
      out.text = str(s.text, 120) ?? d.text;
      out.sub = str(s.sub, 80) ?? d.sub;
      if (kind === "words") out.items = (Array.isArray(s.items) ? s.items : d.items!).map((x: any) => String(x).slice(0, 18)).filter(Boolean).slice(0, 16);
      if (kind === "icons") out.items = (Array.isArray(s.items) ? s.items : d.items!).filter((x: any) => x in ITEMS).slice(0, 6);
      if (s.theme in THEMES) out.theme = s.theme;
      if (s.transition in TRANSITIONS) out.transition = s.transition;
      else if (s.flash === false) out.transition = "cut";
      if (kind === "cta") out.items = (Array.isArray(s.items) ? s.items : d.items!).map((x: any) => String(x).slice(0, 18)).slice(0, 4);
      if (kind === "plate") out.plate = s.plate in PLATES ? s.plate : "fp0";
      if (kind === "voxel") out.variant = s.variant === "icon" ? "icon" : "hero";
      out.beats = Math.min(32, Math.max(out.beats, minBeats(out))); // every action needs a beat of its own
      return out;
    });
  if (!scenes.length) scenes = SAMPLE.scenes.map((s) => ({ ...s }));
  const music = raw?.music === "none" ? "none" : raw?.music === "custom" ? "custom" : "trailer";
  // trim to the length of the score
  let left = maxBeats({ music });
  scenes = scenes.filter((s) => left > 0).map((s) => { const b = Math.min(s.beats, left); left -= b; return { ...s, beats: b }; });
  return {
    title: str(raw?.title, 80) || "Untitled reel",
    format: raw?.format in FORMATS ? raw.format : "9:16",
    theme: raw?.theme in THEMES ? raw.theme : "sunny",
    bpm: music === "custom" ? Math.round(clampNum(raw?.bpm, 70, 180, 128)) : 128,
    music,
    track: music === "custom" ? sanitizeTrack(raw?.track) : raw?.track ? sanitizeTrack(raw.track) : undefined,
    overlays: (Array.isArray(raw?.overlays) ? raw.overlays : []).slice(0, 40).map((o: any): Overlay => ({
      id: str(o?.id, 24) || newId(), text: str(o?.text, 60) ?? "",
      at: Math.round(clampNum(o?.at, 0, 160, 0)), beats: Math.round(clampNum(o?.beats, 1, 64, 4)),
      x: clampNum(o?.x, 0, 100, 50), y: clampNum(o?.y, 0, 100, 20), size: clampNum(o?.size, 0.4, 3, 1),
      color: o?.color in OVERLAY_COLORS ? o.color : "gold", style: o?.style === "caption" || o?.style === "plain" ? o.style : "sticker",
    })),
    musicStartBar: clampInt(raw?.musicStartBar, 0, 12, 0),
    scenes,
  };
}

// ---- what the music has to line up with

export type Cue = { beat: number; kind: "impact" | "big" | "tick" | "riser"; len?: number; step?: number };

// When each thing inside a scene happens, in beats from the scene's start. The renderer animates from these and the
// music is scored from the same numbers, so every pop is on the grid (whole beats, or 1/4 beat when a scene is crowded).
export type Timing = { lines?: number[]; sub?: number; caption?: number; sticker?: number; built?: number; items?: number[]; banner?: number; logo?: number; tagline?: number; chips?: number[]; soon?: number; num?: number; label?: number; per?: number };
const cl = (sc: Scene, b: number) => Math.max(0, Math.min(Math.max(0, sc.beats - 1), b));
const linesOf = (t?: string) => (t ?? "").split(/\\n|\n/);

export function timing(sc: Scene): Timing {
  const n = sc.beats;
  switch (sc.kind) {
    case "title": { const ls = linesOf(sc.text); return { lines: ls.map((_, i) => cl(sc, i)), sub: cl(sc, ls.length) }; }
    case "words": return { per: Math.max(1, Math.round(n / Math.max(1, sc.items?.length ?? 1))) };
    case "plate": return { caption: 0, sticker: cl(sc, 1) };
    case "voxel": return { caption: 0, built: Math.max(1, Math.min(2, n - 1)) };
    case "icons": {
      const k = sc.items?.length ?? 0;
      const step = Math.min(1, Math.max(0.25, Math.floor(((n - 1) / Math.max(1, k)) * 4) / 4));
      return { caption: 0, items: Array.from({ length: k }, (_, i) => 1 + i * step) };
    }
    case "alert": return { banner: 0, sub: cl(sc, 1) };
    case "cta": { const k = sc.items?.length ?? 0; return { logo: 0, tagline: cl(sc, 1), chips: Array.from({ length: k }, (_, i) => cl(sc, 2 + i)), soon: cl(sc, 2 + k) }; }
    case "stat": return { num: 0, label: cl(sc, 1) };
  }
}

/** Fewest beats a scene needs so every action gets a beat of its own. */
export function minBeats(sc: Scene) {
  if (sc.kind === "icons") return (sc.items?.length ?? 0) + 1;
  if (sc.kind === "cta") return 3 + (sc.items?.length ?? 0);
  if (sc.kind === "title") return linesOf(sc.text).length + 1;
  if (sc.kind === "alert" || sc.kind === "stat" || sc.kind === "plate") return 2;
  if (sc.kind === "voxel") return 3;
  return 1;
}

export type SceneEvent = { beat: number; label: string; kind: "impact" | "big" | "tick"; step?: number };

/** Everything that pops in a scene, as musical events. */
export function sceneEvents(sc: Scene): SceneEvent[] {
  const t = timing(sc);
  const ev: SceneEvent[] = [];
  if (sc.kind === "title") { t.lines!.forEach((b, i) => ev.push({ beat: b, label: `headline line ${i + 1}`, kind: i === 0 ? "big" : "impact" })); if (sc.sub) ev.push({ beat: t.sub!, label: "sub line", kind: "impact" }); }
  if (sc.kind === "words") { const per = t.per!; (sc.items ?? []).forEach((w, i) => { if (i * per < sc.beats) ev.push({ beat: i * per, label: `word ${w}`, kind: i === 0 ? "big" : "tick", step: i }); }); }
  if (sc.kind === "plate") { ev.push({ beat: 0, label: "gameplay frame slides in", kind: "impact" }); if (sc.sub) ev.push({ beat: t.sticker!, label: "sticker", kind: "impact" }); }
  if (sc.kind === "voxel") { ev.push({ beat: 0, label: "blocks start falling", kind: "impact" }); ev.push({ beat: t.built!, label: "diorama complete", kind: "impact" }); }
  if (sc.kind === "icons") (sc.items ?? []).forEach((it, i) => ev.push({ beat: t.items![i], label: `item ${ITEMS[it] ?? it} pops`, kind: "tick", step: i }));
  if (sc.kind === "alert") { ev.push({ beat: 0, label: "RUN banner slams", kind: "big" }); if (sc.sub) ev.push({ beat: t.sub!, label: "sub line", kind: "impact" }); }
  if (sc.kind === "cta") {
    ev.push({ beat: 0, label: "logo slams", kind: "big" }); ev.push({ beat: t.tagline!, label: "tagline", kind: "impact" });
    (sc.items ?? []).forEach((c, i) => ev.push({ beat: t.chips![i], label: `chip ${c}`, kind: "tick", step: i }));
    ev.push({ beat: t.soon!, label: "COMING SOON button", kind: "big" });
  }
  if (sc.kind === "stat") { ev.push({ beat: 0, label: "number slams", kind: "big" }); if (sc.sub) ev.push({ beat: t.label!, label: "label", kind: "impact" }); }
  return ev.sort((a, b) => a.beat - b.beat);
}

/** Every moment in the reel the music should react to, in beats from the start. */
export function cueList(spec: ReelSpec): Cue[] {
  const cues: Cue[] = [];
  let b = 0;
  for (const sc of spec.scenes) {
    const big = sc.kind === "alert" || sc.kind === "cta" || sc.kind === "stat";
    if (sc.kind === "alert" && b >= 2) cues.push({ beat: b - 2, kind: "riser", len: 2 });
    cues.push({ beat: b, kind: big ? "big" : "impact" });
    for (const e of sceneEvents(sc)) if (e.beat > 0) cues.push({ beat: b + e.beat, kind: e.kind, step: e.step });
    b += sc.beats;
  }
  for (const o of spec.overlays) cues.push({ beat: o.at, kind: "tick" });
  return cues;
}

export type CueRow = { i: number; kind: SceneKind; label: string; startBeat: number; bar: number; beatInBar: number; beats: number; seconds: number; energy: "low" | "medium" | "high" };
const ENERGY: Record<SceneKind, CueRow["energy"]> = { title: "medium", words: "medium", plate: "low", voxel: "low", icons: "medium", alert: "high", cta: "high", stat: "high" };

/** Scene-by-scene timing table, bars and beats counted from 1. */
export function cueSheet(spec: ReelSpec): CueRow[] {
  let b = 0;
  return spec.scenes.map((sc, i) => {
    const row: CueRow = {
      i, kind: sc.kind, label: (sc.text || sc.items?.join(" ") || KINDS[sc.kind].label).replace(/\\n|\n/g, " ").slice(0, 40),
      startBeat: b, bar: Math.floor(b / 4) + 1, beatInBar: (b % 4) + 1, beats: sc.beats, seconds: sc.beats * beatOf(spec), energy: ENERGY[sc.kind],
    };
    b += sc.beats;
    return row;
  });
}

/** Bar (0-based) where the first high-energy scene starts, so the drop can land on it. */
export function suggestDropBar(spec: ReelSpec) {
  const first = cueSheet(spec).find((r) => r.energy === "high" && r.startBeat >= 4) ?? cueSheet(spec).find((r) => r.startBeat >= 4);
  return first ? Math.floor(first.startBeat / 4) : 0;
}
