import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Player, PlayerRef } from "@remotion/player";
import { Reel } from "../src/reel/Reel";
import {
  DEFAULT_OVERLAY, DEFAULT_SCENE, FORMATS, FPS, SAMPLE, THEMES, TRACK_PRESETS, beatOf, durationFrames, durationSeconds, maxBeats, minBeats, newId, sceneFrames, totalBeats,
  Format, Overlay, ReelSpec, Scene, SceneKind,
} from "../src/reel/spec";
import { api, Generation, Job, LibScene, LibTrack, MusicMode, ReelRow, RenderRow } from "./api";
import { useTrackUrl } from "./audio";
import { OverlayInspector, SceneInspector } from "./Inspector";
import { MusicPanel } from "./MusicPanel";
import { KIND_COLOR, Timeline } from "./Timeline";

const IDEAS = [
  "15s hook: your teacher is watching, friends panic, escape",
  "Proximity voice: staff hear how loud you are, never what you say",
  "Chaos tools: trolley, paper ball, blame a friend",
  "Coming soon teaser, 20s, hype",
  "Item trading: hall pass, samosa, medical note",
];
const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 32) || "reel";
const pref = (k: string, d: string) => { try { return localStorage.getItem(k) ?? d; } catch { return d; } };
const inField = (t: EventTarget | null) => t instanceof HTMLInputElement || t instanceof HTMLTextAreaElement || t instanceof HTMLSelectElement;

export const App: React.FC = () => {
  const [reels, setReels] = useState<ReelRow[]>([]);
  const [id, setId] = useState<string | null>(null);
  const [spec, setSpecRaw] = useState<ReelSpec>(SAMPLE);
  const [sel, setSel] = useState(0);
  const [selOv, setSelOv] = useState<string | null>(null);
  const [prompt, setPrompt] = useState("");
  const [variants, setVariants] = useState(1);
  const [musicMode, setMusicMode] = useState<MusicMode>(pref("musicMode", "compose") as MusicMode);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");
  const [err, setErr] = useState("");
  const [caps, setCaps] = useState({ hasKey: false, hasCli: false, models: [] as { id: string; label: string }[] });
  const [provider, setProvider] = useState(pref("provider", "subscription"));
  const [model, setModel] = useState(pref("model", "claude-opus-5-5"));
  const [gens, setGens] = useState<Generation[]>([]);
  const [lib, setLib] = useState<LibScene[]>([]);
  const [tracks, setTracks] = useState<LibTrack[]>([]);
  const [tab, setTab] = useState<"scene" | "music" | "renders">("scene");
  const [jobs, setJobs] = useState<Job[]>([]);
  const [renders, setRenders] = useState<RenderRow[]>([]);
  const player = useRef<PlayerRef>(null);
  const hist = useRef<{ stack: ReelSpec[]; at: number }>({ stack: [], at: 0 });
  const [, bump] = useState(0);
  const audioSrc = useTrackUrl(spec);

  useEffect(() => { try { localStorage.setItem("provider", provider); localStorage.setItem("model", model); localStorage.setItem("musicMode", musicMode); } catch { /* private mode */ } }, [provider, model, musicMode]);
  const refreshReels = useCallback(() => api.reels().then(setReels).catch(() => {}), []);
  const refreshRenders = useCallback(() => api.renders().then(setRenders).catch(() => {}), []);

  // every edit goes through here so undo works; rapid typing collapses into one step
  const setSpec = useCallback((next: ReelSpec | ((s: ReelSpec) => ReelSpec)) => {
    setSpecRaw((cur) => {
      const n = typeof next === "function" ? next(cur) : next;
      const h = hist.current;
      if (Date.now() - h.at > 700) { h.stack.push(cur); if (h.stack.length > 80) h.stack.shift(); }
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
    setId(rid); setSpecRaw(s); setSel(0); setSelOv(null); setErr("");
  }, []);
  /** Saves a spec as a new reel and returns its id (does not switch to it). */
  const createReel = (s: ReelSpec) => {
    const rid = `${slug(s.title)}-${Math.random().toString(36).slice(2, 6)}`;
    api.save(rid, s);
    return rid;
  };
  const newReel = (s: ReelSpec = SAMPLE) => {
    const rid = createReel(s);
    hist.current = { stack: [], at: 0 };
    setId(rid); setSpecRaw(s); setSel(0); setSelOv(null);
    setTimeout(refreshReels, 300);
  };

  useEffect(() => {
    api.status().then((s) => { setCaps(s); if (!s.hasCli && s.hasKey) setProvider("api"); }).catch(() => {});
    api.generations().then(setGens).catch(() => {});
    api.scenes().then(setLib).catch(() => {});
    api.tracks().then(setTracks).catch(() => {});
    refreshRenders();
    api.reels().then((list) => { setReels(list); if (list.length) openReel(list[0].id); else newReel(); }).catch((e) => setErr(String(e.message)));
  }, []); // eslint-disable-line

  useEffect(() => {
    if (!id) return;
    const t = setTimeout(() => api.save(id, spec).then(refreshReels).catch(() => {}), 500);
    return () => clearTimeout(t);
  }, [spec, id, refreshReels]);

  const active = jobs.some((j) => j.status === "bundling" || j.status === "rendering");
  useEffect(() => {
    if (!active) return;
    const t = setInterval(() => api.jobs().then((j) => { setJobs(j); if (!j.some((x) => x.status === "bundling" || x.status === "rendering")) refreshRenders(); }), 1000);
    return () => clearInterval(t);
  }, [active, refreshRenders]);

  const frames = useMemo(() => sceneFrames(spec), [spec]);
  const fmt = FORMATS[spec.format];
  const beat = beatOf(spec);
  const scene = spec.scenes[Math.min(sel, spec.scenes.length - 1)];
  const ov = selOv ? spec.overlays.find((o) => o.id === selOv) : undefined;
  const canAsk = provider === "api" ? caps.hasKey : caps.hasCli;
  const limit = maxBeats(spec);

  // ---- scenes
  const patch = (p: Partial<Scene>) => setSpec((s) => ({ ...s, scenes: s.scenes.map((x, i) => (i === sel ? { ...x, ...p } : x)) }));
  const select = (i: number) => {
    setSel(i); setSelOv(null); setTab((t) => (t === "renders" ? "scene" : t === "music" ? "scene" : t));
    player.current?.pause();
    player.current?.seekTo(frames[i].from + Math.min(frames[i].frames - 1, 12));
  };
  const addScene = (kind: SceneKind) => {
    if (totalBeats(spec) + DEFAULT_SCENE[kind].beats > limit) return setErr(`This reel is at its ${limit}-beat limit. Shorten a scene first.`);
    const at = Math.min(sel + 1, spec.scenes.length);
    setSpec((s) => ({ ...s, scenes: [...s.scenes.slice(0, at), { ...DEFAULT_SCENE[kind], id: newId() }, ...s.scenes.slice(at)] }));
    setSel(at); setSelOv(null); setErr("");
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
  const setBeatsAt = (i: number, n: number) =>
    setSpec((s) => {
      const others = totalBeats(s) - s.scenes[i].beats;
      const b = Math.max(minBeats(s.scenes[i]), Math.min(32, Math.min(n, maxBeats(s) - others)));
      return b === s.scenes[i].beats ? s : { ...s, scenes: s.scenes.map((x, k) => (k === i ? { ...x, beats: b } : x)) };
    });

  // ---- overlays
  const patchOv = (oid: string, p: Partial<Overlay>) => setSpec((s) => ({ ...s, overlays: s.overlays.map((o) => (o.id === oid ? { ...o, ...p } : o)) }));
  const addOverlay = () => {
    const f = player.current?.getCurrentFrame() ?? 0;
    const o: Overlay = { ...DEFAULT_OVERLAY, id: newId(), at: Math.min(Math.max(0, totalBeats(spec) - 1), Math.round(f / FPS / beat)) };
    setSpec((s) => ({ ...s, overlays: [...s.overlays, o] }));
    setSelOv(o.id); setTab("scene");
  };

  // ---- music source
  const setMusic = (m: ReelSpec["music"]) => {
    setSpec((s) => {
      if (m === "custom") { const p = TRACK_PRESETS.hype; return { ...s, music: m, bpm: s.track ? s.bpm : p.bpm, track: s.track ?? structuredClone(p.track) }; }
      return { ...s, music: m, bpm: m === "trailer" ? 128 : s.bpm };
    });
    if (m === "custom") setTab("music");
  };

  // ---- generation
  const generate = async (revise: boolean) => {
    if (!prompt.trim()) return;
    setBusy(true); setErr(""); setNotice("");
    try {
      if (revise) {
        const r = await api.generate(prompt, spec.format, provider, model, spec, musicMode);
        setSpec(r.spec);
        if (r.warning) setNotice(r.warning);
      } else {
        const { specs, failed, warnings } = await api.generateBatch(prompt, spec.format, provider, model, variants, musicMode);
        const ids = specs.map(createReel);
        await refreshReels();
        await openReel(ids[0]);
        const msg = [specs.length > 1 || failed ? `${specs.length} reels made${failed ? `, ${failed} failed` : ""}. They are saved in Reels below.` : "", ...warnings].filter(Boolean).join(" ");
        if (msg) setNotice(msg);
      }
      api.generations().then(setGens);
      setSel(0); player.current?.seekTo(0);
    } catch (e: any) { setErr(e.message); }
    setBusy(false);
  };

  // ---- render / export
  const render = async (formats: Format[] = [spec.format]) => {
    if (!id) return;
    setErr("");
    try {
      await api.save(id, spec);
      for (const f of formats) {
        const job = await api.render(`${id}-${f.replace(":", "x")}`, { ...spec, format: f });
        setJobs((j) => [job, ...j]);
      }
      setTab("renders");
    } catch (e: any) { setErr(e.message); }
  };
  const exportJson = () => {
    const a = document.createElement("a");
    a.href = URL.createObjectURL(new Blob([JSON.stringify(spec, null, 2)], { type: "application/json" }));
    a.download = `${slug(spec.title)}.json`;
    a.click();
  };
  const duplicateReel = () => newReel({ ...structuredClone(spec), title: `${spec.title} copy` });

  // ---- keyboard: space play/pause, arrows scenes, delete, undo
  useEffect(() => {
    const k = (e: KeyboardEvent) => {
      if (inField(e.target)) return;
      if ((e.metaKey || e.ctrlKey) && e.key === "z") { e.preventDefault(); undo(); }
      else if (e.key === " ") { e.preventDefault(); player.current?.toggle(); }
      else if (e.key === "ArrowRight" && sel < spec.scenes.length - 1) select(sel + 1);
      else if (e.key === "ArrowLeft" && sel > 0) select(sel - 1);
      else if (e.key === "Delete" || e.key === "Backspace") {
        if (selOv) { setSpec((s) => ({ ...s, overlays: s.overlays.filter((o) => o.id !== selOv) })); setSelOv(null); } else del();
      }
    };
    window.addEventListener("keydown", k);
    return () => window.removeEventListener("keydown", k);
  });

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
        <select style={{ width: 100 }} value={spec.theme} onChange={(e) => setSpec((s) => ({ ...s, theme: e.target.value as any }))} aria-label="Theme">
          {Object.entries(THEMES).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
        </select>
        <div className="seg" title="Music source">
          <button className={spec.music === "trailer" ? "on" : ""} onClick={() => setMusic("trailer")}>Trailer</button>
          <button className={spec.music === "custom" ? "on" : ""} onClick={() => setMusic("custom")}>Custom</button>
          <button className={spec.music === "none" ? "on" : ""} onClick={() => setMusic("none")}>Mute</button>
        </div>
        <button className="btn" onClick={undo} disabled={!hist.current.stack.length}>Undo</button>
        <button className="btn gold" onClick={() => render()} disabled={!id || active}>{active ? "Rendering…" : "Render MP4"}</button>
        <button className="btn" onClick={() => render(["9:16", "1:1", "16:9"])} disabled={!id || active} title="Render all three sizes">All sizes</button>
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
              <select className="varsel" value={variants} onChange={(e) => setVariants(Number(e.target.value))} aria-label="How many reels">
                {[1, 2, 3, 4, 6].map((n) => <option key={n} value={n}>{n} {n === 1 ? "reel" : "reels"}</option>)}
              </select>
              <button className="btn orange" style={{ flex: 1 }} disabled={busy || !prompt.trim() || !canAsk} onClick={() => generate(false)}>{busy ? "Working…" : variants > 1 ? `Make ${variants}` : "New reel"}</button>
              <button className="btn" disabled={busy || !prompt.trim() || !canAsk} onClick={() => generate(true)} title="Rewrite the open reel to match the brief">Revise</button>
            </div>
            <label>Music for the new reel</label>
            <div className="seg" style={{ width: "100%" }}>
              <button style={{ flex: 1 }} className={musicMode === "compose" ? "on" : ""} onClick={() => setMusicMode("compose")} title="Claude composes a new beat scored to the reel's own scenes">New beat</button>
              <button style={{ flex: 1 }} className={musicMode === "trailer" ? "on" : ""} onClick={() => setMusicMode("trailer")}>Trailer score</button>
              <button style={{ flex: 1 }} className={musicMode === "none" ? "on" : ""} onClick={() => setMusicMode("none")}>None</button>
            </div>
            {busy && <div className="empty" style={{ marginTop: 6 }}>Claude is writing {variants > 1 ? `${variants} different takes in parallel` : "the storyboard"}{musicMode === "compose" ? ", then composing a beat scored to each" : ""}. This takes 1 to 3 min.</div>}
            {musicMode === "compose" && <div className="chips"><button className="chip" onClick={() => setPrompt((p) => `${p}${p.trim() ? ". " : ""}Music like the trailer score: bright chip-pop, 128 BPM D minor, sneaky intro then a big four-on-the-floor drop.`)}>+ trailer-style music</button></div>}
            <div className="chips">{IDEAS.map((i) => <button key={i} className="chip" onClick={() => setPrompt(i)}>{i.split(":")[0]}</button>)}</div>
            {notice && <div className="note" style={{ marginTop: 8 }}>{notice}</div>}
            {err && <div className="err">{err}</div>}
          </section>
          <section>
            <div className="row" style={{ justifyContent: "space-between" }}>
              <h3 style={{ margin: 0 }}>Reels</h3>
              <div className="row">
                <button className="btn sm" onClick={duplicateReel} title="Duplicate this reel">Copy</button>
                <button className="btn sm" onClick={exportJson} title="Download the reel as JSON">Export</button>
                <button className="btn sm" onClick={() => newReel({ ...SAMPLE, title: "New reel" })}>+ Blank</button>
              </div>
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
              <div key={l.id} className="reel-item" title="Insert after the selected scene" onClick={() => { setSpec((sp) => ({ ...sp, scenes: [...sp.scenes.slice(0, sel + 1), { ...l.scene, id: newId() }, ...sp.scenes.slice(sel + 1)] })); setSel(sel + 1); setSelOv(null); }}>
                <span style={{ width: 10, height: 10, borderRadius: 3, background: KIND_COLOR[l.scene.kind] }} />
                <div className="t">{l.name}</div>
                <button className="x" onClick={(e) => { e.stopPropagation(); api.delScene(l.id).then(() => setLib((x) => x.filter((y) => y.id !== l.id))); }}>✕</button>
              </div>
            ))}
            {!lib.length && <div className="empty">Save scenes from the Scene tab (★) to reuse them in any reel.</div>}
          </section>
          <section>
            <h3>Generation history</h3>
            {gens.slice(0, 15).map((g) => (
              <div key={g.id} className="reel-item" style={{ display: "block" }}>
                <div className="t" style={{ whiteSpace: "normal" }}>{g.prompt}</div>
                <div className="m">{caps.models.find((m) => m.id === g.model)?.label ?? g.model} · {g.spec.scenes.length} scenes{g.spec.music === "custom" ? " · music" : ""} · {new Date(g.at).toLocaleDateString()}</div>
                <div className="row" style={{ marginTop: 6 }}>
                  <button className="btn sm" onClick={() => newReel(g.spec)}>Open as reel</button>
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
                ref={player} component={Reel} inputProps={{ spec, audioSrc }} durationInFrames={durationFrames(spec)} fps={FPS}
                compositionWidth={fmt.width} compositionHeight={fmt.height} controls loop acknowledgeRemotionLicense
                style={{ width: "100%", height: "100%" }} clickToPlay
              />
            </div>
          </div>
          <div className="stage-info">
            <span>{fmt.label} · {fmt.width}×{fmt.height} · {FPS} fps</span>
            <span>{durationSeconds(spec).toFixed(1)} s · {totalBeats(spec)}/{limit} beats · {spec.bpm} BPM · space plays, ←/→ scenes</span>
          </div>
          <Timeline
            spec={spec} frames={frames} sel={sel} selOv={selOv} player={player} onSelect={select}
            onSelectOv={(oid) => { setSelOv(oid); setTab("scene"); }} onMove={move} onAdd={addScene} onResize={setBeatsAt} onOverlay={patchOv} onAddOverlay={addOverlay}
          />
        </main>

        <aside className="col right">
          <div className="seg" style={{ marginBottom: 14 }}>
            <button className={tab === "scene" ? "on" : ""} onClick={() => setTab("scene")}>Scene</button>
            <button className={tab === "music" ? "on" : ""} onClick={() => setTab("music")}>Music</button>
            <button className={tab === "renders" ? "on" : ""} onClick={() => setTab("renders")}>Renders{active ? " •" : ""}</button>
          </div>
          {tab === "scene" && (ov ? (
            <OverlayInspector o={ov} bpm={spec.bpm} patch={(p) => patchOv(ov.id, p)} del={() => { setSpec((s) => ({ ...s, overlays: s.overlays.filter((o) => o.id !== ov.id) })); setSelOv(null); }}
              dup={() => { const c = { ...ov, id: newId(), y: Math.min(95, ov.y + 8) }; setSpec((s) => ({ ...s, overlays: [...s.overlays, c] })); setSelOv(c.id); }} />
          ) : scene && (
            <SceneInspector
              scene={scene} idx={sel} count={spec.scenes.length} bpm={spec.bpm} patch={patch} move={move} dup={dup} del={del}
              setBeats={(n) => setBeatsAt(sel, n)}
              saveToLib={() => { const n = window.prompt("Name for this scene", `${scene.kind}: ${(scene.text ?? "").replace(/\\n|\n/g, " ").slice(0, 30)}`); if (n) api.saveScene(n, scene).then(setLib); }}
            />
          ))}
          {tab === "music" && (spec.music === "custom" && spec.track ? (
            <MusicPanel spec={spec} setSpec={setSpec} provider={provider} model={model} canAsk={canAsk} tracks={tracks} setTracks={setTracks} />
          ) : (
            <div>
              <p className="empty">{spec.music === "trailer" ? "This reel uses the 128 BPM trailer score." : "This reel is silent."}</p>
              <button className="btn gold" style={{ marginTop: 10 }} onClick={() => setMusic("custom")}>Make original music</button>
              <p className="empty" style={{ marginTop: 10 }}>A drum machine, bass, lead and chords in your reel's own tempo. Every scene length snaps to its beats.</p>
            </div>
          ))}
          {tab === "renders" && <Renders jobs={jobs} renders={renders} />}
        </aside>
      </div>
    </div>
  );
};

const Renders: React.FC<{ jobs: Job[]; renders: RenderRow[] }> = ({ jobs, renders }) => {
  const running = jobs.filter((j) => j.status !== "done");
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
    </div>
  );
};
