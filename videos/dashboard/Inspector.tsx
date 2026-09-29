import React from "react";
import {
  DEFAULT_SCENE, ITEMS, KINDS, OVERLAY_COLORS, Overlay, PLATES, Scene, SceneKind, THEMES, TRANSITIONS, beatOf,
} from "../src/reel/spec";

const toggle = (list: string[], v: string) => (list.includes(v) ? list.filter((x) => x !== v) : [...list, v]);
const Ta: React.FC<{ v: string; on: (v: string) => void; h?: number }> = ({ v, on, h = 56 }) => <textarea style={{ minHeight: h }} value={v} onChange={(e) => on(e.target.value)} />;

export const SceneInspector: React.FC<{
  scene: Scene; idx: number; count: number; bpm: number; patch: (p: Partial<Scene>) => void; setBeats: (n: number) => void;
  move: (a: number, b: number) => void; dup: () => void; del: () => void; saveToLib: () => void;
}> = ({ scene, idx, count, bpm, patch, setBeats, move, dup, del, saveToLib }) => {
  const k = scene.kind;
  const beat = beatOf({ bpm });
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
      <select value={k} onChange={(e) => { const nk = e.target.value as SceneKind; patch({ ...DEFAULT_SCENE[nk], beats: scene.beats, kind: nk }); }}>
        {Object.entries(KINDS).map(([key, v]) => <option key={key} value={key}>{v.label}</option>)}
      </select>

      <label>Length</label>
      <div className="stepper">
        <button className="btn sm" onClick={() => setBeats(scene.beats - 1)}>−</button>
        <output>{scene.beats} beats · {(scene.beats * beat).toFixed(2)}s</output>
        <button className="btn sm" onClick={() => setBeats(scene.beats + 1)}>+</button>
        <button className="btn sm ghost" onClick={() => setBeats(scene.beats + 4)} title="Add one bar">+bar</button>
      </div>

      {k === "title" && (<><label>Headline (Enter = new line)</label><Ta h={64} v={(scene.text ?? "").replace(/\\n/g, "\n")} on={(v) => patch({ text: v })} /></>)}
      {(k === "plate" || k === "voxel" || k === "icons") && (<><label>Caption</label><input type="text" value={scene.text ?? ""} onChange={(e) => patch({ text: e.target.value })} /></>)}
      {k === "alert" && (<><label>Banner</label><input type="text" value={scene.text ?? ""} onChange={(e) => patch({ text: e.target.value })} /></>)}
      {k === "cta" && (<><label>Tagline</label><input type="text" value={scene.text ?? ""} onChange={(e) => patch({ text: e.target.value })} /></>)}
      {k === "stat" && (<><label>Number or word</label><input type="text" value={scene.text ?? ""} onChange={(e) => patch({ text: e.target.value })} /></>)}
      {(k === "title" || k === "plate" || k === "alert" || k === "stat") && (<><label>{k === "plate" ? "Sticker" : k === "stat" ? "Label" : "Sub line"}</label><input type="text" value={scene.sub ?? ""} onChange={(e) => patch({ sub: e.target.value })} /></>)}

      {k === "words" && (<><label>Words (one per line, one per beat)</label><Ta h={90} v={(scene.items ?? []).join("\n")} on={(v) => patch({ items: v.split("\n").slice(0, 16) })} /></>)}
      {k === "cta" && (<><label>Platform chips (one per line)</label><Ta v={(scene.items ?? []).join("\n")} on={(v) => patch({ items: v.split("\n").slice(0, 4) })} /></>)}
      {k === "plate" && (
        <>
          <label>Screenshot</label>
          <div className="plates">
            {Object.keys(PLATES).map((p) => (
              <button key={p} className={scene.plate === p ? "on" : ""} title={PLATES[p]} onClick={() => patch({ plate: p })}><img src={`/plates/${p}.jpg`} alt={PLATES[p]} /></button>
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

      <label>Transition in</label>
      <select value={scene.transition ?? "flash"} onChange={(e) => patch({ transition: e.target.value as Scene["transition"] })}>
        {Object.entries(TRANSITIONS).map(([key, v]) => <option key={key} value={key}>{v}</option>)}
      </select>
      <label>Look</label>
      <select value={scene.theme ?? ""} onChange={(e) => patch({ theme: (e.target.value || undefined) as Scene["theme"] })}>
        <option value="">Same as reel</option>
        {Object.entries(THEMES).map(([key, v]) => <option key={key} value={key}>{v.label}</option>)}
      </select>
    </div>
  );
};

export const OverlayInspector: React.FC<{ o: Overlay; bpm: number; patch: (p: Partial<Overlay>) => void; del: () => void; dup: () => void }> = ({ o, bpm, patch, del, dup }) => {
  const beat = beatOf({ bpm });
  return (
    <div>
      <div className="insp-head">
        <h3 style={{ margin: 0 }}>Overlay</h3>
        <div className="row"><button className="btn sm" onClick={dup}>Copy</button><button className="btn sm" onClick={del}>Delete</button></div>
      </div>
      <label>Text</label>
      <input type="text" value={o.text} onChange={(e) => patch({ text: e.target.value })} />
      <label>Style</label>
      <div className="seg">
        {(["sticker", "caption", "plain"] as const).map((s) => <button key={s} className={o.style === s ? "on" : ""} onClick={() => patch({ style: s })}>{s}</button>)}
      </div>
      <label>Colour</label>
      <div className="swatches">
        {(Object.keys(OVERLAY_COLORS) as (keyof typeof OVERLAY_COLORS)[]).map((c) => (
          <button key={c} className={o.color === c ? "on" : ""} style={{ background: OVERLAY_COLORS[c] }} onClick={() => patch({ color: c })} aria-label={c} />
        ))}
      </div>
      <label>Starts at beat {o.at + 1} ({(o.at * beat).toFixed(1)}s)</label>
      <input type="range" min={0} max={120} value={o.at} onChange={(e) => patch({ at: Number(e.target.value) })} />
      <label>Lasts {o.beats} beats ({(o.beats * beat).toFixed(1)}s)</label>
      <input type="range" min={1} max={32} value={o.beats} onChange={(e) => patch({ beats: Number(e.target.value) })} />
      <label>Horizontal {Math.round(o.x)}%</label>
      <input type="range" min={0} max={100} value={o.x} onChange={(e) => patch({ x: Number(e.target.value) })} />
      <label>Vertical {Math.round(o.y)}%</label>
      <input type="range" min={0} max={100} value={o.y} onChange={(e) => patch({ y: Number(e.target.value) })} />
      <label>Size {o.size.toFixed(1)}×</label>
      <input type="range" min={0.5} max={3} step={0.1} value={o.size} onChange={(e) => patch({ size: Number(e.target.value) })} />
    </div>
  );
};
