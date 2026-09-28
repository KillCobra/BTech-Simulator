// 2D pieces for the crew act: slammed titles (trailer 1 treatment), lobby name tags with READY chips,
// the lobby's "STUDENTS n / 8" card, voice rings, exit markers and stars. All pure functions of t.
import React from "react";
import { outline } from "../../launch/ui";
import { clamp01, easeOut, POP, sp, squash, WOBBLE } from "../../launch/juice";

export const INK = "#2a1a0e";
export const GOLD = "#ffc93c";
export const GREEN = "#7fe0a0";
export const FONT = "Jersey10";

export const txt = (size: number, color = "#fff"): React.CSSProperties => ({ fontFamily: FONT, fontSize: size, lineHeight: 1, color, whiteSpace: "nowrap" });

/** Scale for slam entries: big -> 1 with an overshoot, 0 before `at`. */
export function slam(t: number, at: number, from = 2.3, len = 0.26) {
  if (t < at) return 0;
  const u = clamp01((t - at) / len);
  const s = 2.4, x = u - 1;
  const back = 1 + (s + 1) * x * x * x + s * x * x;
  return 1 + (from - 1) * (1 - back);
}

/** A title word/line that slams in on `at`: scale from big, motion blur, then a squash wobble. */
export const Slam: React.FC<{
  t: number; at: number; text: string; size: number; color?: string; stroke?: number; from?: number; tilt?: number;
  origin?: string; out?: number; style?: React.CSSProperties;
}> = ({ t, at, text, size, color = GOLD, stroke, from = 2.3, tilt = 0, origin = "50% 60%", out = 1e9, style }) => {
  if (t < at || t >= out) return null;
  const s = slam(t, at, from);
  const [sx, sy] = squash(t, at + 0.2, 0.08, 20, 9);
  const blur = Math.max(0, (1 - clamp01((t - at) / 0.1)) * 10);
  const rot = tilt * (1 - clamp01((t - at) / 0.3));
  return (
    <div style={{ ...style, transformOrigin: origin, scale: `${s * sx} ${s * sy}`, rotate: `${rot}deg`, filter: `drop-shadow(0 ${size * 0.06}px 0 ${INK})${blur > 0.3 ? ` blur(${blur}px)` : ""}` }}>
      <div style={{ ...txt(size, color), ...outline(stroke ?? Math.round(size * 0.075), INK) }}>{text}</div>
    </div>
  );
};

/** Lobby row twin (main.gd _refresh_lobby), cut to what reads at a glance: class chip + name, and a green
 *  READY tick (the lobby's 7fe0a0) that pops on when the friend readies up. */
export const Tag: React.FC<{ t: number; at: number; readyAt: number; name: string; cls: string; x: number; y: number; scale?: number }> = ({ t, at, readyAt, name, cls, x, y, scale = 1 }) => {
  const u = sp(t, at, WOBBLE);
  if (u <= 0.001) return null;
  const tick = sp(t, readyAt, WOBBLE);
  const [sx, sy] = squash(t, readyAt + 0.1, 0.25, 22, 10);
  const ready = t >= readyAt;
  return (
    <div style={{ position: "absolute", left: x, top: y, translate: "-50% -100%", scale: `${u * scale}`, transformOrigin: "50% 100%" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10, background: ready ? "rgba(26,77,46,0.94)" : "rgba(20,20,36,0.88)", borderRadius: 16, padding: "8px 16px 5px 12px", boxShadow: "0 6px 0 rgba(42,26,14,0.35)", scale: `${ready ? sx : 1} ${ready ? sy : 1}` }}>
        <div style={{ width: 22, height: 22, background: cls, borderRadius: 4 }} />
        <div style={{ ...txt(48, "#fff") }}>{name}</div>
      </div>
      {tick > 0.001 ? (
        <div style={{ position: "absolute", right: -22, top: -22, scale: `${tick}`, rotate: `${(1 - Math.min(1, tick)) * -40}deg` }}>
          <svg width={50} height={50} viewBox="-12 -12 24 24" style={{ display: "block", overflow: "visible" }}>
            <circle r={11.5} fill={INK} />
            <circle r={9.5} fill={GREEN} />
            <path d="M-5 0.5 L-1.5 4 L5.5 -3.5" fill="none" stroke={INK} strokeWidth={3} strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </div>
      ) : null}
    </div>
  );
};

/** The lobby header (main.gd:1197): "STUDENTS n / 8" and the ready note, on a HUD card. */
export const LobbyHead: React.FC<{ t: number; at: number; n: number; waiting: number; x: number; y: number; bump: number }> = ({ t, at, n, waiting, x, y, bump }) => {
  const u = sp(t, at, POP);
  if (u <= 0.001) return null;
  return (
    <div style={{ position: "absolute", left: x, top: y, scale: `${u * (1 + bump * 0.05)}`, transformOrigin: "0 0", background: "rgba(20,20,36,0.86)", borderRadius: 16, padding: "14px 22px 10px" }}>
      <div style={{ display: "flex", alignItems: "baseline", gap: 18 }}>
        <div style={{ ...txt(34, "rgba(255,255,255,0.72)") }}>STUDENTS</div>
        <div style={{ ...txt(50, "#fff") }}>{n} / 8</div>
      </div>
      <div style={{ ...txt(34, waiting === 0 ? GREEN : "#ffb37a"), marginTop: 6 }}>{waiting === 0 ? "Everyone's ready!" : `${waiting} not ready yet`}</div>
    </div>
  );
};

/** map_view.gd draw_icon_exit: ink r11, green 2fa85a r9.5, white flag. */
export const ExitIcon: React.FC<{ size: number }> = ({ size }) => (
  <svg width={size} height={size} viewBox="-12 -12 24 24" style={{ overflow: "visible", display: "block" }}>
    <circle r={11} fill="#2a2230" />
    <circle r={9.5} fill="#2fa85a" />
    <path d="M-3 6 L-3 -6" stroke="#fff" strokeWidth={1.8} strokeLinecap="round" />
    <path d="M-3 -6 L5 -3.5 L-3 -1 Z" fill="#fff" />
  </svg>
);

/** map_view.gd draw_icon_star: 10 points, radii 8 / 3.6, ink rim +2. */
export const starPts = (ro: number, ri: number) =>
  Array.from({ length: 10 }, (_, i) => {
    const a = -Math.PI / 2 + (i * Math.PI) / 5;
    const r = i % 2 ? ri : ro;
    return `${(Math.cos(a) * r).toFixed(2)},${(Math.sin(a) * r).toFixed(2)}`;
  }).join(" ");
export const StarIcon: React.FC<{ size: number; fill?: string }> = ({ size, fill = GREEN }) => (
  <svg width={size} height={size} viewBox="-10 -10 20 20" style={{ overflow: "visible", display: "block" }}>
    <polygon points={starPts(10, 5.6)} fill="#2a2230" />
    <polygon points={starPts(8, 3.6)} fill={fill} />
  </svg>
);

/** Green stars that burst out of a point and fall (deterministic). */
export const StarBurst: React.FC<{ t: number; at: number; x: number; y: number; n?: number; seed?: number; power?: number; size?: number; colors?: string[] }> = ({
  t, at, x, y, n = 9, seed = 1, power = 520, size = 34, colors = [GREEN, "#2fa85a", GOLD, "#ffffff"],
}) => {
  const d = t - at;
  if (d < 0 || d > 1.1) return null;
  const h = (k: number) => {
    const v = Math.sin(k * 127.1 + seed * 311.7) * 43758.5453;
    return v - Math.floor(v);
  };
  return (
    <>
      {Array.from({ length: n }, (_, i) => {
        const a = (i / n) * Math.PI * 2 + h(i) * 0.6;
        const v = power * (0.6 + 0.5 * h(i + 20));
        const k = d * Math.exp(-d * 2.2);
        const px = x + Math.cos(a) * v * k;
        const py = y + Math.sin(a) * v * k + 520 * d * d;
        const s = size * (0.55 + 0.6 * h(i + 40)) * (1 - clamp01((d - 0.45) / 0.6)) * clamp01(d / 0.05);
        if (s < 1) return null;
        return (
          <div key={i} style={{ position: "absolute", left: px, top: py, translate: "-50% -50%", rotate: `${(h(i + 60) - 0.5) * 720 * d}deg` }}>
            <StarIcon size={s} fill={colors[i % colors.length]} />
          </div>
        );
      })}
    </>
  );
};

/** Expanding ring (shockwave) in px. */
export const Ring: React.FC<{ t: number; at: number; x: number; y: number; r: number; color: string; width?: number; dur?: number }> = ({ t, at, x, y, r, color, width = 14, dur = 0.45 }) => {
  const u = (t - at) / dur;
  if (u < 0 || u > 1) return null;
  const e = easeOut(u);
  return <div style={{ position: "absolute", left: x - r * e, top: y - r * e, width: 2 * r * e, height: 2 * r * e, borderRadius: "50%", border: `${width * (1 - u)}px solid ${color}`, opacity: 1 - u * 0.5 }} />;
};
