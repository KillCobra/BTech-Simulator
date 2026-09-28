// Frame-driven twins of the game's 2D UI (scenes/ui/hud.gd, exam_game.gd, scenes/main.gd).
// Same colours, radii and strings; sizes doubled so they read at 1080p video.
import React from "react";
import { Img, staticFile } from "remotion";
import { C, FONT } from "./tokens";
import { clamp01, easeOut, POP, sp, squash, WOBBLE } from "./juice";
import { svgUrl } from "./icons";

export const font = (size: number, color = C.white, extra: React.CSSProperties = {}): React.CSSProperties => ({
  fontFamily: FONT, fontSize: size, color, lineHeight: 1, ...extra,
});
/** Godot's font outline: stroke painted under the fill. */
export const outline = (px: number, color = C.ink): React.CSSProperties => ({
  WebkitTextStroke: `${px * 2}px ${color}`, paintOrder: "stroke fill",
});

/** hud.gd `_card`: dark translucent card, radius 12, no border. */
export const Card: React.FC<{ style?: React.CSSProperties; children?: React.ReactNode; radius?: number; bg?: string; pad?: number }> = ({ style, children, radius = 24, bg = C.card, pad = 24 }) => (
  <div style={{ background: bg, borderRadius: radius, padding: pad, ...style }}>{children}</div>
);

/** main.gd `_button`: fill, radius 12, border-bottom 6 in the colour darkened 0.35; pressed = 2. */
export const GameButton: React.FC<{ label: string; color: string; ink?: string; press?: number; size?: number; style?: React.CSSProperties }> = ({ label, color, ink = C.ink, press = 0, size = 40, style }) => {
  const dark = darken(color, 0.35);
  const bottom = 12 - 8 * press;
  return (
    <div style={{ display: "inline-block", paddingTop: 8 * press, ...style }}>
      <div style={{ background: color, borderRadius: 22, borderBottom: `${bottom}px solid ${dark}`, padding: `${size * 0.42}px ${size * 0.9}px ${size * 0.36}px`, ...font(size, ink), whiteSpace: "nowrap" }}>
        {label}
      </div>
    </div>
  );
};

export function darken(hex: string, a: number) {
  const n = parseInt(hex.slice(1), 16);
  const r = ((n >> 16) & 255) * (1 - a), g = ((n >> 8) & 255) * (1 - a), bl = (n & 255) * (1 - a);
  return `rgb(${Math.round(r)},${Math.round(g)},${Math.round(bl)})`;
}

export const Icon: React.FC<{ svg: string; size: number; style?: React.CSSProperties }> = ({ svg, size, style }) => (
  <img src={svgUrl(svg)} width={size} height={size} style={{ display: "block", ...style }} />
);

/** A "!" or "?" alert over a head (npc.gd alert Label3D: "?" ffd24a, "!" ff4a4a). */
export const Alert: React.FC<{ t: number; at: number; x: number; y: number; kind: "!" | "?"; size?: number }> = ({ t, at, x, y, kind, size = 150 }) => {
  const s = sp(t, at, WOBBLE);
  if (s <= 0.001) return null;
  const [sx, sy] = squash(t, at + 0.12, 0.25);
  return (
    <div style={{ position: "absolute", left: x, top: y, translate: "-50% -100%", scale: `${s * sx} ${s * sy}`, transformOrigin: "50% 100%", rotate: `${(1 - Math.min(1, s)) * -30}deg`, ...font(size, kind === "!" ? C.alarm : C.warn), ...outline(9, C.ink), textShadow: "0 8px 0 rgba(0,0,0,.3)" }}>
      {kind}
    </div>
  );
};

/** NPC speech (npc.gd Label3D: white, black outline 12). */
export const Speech: React.FC<{ t: number; at: number; x: number; y: number; text: string; size?: number }> = ({ t, at, x, y, text, size = 84 }) => {
  const s = sp(t, at, POP);
  if (s <= 0.001) return null;
  return (
    <div style={{ position: "absolute", left: x, top: y, translate: "-50% -100%", scale: `${s}`, transformOrigin: "50% 100%", ...font(size, C.white), ...outline(7, "#000"), whiteSpace: "nowrap" }}>
      {text}
    </div>
  );
};

/** Centre-top banner (hud.gd:569): colour at 0.9, radius 14, text 24 (x2). Drops in with a squash. */
export const Banner: React.FC<{ t: number; at: number; out?: number; color: string; text: string; sub?: string; top?: number; size?: number }> = ({ t, at, out = 1e9, color, text, sub, top = 70, size = 64 }) => {
  if (t < at - 0.2) return null;
  const drop = sp(t, at, { stiffness: 600, damping: 22 });
  const [sx, sy] = squash(t, at + 0.06, 0.18, 22, 9);
  const leave = easeOut(clamp01((t - out) / 0.2));
  return (
    <div style={{ position: "absolute", left: "50%", top, translate: `-50% ${(1 - drop) * -260 - leave * 300}px`, scale: `${sx} ${sy}`, transformOrigin: "50% 0%", opacity: 1 - leave }}>
      <div style={{ background: color, opacity: 0.94, position: "absolute", inset: 0, borderRadius: 28, boxShadow: "0 18px 0 rgba(0,0,0,.18)" }} />
      <div style={{ position: "relative", padding: "30px 64px 26px", textAlign: "center", minWidth: 920 }}>
        <div style={{ ...font(size, C.white), ...outline(5, "rgba(0,0,0,.35)"), whiteSpace: "nowrap" }}>{text}</div>
        {sub ? <div style={{ ...font(size * 0.5, C.white), marginTop: 10, opacity: 0.9, whiteSpace: "nowrap" }}>{sub}</div> : null}
      </div>
    </div>
  );
};

/** A plate (real game capture) as a background image. */
export const Plate: React.FC<{ name: string; style?: React.CSSProperties }> = ({ name, style }) => (
  <Img src={staticFile(`plates/${name}.jpg`)} style={{ position: "absolute", width: 1920, height: 1080, left: 0, top: 0, ...style }} />
);

/** Words that land one by one with a squash (for taglines and lines of copy). */
export const PopWords: React.FC<{ t: number; words: [string, number][]; size: number; color?: string; stroke?: number; gap?: number }> = ({ t, words, size, color = C.white, stroke = 0, gap = 0.26 }) => (
  <div style={{ display: "flex", gap: `${gap}em`, fontFamily: FONT, fontSize: size, whiteSpace: "nowrap" }}>
    {words.map(([w, at], i) => {
      const s = sp(t, at, POP);
      return (
        <span key={i} style={{ display: "inline-block", opacity: clamp01(s * 3), scale: `${Math.max(0, s)}`, translate: `0 ${(1 - Math.min(1, s)) * 30}px`, color, ...(stroke ? outline(stroke) : {}), filter: s < 0.6 ? `blur(${(0.6 - s) * 14}px)` : undefined }}>
          {w}
        </span>
      );
    })}
  </div>
);
