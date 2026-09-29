import type { ReelSpec, Scene, Track } from "../src/reel/spec";

async function call<T>(url: string, init?: RequestInit): Promise<T> {
  const r = await fetch(url, init && { ...init, headers: { "content-type": "application/json" } });
  const data = await r.json();
  if (!r.ok) throw new Error(data?.error ?? `HTTP ${r.status}`);
  return data;
}
const body = (method: string, b: unknown): RequestInit => ({ method, body: JSON.stringify(b) });

export type ReelRow = { id: string; title: string; format: string; scenes: number; mtime: number };
export type Job = { id: string; reel: string; status: "bundling" | "rendering" | "done" | "error"; progress: number; file?: string; error?: string; startedAt: number };
export type RenderRow = { file: string; title: string; mtime: number; size: number };

export const api = {
  status: () => call<{ hasKey: boolean; hasCli: boolean; models: { id: string; label: string }[] }>("/api/status"),
  generations: () => call<Generation[]>("/api/generations"),
  delGeneration: (id: string) => call(`/api/generations/${id}`, { method: "DELETE" }),
  scenes: () => call<LibScene[]>("/api/library/scenes"),
  saveScene: (name: string, scene: Scene) => call<LibScene[]>("/api/library/scenes", body("POST", { name, scene })),
  delScene: (id: string) => call(`/api/library/scenes/${id}`, { method: "DELETE" }),
  reels: () => call<ReelRow[]>("/api/reels"),
  load: (id: string) => call<ReelSpec>(`/api/reels/${id}`),
  save: (id: string, spec: ReelSpec) => call(`/api/reels/${id}`, body("PUT", spec)),
  remove: (id: string) => call(`/api/reels/${id}`, { method: "DELETE" }),
  generate: (prompt: string, format: string, provider: string, model: string, current?: ReelSpec, music: MusicMode = "trailer") => call<{ spec: ReelSpec; warning?: string }>("/api/generate", body("POST", { prompt, format, provider, model, current, music })),
  generateBatch: (prompt: string, format: string, provider: string, model: string, count: number, music: MusicMode) =>
    call<{ specs: ReelSpec[]; failed: number; warnings: string[] }>("/api/generate-batch", body("POST", { prompt, format, provider, model, count, music })),
  generateMusic: (prompt: string, provider: string, model: string, spec: ReelSpec) => call<{ bpm: number; track: Track }>("/api/generate-music", body("POST", { prompt, provider, model, spec })),
  tracks: () => call<LibTrack[]>("/api/library/tracks"),
  saveTrack: (name: string, bpm: number, track: Track) => call<LibTrack[]>("/api/library/tracks", body("POST", { name, bpm, track })),
  delTrack: (id: string) => call(`/api/library/tracks/${id}`, { method: "DELETE" }),
  render: (id: string, spec: ReelSpec) => call<Job>("/api/render", body("POST", { id, spec })),
  jobs: () => call<Job[]>("/api/jobs"),
  renders: () => call<RenderRow[]>("/api/renders"),
};
export type Generation = { id: string; at: number; prompt: string; model: string; provider: string; revise: boolean; spec: ReelSpec };
export type LibScene = { id: string; name: string; scene: Scene };
export type LibTrack = { id: string; name: string; bpm: number; track: Track };
export type MusicMode = "trailer" | "compose" | "none";
