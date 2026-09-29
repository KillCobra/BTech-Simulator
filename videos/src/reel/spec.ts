// A reel is plain JSON: scenes measured in beats of the game's 128 BPM score. The dashboard edits it,
// the model writes it, Remotion renders it. Nothing here imports React so the server can use it too.

export const BPM = 128;
export const BEAT = 60 / BPM; // 0.46875 s
export const FPS = 30;

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

export type SceneKind = "title" | "words" | "plate" | "voxel" | "icons" | "alert" | "cta";

export const KINDS: Record<SceneKind, { label: string; hint: string; fields: string }> = {
  title: { label: "Title", hint: "Big outlined headline that slams in", fields: "text (use \\n for lines), sub" },
  words: { label: "Punch words", hint: "One huge word per beat, hard cuts", fields: "items = list of words" },
  plate: { label: "Gameplay shot", hint: "Real screenshot in a frame, slow push-in, caption", fields: "plate id, text, sub" },
  voxel: { label: "Voxel diorama", hint: "The school builds itself block by block", fields: "variant hero|icon, text" },
  icons: { label: "Item burst", hint: "Game items pop in one by one", fields: "items = item ids, text" },
  alert: { label: "Alert", hint: "Red RUN! banner, suspicion bar fills", fields: "text (the banner), sub" },
  cta: { label: "Logo + CTA", hint: "Logo, tagline, platform chips, Coming soon", fields: "text (tagline), items = chips" },
};

export type Scene = {
  id: string;
  kind: SceneKind;
  beats: number;
  text?: string;
  sub?: string;
  items?: string[];
  plate?: string;
  variant?: "hero" | "icon";
  flash?: boolean;
};

export type ReelSpec = {
  title: string;
  format: Format;
  theme: Theme;
  music: "trailer" | "none";
  musicStartBar: number; // 0-based bar of the 16-bar score to start from
  scenes: Scene[];
};

export const MAX_BEATS = 64;

export const totalBeats = (spec: ReelSpec) => spec.scenes.reduce((n, s) => n + s.beats, 0);
export const durationFrames = (spec: ReelSpec) => Math.max(1, Math.round(totalBeats(spec) * BEAT * FPS));
export const durationSeconds = (spec: ReelSpec) => totalBeats(spec) * BEAT;
/** Start frame of every scene (rounded on the running total so cuts never drift off the beat). */
export function sceneFrames(spec: ReelSpec) {
  let beats = 0;
  return spec.scenes.map((s) => {
    const from = Math.round(beats * BEAT * FPS);
    beats += s.beats;
    return { from, frames: Math.max(1, Math.round(beats * BEAT * FPS) - from) };
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
};

export const SAMPLE: ReelSpec = {
  title: "Sneak out with friends",
  format: "9:16",
  theme: "sunny",
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
      if (kind === "cta") out.items = (Array.isArray(s.items) ? s.items : d.items!).map((x: any) => String(x).slice(0, 18)).slice(0, 4);
      if (kind === "plate") out.plate = s.plate in PLATES ? s.plate : "fp0";
      if (kind === "voxel") out.variant = s.variant === "icon" ? "icon" : "hero";
      if (s.flash === false) out.flash = false;
      return out;
    });
  if (!scenes.length) scenes = SAMPLE.scenes.map((s) => ({ ...s }));
  // trim to the length of the score
  let left = MAX_BEATS;
  scenes = scenes.filter((s) => left > 0).map((s) => { const b = Math.min(s.beats, left); left -= b; return { ...s, beats: b }; });
  return {
    title: str(raw?.title, 80) || "Untitled reel",
    format: raw?.format in FORMATS ? raw.format : "9:16",
    theme: raw?.theme in THEMES ? raw.theme : "sunny",
    music: raw?.music === "none" ? "none" : "trailer",
    musicStartBar: clampInt(raw?.musicStartBar, 0, 12, 0),
    scenes,
  };
}
