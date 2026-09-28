// Act "dodge", bar 9: proximity voice, explained as one big build (README "Voice chat (proximity)"):
// staff hear how loud you are, never what you say; a whisper carries a metre or two, talking about 8 m,
// a yell down the corridor. A top-down corridor to scale (1 floor tile = 1 m), rings land one per beat.
import React from "react";
import { FONT } from "../../launch/tokens";
import { outline } from "../../launch/ui";
import { b } from "../cues";
import { GOLD, INK, SlamWord, TitleText } from "./ui";
import { clamp01, JELLY, POP, sp, WOBBLE } from "./world";

const W = 1920, H = 1080;
const M = 92; // px per metre
const SX = 250; // the speaker, on the corridor's centre line
const Y0 = 420, Y1 = 780; // the corridor strip
const CY = (Y0 + Y1) / 2;

export const RINGS = [
  { at: b(9), r: 1.5, col: "#7fe0a0", ink: "#1f6b43", label: "WHISPER", dist: "1-2 m" },
  { at: b(9, 1), r: 8, col: "#ff9a3c", ink: "#8a4a12", label: "TALK", dist: "~8 m" },
  { at: b(9, 2), r: 16.5, col: "#e0524f", ink: "#7a1f1d", label: "YELL", dist: "down the corridor" },
];

/** A voxel head, front on, drawn flat (student_model.gd _build_head proportions). */
const Head: React.FC<{ x: number; y: number; s: number; skin: string; hair: string; glasses?: boolean; cap?: string; tuft?: boolean }> = ({ x, y, s, skin, hair, glasses, cap, tuft }) => (
  <g transform={`translate(${x} ${y}) scale(${s})`}>
    <rect x={-40} y={-36} width={80} height={80} rx={4} fill={INK} transform="translate(0 8)" opacity={0.35} />
    <rect x={-38} y={-38} width={76} height={76} rx={3} fill={INK} />
    <rect x={-34} y={-34} width={68} height={68} fill={skin} />
    <rect x={-34} y={-34} width={68} height={16} fill={hair} />
    {tuft ? [-22, -6, 10].map((tx) => <rect key={tx} x={tx} y={-44} width={12} height={12} fill={hair} />) : null}
    {cap ? (
      <>
        <rect x={-36} y={-42} width={72} height={18} fill={cap} />
        <rect x={-36} y={-26} width={72} height={6} fill={INK} opacity={0.4} />
      </>
    ) : null}
    <rect x={-20} y={-6} width={9} height={13} fill="#1c1c24" />
    <rect x={11} y={-6} width={9} height={13} fill="#1c1c24" />
    <rect x={-28} y={12} width={10} height={6} fill="#ff9a8a" />
    <rect x={18} y={12} width={10} height={6} fill="#ff9a8a" />
    <rect x={-7} y={20} width={14} height={4} fill="rgba(0,0,0,0.35)" />
    {glasses ? (
      <>
        <rect x={-25} y={-10} width={20} height={20} fill="none" stroke="#5a3a22" strokeWidth={4} />
        <rect x={5} y={-10} width={20} height={20} fill="none" stroke="#5a3a22" strokeWidth={4} />
        <rect x={-5} y={-2} width={10} height={3} fill="#5a3a22" />
      </>
    ) : null}
  </g>
);

/** A "?" or "!" over a head, npc.gd colours, with a wobble in. */
const Mark: React.FC<{ t: number; at: number; x: number; y: number; kind: "?" | "!" }> = ({ t, at, x, y, kind }) => {
  const s = sp(t, at, WOBBLE);
  if (s <= 0.001) return null;
  return (
    <div style={{ position: "absolute", left: x, top: y, translate: "-50% -100%", scale: `${s}`, transformOrigin: "50% 100%", fontFamily: FONT, fontSize: 130, lineHeight: 1, color: kind === "!" ? "#ff4a4a" : "#ffd24a", ...outline(8, INK), filter: `drop-shadow(0 8px 0 ${INK})` }}>
      {kind}
    </div>
  );
};

const TEACHER_X = SX + 5.5 * M, GUARD_X = SX + 13.5 * M;

export const VoiceBuild: React.FC<{ t: number }> = ({ t }) => {
  if (t < b(9) || t >= b(10)) return null;
  const drift = (t - b(9)) * 30;
  const breathe = (at: number) => (t > at ? 1 + 0.015 * Math.sin((t - at) * 9) : 1);
  return (
    <div style={{ position: "absolute", inset: 0, background: "#8dd0ef", overflow: "hidden" }}>
      <svg width={W} height={H} style={{ position: "absolute", inset: 0, opacity: 0.12 }}>
        {Array.from({ length: 26 }, (_, i) => (
          <rect key={i} x={-700 + i * 160 + (drift % 160)} y={-300} width={62} height={1700} fill="#ffffff" transform={`rotate(22 ${W / 2} ${H / 2})`} />
        ))}
      </svg>
      {/* the corridor from above, to scale: one tile = one metre; lockers on the wall, pillars on the open side */}
      <svg width={W} height={H} style={{ position: "absolute", inset: 0 }}>
        <defs>
          <clipPath id="dodge-voice-strip"><rect x={60} y={Y0} width={W} height={Y1 - Y0} /></clipPath>
        </defs>
        <rect x={60 + 6} y={Y0 + 14} width={W} height={Y1 - Y0} fill={INK} opacity={0.3} />
        <g clipPath="url(#dodge-voice-strip)">
          {Array.from({ length: 22 }, (_, i) =>
            Array.from({ length: 5 }, (_, j) => (
              <rect key={`${i}-${j}`} x={60 + i * M} y={Y0 + j * M - 40} width={M} height={M} fill={(i + j) % 2 ? "#efe4cc" : "#d9c6a4"} />
            )),
          )}
          {Array.from({ length: 30 }, (_, i) => <rect key={i} x={60 + i * 70} y={Y0} width={64} height={34} fill="#5f8fb8" stroke="#2a3a4a" strokeWidth={2} />)}
          {Array.from({ length: 6 }, (_, i) => <rect key={i} x={60 + 150 + i * 368} y={Y1 - 22} width={30} height={22} fill="#c8704f" />)}
          {RINGS.map((r, i) => {
            const k = sp(t, r.at, POP);
            if (k <= 0.001) return null;
            const R = r.r * M * k * breathe(r.at + 0.4);
            return (
              <g key={i}>
                <circle cx={SX} cy={CY} r={R} fill={r.col} opacity={i === 0 ? 0.3 : 0.1} />
                <circle cx={SX} cy={CY} r={R} fill="none" stroke={r.col} strokeWidth={14} />
                <circle cx={SX} cy={CY} r={R} fill="none" stroke={r.ink} strokeWidth={3} opacity={0.6} />
              </g>
            );
          })}
        </g>
        <rect x={60} y={Y0 - 10} width={W} height={10} fill="#3a2d26" />
        <rect x={60} y={Y0} width={10} height={Y1 - Y0} fill="#3a2d26" />
        {/* who's in the corridor: you (talking), a teacher at 5.5 m, the guard at 13.5 m */}
        <Head x={SX} y={CY} s={1.45} skin="#8a5a36" hair="#1f1a17" tuft />
        <Head x={TEACHER_X} y={CY + 40} s={1.2} skin="#d09a6a" hair="#b9b6b0" glasses />
        <Head x={GUARD_X} y={CY - 30} s={1.2} skin="#a86e45" hair="#3b2618" cap="#24315e" />
      </svg>
      <Mark t={t} at={RINGS[1].at + 0.12} x={TEACHER_X} y={CY + 40 - 62} kind="?" />
      <Mark t={t} at={RINGS[2].at + 0.16} x={GUARD_X} y={CY - 30 - 72} kind="!" />
      {/* labels, one per ring, under the corridor at the ring's edge */}
      {RINGS.map((r, i) => {
        const k = sp(t, r.at + 0.04, JELLY);
        if (k <= 0.001) return null;
        const x = i === 0 ? SX + 60 : i === 1 ? SX + r.r * M : W - 40;
        const anchor = i === 2 ? "-100%" : "-50%";
        return (
          <div key={i} style={{ position: "absolute", left: x, top: Y1 + 34, translate: `${anchor} 0`, scale: `${k}`, transformOrigin: i === 2 ? "100% 0" : "50% 0" }}>
            <div style={{ display: "flex", alignItems: "baseline", gap: 18, background: r.col, borderRadius: 22, padding: "14px 28px 10px", boxShadow: `0 10px 0 ${INK}`, whiteSpace: "nowrap" }}>
              <span style={{ fontFamily: FONT, fontSize: 84, lineHeight: 1, color: INK }}>{r.label}</span>
              <span style={{ fontFamily: FONT, fontSize: 56, lineHeight: 1, color: INK, opacity: 0.85 }}>{r.dist}</span>
            </div>
          </div>
        );
      })}
      {/* title + the claim, carried over from bar 8 */}
      <div style={{ position: "absolute", left: 0, right: 0, top: 36, display: "flex", flexDirection: "column", alignItems: "center", gap: 14 }}>
        <SlamWord t={t} at={b(9)} size={170} color={GOLD} from={2.2} tilt={-4}>PROXIMITY VOICE</SlamWord>
        <div style={{ opacity: clamp01(sp(t, b(9) + 0.06, POP) * 3), scale: `${Math.max(0, sp(t, b(9) + 0.06, POP))}` }}>
          <TitleText size={64} color="#ffffff">They hear how loud. Never what you say.</TitleText>
        </div>
      </div>
      {/* hard cut in from bar 8: a short white pop */}
      <div style={{ position: "absolute", inset: 0, background: "#fff", opacity: Math.max(0, 0.6 - (t - b(9)) / 0.2) }} />
    </div>
  );
};
