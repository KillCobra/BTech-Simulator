import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Player, PlayerRef } from "@remotion/player";
import { Reel } from "../src/reel/Reel";
import {
  BEAT, DEFAULT_SCENE, FORMATS, FPS, ITEMS, KINDS, PLATES, SAMPLE, THEMES, durationFrames, durationSeconds, newId, sanitize, sceneFrames, totalBeats,
  Format, ReelSpec, Scene, SceneKind, MAX_BEATS,
} from "../src/reel/spec";
import { api, Generation, Job, LibScene, ReelRow, RenderRow } from "./api";

const KIND_COLOR: Record<SceneKind, string> = { title: "#ffc93c", words: "#b07cff", plate: "#9fd8ff", voxel: "#7fe0a0", icons: "#ff9a3c", alert: "#ff6b63", cta: "#ffd24a" };
const IDEAS = [
  "15s hook: your teacher is watching, friends panic, escape",
  "Proximity voice: staff hear how loud you are, never what you say",
  "Chaos tools: trolley, paper ball, blame a friend",
  "Coming soon teaser, 20s, hype",
  "Item trading: hall pass, samosa, medical note",
];
const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 32) || "reel";

export const App: React.FC = () => {
  const [reels, setReels] = useState<ReelRow[]>([]);
  const [id, setId] = useState<string | null>(null);
  const [spec, setSpecRaw] = useState<ReelSpec>(SAMPLE);
  const [sel, setSel] = useState(0);
  const [prompt, setPrompt] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const [caps, setCaps] = useState({ hasKey: false, hasCli: false, models: [] as { id: string; label: string }[] });
  const pref = (k: string, d: string) => { try { return localStorage.getItem(k) ?? d; } catch { return d; } };
  const [provider, setProvider] = useState(pref("provider", "subscription"));
  const [model, setModel] = useState(pref("model", "claude-opus-5-5"));
  const [gens, setGens] = useState<Generation[]>([]);
  const [lib, setLib] = useState<LibScene[]>([]);
  useEffect(() => { try { localStorage.setItem("provider", provider); localStorage.setItem("model", model); } catch { /* private mode */ } }, [provider, model]);
  const [tab, setTab] = useState<"scene" | "renders">("scene");
  const [jobs, setJobs] = useState<Job[]>([]);
  const [renders, setRenders] = useState<RenderRow[]>([]);
  const player = useRef<PlayerRef>(null);
  const hist = useRef<{ stack: ReelSpec[]; at: number }>({ stack: [], at: 0 });
  const [, bump] = useState(0);

  const refreshReels = useCallback(() => api.reels().then(setReels).catch(() => {}), []);
  const refreshRenders = useCallback(() => api.renders().then(setRenders).catch(() => {}), []);

  // spec edits go through here so undo works; rapid typing collapses into one step
  const setSpec = useCallback((next: ReelSpec | ((s: ReelSpec) => ReelSpec)) => {
    setSpecRaw((cur) => {
      const n = typeof next === "function" ? next(cur) : next;
      const h = hist.current;
      if (Date.now() - h.at > 700) { h.stack.push(cur); if (h.stack.length > 60) h.stack.shift(); }
      h.at = Date.now();
      bump((x) => x + 1);
      return n;
    });
  }, []);
  const undo = () => {
    const prev = hist.current.stack.pop();
    if (prev) { hist.current.at = 0; setSpecRaw(prev); setSel((s) => Math.min(s, prev.scenes.length - 1)); bump((x) => x + 1); }
  };

  const openReel = useCallback(async (rid: string) => {
    const s = await api.load(rid);
    hist.current = { stack: [], at: 0 };
    setId(rid); setSpecRaw(s); setSel(0); setErr("");
  }, []);
  const newReel = (s: ReelSpec = SAMPLE) => {
    const rid = `${slug(s.title)}-${Math.random().toString(36).slice(2, 6)}`;
    hist.current = { stack: [], at: 0 };
    setId(rid); setSpecRaw(s); setSel(0);
    api.save(rid, s).then(refreshReels);
    return rid;
  };

  useEffect(() => {
    api.status().then((s) => { setCaps(s); if (!s.hasCli && s.hasKey) setProvider("api"); }).catch(() => {});
    api.generations().then(setGens).catch(() => {});
    api.scenes().then(setLib).catch(() => {});
    refreshRenders();
    api.reels().then((list) => { setReels(list); list.length ? openReel(list[0].id) : newReel(); }).catch((e) => setErr(String(e.message)));
  }, []); // eslint-disable-line

  // autosave
  useEffect(() => {
    if (!id) return;
    const t = setTimeout(() => api.save(id, spec).then(refreshReels).catch(() => {}), 500);
    return () => clearTimeout(t);
  }, [spec, id, refreshReels]);

  // render jobs
  const active = jobs.some((j) => j.status === "bundling" || j.status === "rendering");
  useEffect(() => {
    if (!active) return;
    const t = setInterval(() => api.jobs().then((j) => { setJobs(j); if (!j.some((x) => x.status === "bundling" || x.status === "rendering")) refreshRenders(); }), 1000);
    return () => clearInterval(t);
  }, [active, refreshRenders]);

  useEffect(() => {
    const k = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "z" && !(e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement)) { e.preventDefault(); undo(); }
    };
    window.addEventListener("keydown", k);
    return () => window.removeEventListener("keydown", k);
  }, []);

  const canAsk = provider === "api" ? caps.hasKey : caps.hasCli;
  const frames = useMemo(() => sceneFrames(spec), [spec]);
  const fmt = FORMATS[spec.format];
  const scene = spec.scenes[Math.min(sel, spec.scenes.length - 1)];

  const patch = (p: Partial<Scene>) => setSpec((s) => ({ ...s, scenes: s.scenes.map((x, i) => (i === sel ? { ...x, ...p } : x)) }));
  const select = (i: number) => {
    setSel(i);
    setTab("scene");
    player.current?.pause();
    player.current?.seekTo(frames[i].from + Math.min(frames[i].frames - 1, 12));
  };
  const addScene = (kind: SceneKind) => {
    if (totalBeats(spec) + DEFAULT_SCENE[kind].beats > MAX_BEATS) return setErr(`Music is ${MAX_BEATS} beats long; shorten a scene first.`);
    const at = Math.min(sel + 1, spec.scenes.length);
    setSpec((s) => ({ ...s, scenes: [...s.scenes.slice(0, at), { ...DEFAULT_SCENE[kind], id: newId() }, ...s.scenes.slice(at)] }));
    setSel(at); setErr("");
  };
  const move = (from: number, to: number) => {
    if (from === to || to < 0 || to >= spec.scenes.length) return;
    setSpec((s) => { const a = [...s.scenes]; const [m] = a.splice(from, 1); a.splice(to, 0, m); return { ...s, scenes: a }; });
    setSel(to);
  };
  const dup = () => setSpec((s) => ({ ...s, scenes: [...s.scenes.slice(0, sel + 1), { ...scene, id: newId() }, ...s.scenes.slice(sel + 1)] }));
  const del = () => {
    if (spec.scenes.length <= 1) return;
    setSpec((s) => ({ ...s, scenes: s.scenes.filter((_, i) => i !== sel) }));
    setSel((v) => Math.max(0, v - 1));
  };
  const setBeats = (n: number) => {
    const others = totalBeats(spec) - scene.beats;
    patch({ beats: Math.max(1, Math.min(32, Math.min(n, MAX_BEATS - others))) });
  };

  const generate = async (revise: boolean) => {
    if (!prompt.trim()) return;
    setBusy(true); setErr("");
    try {
      const next = await api.generate(prompt, spec.format, provider, model, revise ? spec : undefined);
      api.generations().then(setGens);
      if (revise || !id) setSpec(next); else { newReel(next); }
      setSel(0);
      player.current?.seekTo(0);
    } catch (e: any) { setErr(e.message); }
    setBusy(false);
  };

  const render = async () => {
    if (!id) return;
    setErr("");
    try {
      await api.save(id, spec);
      const job = await api.render(id, spec);
      setJobs((j) => [job, ...j]);
      setTab("renders");
    } catch (e: any) { setErr(e.message); }
  };

  return (
    <div className="app">
      <header className="top">
        <div className="brand">BUNK MASTER<small>Reel Studio</small></div>
        <input className="title-in" value={spec.title} onChange={(e) => setSpec((s) => ({ ...s, title: e.target.value }))} aria-label="Reel title" />
        <div className="spacer" />
        <div className="seg" title="Format">
          {(Object.keys(FORMATS) as Format[]).map((f) => (
            <button key={f} className={spec.format === f ? "on" : ""} onClick={() => setSpec((s) => ({ ...s, format: f }))}>{f}</button>
          ))}
        </div>
        <select style={{ width: 110 }} value={spec.theme} onChange={(e) => setSpec((s) => ({ ...s, theme: e.target.value as any }))} aria-label="Theme">
          {Object.entries(THEMES).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
        </select>
        <div className="seg" title="Music">
          <button className={spec.music === "trailer" ? "on" : ""} onClick={() => setSpec((s) => ({ ...s, music: "trailer" }))}>Music</button>
          <button className={spec.music === "none" ? "on" : ""} onClick={() => setSpec((s) => ({ ...s, music: "none" }))}>Mute</button>
        </div>
        <button className="btn" onClick={undo} disabled={!hist.current.stack.length}>Undo</button>
        <button className="btn gold" onClick={render} disabled={!id || active}>{active ? "Rendering…" : "Render MP4"}</button>
      </header>

      <div className="main">
        <aside className="col left">
          <section>
            <h3>Ask Claude</h3>
            <div className="seg" style={{ marginBottom: 8, width: "100%" }}>
              <button style={{ flex: 1 }} className={provider === "subscription" ? "on" : ""} onClick={() => setProvider("subscription")} title="Uses your Claude login through Claude Code">Subscription</button>
              <button style={{ flex: 1 }} className={provider === "api" ? "on" : ""} onClick={() => setProvider("api")} title="Uses ANTHROPIC_API_KEY (pay per token)">API key</button>
            </div>
            <select value={model} onChange={(e) => setModel(e.target.value)} aria-label="Model" style={{ marginBottom: 8 }}>
              {caps.models.map((m) => <option key={m.id} value={m.id}>{m.label}</option>)}
            </select>
            {!canAsk && (
              <div className="note" style={{ marginBottom: 8 }}>
                {provider === "api" ? <>No API key. Add <code>ANTHROPIC_API_KEY=…</code> to <code>videos/dashboard/.env</code> and restart.</> : <>Claude Code CLI not found. Install it and run <code>claude</code> once to sign in.</>}
              </div>
            )}
            <textarea placeholder="Describe the reel: audience, feature to sell, mood, length…" value={prompt} onChange={(e) => setPrompt(e.target.value)} />
            <div className="row" style={{ marginTop: 8 }}>
              <button className="btn orange" style={{ flex: 1 }} disabled={busy || !prompt.trim() || !canAsk} onClick={() => generate(false)}>{busy ? "Thinking…" : "New reel"}</button>
              <button className="btn" style={{ flex: 1 }} disabled={busy || !prompt.trim() || !canAsk} onClick={() => generate(true)}>Revise this</button>
            </div>
            <div className="chips">{IDEAS.map((i) => <button key={i} className="chip" onClick={() => setPrompt(i)}>{i.split(":")[0]}</button>)}</div>
            {err && <div className="err">{err}</div>}
          </section>
          <section>
            <div className="row" style={{ justifyContent: "space-between" }}>
              <h3 style={{ margin: 0 }}>Reels</h3>
              <button className="btn sm" onClick={() => newReel({ ...SAMPLE, title: "New reel" })}>+ Blank</button>
            </div>
            <div className="reel-list" style={{ marginTop: 8 }}>
              {reels.map((r) => (
                <div key={r.id} className={`reel-item ${r.id === id ? "on" : ""}`} onClick={() => openReel(r.id)}>
                  <div className="t">{r.title}</div>
                  <div className="m">{r.format} · {r.scenes}</div>
                  <button className="x" title="Delete" onClick={(e) => { e.stopPropagation(); if (confirm(`Delete "${r.title}"?`)) api.remove(r.id).then(() => { refreshReels(); if (r.id === id) { setId(null); api.reels().then((l) => { if (l.length) openReel(l[0].id); else newReel(); }); } }); }}>✕</button>
                </div>
              ))}
              {!reels.length && <div className="empty">No saved reels yet.</div>}
            </div>
          </section>
          <section>
            <h3>Scene library</h3>
            {lib.map((l) => (
              <div key={l.id} className="reel-item" title="Insert after the selected scene" onClick={() => { setSpec((sp) => ({ ...sp, scenes: [...sp.scenes.slice(0, sel + 1), { ...l.scene, id: newId() }, ...sp.scenes.slice(sel + 1)] })); setSel(sel + 1); }}>
                <span style={{ width: 10, height: 10, borderRadius: 3, background: KIND_COLOR[l.scene.kind] }} />
                <div className="t">{l.name}</div>
                <button className="x" onClick={(e) => { e.stopPropagation(); api.delScene(l.id).then(() => setLib((x) => x.filter((y) => y.id !== l.id))); }}>✕</button>
              </div>
            ))}
            {!lib.length && <div className="empty">Save scenes from the Scene tab to reuse them in any reel.</div>}
          </section>
          <section>
            <h3>Generation history</h3>
            {gens.slice(0, 15).map((g) => (
              <div key={g.id} className="reel-item" style={{ display: "block" }}>
                <div className="t" style={{ whiteSpace: "normal" }}>{g.prompt}</div>
                <div className="m">{caps.models.find((m) => m.id === g.model)?.label ?? g.model} · {g.spec.scenes.length} scenes · {new Date(g.at).toLocaleDateString()}</div>
                <div className="row" style={{ marginTop: 6 }}>
                  <button className="btn sm" onClick={() => newReel({ ...g.spec, title: g.spec.title })}>Open as reel</button>
                  <button className="btn sm" onClick={() => setPrompt(g.prompt)}>Reuse prompt</button>
                  <button className="x" onClick={() => api.delGeneration(g.id).then(() => setGens((x) => x.filter((y) => y.id !== g.id)))}>✕</button>
                </div>
              </div>
            ))}
            {!gens.length && <div className="empty">Every storyboard Claude makes is kept here.</div>}
          </section>
        </aside>

        <main className="col center">
          <div className="stage">
            <div className="frame" style={{ aspectRatio: `${fmt.width} / ${fmt.height}` }}>
              <Player
                ref={player} component={Reel} inputProps={{ spec }} durationInFrames={durationFrames(spec)} fps={FPS}
                compositionWidth={fmt.width} compositionHeight={fmt.height} controls loop acknowledgeRemotionLicense
                style={{ width: "100%", height: "100%" }} clickToPlay
              />
            </div>
          </div>
          <div className="stage-info">
            <span>{fmt.label} · {fmt.width}×{fmt.height} · {FPS} fps</span>
            <span>{durationSeconds(spec).toFixed(1)} s · {totalBeats(spec)}/{MAX_BEATS} beats · 128 BPM</span>
          </div>
          <Timeline spec={spec} frames={frames} sel={sel} player={player} onSelect={select} onMove={move} onAdd={addScene} />
        </main>

        <aside className="col right">
          <div className="seg" style={{ marginBottom: 14 }}>
            <button className={tab === "scene" ? "on" : ""} onClick={() => setTab("scene")}>Scene</button>
            <button className={tab === "renders" ? "on" : ""} onClick={() => setTab("renders")}>Renders{active ? " •" : ""}</button>
          </div>
          {tab === "scene" ? (
            scene && <Inspector saveToLib={() => { const n = prompt2(scene); if (n) api.saveScene(n, scene).then(setLib); }} scene={scene} idx={sel} count={spec.scenes.length} patch={patch} setBeats={setBeats} move={move} dup={dup} del={del} />
          ) : (
            <Renders jobs={jobs} renders={renders} />
          )}
        </aside>
      </div>
    </div>
  );
};

const Timeline: React.FC<{
  spec: ReelSpec; frames: { from: number; frames: number }[]; sel: number; player: React.RefObject<PlayerRef | null>;
  onSelect: (i: number) => void; onMove: (a: number, b: number) => void; onAdd: (k: SceneKind) => void;
}> = ({ spec, frames, sel, player, onSelect, onMove, onAdd }) => {
  const [frame, setFrame] = useState(0);
  const [drag, setDrag] = useState<number | null>(null);
  const [over, setOver] = useState<number | null>(null);
  useEffect(() => {
    const p = player.current;
    if (!p) return;
    const f = (e: { detail: { frame: number } }) => setFrame(e.detail.frame);
    p.addEventListener("frameupdate", f);
    return () => p.removeEventListener("frameupdate", f);
  }, [player]);
  const total = durationFrames(spec);
  return (
    <div className="timeline">
      <div className="tl-head">
        <h3 style={{ margin: 0 }}>Timeline · drag to reorder</h3>
      </div>
      <div className="tl-track">
        {spec.scenes.map((s, i) => (
          <div
            key={s.id} draggable className={`blk ${i === sel ? "on" : ""} ${over === i && drag !== i ? "over" : ""}`}
            style={{ flex: `${frames[i].frames} 1 0`, background: KIND_COLOR[s.kind] }}
            onClick={() => onSelect(i)} onDragStart={() => setDrag(i)} onDragOver={(e) => { e.preventDefault(); setOver(i); }}
            onDrop={() => { if (drag !== null) onMove(drag, i); setDrag(null); setOver(null); }} onDragEnd={() => { setDrag(null); setOver(null); }}
          >
            <b>{KINDS[s.kind].label}</b>
            <span>{s.beats} beats · {(s.beats * BEAT).toFixed(1)}s{s.text ? ` · ${s.text.replace(/\\n|\n/g, " ")}` : ""}</span>
          </div>
        ))}
        <div className="playhead" style={{ left: `${(frame / total) * 100}%` }} />
      </div>
      <div className="add">
        {(Object.keys(KINDS) as SceneKind[]).map((k) => (
          <button key={k} className="btn sm ghost" title={KINDS[k].hint} onClick={() => onAdd(k)}>+ {KINDS[k].label}</button>
        ))}
      </div>
    </div>
  );
};

const prompt2 = (sc: Scene) => window.prompt("Name for this scene", `${KINDS[sc.kind].label}: ${(sc.text ?? "").replace(/\\n|\n/g, " ").slice(0, 30)}`);

const Inspector: React.FC<{ saveToLib: () => void;
  scene: Scene; idx: number; count: number; patch: (p: Partial<Scene>) => void; setBeats: (n: number) => void;
  move: (a: number, b: number) => void; dup: () => void; del: () => void;
}> = ({ scene, idx, count, patch, setBeats, move, dup, del, saveToLib }) => {
  const k = scene.kind;
  const toggle = (list: string[], v: string) => (list.includes(v) ? list.filter((x) => x !== v) : [...list, v]);
  const changeKind = (nk: SceneKind) => patch({ ...DEFAULT_SCENE[nk], beats: scene.beats, kind: nk });
  return (
    <div>
      <div className="insp-head">
        <h3 style={{ margin: 0 }}>Scene {idx + 1} of {count}</h3>
        <div className="row">
          <button className="btn sm" onClick={() => move(idx, idx - 1)} disabled={idx === 0} title="Earlier">←</button>
          <button className="btn sm" onClick={() => move(idx, idx + 1)} disabled={idx === count - 1} title="Later">→</button>
          <button className="btn sm" onClick={dup}>Copy</button>
          <button className="btn sm" onClick={saveToLib} title="Save to scene library">★</button>
          <button className="btn sm" onClick={del} disabled={count <= 1}>Delete</button>
        </div>
      </div>
      <p className="empty" style={{ marginTop: 4 }}>{KINDS[k].hint}</p>

      <label>Type</label>
      <select value={k} onChange={(e) => changeKind(e.target.value as SceneKind)}>
        {Object.entries(KINDS).map(([key, v]) => <option key={key} value={key}>{v.label}</option>)}
      </select>

      <label>Length</label>
      <div className="stepper">
        <button className="btn sm" onClick={() => setBeats(scene.beats - 1)}>−</button>
        <output>{scene.beats} beats · {(scene.beats * BEAT).toFixed(2)}s</output>
        <button className="btn sm" onClick={() => setBeats(scene.beats + 1)}>+</button>
        <button className="btn sm ghost" onClick={() => setBeats(scene.beats + 4)} title="Add one bar">+bar</button>
      </div>

      {(k === "title") && (<><label>Headline (Enter = new line)</label><textarea style={{ minHeight: 64 }} value={(scene.text ?? "").replace(/\\n/g, "\n")} onChange={(e) => patch({ text: e.target.value })} /></>)}
      {(k === "plate" || k === "voxel" || k === "icons") && (<><label>Caption</label><input type="text" value={scene.text ?? ""} onChange={(e) => patch({ text: e.target.value })} /></>)}
      {k === "alert" && (<><label>Banner</label><input type="text" value={scene.text ?? ""} onChange={(e) => patch({ text: e.target.value })} /></>)}
      {k === "cta" && (<><label>Tagline</label><input type="text" value={scene.text ?? ""} onChange={(e) => patch({ text: e.target.value })} /></>)}
      {(k === "title" || k === "plate" || k === "alert") && (<><label>{k === "plate" ? "Sticker" : "Sub line"}</label><input type="text" value={scene.sub ?? ""} onChange={(e) => patch({ sub: e.target.value })} /></>)}

      {k === "words" && (
        <>
          <label>Words (one per line, one per beat)</label>
          <textarea value={(scene.items ?? []).join("\n")} onChange={(e) => patch({ items: e.target.value.split("\n").slice(0, 16) })} />
        </>
      )}
      {k === "cta" && (
        <>
          <label>Platform chips (one per line)</label>
          <textarea style={{ minHeight: 56 }} value={(scene.items ?? []).join("\n")} onChange={(e) => patch({ items: e.target.value.split("\n").slice(0, 4) })} />
        </>
      )}
      {k === "plate" && (
        <>
          <label>Screenshot</label>
          <div className="plates">
            {Object.keys(PLATES).map((p) => (
              <button key={p} className={scene.plate === p ? "on" : ""} title={PLATES[p]} onClick={() => patch({ plate: p })}>
                <img src={`/plates/${p}.jpg`} alt={PLATES[p]} />
              </button>
            ))}
          </div>
          <p className="empty">{PLATES[scene.plate ?? "fp0"]}</p>
        </>
      )}
      {k === "voxel" && (
        <>
          <label>Diorama</label>
          <div className="seg"><button className={scene.variant !== "icon" ? "on" : ""} onClick={() => patch({ variant: "hero" })}>Student</button><button className={scene.variant === "icon" ? "on" : ""} onClick={() => patch({ variant: "icon" })}>Icon</button></div>
        </>
      )}
      {k === "icons" && (
        <>
          <label>Items (order = pop order)</label>
          <div className="items">
            {Object.entries(ITEMS).map(([key, name]) => (
              <button key={key} className={(scene.items ?? []).includes(key) ? "on" : ""} onClick={() => patch({ items: toggle(scene.items ?? [], key).slice(0, 6) })}>{name}</button>
            ))}
          </div>
        </>
      )}
      <label style={{ display: "flex", gap: 8, alignItems: "center", marginTop: 16 }}>
        <input type="checkbox" checked={scene.flash !== false} onChange={(e) => patch({ flash: e.target.checked ? undefined : false })} /> Flash on cut
      </label>
    </div>
  );
};

const Renders: React.FC<{ jobs: Job[]; renders: RenderRow[] }> = ({ jobs, renders }) => {
  const running = jobs.filter((j) => j.status !== "done");
  const doneFiles = new Set(renders.map((r) => r.file));
  return (
    <div className="jobs">
      {running.map((j) => (
        <div className="job" key={j.id}>
          <b>{j.reel}</b> · {j.status === "bundling" ? "Preparing (first render takes ~30 s)…" : j.status === "rendering" ? `Rendering ${Math.round(j.progress * 100)}%` : "Failed"}
          {j.error && <div className="err">{j.error}</div>}
          {j.status !== "error" && <div className="bar"><i style={{ width: `${Math.max(3, j.progress * 100)}%` }} /></div>}
        </div>
      ))}
      {renders.map((r) => (
        <div className="job" key={r.file}>
          <div className="row" style={{ justifyContent: "space-between" }}>
            <b>{r.title}</b>
            <span className="empty">{(r.size / 1e6).toFixed(1)} MB</span>
          </div>
          <video className="vid" src={`/renders/${r.file}`} controls preload="metadata" />
          <div className="row" style={{ marginTop: 6 }}>
            <a href={`/renders/${r.file}?download=1`}>Download</a>
            <span className="empty">{new Date(r.mtime).toLocaleString()}</span>
          </div>
        </div>
      ))}
      {!renders.length && !running.length && <div className="empty">Rendered MP4s appear here. Hit “Render MP4”.</div>}
      {void doneFiles}
    </div>
  );
};
