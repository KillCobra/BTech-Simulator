// Reel dashboard server: Vite (the UI), a small JSON API, Remotion renders and Claude-written storyboards.
// Run from videos/: npm run dashboard
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { spawn, spawnSync } from "node:child_process";
import { createServer as createVite } from "vite";
import { bundle } from "@remotion/bundler";
import { renderMedia, selectComposition } from "@remotion/renderer";
// spec.ts is shared with the browser and loads as CommonJS here, so take its exports from the namespace
import * as specNs from "../src/reel/spec.ts";
import * as synthNs from "../src/reel/synth.ts";
import type { ReelSpec } from "../src/reel/spec.ts";

const { BPM, FORMATS, ITEMS, KINDS, MAX_BEATS, PLATES, THEMES, TRANSITIONS, sanitize, sanitizeTrack, durationSeconds, cueList, cueSheet, suggestDropBar, sceneEvents } = ((specNs as any).default ?? specNs) as typeof specNs;
const { renderTrack, encodeWav } = ((synthNs as any).default ?? synthNs) as typeof synthNs;
const ROOT = process.cwd();
const REELS = path.join(ROOT, "reels");
const OUT = path.join(ROOT, "out", "reels");
const TRACKS = path.join(ROOT, "out", "tracks");
const PORT = Number(process.env.PORT ?? 5174);
const LIB = path.join(ROOT, "library");
const MODELS = [
  { id: "claude-opus-5-5", label: "Opus 5.5" },
  { id: "claude-sonnet-5-5", label: "Sonnet 5.5" },
  { id: "claude-fable-5-1", label: "Fable 5.1" },
  { id: "claude-haiku-4-5-20251001", label: "Haiku 4.5" },
];
fs.mkdirSync(LIB, { recursive: true });
const readList = (f: string): any[] => { try { return JSON.parse(fs.readFileSync(path.join(LIB, f), "utf8")); } catch { return []; } };
const writeList = (f: string, l: any[]) => fs.writeFileSync(path.join(LIB, f), JSON.stringify(l, null, 2));
const HAS_CLI = spawnSync("claude", ["--version"]).status === 0;
fs.mkdirSync(REELS, { recursive: true });
fs.mkdirSync(OUT, { recursive: true });
fs.mkdirSync(TRACKS, { recursive: true });

// API key: environment, or videos/dashboard/.env (git-ignored)
function apiKey() {
  if (process.env.ANTHROPIC_API_KEY) return process.env.ANTHROPIC_API_KEY;
  try {
    const m = fs.readFileSync(path.join(ROOT, "dashboard", ".env"), "utf8").match(/^ANTHROPIC_API_KEY\s*=\s*(.+)$/m);
    return m ? m[1].trim().replace(/^["']|["']$/g, "") : "";
  } catch {
    return "";
  }
}

const json = (res: http.ServerResponse, code: number, body: unknown) => {
  res.writeHead(code, { "content-type": "application/json" });
  res.end(JSON.stringify(body));
};
const readBody = (req: http.IncomingMessage) =>
  new Promise<any>((ok, no) => {
    let s = "";
    req.on("data", (c) => (s += c));
    req.on("end", () => {
      try { ok(s ? JSON.parse(s) : {}); } catch (e) { no(e); }
    });
  });
const safeId = (s: string) => s.replace(/[^a-zA-Z0-9_-]/g, "").slice(0, 60) || "reel";

// ---------- storyboard generation ----------
const SYSTEM = `You are the creative director for short vertical ads ("reels") for Bunk Master, a voxel multiplayer game where up to 8 friends sneak out of school without getting caught. You design a reel as JSON. Reply with ONLY the JSON object, no prose, no code fence.

GAME FACTS (only claim these): co-op for up to 8 players; proximity voice (staff hear how LOUD you are, never what you say); chaos tools (trolley, paper ball, excuses, blame a friend); big maps with escape routes; surprise tests (quizzes); side quests (fire extinguisher); CCTV; items (hall pass, samosa, medical note, canteen key, library book, detention ticket); Windows and Mac; status is "Coming soon" (no price, no download link, no release date). Tagline: "Sneak out of class. Don't get caught." Pitch: "Make a plan, someone ruins it, improvise, panic, barely get out." Voice: playful, punchy, short. Never invent features, numbers, reviews or awards.

TIMING: music is 128 BPM; every scene length is in BEATS (1 beat = ${(60 / BPM).toFixed(3)} s). 4 beats = 1.9 s, 8 beats = 3.75 s. Total must be <= ${MAX_BEATS} beats. Typical reel: 24 to 48 beats. First scene must hook within 2 s. End on a "cta" scene (6 to 8 beats).

SCENE KINDS (fields):
${Object.entries(KINDS).map(([k, v]) => `- ${k}: ${v.hint}. Uses: ${v.fields}`).join("\n")}

PLATE IDS: ${Object.entries(PLATES).map(([k, v]) => `${k} (${v})`).join("; ")}
ITEM IDS: ${Object.keys(ITEMS).join(", ")}
THEMES: ${Object.keys(THEMES).join(", ")}  (sunny = bright default, night = moody, alarm = red/urgent, grass, dusk)
FORMATS: ${Object.keys(FORMATS).join(", ")}

RULES: on-screen text is SHORT (headline <= 5 words per line, use \\n for 2 lines; captions <= 6 words). Vary scene kinds, do not repeat one kind three times in a row. Use "words" for rhythm (3 to 6 words, scene beats = number of words). Use "alert" when something goes wrong. Every action inside a scene lands on its own beat (each title line, punch word, item, platform chip), so an "icons" scene needs items+1 beats and a "cta" scene 3+chips beats. Each scene needs a unique short "id".

TRANSITIONS (optional per scene "transition"): ${Object.keys(TRANSITIONS).join(", ")}. Optional per-scene "theme" overrides the reel theme (use sparingly, e.g. alarm for a panic scene).
OVERLAYS (optional, 0 to 4): floating stickers/captions over the scenes: {"id","text","at":beat index from reel start,"beats":int,"x":0-100,"y":0-100,"size":0.6-2,"color":"gold|white|red|green|blue|ink","style":"sticker|caption|plain"}. Keep them short and never over the main headline.

SCHEMA: {"title":string,"format":"9:16"|"1:1"|"16:9","theme":string,"music":"trailer","musicStartBar":0-12,"scenes":[{"id":string,"kind":string,"beats":int,"text"?:string,"sub"?:string,"items"?:string[],"plate"?:string,"variant"?:"hero"|"icon","transition"?:string,"theme"?:string}],"overlays"?:[...]}`;

const TRACK_DOC = `MUSIC (custom): instead of the trailer score, write an original track. Set "music":"custom", "bpm":80-170 (scene beats are beats of this tempo) and "track":
{"key":0-11 (0=C, 9=A),"scale":"minor|major|phrygian|pentatonic","kit":"punch|hard|8bit|lofi","swing":0-0.3,"prog":[scale degree per bar, 2-8 numbers, e.g. 0,5,3,6],"dropBar":0-8 (bars before this are a stripped build with hats/pad, then everything hits),"fill":bool,"riser":bool,
"drums":{"kick":[16 numbers 0/1/2],"snare":[16],"clap":[16],"hat":[16],"perc":[16]} (16 sixteenth-note steps of one bar, 2 = accent),
"bass":[16 entries: scale degree or null; 0 is the root, negative goes lower],"lead":[16 entries: scale degree or null; 0..9 is a good range],
"chords":"off|pad|stab","mix":{"drums":0-1,"bass":0-1,"lead":0-1,"chords":0-1}}. Make it fit the mood: hype trailer = 128 BPM minor, four-on-floor kick, backbeat snare/clap; chill = 80-95 BPM major with swing 0.15+; frantic chase = 150 BPM 8bit kit with an arpeggiated lead. Drop bar should land at the first big scene.
SYNC RULES: the reel is a list of scenes measured in beats, and the music must line up with it. Bar N starts at beat 4*(N-1). Scene starts that fall on a bar line (multiples of 4 beats) get the strongest hits. Set "dropBar" (0-based) to the bar where the first high-energy scene (alert, cta, big number) starts, so the build runs under the calm scenes and everything hits on the cut. Use "riser":true when a high-energy scene follows a calm one. Set "fill":true so the bar before a big cut ends in a snare roll. Punch-word scenes have one word per beat, so keep the kick or a hat on every beat there. Choose a tempo so total length suits the reel: the reel's beats are in the tempo you choose. The player also adds an impact on every scene cut, a tick on every punch word and a riser into alerts automatically ("syncCuts": true), so do not fight them: leave space on the cut beat and keep the lead sparse on scene starts. Calm scenes (gameplay shot, voxel diorama) = sparse, pad-led. High-energy scenes = full drums and bass.`;

const TRAILER_STYLE = `HOUSE STYLE ("the trailer score", "default music", "like the trailer"): the game's own 30 s trailer cue. Chip-pop, bright and cheeky, 128 BPM, D minor (key 2, scale minor), chords Dm-Bb-F-C (prog [0,5,2,6]), kit "punch", chords "stab" (bright supersaw stabs on the off-beats), swing 0. Structure over 16 bars: bars 1-2 sneaky intro (school bell, ticking clock, plucky bass, soft pad, no drums), bars 3-4 hats and claps enter, riser, snare roll into the drop; bar 5 DROP 1 (four-on-the-floor kick, claps on beats 2 and 4, off-beat 8th hats with 16th ghost hats, driving 8th-note bass on the chord root, chip-tune square lead playing a singable 8-note hook that answers the chords); bar 9 DROP 2 (same, busier); bars 13-14 half-time lift; bars 15-16 final chord hit with the bell again. As a Track: {"key":2,"scale":"minor","kit":"punch","swing":0,"prog":[0,5,2,6],"dropBar":4,"fill":true,"riser":true,"chords":"stab","drums":{"kick":"X...x...x...x...","snare":"................","clap":"....x.......x...","hat":"..x...x...x...x.","perc":"x.....x.x.....x."},"bass":"0 . 0 . 0 . 0 . 0 . 0 . 0 . 0 .","lead":"7 . . 9 11 . 10 . 9 . 8 9 7 . . .","mix":{"drums":0.9,"bass":0.7,"lead":0.5,"chords":0.5}} (patterns shown compactly: x = 1, X = 2, . = 0 or null; output real arrays). When the brief asks for this style, keep that feel: same kit, chord loop, groove and melodic shape, but you may move the key, change the hook, and place the drop on the reel's first big scene instead of bar 5.`;

const MUSIC_ONLY_SYSTEM = `You are a game-trailer music producer. Reply with ONLY a JSON object {"bpm":number,"track":{...}}, no prose, no code fence. ${TRACK_DOC}\n\n${TRAILER_STYLE}`;

function viaCli(model: string, system: string, user: string) {
  // Runs the user's own Claude Code login, so it bills their subscription. No tools, no session saved.
  return new Promise<string>((ok, no) => {
    const p = spawn("claude", ["-p", "--model", model, "--system-prompt", system, "--tools", "", "--output-format", "json", "--no-session-persistence"], { cwd: LIB });
    let out = "", errText = "";
    p.stdout.on("data", (d) => (out += d));
    p.stderr.on("data", (d) => (errText += d));
    p.on("error", () => no(new Error("Claude Code CLI not found. Install it and run `claude` once to sign in.")));
    p.on("close", () => {
      try {
        const r = JSON.parse(out);
        if (r.is_error) return no(new Error(String(r.result ?? "Claude Code error")));
        ok(String(r.result ?? ""));
      } catch {
        no(new Error((errText || out || "Claude Code returned nothing").slice(0, 400)));
      }
    });
    p.stdin.end(user);
  });
}

async function viaApi(model: string, system: string, user: string) {
  const key = apiKey();
  if (!key) throw new Error("No ANTHROPIC_API_KEY. Put it in videos/dashboard/.env, or switch to your Claude subscription.");
  const r = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "content-type": "application/json", "x-api-key": key, "anthropic-version": "2023-06-01" },
    body: JSON.stringify({ model, max_tokens: 4000, system, messages: [{ role: "user", content: user }] }),
  });
  const data: any = await r.json();
  if (!r.ok) throw new Error(data?.error?.message ?? `Anthropic API ${r.status}`);
  return (data.content ?? []).map((c: any) => c.text ?? "").join("");
}

const ask = (provider: string, model: string, system: string, user: string) => (provider === "api" ? viaApi(model, system, user) : viaCli(model, system, user));
const pickModel = (m: string) => (MODELS.some((x) => x.id === m) ? m : MODELS[0].id);
const parseJson = (text: string) => {
  const a = text.indexOf("{"), b = text.lastIndexOf("}");
  if (a < 0 || b < a) throw new Error("Model returned no JSON");
  return JSON.parse(text.slice(a, b + 1));
};

const musicMode = (v: unknown): "trailer" | "compose" | "none" => (v === "compose" || v === true ? "compose" : v === "none" ? "none" : "trailer");

const ANGLES = [
  "hook-first: a 2 second shock or question, then fast payoff",
  "feature spotlight: one game feature explained visually",
  "chaos and comedy: things go wrong, friends blame each other",
  "mystery teaser: few words, mood, build to the logo",
  "co-op friendship: the squad plan, up to 8 players",
  "how-to-play in five beats: plan, sneak, panic, improvise, escape",
];

type GenOpts = { prompt: string; format: string; provider: string; model: string; current?: ReelSpec; music: "trailer" | "compose" | "none"; angle?: string };

/** Storyboard first; then, if asked, a second pass composes a beat that is scored against that storyboard's own cues. */
async function generate(o: GenOpts) {
  const model = pickModel(o.model);
  const user = [
    `Brief: ${o.prompt}`,
    o.angle ? `Creative angle for this version: ${o.angle}` : "",
    `Format: ${o.format}`,
    o.current ? `Current reel (revise it according to the brief, keep what still works):\n${JSON.stringify(o.current)}` : "No current reel: design a new one.",
    o.music === "compose" ? "A new original beat will be composed for this reel afterwards, so make scene lengths multiples of 4 beats where it helps the cuts land on bar lines, and put the biggest moment (alert, big number or logo) on a bar line." : "",
  ].filter(Boolean).join("\n\n");
  let spec = sanitize(parseJson(await ask(o.provider, model, SYSTEM, user)));
  if (o.format in FORMATS) spec.format = o.format as ReelSpec["format"];
  let warning: string | undefined;
  if (o.music === "none") spec.music = "none";
  else if (o.music === "compose") {
    try {
      const m = await generateMusic(o.prompt, o.provider, model, spec);
      spec = sanitize({ ...spec, music: "custom", bpm: m.bpm, track: m.track });
    } catch (e: any) {
      warning = `"${spec.title}": beat failed (${String(e?.message ?? e).slice(0, 120)}), kept the trailer score.`;
    }
  }
  const gens = readList("generations.json");
  gens.unshift({ id: Date.now().toString(36) + Math.random().toString(36).slice(2, 5), at: Date.now(), prompt: o.prompt, model, provider: o.provider, revise: !!o.current, spec });
  writeList("generations.json", gens.slice(0, 100));
  return { spec, warning };
}

const pos = (beat: number) => `${Math.floor(beat / 4) + 1}.${Math.round(((beat % 4) + 1) * 100) / 100}`; // bar.beat, both from 1

function cueText(spec: ReelSpec) {
  const rows = cueSheet(spec);
  const total = rows.reduce((n, r) => n + r.beats, 0);
  const lines = rows.map((r) => {
    const hits = sceneEvents(spec.scenes[r.i]).map((e) => `${pos(r.startBeat + e.beat)} ${e.label}`);
    return `  ${r.i + 1}. ${r.kind} "${r.label}" | starts bar ${r.bar} beat ${r.beatInBar} (beat ${r.startBeat}) | ${r.beats} beats | energy ${r.energy}\n       pops on (bar.beat): ${hits.join("; ")}`;
  });
  const ovs = spec.overlays.map((o) => `  overlay "${o.text}" pops on ${pos(o.at)}`);
  return `REEL TO SCORE (title: "${spec.title}"), ${rows.length} scenes, ${total} beats = ${(total / 4).toFixed(1)} bars.\nScene beats are counted in the tempo you pick (currently ${spec.bpm} BPM, you may change it).\n${lines.join("\n")}${ovs.length ? "\nOverlays:\n" + ovs.join("\n") : ""}\n\nEVERY pop listed above is a visual action that is locked to a beat, so the rhythm you write must land on them: put kick, snare, clap or a hat accent on the beat of each pop, and where pops sit on consecutive beats (item pops, chips, punch words) keep a steady kick or hat on every one of those beats. Rests in your pattern on a pop beat make it feel late. Fractional beats (.25 or .5) are 16th or 8th notes.\nThe player also plays every sequenced pop (items, chips, words) as a rising note run in your key and an impact on every scene cut, so choose a key and scale where a rising run sounds good and keep your lead quiet and the bass simple on those beats.\nFirst high-energy scene starts in bar ${suggestDropBar(spec) + 1}, so dropBar should be ${suggestDropBar(spec)}.`;
}

async function generateMusic(prompt: string, provider: string, model: string, spec?: ReelSpec) {
  const user = `Brief: ${prompt || "fit the reel"}${spec ? `\n\n${cueText(spec)}` : ""}`;
  const r = parseJson(await ask(provider, pickModel(model), MUSIC_ONLY_SYSTEM, user));
  const track = sanitizeTrack(r.track ?? r);
  if (spec) {
    // keep the drop inside the reel; if the model left it out, land it on the first big scene
    const bars = Math.max(1, Math.floor(spec.scenes.reduce((n, s) => n + s.beats, 0) / 4));
    const want = suggestDropBar(spec);
    track.dropBar = track.dropBar > 0 ? Math.min(track.dropBar, bars - 1) : want;
  }
  return { bpm: Math.round(Math.min(180, Math.max(70, Number(r.bpm) || spec?.bpm || 128))), track };
}

// ---------- rendering ----------
type Job = { id: string; reel: string; status: "bundling" | "rendering" | "done" | "error"; progress: number; file?: string; error?: string; startedAt: number };
const jobs = new Map<string, Job>();
let bundled: Promise<string> | null = null;
// Scene code changes need a fresh bundle; cache is per server run, and dropped when a render fails.
const getBundle = () =>
  (bundled ??= bundle({ entryPoint: path.join(ROOT, "src", "index.ts") }).catch((e) => {
    bundled = null;
    throw e;
  }));

function startRender(reel: string, spec: ReelSpec) {
  const id = `${safeId(reel)}-${Date.now().toString(36)}`;
  const job: Job = { id, reel, status: "bundling", progress: 0, startedAt: Date.now() };
  jobs.set(id, job);
  (async () => {
    try {
      const serveUrl = await getBundle();
      job.status = "rendering";
      let audioSrc: string | undefined;
      if (spec.music === "custom" && spec.track) {
        // the same synth the editor previews with, written out and served so the headless render can fetch it
        fs.writeFileSync(path.join(TRACKS, `${id}.wav`), encodeWav(renderTrack(spec.track, spec.bpm, durationSeconds(spec) + 0.3, 44100, false, cueList(spec))));
        audioSrc = `http://localhost:${PORT}/tracks/${id}.wav`;
      }
      const inputProps = { spec, audioSrc };
      const composition = await selectComposition({ serveUrl, id: "Reel", inputProps, logLevel: "error" });
      const file = `${id}.mp4`;
      await renderMedia({
        composition, serveUrl, codec: "h264", crf: 16, pixelFormat: "yuv420p", inputProps, logLevel: "error",
        outputLocation: path.join(OUT, file),
        onProgress: ({ progress }) => { job.progress = progress; },
      });
      fs.writeFileSync(path.join(OUT, `${id}.json`), JSON.stringify(spec, null, 2));
      job.file = file;
      job.status = "done";
      job.progress = 1;
    } catch (e: any) {
      job.status = "error";
      job.error = String(e?.message ?? e);
    }
  })();
  return job;
}

// ---------- http ----------
async function api(req: http.IncomingMessage, res: http.ServerResponse, url: URL) {
  const p = url.pathname;
  try {
    if (p === "/api/status") return json(res, 200, { hasKey: !!apiKey(), hasCli: HAS_CLI, models: MODELS });
    if (p === "/api/generations") return json(res, 200, readList("generations.json"));
    let g = p.match(/^\/api\/generations\/([\w-]+)$/);
    if (g && req.method === "DELETE") { writeList("generations.json", readList("generations.json").filter((x) => x.id !== g![1])); return json(res, 200, { ok: true }); }
    if (p === "/api/library/scenes" && req.method === "GET") return json(res, 200, readList("scenes.json"));
    if (p === "/api/library/scenes" && req.method === "POST") {
      const b = await readBody(req);
      const one = sanitize({ scenes: [b.scene] }).scenes[0];
      const l = readList("scenes.json");
      l.unshift({ id: Date.now().toString(36), name: String(b.name ?? "Scene").slice(0, 60), scene: one });
      writeList("scenes.json", l);
      return json(res, 200, l);
    }
    g = p.match(/^\/api\/library\/scenes\/([\w-]+)$/);
    if (g && req.method === "DELETE") { writeList("scenes.json", readList("scenes.json").filter((x) => x.id !== g![1])); return json(res, 200, { ok: true }); }
    if (p === "/api/reels" && req.method === "GET") {
      const list = fs.readdirSync(REELS).filter((f) => f.endsWith(".json")).map((f) => {
        const spec = sanitize(JSON.parse(fs.readFileSync(path.join(REELS, f), "utf8")));
        return { id: f.slice(0, -5), title: spec.title, format: spec.format, scenes: spec.scenes.length, mtime: fs.statSync(path.join(REELS, f)).mtimeMs };
      });
      return json(res, 200, list.sort((a, b) => b.mtime - a.mtime));
    }
    const m = p.match(/^\/api\/reels\/([\w-]+)$/);
    if (m) {
      const file = path.join(REELS, `${safeId(m[1])}.json`);
      if (req.method === "GET") return fs.existsSync(file) ? json(res, 200, sanitize(JSON.parse(fs.readFileSync(file, "utf8")))) : json(res, 404, { error: "not found" });
      if (req.method === "PUT") { fs.writeFileSync(file, JSON.stringify(sanitize(await readBody(req)), null, 2)); return json(res, 200, { ok: true }); }
      if (req.method === "DELETE") { fs.rmSync(file, { force: true }); return json(res, 200, { ok: true }); }
    }
    if (p === "/api/generate" && req.method === "POST") {
      const b = await readBody(req);
      return json(res, 200, await generate({ prompt: String(b.prompt ?? "").slice(0, 2000), format: String(b.format ?? "9:16"), provider: String(b.provider ?? "subscription"), model: String(b.model ?? ""), current: b.current ? sanitize(b.current) : undefined, music: musicMode(b.music) }));
    }
    if (p === "/api/generate-batch" && req.method === "POST") {
      // N different takes on one brief, made in parallel and saved as separate reels
      const b = await readBody(req);
      const n = Math.min(6, Math.max(1, Number(b.count) || 1));
      const start = Math.floor(Math.random() * ANGLES.length);
      const results = await Promise.allSettled(Array.from({ length: n }, (_, i) =>
        generate({ prompt: String(b.prompt ?? "").slice(0, 2000), format: String(b.format ?? "9:16"), provider: String(b.provider ?? "subscription"), model: String(b.model ?? ""), music: musicMode(b.music), angle: n > 1 ? ANGLES[(start + i) % ANGLES.length] : undefined })));
      const ok = results.flatMap((r) => (r.status === "fulfilled" ? [r.value] : []));
      if (!ok.length) throw new Error((results[0] as PromiseRejectedResult).reason?.message ?? "Generation failed");
      return json(res, 200, { specs: ok.map((x) => x.spec), failed: n - ok.length, warnings: ok.flatMap((x) => (x.warning ? [x.warning] : [])) });
    }
    if (p === "/api/generate-music" && req.method === "POST") {
      const b = await readBody(req);
      return json(res, 200, await generateMusic(String(b.prompt ?? "").slice(0, 1000), String(b.provider ?? "subscription"), String(b.model ?? ""), b.spec ? sanitize(b.spec) : undefined));
    }
    if (p === "/api/library/tracks" && req.method === "GET") return json(res, 200, readList("tracks.json"));
    if (p === "/api/library/tracks" && req.method === "POST") {
      const b = await readBody(req);
      const l = readList("tracks.json");
      l.unshift({ id: Date.now().toString(36), name: String(b.name ?? "Track").slice(0, 60), bpm: Math.min(180, Math.max(70, Number(b.bpm) || 128)), track: sanitizeTrack(b.track) });
      writeList("tracks.json", l);
      return json(res, 200, l);
    }
    g = p.match(/^\/api\/library\/tracks\/([\w-]+)$/);
    if (g && req.method === "DELETE") { writeList("tracks.json", readList("tracks.json").filter((x) => x.id !== g![1])); return json(res, 200, { ok: true }); }
    if (p === "/api/render" && req.method === "POST") {
      const b = await readBody(req);
      return json(res, 200, startRender(String(b.id ?? "reel"), sanitize(b.spec)));
    }
    if (p === "/api/jobs") return json(res, 200, [...jobs.values()].sort((a, b) => b.startedAt - a.startedAt));
    if (p === "/api/renders") {
      const list = fs.readdirSync(OUT).filter((f) => f.endsWith(".mp4")).map((f) => {
        const jf = path.join(OUT, f.replace(/\.mp4$/, ".json"));
        const st = fs.statSync(path.join(OUT, f));
        return { file: f, title: fs.existsSync(jf) ? JSON.parse(fs.readFileSync(jf, "utf8")).title : f, mtime: st.mtimeMs, size: st.size };
      });
      return json(res, 200, list.sort((a, b) => b.mtime - a.mtime));
    }
    return json(res, 404, { error: "no such endpoint" });
  } catch (e: any) {
    return json(res, 500, { error: String(e?.message ?? e) });
  }
}

function serveRender(req: http.IncomingMessage, res: http.ServerResponse, url: URL) {
  const file = path.join(OUT, path.basename(decodeURIComponent(url.pathname)));
  if (!fs.existsSync(file)) { res.writeHead(404); return res.end(); }
  const size = fs.statSync(file).size;
  const range = req.headers.range?.match(/bytes=(\d*)-(\d*)/);
  const dl = url.searchParams.get("download") ? { "content-disposition": `attachment; filename="${path.basename(file)}"` } : {};
  if (range) {
    const start = range[1] ? Number(range[1]) : 0, end = range[2] ? Number(range[2]) : size - 1;
    res.writeHead(206, { "content-type": "video/mp4", "accept-ranges": "bytes", "content-range": `bytes ${start}-${end}/${size}`, "content-length": end - start + 1, ...dl });
    fs.createReadStream(file, { start, end }).pipe(res);
  } else {
    res.writeHead(200, { "content-type": "video/mp4", "accept-ranges": "bytes", "content-length": size, ...dl });
    fs.createReadStream(file).pipe(res);
  }
}

const vite = await createVite({
  root: path.join(ROOT, "dashboard"),
  configFile: path.join(ROOT, "dashboard", "vite.config.ts"),
  server: { middlewareMode: true },
  appType: "spa",
});
http
  .createServer((req, res) => {
    const url = new URL(req.url ?? "/", "http://x");
    if (url.pathname.startsWith("/api/")) return void api(req, res, url);
    if (url.pathname.startsWith("/renders/")) return serveRender(req, res, url);
    if (url.pathname.startsWith("/tracks/")) {
      const f = path.join(TRACKS, path.basename(url.pathname));
      if (!fs.existsSync(f)) { res.writeHead(404); return void res.end(); }
      res.writeHead(200, { "content-type": "audio/wav", "content-length": fs.statSync(f).size, "access-control-allow-origin": "*" });
      return void fs.createReadStream(f).pipe(res);
    }
    vite.middlewares(req, res);
  })
  .listen(PORT, () => {
    console.log(`\n  Bunk Master reel studio: http://localhost:${PORT}`);
    console.log(`  Storyboards: ${HAS_CLI ? "Claude subscription (Claude Code CLI)" : "CLI not found"}${apiKey() ? " + API key" : ""}`);
  });
