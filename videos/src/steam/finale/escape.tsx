// Bar 20: out through the main gate past the guard on his chai break; the green escape banner and confetti.
// Bar 21: FINAL BELL! (hud.gd end screen twin): points count, CCTV archive awards (director.gd), then the rank
// ladder from autoload/profile.gd flips up to BUNK MASTER, which flies out of the card into the logo.
import React, { useMemo } from "react";
import { Alert, Banner, font, outline } from "../../launch/ui";
import { C } from "../../launch/tokens";
import { CHAI_GLASS } from "../../launch/sets";
import { Character, Voxels } from "../../launch/three";
import { CAST, HIP_HEIGHT, mixPose, REST, sitPose, walkPose, type Box, type Look, type Pose, type V3 } from "../../launch/voxel";
import type { Cam } from "../../launch/camera3d";
import { step } from "../../kit/spring";
import { b, BEAT } from "../cues";
import { Stage3D, toScreen } from "../Stage3D";
import { Burst } from "../../film/fxui";
import { campus } from "./sets";
import { clamp01, Confetti, InkText, Dust, Flash, inCubic, Label, lerp, lerp3, outCubic, outExpo, PI, rnd, shake, smooth } from "./kit";

const WOBBLE = { stiffness: 380, damping: 11 };
const SNAP = { stiffness: 700, damping: 30 };
const POP = { stiffness: 520, damping: 20 };
const sp = (t: number, at: number, cfg = POP) => step(t - at, cfg);

type Actor = { id: string; look: Look; pose: Pose; p: V3; yaw: number; pitch?: number; squash?: number; chai?: boolean };
const GUARD2: Look = { ...CAST.guard, skin: "#e0ac7e" };
const GUARD_SEAT: V3 = [3.35, 0, 3.45];

// Gang: [id, look, start x, lag (m behind), target on the road, hop phase]
const GANG: [string, Look, number, number, [number, number], number][] = [
  ["hero", CAST.hero, 0.3, 0, [0.75, 7.7], 0],
  ["friendA", CAST.friendA, 1.2, 0.9, [-0.6, 7.0], 0.5],
  ["friendB", CAST.friendB, -0.7, 1.6, [-1.85, 6.6], 0.25],
  ["friendC", CAST.friendC, 0.6, 2.3, [1.9, 6.3], 0.75],
];

const cheer = (t: number, ph: number): Pose => {
  const k = Math.sin((t / BEAT + ph) * PI * 2);
  return { ...REST, armLX: 2.7 + 0.35 * k, armRX: 2.9 - 0.35 * k, armLZ: -0.45, armRZ: 0.45, headX: -0.25, legL: 0.15 * Math.max(0, k), legR: 0.15 * Math.max(0, -k) };
};

export function escapeActors(t: number): Actor[] {
  const T = b(20);
  const out: Actor[] = GANG.map(([id, look, x0, lag, [xt, zt], ph], i) => {
    const d = t - T - lag / 7.5;
    const zStart = 1.2 - lag;
    // Sprint out of the gate, then brake onto the road.
    const run = clamp01(d / 0.62);
    const e = 1 - Math.pow(1 - run, 2.2);
    const x = lerp(x0, xt, smooth(run)), z = lerp(zStart, zt, e);
    const moving = run < 1;
    let pose: Pose = moving ? walkPose(t * 15.5 + i, 1 - 0.6 * run, 0, true) : REST;
    pose = { ...pose, armLX: pose.armLX * 1.6, armRX: pose.armRX * 1.6 };
    let y = 0, sq = 1;
    // Everybody jumps on 20.2 (the banner), then hops on the beat.
    const jumpAt = b(20, 2) + i * 0.035;
    if (t > jumpAt - 0.08) {
      const c = cheer(t, ph);
      pose = mixPose(pose, c, clamp01((t - jumpAt + 0.08) / 0.12));
      const j = t - jumpAt;
      if (j > 0 && j < 0.5) y = 0.85 * Math.sin((j / 0.5) * PI);
      else if (j >= 0.5) {
        const k = ((t - b(20, 3) + ph * 0.1) % BEAT + BEAT) % BEAT;
        y = t > b(20, 3) ? 0.42 * Math.sin(Math.min(1, k / (BEAT * 0.62)) * PI) : 0;
      }
      if (j > 0.5 && j < 0.7) sq = 1 - 0.25 * Math.sin(((j - 0.5) / 0.2) * PI);
    }
    // Face the camera side once out; the hero turns back to wave at the gate.
    const yaw = moving ? PI - 0.2 * (xt - x0) : lerp(PI, PI + 0.9 + i * 0.25, smooth((t - b(20, 1.5)) / 0.3));
    return { id, look, pose, p: [x, y, z], yaw, squash: sq };
  });
  // Staff pile up at the gate and skid to a stop on 20.3 (they don't leave campus).
  const staff: [string, Look, number, number, number][] = [
    ["guard2", GUARD2, -0.4, 0, 0.3],
    ["proctor", CAST.proctor, 1.3, 0.16, 1.1],
  ];
  for (const [id, look, x, delay, ph] of staff) {
    const stop = b(20, 3) + delay;
    const zStop = 1.75 - delay * 2;
    const z = t < stop ? zStop - 7.2 * (stop - t) : zStop + 0.35 * (1 - Math.exp(-(t - stop) * 12));
    const skid = t > stop ? Math.exp(-(t - stop) * 4) : 0;
    const pant = t > stop + 0.25;
    const run = walkPose(t * 15 + ph, 1, 0, true);
    let pose: Pose = t < stop ? { ...run, armLX: run.armLX * 1.6, armRX: run.armRX * 1.6, torsoX: -0.2 } : { ...REST, torsoX: 0.35 * skid, legL: -0.5 * skid, legR: 0.4 * skid, armLX: 1.6 * skid, armRX: 1.8 * skid, armLZ: -0.7 * skid, armRZ: 0.7 * skid };
    if (pant) pose = mixPose(pose, { ...REST, torsoX: -0.45 + 0.06 * Math.sin(t * 16 + ph), armLX: 0.55, armRX: 0.55, headX: 0.3 }, clamp01((t - stop - 0.25) / 0.2));
    out.push({ id, look, pose, p: [x, 0, z], yaw: PI });
  }
  // The gate guard: sitting on a stool with his chai, sipping on the beat; turns far too late (20.3 "?").
  const turn = sp(t, b(20, 3), WOBBLE);
  const sip = Math.max(0, Math.sin(((t - b(20)) / (BEAT * 2)) * PI * 2));
  out.push({
    id: "guard", look: CAST.guard, chai: true, p: [GUARD_SEAT[0], 0, GUARD_SEAT[2]], yaw: PI + 0.55 - 1.05 * turn,
    pose: { ...sitPose(1), armRX: 1.55 + 0.75 * sip * (1 - turn) + 0.2 * turn, armRZ: -0.28, armLX: 0.6, headX: -0.18 * sip * (1 - turn) - 0.1 * turn, headY: 0.45 * turn },
  });
  return out;
}

export const headTop = (a: Actor): V3 => [a.p[0], a.p[1] + (a.pose.hipY + 1.06) * (a.squash ?? 1), a.p[2]];

// ------------------------------------------------------------------ cameras
export function escapeCam(t: number): Cam {
  if (t < b(20, 2)) {
    // S6: low on the road, looking back at the gate; they burst out at us. Whip in from the push.
    const u = (t - b(20)) / (b(20, 2) - b(20));
    const w = 1 - outExpo(clamp01((t - b(20)) / 0.16));
    return { pos: [0.9 + 0.3 * u, 0.7, 12.9 - 0.9 * u], look: [0.6 - 3 * w, 1.5 + 2 * w, 2.4], fov: 40 + 12 * w, roll: -0.03 };
  }
  // S7: the celebration on the road, guard in the foreground, the gate and the staff behind.
  const u = smooth((t - b(20, 2)) / (b(22, 3.5) - b(20, 2)));
  const w = 1 - outExpo(clamp01((t - b(20, 2)) / 0.16));
  let pos: V3 = lerp3([5.6, 1.25, 10.6], [5.0, 1.5, 9.9], u);
  let look: V3 = [0.2 - 2 * w, 1.85, 4.0];
  let fov = 44;
  // Whip-tilt up into the sky on 21.3.25 (the logo's sky).
  const up = clamp01((t - b(22, 3.2)) / (b(22, 3.5) - b(22, 3.2)));
  if (up > 0) {
    const e = up * up * up;
    look = [look[0], look[1] + 28 * e, look[2] + 6 * e];
    pos = [pos[0], pos[1] + 2 * e, pos[2]];
    fov = 44 + 16 * e;
  }
  return { pos, look, fov, roll: 0.02 };
}

// ------------------------------------------------------------------ the set
function extras(): Box[] {
  const L: Box[] = [];
  // Blue plastic stool for the guard.
  L.push({ c: [GUARD_SEAT[0], 0.21, GUARD_SEAT[2] + 0.15], s: [0.46, 0.06, 0.46], col: "#3f7fd9" });
  for (const dx of [-0.19, 0.19]) for (const dz of [-0.19, 0.19]) L.push({ c: [GUARD_SEAT[0] + dx, 0.1, GUARD_SEAT[2] + 0.15 + dz], s: [0.06, 0.2, 0.06], col: "#2f5fb0" });
  // A kettle on a little crate beside him.
  L.push({ c: [GUARD_SEAT[0] + 0.7, 0.2, GUARD_SEAT[2]], s: [0.4, 0.4, 0.4], col: "#b0703e" });
  L.push({ c: [GUARD_SEAT[0] + 0.7, 0.5, GUARD_SEAT[2]], s: [0.18, 0.2, 0.18], col: "#9aa3ad" });
  L.push({ c: [GUARD_SEAT[0] + 0.7, 0.62, GUARD_SEAT[2]], s: [0.08, 0.04, 0.08], col: "#4a4f5a" });
  return L;
}

const EscapeSet: React.FC = () => {
  const out = useMemo(() => campus(), []);
  const ex = useMemo(() => extras(), []);
  return (
    <>
      <Voxels boxes={out} />
      <Voxels boxes={ex} />
      <Label text="ROYAL ACADEMY OF UNNECESSARY SCIENCES" p={[0, 3.35, 2.51]} w={5.4} h={0.6} yaw={0} color="#ffd24a" px={60} />
      <Label text="CHAI  ·  SUTTA  ·  MAGGI" p={[-7, 1.6, 11.25]} w={2.5} h={0.46} yaw={PI} color="#ffffff" px={70} />
    </>
  );
};

export const EscapeWorld: React.FC<{ t: number; blur?: number }> = ({ t, blur = 0 }) => {
  const cam = escapeCam(t);
  const cast = escapeActors(t);
  return (
    <Stage3D cam={cam} bg="#8dd0ef" fog={[24, 70]} shadowTarget={[0.5, 0, 5]} shadowSize={14} blur={blur}>
      <EscapeSet />
      {cast.map((a) => (
        <Character key={a.id} look={a.look} pose={a.pose} p={a.p} yaw={a.yaw} pitch={a.pitch ?? 0} squash={a.squash ?? 1} extra={a.chai ? { armR: CHAI_GLASS } : undefined} />
      ))}
      <Confetti t={t} at={b(20, 2)} origin={[0, 1.8, 7.2]} n={90} power={1.1} />
      <Confetti t={t} at={b(20, 2.5)} origin={[-1.5, 1.2, 6.0]} n={40} power={0.8} seed={31} />
      <Dust t={t} at={b(20, 3)} p={[-0.4, 0, 2.0]} n={8} spread={1.1} seed={5} />
      <Dust t={t} at={b(20, 3) + 0.16} p={[1.3, 0, 1.7]} n={6} spread={0.9} seed={8} />
    </Stage3D>
  );
};

// ------------------------------------------------------------------ bar 20 overlay
export const EscapeOverlay: React.FC<{ t: number }> = ({ t }) => {
  if (t >= b(21, 0.2)) return null;
  const cam = escapeCam(t);
  const guard = escapeActors(t).find((a) => a.id === "guard")!;
  const g = toScreen(cam, headTop(guard));
  return (
    <>
      {t >= b(20, 2) ? <Alert t={t} at={b(20, 3)} x={g.x} y={g.y - 8} kind="?" size={170} /> : null}
      <Banner t={t} at={b(20, 2)} out={b(21) - 0.1} color={C.escape} text="YOU ESCAPED THE UNIVERSITY!   3:42" sub="The chai outside the gate tastes like freedom." top={60} size={96} />
      <Flash t={t} at={b(20, 2)} color="#ffffff" dur={0.16} peak={0.4} />
    </>
  );
};

// ------------------------------------------------------------------ bar 21: FINAL BELL!
const ROWS: [string, number, string][] = [
  ["YOU", 1250, "ESCAPED in 3:42"],
  ["PRIYA", 1120, "ESCAPED in 3:43"],
  ["ARJUN", 980, "ESCAPED in 3:44"],
  ["MEERA", 910, "ESCAPED in 3:45"],
];
// director.gd awards: title, name, line.
const AWARDS: [string, string, string][] = [
  ["BIGGEST SNITCH", "Arjun", "blamed a friend 4 time(s)"],
  ["SMOOTH TALKER", "You", "talked their way out 3 time(s)"],
  ["MOST BETRAYED", "Meera", "blamed by friends 4 time(s)"],
];
// profile.gd RANKS [level, title] with their name-tag colours.
const RANKS: [number, string, string, string][] = [
  [1, "Fresher", "#ffffff", "#000000"],
  [3, "Backbencher", "#9fd8ff", "#1a3a5a"],
  [6, "Proxy King", "#7fe0a0", "#1a4a2a"],
  [10, "Canteen Legend", "#d6a8ff", "#3a1a5a"],
  [15, "Bunk Master", "#ffd24a", "#5a3a00"],
];
// Rank slot in the card: Fresher shows with the strip, then one flip per 16th up to Bunk Master on 22.1.
const RANK_AT = [b(21, 3.75), b(22, 0.25), b(22, 0.5), b(22, 0.75), b(22, 1)];
const CARD_OUT = b(22, 1.75);
/** NEW RANK: BUNK MASTER takes the screen. */
export const RANK_TOP = b(22, 2);

export const FinalBell: React.FC<{ t: number }> = ({ t }) => {
  if (t < b(21) - 0.05 || t >= b(22, 3.6)) return null;
  const T = b(21);
  const s = step(t - T, { stiffness: 520, damping: 21 });
  const ring = t > T ? Math.sin((t - T) * 38) * 5 * Math.exp(-(t - T) * 5) : 0;
  const leave = inCubic(clamp01((t - b(22, 3.25)) / (b(22, 3.5) - b(22, 3.25))));
  const drop = inCubic(clamp01((t - CARD_OUT) / (RANK_TOP - CARD_OUT)));
  const ri = RANK_AT.filter((a) => t >= a).length - 1;
  const rank = RANKS[Math.max(0, ri)];
  const xp = outCubic(clamp01((t - b(22)) / (b(22, 1) - b(22))));
  const top = t >= RANK_TOP;
  const flip = ri >= 0 ? sp(t, RANK_AT[ri], { stiffness: 900, damping: 24 }) : 0;
  return (
    <>
      <div style={{ position: "absolute", inset: 0, background: "rgba(20,20,36,0.38)", opacity: clamp01((t - T + 0.05) / 0.08) * (1 - leave) }} />
      <div style={{ position: "absolute", left: "50%", top: 64, width: 1480, translate: `-50% ${(1 - s) * 900 + drop * 1100}px`, rotate: `${(1 - Math.min(1, s)) * -5}deg`, transformOrigin: "50% 0%" }}>
        <div style={{ background: "rgba(20,20,36,0.94)", borderRadius: 44, padding: "30px 64px 38px", boxShadow: "0 22px 0 rgba(0,0,0,.25)" }}>
          <div style={{ display: "flex", justifyContent: "center", rotate: `${ring}deg` }}><InkText text="FINAL BELL!" size={128} stroke={0.06} shadow={0.07} /></div>
          {ROWS.map(([n, pts, note], i) => {
            const at = T + BEAT * (0.25 + i * 0.5); // 8ths: 21.0.25 .. 21.1.75
            const rs = sp(t, at, SNAP);
            const count = Math.round(pts * outCubic(clamp01((t - at) / 0.45)));
            return (
              <div key={n} style={{ ...font(i === 0 ? 52 : 44, i === 0 ? C.gold : C.white), marginTop: i === 0 ? 14 : 8, display: "flex", justifyContent: "center", gap: 22, opacity: clamp01(rs * 2), translate: `${(1 - rs) * 160}px 0`, whiteSpace: "nowrap" }}>
                <span style={{ width: 70 }}>{i + 1}.</span>
                <span style={{ width: 230 }}>{n}</span>
                <span style={{ width: 300 }}>{count.toLocaleString("en-US")} pts</span>
                <span style={{ width: 360, opacity: 0.8 }}>({note})</span>
              </div>
            );
          })}
          <div style={{ ...font(46, C.good), ...outline(3), marginTop: 16, textAlign: "center", opacity: clamp01(sp(t, b(21, 2), SNAP) * 2), scale: `${Math.max(0, sp(t, b(21, 2), WOBBLE))}`, whiteSpace: "nowrap" }}>
            THE WHOLE CLASS ESCAPED!  +50% for everyone
          </div>
          <div style={{ display: "flex", gap: 22, marginTop: 20 }}>
            {AWARDS.map(([title, who, line], i) => {
              const as = sp(t, b(21, 2.5 + i * 0.5), WOBBLE);
              return (
                <div key={title} style={{ flex: "1 1 0", minWidth: 0, background: "rgba(255,255,255,.08)", borderRadius: 22, padding: "16px 22px", scale: `${Math.max(0, as)}`, opacity: clamp01(as * 3) }}>
                  <div style={font(34, "#ffb37a")}>{title}</div>
                  <div style={{ ...font(46, "#ffd24a"), marginTop: 4 }}>{who}</div>
                  <div style={{ ...font(30, "rgba(255,255,255,.75)"), marginTop: 4 }}>{line}</div>
                </div>
              );
            })}
          </div>
          {/* YOUR PROGRESS: level, rank title (name-tag colours), XP bar */}
          <div style={{ marginTop: 22, display: "flex", alignItems: "center", gap: 28, opacity: clamp01((t - b(21, 3.75)) / 0.08) }}>
            <div style={{ ...font(46, "#9fd8ff"), whiteSpace: "nowrap", width: 230 }}>Level {rank[0]}</div>
            <div style={{ flex: 1 }}>
              <div style={{ height: 26, background: "rgba(255,255,255,.12)", borderRadius: 6, overflow: "hidden" }}>
                <div style={{ width: `${xp * 100}%`, height: "100%", background: C.good }} />
              </div>
            </div>
            <div style={{ ...font(46, C.good), whiteSpace: "nowrap", width: 200, textAlign: "right" }}>+{Math.round(xp * 450)} XP</div>
          </div>
          <div style={{ height: 96, marginTop: 10, display: "flex", justifyContent: "center", alignItems: "center" }}>
            {ri >= 0 && !top ? (
              <div style={{ ...font(88, rank[2]), ...outline(7, rank[3]), scale: `${lerp(1.5, 1, flip)} ${lerp(0.4, 1, flip)}`, opacity: clamp01(flip * 3), whiteSpace: "nowrap" }}>{rank[1].toUpperCase()}</div>
            ) : null}
          </div>
        </div>
      </div>
      {top ? <RankUp t={t} leave={leave} /> : null}
      <Flash t={t} at={T} color="#ffffff" dur={0.14} peak={0.35} />
    </>
  );
};

/** 21.2.5: NEW RANK: BUNK MASTER on a purple field with gold rays; whips up into the sky on 21.3.25. */
const RankUp: React.FC<{ t: number; leave: number }> = ({ t, leave }) => {
  const d = t - RANK_TOP;
  const iris = outCubic(clamp01(d / 0.13));
  const title = slam(t, RANK_TOP + 0.03, 2.6, 0.26);
  const head = sp(t, RANK_TOP, SNAP);
  const sticker = sp(t, RANK_TOP + 0.12, WOBBLE);
  const [sx, sy] = squashAt(t, RANK_TOP + 0.1);
  const y = -leave * 1250;
  return (
    <div style={{ position: "absolute", inset: 0, translate: `0 ${y}px` }}>
      <svg width={1920} height={1080} style={{ position: "absolute", inset: 0, overflow: "visible" }}>
        <circle cx={960} cy={880} r={2300 * iris} fill="#b07cff" />
        <rect x={0} y={1080} width={1920} height={1400} fill="#b07cff" />
        <g transform={`translate(960 560) rotate(${d * 50})`} opacity={iris}>
          {Array.from({ length: 18 }, (_, i) => {
            const a0 = (i / 18) * PI * 2, a1 = a0 + PI / 18;
            return <polygon key={i} points={`0,0 ${Math.cos(a0) * 1700},${Math.sin(a0) * 1700} ${Math.cos(a1) * 1700},${Math.sin(a1) * 1700}`} fill="#9a62d6" />;
          })}
        </g>
      </svg>
      <Burst t={t} at={RANK_TOP + 0.05} x={960} y={600} colors={["#ffd24a", "#ffffff", "#ff9a3c", "#7fe0a0"]} n={22} seed={17} power={1500} size={24} />
      <div style={{ position: "absolute", left: 0, right: 0, top: 290, display: "grid", justifyItems: "center" }}>
        <div style={{ scale: `${Math.max(0, head)}`, opacity: clamp01(head * 3) }}><InkText text="NEW RANK:" size={84} color="#ffffff" stroke={0.09} shadow={0.08} /></div>
        <div style={{ marginTop: -6, scale: `${title * sx} ${title * sy}`, opacity: t >= RANK_TOP + 0.03 ? 1 : 0 }}><InkText text="BUNK MASTER" size={250} color="#ffd24a" ink="#5a3a00" stroke={0.085} shadow={0.09} spacing={4} /></div>
      </div>
      <div style={{ position: "absolute", left: 1330, top: 225, rotate: `${10 + (1 - Math.min(1, sticker)) * 40}deg`, scale: `${Math.max(0, sticker)}` }}>
        <div style={{ ...font(60, C.ink), background: "#ffd24a", borderRadius: 18, padding: "12px 24px 8px", boxShadow: "0 10px 0 #5a3a00", whiteSpace: "nowrap" }}>LEVEL UP!  Level 15</div>
      </div>
      <Flash t={t} at={RANK_TOP} color="#fff4c0" dur={0.14} peak={0.55} />
    </div>
  );
};
const slam = (t: number, at: number, from: number, len: number) => (t < at ? 0 : 1 + (from - 1) * (1 - backOut(clamp01((t - at) / len), 2.2)));
const backOut = (u: number, s: number) => {
  const x = u - 1;
  return x * x * ((s + 1) * x + s) + 1;
};
const squashAt = (t: number, at: number): [number, number] => {
  const d = t - at;
  if (d < 0) return [1, 1];
  const w = 0.22 * Math.exp(-d * 9) * Math.cos(d * 30);
  return [1 + w, 1 - w];
};

export const ESCAPE_HITS: [number, number][] = [[b(20), 0.5], [b(20, 2), 0.7], [b(20, 3), 0.35], [b(21), 0.6], [b(22), 0.25], [b(22, 1), 0.4], [RANK_TOP, 0.8], [b(22, 3.25), 0.3]];
export const escapeShake = (t: number) => shake(t, ESCAPE_HITS);
void HIP_HEIGHT; void rnd;
