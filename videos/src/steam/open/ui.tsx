// 2D pieces for the open act: HUD twins (hud.gd period card, suspicion meter, dialog card, interact hint,
// RUN! banner), the ringing letters, slam titles and the striped colour fields. All pure functions of t.
import React from "react";
import { step } from "../../kit/spring";
import { clamp01, lerp, POP, sp, squash, WOBBLE } from "../../launch/juice";
import { C, FONT } from "../../launch/tokens";
import { font, outline } from "../../launch/ui";
import { BEAT } from "../cues";

export const INK = "#2a1a0e";
export const GOLD = "#ffc93c";
export const YELLOW = "#ffd24a";
export const RED = "#e0524f";

export const mmss = (s: number) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`;
const hash = (n: number) => {
  const x = Math.sin(n * 127.1 + 311.7) * 43758.5453;
  return (x - Math.floor(x)) * 2 - 1;
};
export function mixHex(a: string, c: string, u: number) {
  const x = parseInt(a.slice(1), 16), y = parseInt(c.slice(1), 16);
  const ch = (s: number) => Math.round(((x >> s) & 255) + ((((y >> s) & 255) - ((x >> s) & 255)) * clamp01(u)));
  return `#${((1 << 24) | (ch(16) << 16) | (ch(8) << 8) | ch(0)).toString(16).slice(1)}`;
}
const HUD_BG = "rgba(20,20,36,0.84)"; // hud.gd _card Color(0.08, 0.08, 0.14, 0.72), a touch denser for video

// ------------------------------------------------------------------ RIIIING!
/** Letters pop on 32nds from `at` and shiver on 32nds while the clock rings; `ring` is 0..1. */
export const Riiing: React.FC<{ t: number; at: number; ring: number; out: number; size?: number }> = ({ t, at, ring, out, size = 210 }) => {
  const letters = "RIIIING!".split("");
  const q = Math.floor(t / (BEAT / 8));
  return (
    <div style={{ display: "flex", gap: size * 0.02, alignItems: "flex-end" }}>
      {letters.map((ch, i) => {
        const s = step(t - (at + i * BEAT / 16), { stiffness: 700, damping: 16 });
        const shiver = 0.25 + ring;
        const jx = hash(q * 7 + i) * 9 * shiver, jy = hash(q * 13 + i * 3) * 12 * shiver;
        const rot = hash(q * 3 + i * 11) * 9 * shiver;
        const leave = clamp01((out - i * 0.05) / 0.5);
        const big = i >= 1 && i <= 4 ? 1 + 0.12 * Math.sin(i * 1.3) : 1;
        return (
          <div key={i} style={{
            ...font(size * big, GOLD), ...outline(size * 0.055), textShadow: `0 ${size * 0.07}px 0 #000`,
            translate: `${jx}px ${jy - leave * 700}px`, rotate: `${rot + leave * (i - 3.5) * 14}deg`,
            scale: `${Math.max(0, s)}`, opacity: s > 0.02 ? 1 : 0, transformOrigin: "50% 100%",
          }}>{ch}</div>
        );
      })}
    </div>
  );
};

// ------------------------------------------------------------------ the HUD period card (hud.gd _build_left_column)
/** `at`: when each of the 4 rows lands (one per 8th). `secs`: the Final bell countdown. `k`: scale over the game's px. */
export const PeriodCard: React.FC<{ t: number; k: number; panelAt: number; at: number[]; secs: number; tickAt?: number }> = ({ t, k, panelAt, at, secs, tickAt }) => {
  const f = (n: number) => n * k;
  const tick = tickAt !== undefined && t >= tickAt ? Math.exp(-(t - tickAt) / 0.08) : 0;
  const cashU = clamp01((t - at[3]) / (BEAT / 2));
  const cash = Math.round(Math.floor(cashU * 3.999) * 10);
  const rows: React.ReactNode[] = [
    <div style={{ display: "flex", alignItems: "center", gap: f(10) }}>
      <span style={font(f(22), "#fff")}>YOU</span>
      <span style={{ ...font(f(15), "#fff"), background: C.classes[0], borderRadius: f(6), padding: `${f(3)}px ${f(7)}px ${f(1.5)}px` }}>Class A</span>
    </div>,
    <span style={font(f(15), "#fff")}>Final bell in <span style={{ display: "inline-block", scale: `${1 + 0.18 * tick}`, color: tick > 0.3 ? YELLOW : "#fff" }}>{mmss(secs)}</span></span>,
    <span style={font(f(15), "#9fd8ff")}>Period 1/3  ·  Thermodynamics</span>,
    <span style={font(f(15), YELLOW)}>Pocket money: Rs {cash}</span>,
  ];
  const panel = step(t - panelAt, { stiffness: 520, damping: 18 });
  return (
    <div style={{ background: HUD_BG, borderRadius: f(12), padding: `${f(12)}px ${f(14)}px`, display: "flex", flexDirection: "column", gap: f(7), width: f(262), scale: `${Math.max(0, panel)}`, transformOrigin: "0% 50%" }}>
      {rows.map((node, i) => {
        const u = step(t - at[i], { stiffness: 700, damping: 22 });
        const [sx, sy] = squash(t, at[i] + 0.06, 0.22, 28, 10);
        const flash = t >= at[i] ? Math.exp(-(t - at[i]) / 0.12) : 0;
        return (
          <div key={i} style={{ opacity: clamp01(u * 5), translate: `0 ${(1 - Math.min(1, u)) * -f(18)}px`, scale: `${lerp(1.6, 1, u) * sx} ${lerp(1.6, 1, u) * sy}`, transformOrigin: "0% 70%", filter: flash > 0.05 ? `brightness(${1 + flash * 1.4})` : undefined }}>
            {node}
          </div>
        );
      })}
    </div>
  );
};

// ------------------------------------------------------------------ dialog card (hud.gd _build_dialog)
export const DialogCard: React.FC<{ t: number; at: number; out: number; who: string; chunks: [string, number][]; k?: number }> = ({ t, at, out, who, chunks, k = 2.7 }) => {
  if (t < at - 0.05) return null;
  const s = step(t - at, { stiffness: 420, damping: 22 });
  const leave = clamp01((t - out) / 0.2);
  if (leave >= 1) return null;
  return (
    <div style={{ position: "absolute", left: "50%", bottom: 56, translate: `-50% ${(1 - s) * 300 + leave * leave * 420}px`, opacity: 1 - leave }}>
      <div style={{ background: "rgba(15,15,26,0.92)", borderRadius: 14 * k, padding: `${14 * k}px ${22 * k}px ${16 * k}px`, minWidth: 1180 }}>
        <div style={font(15 * k, YELLOW)}>{who}</div>
        <div style={{ ...font(26 * k, "#fff"), marginTop: 6 * k, whiteSpace: "nowrap", display: "flex", gap: `${0.28}em` }}>
          {chunks.map(([w, wAt], i) => {
            const u = step(t - wAt, { stiffness: 700, damping: 20 });
            const [sx, sy] = squash(t, wAt + 0.05, 0.2, 28, 10);
            const q = (i === 0 ? '"' : "") + w + (i === chunks.length - 1 ? '"' : "");
            return <span key={i} style={{ display: "inline-block", opacity: clamp01(u * 5), translate: `0 ${(1 - Math.min(1, u)) * -40}px`, scale: `${lerp(1.2, 1, u) * sx} ${lerp(1.2, 1, u) * sy}`, transformOrigin: "0% 90%" }}>{q}</span>;
          })}
        </div>
      </div>
    </div>
  );
};

// ------------------------------------------------------------------ interact hint (player.gd interact_hint)
export const Prompt: React.FC<{ t: number; at: number; press: number; out: number }> = ({ t, at, press, out }) => {
  if (t < at) return null;
  const s = step(t - at, { stiffness: 700, damping: 17 });
  const [sx, sy] = squash(t, at + 0.05, 0.2, 26, 10);
  const pr = t >= press ? Math.exp(-(t - press) / 0.1) : 0;
  const pressed = t >= press;
  const leave = clamp01((t - out) / 0.16);
  if (leave >= 1) return null;
  const key = 120;
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 30, scale: `${s * sx * (1 - 0.1 * pr) * (1 + leave * 0.4)} ${s * sy * (1 - 0.1 * pr) * (1 + leave * 0.4)}`, opacity: 1 - leave }}>
      <div style={{ paddingTop: pressed ? 10 : 0 }}>
        <div style={{
          ...font(88, INK), width: key, height: key, display: "grid", placeItems: "center", background: pressed && pr > 0.2 ? "#ffffff" : YELLOW,
          borderRadius: 22, borderBottom: `${pressed ? 4 : 14}px solid #b8902a`, boxShadow: "0 10px 0 rgba(0,0,0,.25)",
        }}>E</div>
      </div>
      <div style={{ ...font(110, "#fff"), ...outline(8, "#000"), textShadow: "0 10px 0 rgba(0,0,0,.35)", whiteSpace: "nowrap" }}>Stand up</div>
    </div>
  );
};

// ------------------------------------------------------------------ suspicion meter (hud.gd _build_meter, top right)
export const SuspicionCard: React.FC<{ t: number; value: number; seenAt: number; k?: number }> = ({ t, value, seenAt, k = 2.2 }) => {
  const seen = t >= seenAt && Math.floor((t - seenAt) / 0.125) % 2 === 0;
  const fill = mixHex(YELLOW, "#ff3b3b", value / 100);
  return (
    <div style={{ background: HUD_BG, borderRadius: 12 * k, padding: `${12 * k}px ${12 * k}px`, width: 280 * k }}>
      <div style={{ display: "flex", alignItems: "center", ...font(15 * k, "#fff") }}>
        <span style={{ flex: 1 }}>SUSPICION</span>
        <span style={{ color: "#ff5a5a", opacity: seen ? 1 : 0, marginRight: 12 * k }}>SEEN!</span>
        <span style={{ minWidth: 40 * k, textAlign: "right" }}>{Math.round(value)}%</span>
      </div>
      <div style={{ marginTop: 6 * k, height: 14 * k, background: "rgba(255,255,255,0.12)" }}>
        <div style={{ width: `${value}%`, height: "100%", background: fill }} />
      </div>
    </div>
  );
};

// ------------------------------------------------------------------ RUN! banner (hud.gd _show_banner, ff4a4a)
export const RunBanner: React.FC<{ t: number; at: number; out?: number }> = ({ t, at, out = 1e9 }) => {
  if (t < at) return null;
  const gone = clamp01((t - out) / 0.1);
  if (gone >= 1) return null;
  const d = t - at;
  const s = lerp(3.2, 1, step(d, { stiffness: 900, damping: 40 }));
  const [sx, sy] = squash(t, at + 0.07, 0.2, 28, 9);
  const q = Math.floor(t / (BEAT / 8));
  return (
    <div style={{ scale: `${s * sx * (1 + gone * 0.6)} ${s * sy * (1 + gone * 0.6)}`, translate: `0 ${-gone * gone * 900}px`, rotate: `${-5 + hash(q) * 1.5}deg`, opacity: clamp01(d / 0.03) }}>
      <div style={{ background: "#ff4a4a", borderRadius: 40, padding: "18px 90px 30px", boxShadow: "0 22px 0 #a82020", textAlign: "center" }}>
        <div style={{ ...font(400, "#fff"), ...outline(10, "rgba(0,0,0,.35)") }}>RUN!</div>
        <div style={{ ...font(72, "#fff"), marginTop: -16 }}>You've been spotted!</div>
      </div>
    </div>
  );
};

// ------------------------------------------------------------------ slam titles
/** One word or line that slams in on `at`: big -> 1 with squash, blur on the way in. */
export const Slam: React.FC<{ t: number; at: number; text: string; size: number; color?: string; tilt?: number; out?: number; origin?: string }> = ({
  t, at, text, size, color = "#ffffff", tilt = -4, out = 1e9, origin = "50% 60%",
}) => {
  if (t < at) return <div style={{ ...font(size), visibility: "hidden", whiteSpace: "nowrap" }}>{text}</div>;
  const u = step(t - at, { stiffness: 1000, damping: 44 });
  const s = lerp(2.7, 1, u);
  const [sx, sy] = squash(t, at + 0.05, 0.24, 28, 9);
  const leave = clamp01((t - out) / 0.18);
  return (
    <div style={{
      ...font(size, color), ...outline(size * 0.06), textShadow: `0 ${size * 0.075}px 0 ${INK}`, whiteSpace: "nowrap",
      scale: `${s * sx * (1 + leave * 0.3)} ${s * sy * (1 + leave * 0.3)}`, rotate: `${tilt * (0.6 + 1.6 * (1 - u))}deg`, transformOrigin: origin,
      opacity: 1 - leave, filter: u < 0.85 ? `blur(${(0.85 - u) * 12}px)` : undefined,
    }}>{text}</div>
  );
};

// ------------------------------------------------------------------ fields
/** Flat colour field with scrolling diagonal stripes; `offset` is the scroll in px (integrate speed yourself). */
export const Stripes: React.FC<{ bg: string; stripe: string; offset: number; width?: number; period?: number; angle?: number; style?: React.CSSProperties }> = ({
  bg, stripe, offset, width = 70, period = 170, angle = 30, style,
}) => {
  const n = 40;
  const px = period;
  const o = ((offset % px) + px) % px;
  return (
    <div style={{ position: "absolute", inset: 0, background: bg, overflow: "hidden", ...style }}>
      <svg width={1920} height={1080} style={{ position: "absolute", inset: 0 }}>
        <g transform={`rotate(${angle} 960 540)`}>
          {Array.from({ length: n }, (_, i) => (
            <rect key={i} x={-1800 + i * px - o} y={-900} width={width} height={2900} fill={stripe} />
          ))}
        </g>
      </svg>
    </div>
  );
};

/** Horizontal speed lines (streaks) moving left, deterministic per index. */
export const SpeedLines: React.FC<{ t: number; color: string; n?: number; speed?: number; y0?: number; y1?: number; o?: number }> = ({ t, color, n = 14, speed = 3200, y0 = 0, y1 = 1080, o = 1 }) => (
  <svg width={1920} height={1080} style={{ position: "absolute", inset: 0, opacity: o }}>
    {Array.from({ length: n }, (_, i) => {
      const len = 180 + ((hash(i * 3) + 1) / 2) * 420;
      const y = y0 + ((hash(i * 7 + 1) + 1) / 2) * (y1 - y0);
      const sp_ = speed * (0.7 + 0.6 * (hash(i * 5 + 2) + 1) / 2);
      const span = 1920 + len + 200;
      const x = 1920 + 100 - (((t * sp_ + ((hash(i * 11) + 1) / 2) * span) % span));
      return <rect key={i} x={x} y={y} width={len} height={6 + ((hash(i) + 1) / 2) * 8} fill={color} />;
    })}
  </svg>
);

export { sp, WOBBLE, FONT };
