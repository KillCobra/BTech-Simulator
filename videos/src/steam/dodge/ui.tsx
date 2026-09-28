// Act "dodge": 2D pieces. Big kinetic titles (trailer 1 language) and twins of the game's HUD
// (hud.gd _pop_style, _refresh_mic, _refresh_question), all pure functions of t.
import React from "react";
import { FONT } from "../../launch/tokens";
import { outline } from "../../launch/ui";
import { clamp01, lerp, POP, SNAP, sp } from "./world";

export const GOLD = "#ffc93c", INK = "#2a1a0e";

const outBack = (u: number, s = 2.2) => {
  const x = clamp01(u) - 1;
  return 1 + (s + 1) * x * x * x + s * x * x;
};
/** Scale for a slam: `from` down to 1 with overshoot, 0 before `at`. */
export const slam = (t: number, at: number, from = 2.4, len = 0.26) => {
  if (t < at) return 0;
  return 1 + (from - 1) * (1 - outBack((t - at) / len));
};

/** Title type: gold (or white) fill, ink outline, hard ink drop shadow. */
export const TitleText: React.FC<{ size: number; color?: string; children: React.ReactNode; style?: React.CSSProperties }> = ({ size, color = GOLD, children, style }) => (
  <div
    style={{
      fontFamily: FONT, fontSize: size, lineHeight: 0.9, color, whiteSpace: "pre", ...outline(size * 0.042, INK), letterSpacing: size * 0.015,
      filter: `drop-shadow(0 ${Math.round(size * 0.07)}px 0 ${INK})`, ...style,
    }}
  >
    {children}
  </div>
);

/** A word that slams in on its beat: big, tilted, overshoots down to size. */
export const SlamWord: React.FC<{ t: number; at: number; size: number; color?: string; tilt?: number; from?: number; children: string }> = ({ t, at, size, color, tilt = -6, from = 2.6, children }) => {
  const s = slam(t, at, from, 0.26);
  const on = t >= at;
  return (
    <div style={{ display: "inline-block", opacity: on ? 1 : 0, scale: `${on ? s : 1}`, rotate: `${on ? tilt * (s - 1) : 0}deg` }}>
      <TitleText size={size} color={color}>{children}</TitleText>
    </div>
  );
};

/** hud.gd _pop_style: "CLOSE CALL  +50", ffd24a, outlined, 1.4 -> 1 in 0.18 s, holds, fades, rising. */
export const StylePop: React.FC<{ t: number; at: number; x: number; y: number; text: string; size?: number }> = ({ t, at, x, y, text, size = 76 }) => {
  if (t < at) return null;
  const d = t - at;
  const s = 1 + 0.4 * (1 - clamp01(d / 0.18)) * (1 - clamp01(d / 0.18));
  const fade = 1 - clamp01((d - 1.2) / 0.4);
  return (
    <div style={{ position: "absolute", left: x, top: y - d * 40, translate: "-50% -50%", scale: `${s}`, opacity: fade }}>
      <div style={{ fontFamily: FONT, fontSize: size, lineHeight: 1, color: "#ffd24a", whiteSpace: "pre", ...outline(size * 0.09, "#000"), filter: "drop-shadow(0 6px 0 rgba(0,0,0,0.35))" }}>{text}</div>
    </div>
  );
};

/** hud.gd _refresh_mic, bottom-left: "● TALKING  ||||   staff hear you ~8 m" (red) or "whisper: safe" (green). */
export const MicMeter: React.FC<{ t: number; at: number; out: number; radius: number; x?: number; y?: number; size?: number }> = ({ t, at, out, radius, x = 64, y = 1010, size = 46 }) => {
  if (t < at || t > out + 0.3) return null;
  const s = sp(t, at, SNAP);
  const leave = clamp01((t - out) / 0.2);
  const bars = Math.max(1, Math.min(8, Math.floor(radius / 2)));
  const loud = radius >= 4;
  const col = loud ? "#ff6a5a" : "#7fe0a0";
  const warn = loud ? `staff hear you ~${Math.round(radius)} m` : "whisper: safe";
  return (
    <div style={{ position: "absolute", left: x, top: y, translate: `${(1 - s) * -500 - leave * 500}px -100%` }}>
      <div style={{ display: "flex", alignItems: "center", gap: 18, background: "rgba(20,20,36,0.8)", borderRadius: size * 0.4, padding: `${size * 0.3}px ${size * 0.5}px ${size * 0.25}px` }}>
        <span style={{ fontFamily: FONT, fontSize: size, lineHeight: 1, color: col, whiteSpace: "pre", ...outline(size * 0.06, "#000") }}>
          {"● TALKING  "}
          <span style={{ letterSpacing: 4 }}>{"|".repeat(bars)}</span>
          {"   " + warn}
        </span>
      </div>
    </div>
  );
};

/** A pill tag pinned in 3D (for the ring radii): "whisper: safe", "~8 m". */
export const Pill: React.FC<{ t: number; at: number; out?: number; x: number; y: number; bg: string; color?: string; size?: number; children: React.ReactNode }> = ({ t, at, out = 1e9, x, y, bg, color = "#fff", size = 40, children }) => {
  const s = sp(t, at, POP) * (1 - clamp01((t - out) / 0.15));
  if (s <= 0.001) return null;
  return (
    <div style={{ position: "absolute", left: x, top: y, translate: "-50% -50%", scale: `${s}` }}>
      <div style={{ fontFamily: FONT, fontSize: size, lineHeight: 1, color, background: bg, borderRadius: 999, padding: `${size * 0.16}px ${size * 0.42}px ${size * 0.12}px`, whiteSpace: "nowrap", boxShadow: "0 5px 0 rgba(42,26,14,0.45)" }}>{children}</div>
    </div>
  );
};

// ------------------------------------------------------------------ the excuse picker (hud.gd _refresh_question)
export type Excuse = { text: string; kind: "proof" | "talk" | "snitch" };
export const EXCUSES: Excuse[] = [
  { text: "I've got a hall pass, look!", kind: "proof" },
  { text: "Just coming back from the washroom!", kind: "talk" },
  { text: "Dr. Haddad sent me to fetch something.", kind: "talk" },
  { text: "It was Arjun! They made me do it!", kind: "snitch" },
];
const ROW_COL = { proof: "#7fe0a0", talk: "#ffffff", snitch: "#ff6a8a" };

export const ExcusePicker: React.FC<{ t: number; at: number; rows: number[]; pick: number; chosen: number; timerFrom: number; k?: number }> = ({ t, at, rows, pick, chosen, timerFrom, k = 2.65 }) => {
  const rise = sp(t, at, { stiffness: 420, damping: 22 });
  if (rise <= 0.001) return null;
  const picked = t >= pick;
  const d = t - pick;
  const left = 1 - clamp01((t - timerFrom) / 4.0);
  // After the pick (hud.gd hides the card): the chosen line flashes, then the card drops away.
  const drop = picked ? clamp01((d - 0.1) / 0.2) : 0;
  if (drop >= 1) return null;
  return (
    <div style={{ position: "absolute", left: "50%", top: 600, translate: `-50% calc(-50% + ${(1 - rise) * 900 + drop * drop * 900}px)`, rotate: `${(1 - Math.min(1, rise)) * 5 + drop * 4}deg` }}>
      <div style={{ position: "relative", width: 1380, padding: 16 * k, borderRadius: 16 * k }}>
        <div style={{ position: "absolute", inset: 0, background: "rgba(26,13,13,0.94)", borderRadius: 16 * k }} />
        <div style={{ position: "relative", display: "flex", flexDirection: "column", gap: 6 * k }}>
          <div style={{ fontFamily: FONT, fontSize: 22 * k, lineHeight: 1, color: "#ff9a7a", whiteSpace: "pre", ...outline(3, "#000") }}>
            {"MS. OKAFOR STOPPED YOU!  Talk your way out:"}
          </div>
          {EXCUSES.map((e, i) => {
            const s = sp(t, rows[i], POP);
            const land = t > rows[i] ? Math.exp(-(t - rows[i]) * 12) * Math.cos((t - rows[i]) * 34) : 0;
            const isChosen = picked && i === chosen;
            const pop = isChosen ? 1 + 0.25 * Math.exp(-d * 10) * Math.cos(d * 30) : 1;
            const gone = picked && !isChosen ? 0.6 * clamp01(d / 0.06) : 0;
            return (
              <div key={i} style={{ opacity: t < rows[i] ? 0 : clamp01(s * 3) * (1 - gone), translate: `${(1 - s) * 260}px 0`, scale: `${pop * (1 + 0.12 * land)} ${pop * (1 - 0.12 * land)}`, transformOrigin: "0% 50%", display: "flex", alignItems: "center" }}>
                <span
                  style={{
                    fontFamily: FONT, fontSize: 19 * k, lineHeight: 1, color: ROW_COL[e.kind], whiteSpace: "pre", ...outline(3, "#000"),
                    background: isChosen ? "rgba(255,106,138,0.22)" : undefined, borderRadius: 10, padding: "4px 10px 2px", marginLeft: -10,
                  }}
                >
                  {`[${i + 1}]  ${e.text}`}
                </span>
              </div>
            );
          })}
          <div style={{ height: 8 * k, background: "rgba(255,255,255,0.12)", marginTop: 4 * k }}>
            <div style={{ width: `${left * 100}%`, height: "100%", background: "#ff6a5a" }} />
          </div>
        </div>
      </div>
    </div>
  );
};

/** A keycap that presses on `at` (the [4] key). */
export const Key: React.FC<{ t: number; at: number; label: string; x: number; y: number; show: number }> = ({ t, at, label, x, y, show }) => {
  const s = sp(t, at - 0.12, POP) * show;
  if (s <= 0.001) return null;
  const press = t >= at ? Math.exp(-(t - at) * 14) : 0;
  const edge = lerp(14, 4, press);
  return (
    <div style={{ position: "absolute", left: x, top: y, translate: "-50% -50%", scale: `${s}` }}>
      <div style={{ paddingTop: 14 - edge }}>
        <div style={{ width: 120, height: 110, borderRadius: 20, background: "#ffffff", borderBottom: `${edge}px solid #b8b0a0`, display: "grid", placeItems: "center", fontFamily: FONT, fontSize: 84, color: INK, lineHeight: 1 }}>{label}</div>
      </div>
    </div>
  );
};
