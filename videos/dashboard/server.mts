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
import type { ReelSpec } from "../src/reel/spec.ts";

const { BPM, FORMATS, ITEMS, KINDS, MAX_BEATS, PLATES, THEMES, sanitize } = ((specNs as any).default ?? specNs) as typeof specNs;
const ROOT = process.cwd();
const REELS = path.join(ROOT, "reels");
const OUT = path.join(ROOT, "out", "reels");
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

RULES: on-screen text is SHORT (headline <= 5 words per line, use \\n for 2 lines; captions <= 6 words). Vary scene kinds, do not repeat one kind three times in a row. Use "words" for rhythm (3 to 6 words, scene beats = number of words). Use "alert" when something goes wrong. Each scene needs a unique short "id".

SCHEMA: {"title":string,"format":"9:16"|"1:1"|"16:9","theme":string,"music":"trailer","musicStartBar":0-12,"scenes":[{"id":string,"kind":string,"beats":int,"text"?:string,"sub"?:string,"items"?:string[],"plate"?:string,"variant"?:"hero"|"icon"}]}`;

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

async function generate(prompt: string, format: string, provider: string, model: string, current?: ReelSpec) {
  if (!MODELS.some((m) => m.id === model)) model = MODELS[0].id;
  const user = [
    `Brief: ${prompt}`,
    `Format: ${format}`,
    current ? `Current reel (revise it according to the brief, keep what still works):\n${JSON.stringify(current)}` : "No current reel: design a new one.",
  ].join("\n\n");
  const text = provider === "api" ? await viaApi(model, SYSTEM, user) : await viaCli(model, SYSTEM, user);
  const a = text.indexOf("{"), b = text.lastIndexOf("}");
  if (a < 0 || b < a) throw new Error("Model returned no JSON");
  const spec = sanitize(JSON.parse(text.slice(a, b + 1)));
  if (format in FORMATS) spec.format = format as ReelSpec["format"];
  const gens = readList("generations.json");
  gens.unshift({ id: Date.now().toString(36), at: Date.now(), prompt, model, provider, revise: !!current, spec });
  writeList("generations.json", gens.slice(0, 100));
  return spec;
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
      const composition = await selectComposition({ serveUrl, id: "Reel", inputProps: { spec }, logLevel: "error" });
      const file = `${id}.mp4`;
      await renderMedia({
        composition, serveUrl, codec: "h264", crf: 16, pixelFormat: "yuv420p", inputProps: { spec }, logLevel: "error",
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
      return json(res, 200, await generate(String(b.prompt ?? "").slice(0, 2000), String(b.format ?? "9:16"), String(b.provider ?? "subscription"), String(b.model ?? ""), b.current ? sanitize(b.current) : undefined));
    }
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
    vite.middlewares(req, res);
  })
  .listen(PORT, () => {
    console.log(`\n  Bunk Master reel studio: http://localhost:${PORT}`);
    console.log(`  Storyboards: ${HAS_CLI ? "Claude subscription (Claude Code CLI)" : "CLI not found"}${apiKey() ? " + API key" : ""}`);
  });
