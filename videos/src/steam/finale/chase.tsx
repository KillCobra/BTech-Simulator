// Bars 18-19 (DROP 2): the chase across campus to the main gate, cut on beats.
// One continuous choreography (a path along the compound wall that turns into the gate) filmed by five cameras:
// S1 low tracking (18.0), S2 head-on (18.2), S3 the bench vault with a speed ramp to the 19.0 apex,
// S4 the staff pile-up at the bench (19.1), S5 the crane to the gate (19.2), whip into bar 20.
import React, { useMemo } from "react";
import { Alert, font, outline } from "../../launch/ui";
import { C } from "../../launch/tokens";
import { bench, tree } from "../../launch/sets";
import { campus } from "./sets";
import { Character, G, Voxels } from "../../launch/three";
import { CAST, HIP_HEIGHT, mixPose, P, walkPose, type Box, type Look, type Pose, type V3 } from "../../launch/voxel";
import type { Cam } from "../../launch/camera3d";
import { step } from "../../kit/spring";
import { b, BEAT } from "../cues";
import { Stage3D, toScreen } from "../Stage3D";
import { clamp01, Dust, InkText, Flash, inCubic, Label, lerp, lerp3, outCubic, outExpo, PI, shake, smooth, SpeedLines, warp, ZoomLines } from "./kit";

// ------------------------------------------------------------------ the clock and the path
const T0 = b(18);
/** Chase clock: real time with a speed ramp (down to 18%) around the vault apex on 19.0. */
export const tau = (t: number) => warp(t, T0, b(19), 0.82, 0.17);
const SPEED = 7.4;
const X0 = 29, ZA = -2.0, XT = 4, R = 3.5;
const LA = X0 - XT, LR = (R * PI) / 2;
const CX = XT, CZ = ZA + R;

function path(s: number) {
  if (s < LA) return { x: X0 - s, z: ZA, hx: -1, hz: 0 };
  if (s < LA + LR) {
    const th = -PI / 2 - (s - LA) / R;
    return { x: CX + R * Math.cos(th), z: CZ + R * Math.sin(th), hx: Math.sin(th), hz: -Math.cos(th) };
  }
  return { x: CX - R, z: CZ + (s - LA - LR), hx: 0, hz: 1 };
}
const yawOf = (hx: number, hz: number) => Math.atan2(-hx, -hz);
const lead = (t: number) => path(SPEED * tau(t));

/** The bench the gang vaults: where the hero is at the 19.0 apex. */
export const BENCH_X = X0 - SPEED * tau(b(19));
const VH = 1.15; // half the vault's run-up length

type Runner = { id: string; look: Look; lag: number; n: number; ph: number; staff?: boolean; trip?: boolean };
const GUARD2: Look = { ...CAST.guard, skin: "#e0ac7e" };
const RUNNERS: Runner[] = [
  { id: "hero", look: CAST.hero, lag: 0, n: -0.2, ph: 0 },
  { id: "friendA", look: CAST.friendA, lag: 0.95, n: 0.8, ph: 1.1 },
  { id: "friendB", look: CAST.friendB, lag: 1.7, n: -0.95, ph: 2.2 },
  { id: "friendC", look: CAST.friendC, lag: 2.4, n: 0.3, ph: 0.6 },
  { id: "guard2", look: GUARD2, lag: 4.5, n: -0.35, ph: 0.3, staff: true },
  { id: "proctor", look: CAST.proctor, lag: 5.3, n: 0.75, ph: 1.7, staff: true },
  { id: "teacher", look: CAST.teacher, lag: 6.0, n: -0.55, ph: 2.9, staff: true, trip: true },
];

const VAULT: Pose = { hipY: HIP_HEIGHT, legL: 1.55, legR: 1.25, torsoX: -0.4, armLX: 1.1, armRX: 2.9, armLZ: -0.35, armRZ: 0.35, headX: 0.3, headY: 0 };
const STAFF_VAULT: Pose = { hipY: HIP_HEIGHT, legL: 1.5, legR: -0.6, torsoX: -0.3, armLX: 2.2, armRX: 2.4, armLZ: -0.6, armRZ: 0.6, headX: 0.2, headY: 0 };

export type Actor = { id: string; look: Look; pose: Pose; p: V3; yaw: number; pitch?: number; roll?: number; squash?: number; staff?: boolean };

export function chaseActors(t: number): Actor[] {
  const T = tau(t);
  return RUNNERS.map((r) => {
    const s = SPEED * T - r.lag;
    const q = path(s);
    const x = q.x + q.hz * r.n, z = q.z - q.hx * r.n;
    const yaw = yawOf(q.hx, q.hz);
    const ph = T * 15.5 + r.ph;
    const run = walkPose(ph, 1, 0, true);
    let pose: Pose = { ...run, armLX: run.armLX * 1.7, armRX: run.armRX * 1.7, torsoX: -0.22 };
    let y = 0, pitch = 0, roll = 0, squash = 1;
    // Vault the bench (the straight part only).
    const u = s < LA ? (BENCH_X + VH - x) / (2 * VH) : -1;
    if (u > 0 && u < 1 && !r.trip) {
      const v = Math.sin(PI * u);
      y = 0.62 * Math.pow(v, 0.8);
      pose = mixPose(pose, r.staff ? STAFF_VAULT : r.id === "hero" ? VAULT : { ...VAULT, armRX: 1.3, legR: 1.5 }, Math.min(1, v * 1.6));
      roll = (r.id === "hero" ? 0.22 : 0.12) * Math.sin(PI * u) * (r.n > 0 ? 1 : -1);
    } else if (u >= 1 && u < 1.25 && !r.trip) {
      squash = 1 - 0.22 * Math.sin(((u - 1) / 0.25) * PI);
    }
    // The teacher catches his foot on the bench and faceplants.
    if (r.trip) {
      const tripX = BENCH_X + 0.85;
      const tt = (X0 - tripX + r.lag) / SPEED; // chase clock when he reaches it
      const d = T - tt;
      if (d > 0) {
        const slide = (SPEED * (1 - Math.exp(-d * 2.6))) / 2.6;
        const fall = outCubic(d / 0.3);
        const bounce = d > 0.3 ? 0.18 * Math.exp(-(d - 0.3) * 7) * Math.abs(Math.sin((d - 0.3) * 18)) : 0;
        return {
          id: r.id, look: r.look, staff: true, yaw,
          p: [tripX - slide, 0.55 * Math.sin(Math.min(1, d / 0.34) * PI) + bounce, z],
          pitch: -1.45 * fall,
          pose: { ...pose, legL: 0.3 + 0.5 * Math.sin(d * 30) * Math.exp(-d * 3), legR: -0.4 - 0.5 * Math.sin(d * 30) * Math.exp(-d * 3), armLX: 2.9 * fall, armRX: 2.7 * fall, armLZ: -0.5, armRZ: 0.5, headX: -0.6 * fall },
        };
      }
    }
    return { id: r.id, look: r.look, pose, p: [x, y, z], yaw, pitch, roll, squash, staff: r.staff };
  });
}
/** Students on the lawn by the wall: they jump back and watch the gang go by. */
const BYSTANDERS: [string, Look, number, number, number][] = [
  ["npc1", CAST.npc1, 25.5, 0.2, 0.0],
  ["npc3", CAST.npc3, 21.0, 0.5, 0.4],
  ["npc2", CAST.npc2, 12.6, 0.1, 0.2],
  ["npc4", CAST.npc4, 10.9, 0.55, 0.7],
];
export function bystanders(t: number): Actor[] {
  const T = tau(t);
  const hx = X0 - SPEED * T;
  return BYSTANDERS.map(([id, look, x, z, ph]) => {
    const passT = (X0 - x + 1.5) / SPEED; // chase clock when the gang reaches them
    const d = T - passT;
    const startle = d > 0 ? Math.exp(-d * 5) * Math.sin(Math.min(PI, d * 9)) : 0;
    const watch = Math.atan2(hx - x, -(-2 - z)) * 0.8;
    const cheer = d > 0.15 ? Math.min(1, (d - 0.15) * 4) : 0;
    const k = Math.sin(t * 14 + ph * 6);
    return {
      id, look, yaw: 0, p: [x, 0.35 * startle, z],
      pose: { ...REST_POSE, headY: Math.max(-1.2, Math.min(1.2, watch)), armLX: 2.6 * cheer + 0.2 * k * cheer, armRX: 2.6 * cheer - 0.2 * k * cheer, armLZ: -0.4 * cheer - 0.06, armRZ: 0.4 * cheer + 0.06, legL: 0.3 * startle, legR: -0.2 * startle, torsoX: 0.2 * startle },
    };
  });
}
const REST_POSE: Pose = { hipY: HIP_HEIGHT, legL: 0, legR: 0, torsoX: 0, armLX: 0, armRX: 0, armLZ: -0.06, armRZ: 0.06, headX: 0, headY: 0 };

/** Chase-clock time the teacher hits the ground (for sound and dust). */
export const TRIP_T = (() => {
  const tripX = BENCH_X + 0.85;
  const tt = (X0 - tripX + 6.0) / SPEED;
  // invert tau numerically (monotonic)
  let lo = T0, hi = b(21);
  for (let i = 0; i < 40; i++) {
    const m = (lo + hi) / 2;
    if (tau(m) < tt) lo = m;
    else hi = m;
  }
  return lo;
})();

export const headTop = (a: Actor): V3 => [a.p[0], a.p[1] + (a.pose.hipY + 1.06) * (a.squash ?? 1), a.p[2]];

// ------------------------------------------------------------------ cameras
export const SHOTS = { s1: b(18), s2: b(18, 2), s3: b(18, 3), s4: b(19, 1), s5: b(19, 2), end: b(20) };

/** Whip: a fast settle from an offset at a cut (the 240 fps render smears it). */
const whip = (t: number, at: number, len = 0.16) => 1 - outExpo(clamp01((t - at) / len));

export function chaseCam(t: number): Cam {
  const L = lead(t);
  if (t < SHOTS.s2) {
    // S1: low tracking, knee height, the brick wall behind; gang to the right, staff chasing on the left.
    const u = (t - SHOTS.s1) / (SHOTS.s2 - SHOTS.s1);
    return { pos: [L.x + 2.9 - u * 0.6, 0.38, -8.6 + u * 0.9], look: [L.x + 2.5, 1.62, -2], fov: 46, roll: 0.035 };
  }
  if (t < SHOTS.s3) {
    // S2: head-on, wide lens, running backwards in front of them; whip in from the right.
    const u = t - SHOTS.s2;
    const w = whip(t, SHOTS.s2);
    return { pos: [L.x - 3.0 + u * 0.5, 1.05, -2.3], look: [L.x + 3, 1.15, -2.1 + 7 * w], fov: 66, roll: -0.07 - 0.25 * w };
  }
  if (t < SHOTS.s4) {
    // S3: side-on at the bench; slow push, a punch-in on the apex.
    const u = (t - SHOTS.s3) / (SHOTS.s4 - SHOTS.s3);
    const w = whip(t, SHOTS.s3);
    const follow = Math.max(-2.2, Math.min(2.6, L.x - BENCH_X));
    const punch = Math.exp(-Math.pow((t - b(19)) / 0.22, 2));
    return { pos: [BENCH_X + 0.3 + follow * 0.35, 0.95 + 0.3 * u, -7.6 + u * 1.2], look: [BENCH_X + follow * 0.55 + 5 * w, 1.62, -2.1], fov: 40 - 7 * punch, roll: 0.03 };
  }
  if (t < SHOTS.s5) {
    // S4: behind the bench, low, the staff charge at us and pile up.
    const u = (t - SHOTS.s4) / (SHOTS.s5 - SHOTS.s4);
    const w = whip(t, SHOTS.s4);
    return { pos: [BENCH_X - 4.4 - u * 0.5, 0.55, -5.2], look: [BENCH_X + 1.6, 1.3 + 3 * w, -1.9], fov: 46, roll: 0.06 - 0.3 * w };
  }
  // S5: crane from high behind the gang down to the gate; last half beat, a push through the gate.
  const u = smooth((t - SHOTS.s5) / (b(19, 3.4) - SHOTS.s5));
  const w = whip(t, SHOTS.s5, 0.2);
  const start: V3 = [18.5, 8.2, -11.5], mid: V3 = [7.5, 3.0, -8.0];
  let pos = lerp3(start, mid, u);
  let look = lerp3([7, 0.5, -1.2], [1.2, 1.3, 2.4], u);
  let fov = 50;
  const push = clamp01((t - b(19, 3.4)) / (b(20) - b(19, 3.4)));
  if (push > 0) {
    const e = push * push * push;
    pos = lerp3(pos, [0.8, 1.7, 1.2], e);
    look = lerp3(look, [0.6, 1.6, 6], e);
    fov = 50 + 30 * e;
  }
  return { pos, look: [look[0], look[1] + 4 * w, look[2]], fov, roll: -0.04 };
}

// ------------------------------------------------------------------ the set
function extension(): Box[] {
  // outside() ends at x = 30: more lawn and wall for the start of the run.
  const L: Box[] = [];
  const b_ = (c: V3, s: V3, col: string) => L.push({ c, s, col });
  for (let x = 30; x < 50; x += 2)
    for (let z = -24; z < 4; z += 2) b_([x + 1, -0.1, z + 1], [2, 0.2, 2], ((x + z) / 2) & 1 ? P.GRASS : P.GRASS_DARK);
  b_([40, 1.1, 2.4], [20, 2.2, 0.4], P.BRICK);
  b_([40, 2.26, 2.4], [20.05, 0.12, 0.5], P.BRICK_CAP);
  for (let x = 31; x < 50; x += 2.5) b_([x, 1.1, 2.4], [0.5, 2.4, 0.55], "#aa553e");
  for (let i = 0; i < 4; i++) b_([32 + i * 4.6, 0.35, 1.4], [1.1, 0.7, 0.9], P.LEAVES[i % 4]);
  tree(L, 38, -9, 21);
  tree(L, 24, -11, 22);
  tree(L, 45, -6, 23);
  // Benches across the gang's path (the vault), and a lamp post or two for parallax.
  for (const z of [-2.95, -1.05]) {
    const bl: Box[] = [];
    bench(bl, 0, 0);
    for (const bx of bl) L.push({ c: [BENCH_X - bx.c[2], bx.c[1], z + bx.c[0]], s: [bx.s[2], bx.s[1], bx.s[0]], col: bx.col });
  }
  for (const x of [22, 11, 33]) {
    b_([x, 1.6, -0.2], [0.14, 3.2, 0.14], "#4a4f5a");
    b_([x, 3.25, -0.2], [0.5, 0.14, 0.3], "#4a4f5a");
    b_([x, 3.15, -0.2], [0.34, 0.08, 0.2], "#fff4c0");
  }
  return L;
}

const ChaseSet: React.FC = () => {
  const out = useMemo(() => campus(), []);
  const ext = useMemo(() => extension(), []);
  return (
    <>
      <Voxels boxes={out} />
      <Voxels boxes={ext} />
      <Label text="ROYAL ACADEMY OF UNNECESSARY SCIENCES" p={[0, 3.35, 2.29]} w={5.4} h={0.6} yaw={PI} color="#ffd24a" px={60} />
      <Label text="CHAI  ·  SUTTA  ·  MAGGI" p={[-7, 1.6, 11.25]} w={2.5} h={0.46} yaw={PI} color="#ffffff" px={70} />
    </>
  );
};

export const ChaseWorld: React.FC<{ t: number }> = ({ t }) => {
  const cam = chaseCam(t);
  const cast = [...chaseActors(t), ...bystanders(t)];
  const hero = cast[0];
  // Impact frame on the downbeat: two frames of inverted ink.
  const impact = t >= b(18) && t < b(18) + 0.04;
  const cuts = [SHOTS.s2, SHOTS.s3, SHOTS.s4, SHOTS.s5, b(19, 3.7)];
  let blur = 0;
  for (const c of cuts) blur += 7 * Math.exp(-Math.abs(t - c) / 0.035);
  blur += 9 * clamp01((t - b(19, 3.6)) / (b(20) - b(19, 3.6))) ** 2;
  return (
    <div style={{ position: "absolute", inset: 0, filter: impact ? "invert(1) grayscale(1) contrast(4)" : undefined }}>
      <Stage3D cam={cam} bg="#8dd0ef" fog={[26, 75]} shadowTarget={[hero.p[0], 0, -1]} shadowSize={16} blur={blur}>
        <ChaseSet />
        {cast.map((a) => (
          <Character key={a.id} look={a.look} pose={a.pose} p={a.p} yaw={a.yaw} roll={a.roll ?? 0} pitch={a.pitch ?? 0} squash={a.squash ?? 1} />
        ))}
        <Dust t={t} at={TRIP_T + 0.12} p={[BENCH_X - 1.6, 0, -2.6]} n={10} spread={1.4} seed={3} />
        <Dust t={t} at={b(19) + 0.28} p={[BENCH_X - 1.3, 0, -2.2]} n={6} spread={0.8} seed={9} />
      </Stage3D>
    </div>
  );
};

// ------------------------------------------------------------------ 2D layer
export const ChaseOverlay: React.FC<{ t: number }> = ({ t }) => {
  const cam = chaseCam(t);
  const cast = chaseActors(t);
  const inShot = (a: number, z: number) => t >= a && t < z;
  // Title: slams on 18.0, holds a bar... then shrinks to the objective card at the top.
  const slamS = step(t - b(18), { stiffness: 720, damping: 24 });
  const shrink = step(t - b(18, 2), { stiffness: 520, damping: 26 });
  const bigScale = lerp(3.2, 1, slamS);
  const scale = lerp(bigScale, 0.5, shrink);
  const top = lerp(46, 34, shrink);
  const sq = t > b(18) ? 0.2 * Math.exp(-(t - b(18) - 0.06) * 9) * Math.cos((t - b(18) - 0.06) * 30) : 0;
  const leave = clamp01((t - b(19, 3.5)) / (BEAT * 0.5));
  // The objective card kicks on every beat once it has shrunk (the HUD keeps time with the drop).
  let kick = 0;
  for (let k = 3; k < 8; k++) {
    const at = b(18, k);
    if (t >= at) kick = 0.07 * Math.exp(-(t - at) / 0.07);
  }
  const alerts = (at: number, ids: string[]) =>
    cast.filter((a) => ids.includes(a.id)).map((a, i) => {
      const s = toScreen(cam, headTop(a));
      if (s.behind || s.x < -100 || s.x > 2020) return null;
      return <Alert key={a.id} t={t} at={at + i * BEAT * 0.25} x={s.x} y={Math.max(s.y - 6, 300)} kind="!" size={a.id === "guard2" ? 160 : 130} />;
    });
  return (
    <>
      <SpeedLines t={t} t0={b(18)} dir={1} o={inShot(SHOTS.s1, SHOTS.s2) ? 0.85 : inShot(SHOTS.s3, SHOTS.s4) ? 0.35 + 0.4 * clamp01(Math.abs(t - b(19)) / 0.3) : 0} seed={4} />
      <ZoomLines t={t} x={960} y={560} o={inShot(SHOTS.s2, SHOTS.s3) ? 0.8 : inShot(SHOTS.s4, SHOTS.s5) ? 0.6 : 0} />
      {inShot(SHOTS.s1, SHOTS.s2) ? alerts(b(18, 1), ["guard2", "proctor", "teacher"]) : null}
      {inShot(SHOTS.s4, SHOTS.s5) ? alerts(SHOTS.s4, ["guard2", "proctor"]) : null}
      {/* ESCAPE THE UNIVERSITY! (the goal line, grand_campus.gd) */}
      <div style={{ position: "absolute", left: "50%", top, translate: `-50% ${-leave * 200}px`, scale: `${scale * (1 + sq + kick * shrink)} ${scale * (1 - sq + kick * shrink)}`, transformOrigin: "50% 0%", opacity: t < b(18) ? 0 : 1 - leave }}>
        <div style={{ position: "absolute", inset: "-22px -60px", background: C.card, borderRadius: 44, opacity: shrink }} />
        <InkText text="ESCAPE THE UNIVERSITY!" size={180} stroke={0.085} shadow={0.1} spacing={3} style={{ position: "relative" }} />
      </div>
      <Flash t={t} at={b(18) + 0.04} color="#ffffff" dur={0.22} peak={0.75} />
      <Flash t={t} at={b(19)} color="#ffffff" dur={0.12} peak={0.35} />
      <Flash t={t} at={TRIP_T + 0.1} color="#ffffff" dur={0.1} peak={0.25} />
    </>
  );
};

/** Screen-shake hits for bars 18-19. */
export const CHASE_HITS: [number, number][] = [
  [b(18), 1.3], [b(18, 1), 0.35], [b(18, 2), 0.45], [b(18, 3), 0.4], [b(19), 0.7], [b(19, 1), 0.4], [TRIP_T + 0.1, 0.75], [b(19, 2), 0.35], [b(19, 3), 0.3],
];
export const chaseShake = (t: number) => shake(t, CHASE_HITS);
void smooth; void inCubic;
