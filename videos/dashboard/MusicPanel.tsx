import React, { useState } from "react";
import { KEYS, KITS, LANES, Lane, ReelSpec, SCALES, TRACK_PRESETS, Track, cueSheet, suggestDropBar } from "../src/reel/spec";
import { api, LibTrack } from "./api";
import { useLoopPreview } from "./audio";

const LANE_LABEL: Record<Lane, string> = { kick: "Kick", snare: "Snare", clap: "Clap", hat: "Hat", perc: "Perc" };
const cellCls = (on: number, i: number) => `cell ${on === 2 ? "acc" : on ? "on" : ""} ${i % 4 === 0 ? "beat" : ""}`;

const Slider: React.FC<{ label: string; value: number; min: number; max: number; step: number; onChange: (v: number) => void; fmt?: (v: number) => string }> = ({ label, value, min, max, step, onChange, fmt }) => (
  <label className="slide">
    <span>{label}</span>
    <input type="range" min={min} max={max} step={step} value={value} onChange={(e) => onChange(Number(e.target.value))} />
    <output>{fmt ? fmt(value) : value}</output>
  </label>
);

const Roll: React.FC<{ title: string; notes: (number | null)[]; lo: number; hi: number; onSet: (i: number, v: number | null) => void }> = ({ title, notes, lo, hi, onSet }) => {
  const rows: number[] = [];
  for (let d = hi; d >= lo; d--) rows.push(d);
  return (
    <div style={{ marginTop: 10 }}>
      <div className="lane-h">{title}</div>
      <div className="roll">
        {rows.map((d) => (
          <div className="roll-row" key={d}>
            {notes.map((n, i) => (
              <button key={i} className={`cell ${n === d ? "on" : ""} ${i % 4 === 0 ? "beat" : ""} ${d === 0 ? "root" : ""}`} onClick={() => onSet(i, n === d ? null : d)} aria-label={`${title} step ${i + 1} degree ${d}`} />
            ))}
          </div>
        ))}
      </div>
    </div>
  );
};

export const MusicPanel: React.FC<{
  spec: ReelSpec; setSpec: (f: (s: ReelSpec) => ReelSpec) => void; provider: string; model: string; canAsk: boolean; tracks: LibTrack[]; setTracks: (t: LibTrack[]) => void;
}> = ({ spec, setSpec, provider, model, canAsk, tracks, setTracks }) => {
  const [prompt, setPrompt] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const track = spec.track!;
  const loop = useLoopPreview(track, spec.bpm);
  const patch = (p: Partial<Track>) => setSpec((s) => ({ ...s, track: { ...s.track!, ...p } }));
  const setLane = (lane: Lane, i: number) => patch({ drums: { ...track.drums, [lane]: track.drums[lane].map((v, k) => (k === i ? (v + 1) % 3 : v)) } });
  const setNote = (which: "bass" | "lead") => (i: number, v: number | null) => patch({ [which]: track[which].map((x, k) => (k === i ? v : x)) } as Partial<Track>);
  const setMix = (k: keyof Track["mix"], v: number) => patch({ mix: { ...track.mix, [k]: v } });

  const compose = async () => {
    setBusy(true); setErr("");
    try {
      const r = await api.generateMusic(prompt, provider, model, spec);
      setSpec((s) => ({ ...s, bpm: r.bpm, track: r.track }));
    } catch (e: any) { setErr(e.message); }
    setBusy(false);
  };
  const randomize = () => {
    const rnd = (p: number) => Math.random() < p;
    const hats = Array.from({ length: 16 }, (_, i) => (i % 2 === 0 ? 1 : rnd(0.3) ? 1 : 0));
    patch({
      drums: {
        kick: Array.from({ length: 16 }, (_, i) => (i % 4 === 0 ? (i === 0 ? 2 : 1) : rnd(0.12) ? 1 : 0)),
        snare: Array.from({ length: 16 }, (_, i) => (i === 4 || i === 12 ? 1 : rnd(0.05) ? 1 : 0)),
        clap: Array.from({ length: 16 }, (_, i) => (i === 4 || i === 12 ? 1 : 0)),
        hat: hats, perc: Array.from({ length: 16 }, () => (rnd(0.12) ? 1 : 0)),
      },
      bass: Array.from({ length: 16 }, (_, i) => (i % 4 === 0 || rnd(0.15) ? [0, 0, 0, 2, 3, 4][Math.floor(Math.random() * 6)] : null)),
      lead: Array.from({ length: 16 }, () => (rnd(0.3) ? [0, 2, 4, 6, 7, 9][Math.floor(Math.random() * 6)] : null)),
      prog: [0, 5, 3, 6, 4, 2].sort(() => Math.random() - 0.5).slice(0, 4),
    });
  };

  return (
    <div>
      <label>Compose with Claude (it sees your scenes, their beats and where the big cuts land)</label>
      <textarea style={{ minHeight: 56 }} placeholder="Optional mood, e.g. tense sneaking, sparse, then a hard drop when the teacher turns" value={prompt} onChange={(e) => setPrompt(e.target.value)} />
      <div className="row" style={{ marginTop: 6 }}>
        <button className="btn orange sm" style={{ flex: 1 }} disabled={busy || !canAsk} onClick={compose}>{busy ? "Composing…" : "Compose"}</button>
        <button className="btn sm" onClick={randomize}>Randomize</button>
      </div>
      <div className="chips">
        <button className="chip" onClick={() => setPrompt("Like the trailer score: bright chip-pop, 128 BPM D minor, sneaky intro then a big four-on-the-floor drop with a chip-tune hook")}>Like the trailer</button>
        <button className="chip" onClick={() => setPrompt("Tense stealth build, sparse and quiet, then a hard drop when the alert hits")}>Stealth then drop</button>
        <button className="chip" onClick={() => setPrompt("Playful chaos, faster (150 BPM), 8-bit chase energy")}>8-bit chase</button>
        <button className="chip" onClick={() => setPrompt("Chill lo-fi, warm and swung, gentle drums")}>Lo-fi chill</button>
      </div>
      {err && <div className="err">{err}</div>}

      <label>Start from a preset</label>
      <select value="" onChange={(e) => { const p = TRACK_PRESETS[e.target.value]; if (p) setSpec((s) => ({ ...s, bpm: p.bpm, track: structuredClone(p.track) })); }}>
        <option value="">Choose…</option>
        {Object.entries(TRACK_PRESETS).map(([k, v]) => <option key={k} value={k}>{v.label} · {v.bpm} BPM</option>)}
      </select>

      <div className="row" style={{ marginTop: 10 }}>
        <button className={`btn sm ${loop.playing ? "gold" : ""}`} onClick={loop.toggle}>{loop.playing ? "■ Stop loop" : "▶ Audition loop"}</button>
        <span className="empty">Groove only. Press play in the preview to hear the full arrangement.</span>
      </div>

      <h3 style={{ marginTop: 16 }}>Sound</h3>
      <Slider label="Tempo" value={spec.bpm} min={70} max={180} step={1} onChange={(v) => setSpec((s) => ({ ...s, bpm: v }))} fmt={(v) => `${v} BPM`} />
      <div className="row" style={{ marginTop: 6 }}>
        <select value={track.key} onChange={(e) => patch({ key: Number(e.target.value) })} aria-label="Key">{KEYS.map((k, i) => <option key={k} value={i}>{k}</option>)}</select>
        <select value={track.scale} onChange={(e) => patch({ scale: e.target.value as Track["scale"] })} aria-label="Scale">{Object.keys(SCALES).map((k) => <option key={k}>{k}</option>)}</select>
      </div>
      <div className="row" style={{ marginTop: 6 }}>
        <select value={track.kit} onChange={(e) => patch({ kit: e.target.value as Track["kit"] })} aria-label="Drum kit">{Object.entries(KITS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select>
        <select value={track.chords} onChange={(e) => patch({ chords: e.target.value as Track["chords"] })} aria-label="Chords"><option value="pad">Pad chords</option><option value="stab">Stab chords</option><option value="off">No chords</option></select>
      </div>
      <Slider label="Swing" value={track.swing} min={0} max={0.3} step={0.01} onChange={(v) => patch({ swing: v })} fmt={(v) => `${Math.round(v * 100)}%`} />

      <h3 style={{ marginTop: 16 }}>Sync with the reel</h3>
      <label className="chk"><input type="checkbox" checked={track.syncCuts} onChange={(e) => patch({ syncCuts: e.target.checked })} /> Hit on every cut, tick on punch words, riser into alerts</label>
      <div className="cue-sheet">
        {cueSheet(spec).map((r) => (
          <div key={r.i} className={`cue ${r.startBeat / 4 === track.dropBar ? "drop" : ""}`} title={`${r.beats} beats`}>
            <span>bar {r.bar}.{r.beatInBar}</span><b>{r.kind}</b><span className="lbl">{r.label}</span><i className={r.energy}>{r.energy}</i>
          </div>
        ))}
      </div>
      <button className="btn sm" style={{ marginTop: 6 }} onClick={() => patch({ dropBar: suggestDropBar(spec), riser: true, fill: true })} title="Put the drop on the first high-energy scene">Match drop to scenes</button>

      <h3 style={{ marginTop: 16 }}>Structure</h3>
      <Slider label="Drop at bar" value={track.dropBar} min={0} max={8} step={1} onChange={(v) => patch({ dropBar: v })} fmt={(v) => (v === 0 ? "none" : String(v + 1))} />
      <div className="row" style={{ marginTop: 6 }}>
        <label className="chk"><input type="checkbox" checked={track.fill} onChange={(e) => patch({ fill: e.target.checked })} /> Snare fills</label>
        <label className="chk"><input type="checkbox" checked={track.riser} onChange={(e) => patch({ riser: e.target.checked })} /> Riser before drop</label>
      </div>
      <label>Chord progression (scale degree per bar)</label>
      <div className="row" style={{ flexWrap: "wrap" }}>
        {track.prog.map((d, i) => (
          <input key={i} type="number" style={{ width: 54 }} min={-7} max={14} value={d} onChange={(e) => patch({ prog: track.prog.map((x, k) => (k === i ? Number(e.target.value) : x)) })} />
        ))}
        <button className="btn sm" disabled={track.prog.length >= 8} onClick={() => patch({ prog: [...track.prog, 0] })}>+</button>
        <button className="btn sm" disabled={track.prog.length <= 1} onClick={() => patch({ prog: track.prog.slice(0, -1) })}>−</button>
      </div>

      <h3 style={{ marginTop: 16 }}>Drums · click to cycle off / hit / accent</h3>
      {LANES.map((l) => (
        <div className="lane" key={l}>
          <span className="lane-n">{LANE_LABEL[l]}</span>
          <div className="lane-c">{track.drums[l].map((v, i) => <button key={i} className={cellCls(v, i)} onClick={() => setLane(l, i)} aria-label={`${l} step ${i + 1}`} />)}</div>
        </div>
      ))}
      <Roll title="Bass (root is the bottom line)" notes={track.bass} lo={-2} hi={5} onSet={setNote("bass")} />
      <Roll title="Lead" notes={track.lead} lo={0} hi={9} onSet={setNote("lead")} />

      <h3 style={{ marginTop: 16 }}>Mix</h3>
      {(["drums", "bass", "lead", "chords"] as const).map((k) => (
        <Slider key={k} label={k[0].toUpperCase() + k.slice(1)} value={track.mix[k]} min={0} max={1} step={0.05} onChange={(v) => setMix(k, v)} fmt={(v) => (v === 0 ? "off" : `${Math.round(v * 100)}%`)} />
      ))}

      <h3 style={{ marginTop: 16 }}>Track library</h3>
      <button className="btn sm" onClick={() => { const n = window.prompt("Name this track", spec.title); if (n) api.saveTrack(n, spec.bpm, track).then(setTracks); }}>★ Save this track</button>
      <div className="reel-list" style={{ marginTop: 8 }}>
        {tracks.map((t) => (
          <div key={t.id} className="reel-item" onClick={() => setSpec((s) => ({ ...s, bpm: t.bpm, track: structuredClone(t.track) }))}>
            <div className="t">{t.name}</div><div className="m">{t.bpm} BPM</div>
            <button className="x" onClick={(e) => { e.stopPropagation(); api.delTrack(t.id).then(() => setTracks(tracks.filter((x) => x.id !== t.id))); }}>✕</button>
          </div>
        ))}
        {!tracks.length && <div className="empty">Saved tracks can be used in any reel.</div>}
      </div>
    </div>
  );
};
