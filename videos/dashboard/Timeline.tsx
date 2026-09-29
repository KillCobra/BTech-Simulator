import React, { useEffect, useRef, useState } from "react";
import { PlayerRef } from "@remotion/player";
import { KINDS, Overlay, ReelSpec, SceneKind, beatOf, durationFrames, maxBeats, sceneEvents, totalBeats } from "../src/reel/spec";

export const KIND_COLOR: Record<SceneKind, string> = { title: "#ffc93c", words: "#b07cff", plate: "#9fd8ff", voxel: "#7fe0a0", icons: "#ff9a3c", alert: "#ff6b63", cta: "#ffd24a", stat: "#f5a3d0" };

type Props = {
  spec: ReelSpec; frames: { from: number; frames: number }[]; sel: number; selOv: string | null; player: React.RefObject<PlayerRef | null>;
  onSelect: (i: number) => void; onSelectOv: (id: string) => void; onMove: (a: number, b: number) => void; onAdd: (k: SceneKind) => void;
  onResize: (i: number, beats: number) => void; onOverlay: (id: string, p: Partial<Overlay>) => void; onAddOverlay: () => void;
};

/** Scene track (drag to reorder, drag the right edge to resize on the beat grid) plus an overlay track. */
export const Timeline: React.FC<Props> = ({ spec, frames, sel, selOv, player, onSelect, onSelectOv, onMove, onAdd, onResize, onOverlay, onAddOverlay }) => {
  const [frame, setFrame] = useState(0);
  const [drag, setDrag] = useState<number | null>(null);
  const [over, setOver] = useState<number | null>(null);
  const [resizing, setResizing] = useState(false);
  const track = useRef<HTMLDivElement>(null);
  const total = durationFrames(spec);
  const beats = totalBeats(spec);

  useEffect(() => {
    const p = player.current;
    if (!p) return;
    const f = (e: { detail: { frame: number } }) => setFrame(e.detail.frame);
    p.addEventListener("frameupdate", f);
    return () => p.removeEventListener("frameupdate", f);
  }, [player]);

  // Drag helper: converts horizontal pixels to whole beats using the track width at drag start.
  const dragBeats = (e: React.PointerEvent, start: number, apply: (beatsDelta: number) => void) => {
    e.stopPropagation();
    e.preventDefault();
    const w = track.current?.getBoundingClientRect().width ?? 1;
    const pxPerBeat = w / Math.max(1, beats);
    const x0 = e.clientX;
    const move = (ev: PointerEvent) => apply(Math.round((ev.clientX - x0) / pxPerBeat));
    const up = () => { window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", up); setResizing(false); };
    setResizing(true);
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
    void start;
  };

  const bars = Math.max(1, beats / 4);
  const ruler = { backgroundImage: `repeating-linear-gradient(90deg, rgba(255,255,255,.28) 0 1px, transparent 1px calc(100% / ${bars}))` };
  return (
    <div className="timeline">
      <div className="tl-head">
        <h3 style={{ margin: 0 }}>Timeline · drag blocks to reorder, drag edges to resize</h3>
        <span className="empty">{beats}/{maxBeats(spec)} beats · bar lines every 4</span>
      </div>
      <div style={{ position: "relative" }}>
        <div className="tl-ruler" style={ruler} />
        <div className="tl-track" ref={track}>
          {spec.scenes.map((s, i) => (
            <div
              key={s.id} draggable={!resizing} className={`blk ${i === sel && !selOv ? "on" : ""} ${over === i && drag !== i ? "over" : ""}`}
              style={{ flex: `${frames[i].frames} 1 0`, background: KIND_COLOR[s.kind] }}
              onClick={() => onSelect(i)} onDragStart={() => setDrag(i)} onDragOver={(e) => { e.preventDefault(); setOver(i); }}
              onDrop={() => { if (drag !== null) onMove(drag, i); setDrag(null); setOver(null); }} onDragEnd={() => { setDrag(null); setOver(null); }}
            >
              <b>{KINDS[s.kind].label}</b>
              <span>{s.beats} beats · {(s.beats * beatOf(spec)).toFixed(1)}s{s.text ? ` · ${s.text.replace(/\\n|\n/g, " ")}` : ""}</span>
              {sceneEvents(s).filter((e) => e.beat > 0).map((e, k) => <em key={k} className="ev" title={`beat ${e.beat + 1}: ${e.label}`} style={{ left: `${(e.beat / s.beats) * 100}%` }} />)}
              <div className="grip" title="Drag to resize" onPointerDown={(e) => { const b0 = s.beats; dragBeats(e, b0, (d) => onResize(i, b0 + d)); }} />
            </div>
          ))}
        </div>
        <div className="tl-label">Overlays</div>
        <div className="tl-ov">
          {spec.overlays.map((o) => (
            <div
              key={o.id} className={`ov-blk ${selOv === o.id ? "on" : ""}`}
              style={{ left: `${(o.at / Math.max(1, beats)) * 100}%`, width: `${(Math.min(o.beats, Math.max(1, beats - o.at)) / Math.max(1, beats)) * 100}%` }}
              onClick={() => onSelectOv(o.id)}
              onPointerDown={(e) => { onSelectOv(o.id); const a0 = o.at; dragBeats(e, a0, (d) => onOverlay(o.id, { at: Math.max(0, Math.min(beats - 1, a0 + d)) })); }}
            >
              {o.text || "(empty)"}
              <div className="grip" onPointerDown={(e) => { const b0 = o.beats; dragBeats(e, b0, (d) => onOverlay(o.id, { beats: Math.max(1, b0 + d) })); }} />
            </div>
          ))}
        </div>
        <div className="playhead" style={{ left: `${(frame / total) * 100}%`, top: 0, bottom: 0 }} />
      </div>
      <div className="add">
        {(Object.keys(KINDS) as SceneKind[]).map((k) => (
          <button key={k} className="btn sm ghost" title={KINDS[k].hint} onClick={() => onAdd(k)}>+ {KINDS[k].label}</button>
        ))}
        <button className="btn sm ghost" onClick={onAddOverlay} title="Text sticker at the playhead">+ Overlay</button>
      </div>
    </div>
  );
};
