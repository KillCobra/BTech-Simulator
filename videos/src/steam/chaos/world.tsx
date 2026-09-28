// Chaos act, bars 10-11: three 3D gags in the corridor, cut on beats.
//   A  10.1-10.3  a friend rams a samosa trolley into the proctor (impact 10.2)
//   B  10.3-11.1  a paper ball bonks a teacher on the back of the head (hit 11.0)
//   C  11.1-12.0  "[E] Take the fire extinguisher", smoke floods, fire alarm (11.3)
// Everything is a pure function of t. Cameras and actors are shared with the 2D overlays (pins).
import React, { useMemo } from "react";
import { b, BEAT } from "../cues";
import { toScreen } from "../Stage3D";
import type { Cam } from "../../launch/camera3d";
import { clamp01, easeIn, easeOut, lerp, rand, SNAP, sp, WOBBLE } from "../../launch/juice";
import { corridor, hash, PAPER_BALL, trolley } from "../../launch/sets";
import { Character, G, Voxels } from "../../launch/three";
import { CAST, P, REST, sitPose, walkPose, type Box, type Look, type Pose, type V3 } from "../../launch/voxel";

const PI = Math.PI;

export const SHOT = {
  trolley: [b(10, 1), b(10, 3)],
  paper: [b(10, 3), b(11, 1)],
  spray: [b(11, 1), b(12)],
} as const;
export const HIT = { trolley: b(10, 2), bonk: b(11), grab: b(11, 1.5), spray: b(11, 2), alarm: b(11, 3) };
export type ShotName = keyof typeof SHOT;
export const shotAt = (t: number): ShotName | null =>
  t >= SHOT.trolley[0] && t < SHOT.trolley[1] ? "trolley" : t >= SHOT.paper[0] && t < SHOT.paper[1] ? "paper" : t >= SHOT.spray[0] && t < SHOT.spray[1] ? "spray" : null;

const lerp3 = (a: V3, c: V3, u: number): V3 => [lerp(a[0], c[0], u), lerp(a[1], c[1], u), lerp(a[2], c[2], u)];
const smooth = (u: number) => {
  u = clamp01(u);
  return u * u * (3 - 2 * u);
};

/** Hit-stop: time after an impact runs at 15% for 70 ms, then normal (a few frozen frames of impact). */
const hitstop = (d: number) => (d < 0 ? d : d < 0.07 ? d * 0.15 : 0.0105 + (d - 0.07));

// ------------------------------------------------------------------ props
const EXTINGUISHER: Box[] = [
  { c: [0, 0, 0], s: [0.2, 0.46, 0.2], col: "#e0524f" },
  { c: [0, -0.24, 0], s: [0.21, 0.04, 0.21], col: "#a8322c" },
  { c: [0, 0.02, -0.102], s: [0.13, 0.14, 0.01], col: "#fbf6e8" },
  { c: [0, 0.27, 0], s: [0.1, 0.08, 0.1], col: "#3a3d47" },
  { c: [0.07, 0.32, 0], s: [0.16, 0.04, 0.05], col: "#26262e" },
  { c: [-0.11, 0.12, 0], s: [0.04, 0.3, 0.04], col: "#26262e" },
  { c: [-0.11, 0.3, -0.04], s: [0.05, 0.06, 0.1], col: "#26262e" },
];
const WALL_BRACKET: Box[] = [{ c: [0, 0, 0.12], s: [0.26, 0.5, 0.04], col: "#c9c5bb" }];
// A samosa that reads at a glance: a stepped golden pyramid like the item icon (world.gd colours).
const SAMOSA_V: Box[] = [
  { c: [0, 0.035, 0], s: [0.3, 0.07, 0.26], col: "#e0a050" },
  { c: [0, 0.1, 0], s: [0.22, 0.07, 0.19], col: "#e8ae5c" },
  { c: [0, 0.16, 0], s: [0.14, 0.06, 0.12], col: "#f2c070" },
  { c: [0, 0.21, 0], s: [0.06, 0.05, 0.05], col: "#ffd98a" },
  { c: [0.08, 0.075, -0.1], s: [0.02, 0.02, 0.01], col: "#8a5020" },
  { c: [-0.05, 0.13, -0.08], s: [0.02, 0.02, 0.01], col: "#8a5020" },
];

/** The v2 corridor, closed in for the reverse angles: a window wall at -z, end walls, a ceiling with tube lights. */
function hallShell(): { solid: Box[]; open: Box[] } {
  const solid: Box[] = [], open: Box[] = [];
  const push = (l: Box[], c: V3, s: V3, col: string) => l.push({ c, s, col });
  for (let x = -16; x < 22; x++)
    for (let z = -3; z < 3; z++) if (x < -10 || x >= 16) push(solid, [x + 0.5, -0.05, z + 0.5], [1, 0.1, 1], (x + z) & 1 ? P.FLOOR_A : P.FLOOR_B);
  // Window wall (no shadows, so the sun still reaches the floor).
  push(open, [3, 0.5, -3.1], [38, 1.0, 0.2], P.WALL);
  push(open, [3, 0.5, -2.99], [38, 1.0, 0.02], P.DADO_INSIDE);
  push(open, [3, 3.0, -3.1], [38, 0.8, 0.2], P.WALL);
  for (let x = -15; x < 21; x += 2.6) {
    push(open, [x, 1.8, -3.1], [0.5, 1.6, 0.2], P.WALL);
    push(open, [x + 1.3, 1.8, -3.12], [2.1, 1.6, 0.06], "#bfe8ff");
    push(open, [x + 1.3, 1.8, -3.09], [0.05, 1.6, 0.05], "#3f86a8");
  }
  push(open, [-16.1, 1.7, 0], [0.2, 3.4, 6.4], P.WALL);
  push(open, [22.1, 1.7, 0], [0.2, 3.4, 6.4], P.WALL);
  // More lockers on the far end so the long lens has something behind the teacher.
  for (let i = 0; i < 8; i++) {
    const x = 14.5 + i * 0.78;
    push(solid, [x, 0.95, 2.7], [0.74, 1.9, 0.56], "#5f8fb8");
    push(solid, [x, 1.25, 2.395], [0.14, 0.06, 0.01], P.CLASS[i % 4]);
  }
  return { solid, open };
}

// ------------------------------------------------------------------ cameras
export function camAt(t: number): Cam {
  const s = shotAt(t) ?? (t < SHOT.trolley[0] ? "trolley" : "spray");
  if (s === "trolley") {
    const u = smooth((t - SHOT.trolley[0]) / (HIT.trolley - SHOT.trolley[0]));
    const d = t - HIT.trolley;
    // Push in toward the impact, then a crash zoom (spring) onto the proctor slamming the lockers.
    const k = sp(t, HIT.trolley, { stiffness: 900, damping: 30 });
    const pos = lerp3(lerp3([-0.4, 0.8, -3.9], [0.4, 0.78, -3.5], u), [1.1, 0.95, -3.0], k);
    const look = lerp3(lerp3([-0.4, 0.95, 0.8], [0.6, 1.0, 0.8], u), [1.8, 1.05, 1.3], k);
    const fov = lerp(44, 34, k) - (d > 0 ? 3 * smooth(d / (BEAT * 2)) : 0);
    return { pos, look, fov, roll: -0.05 * k };
  }
  if (s === "paper") {
    // Over the hero's shoulder; the ball leaves on the "and", the lens crash-zooms after it onto the teacher.
    const throwAt = b(10, 3.5);
    const z = easeIn(clamp01((t - throwAt) / (HIT.bonk - throwAt)));
    const kick = sp(t, HIT.bonk, { stiffness: 800, damping: 26 });
    const pos = lerp3([-4.7, 1.95, 1.2], [-4.4, 1.9, 1.25], smooth((t - SHOT.paper[0]) / BEAT));
    const look = lerp3([0.6, 1.2, 0.4], [3.3, 1.72, 2.35], z); // teacher sits left of centre, clear of the score receipt
    const fov = lerp(44, 12.5, z) + 2.2 * (1 - Math.min(1, kick)) * (t > HIT.bonk ? 1 : 0);
    return { pos, look, fov };
  }
  // spray: behind the hero's right shoulder, looking down the corridor at the staff.
  const u = smooth((t - SHOT.spray[0]) / (BEAT * 4));
  const kick = sp(t, HIT.spray, { stiffness: 500, damping: 24 });
  const pos = lerp3([4.3, 1.5, -1.0], [3.6, 1.35, -0.8], u);
  const look = lerp3([-0.2, 1.15, 1.9], [-3.5, 1.05, 0.9], kick);
  return { pos, look, fov: lerp(40, 44, kick) };
}

// ------------------------------------------------------------------ actors
export type Actor = { id: string; look: Look; pose: Pose; p: V3; yaw: number; roll?: number; pitch?: number; squash?: number; hold?: boolean };
export const headTop = (a: Actor): V3 => [a.p[0], a.p[1] + (a.pose.hipY + 0.56 + 0.5) * (a.squash ?? 1), a.p[2]];

const TROLLEY_Z = 0.7;
/** Trolley centre x over time: accelerates in, stops dead on the proctor. */
export function trolleyX(t: number) {
  const u = clamp01((t - SHOT.trolley[0] + 0.12) / (HIT.trolley - SHOT.trolley[0] + 0.12));
  if (t < HIT.trolley) return -4.6 + 5.05 * Math.pow(u, 1.5);
  return 0.45 + 0.18 * (1 - Math.exp(-hitstop(t - HIT.trolley) * 18));
}
const PROC0: V3 = [1.45, 0, TROLLEY_Z];
const SLAM: V3 = [2.55, 0.55, 1.98];
const FLY = 0.24; // seconds (hit-stopped time) from impact to the lockers

export function actors(t: number): Actor[] {
  const s = shotAt(t);
  if (s === "trolley") {
    const tx = trolleyX(t);
    const d = hitstop(t - HIT.trolley);
    const pushPose = walkPose(t * 16, 1, 0, true);
    const pusher: Actor = {
      id: "friendB", look: CAST.friendB, p: [tx - 1.3 + (d > 0 ? -0.1 * Math.exp(-d * 10) : 0), 0, TROLLEY_Z], yaw: -PI / 2,
      pose: d < 0 ? { ...pushPose, torsoX: -0.35, armLX: 1.35, armRX: 1.35, headX: 0.25 }
        : { ...REST, torsoX: -0.1, armLX: lerp(1.35, 2.9, sp(t, HIT.trolley + 0.12, WOBBLE)), armRX: lerp(1.35, 2.9, sp(t, HIT.trolley + 0.18, WOBBLE)), armLZ: -0.3, armRZ: 0.3, headX: -0.2 },
      squash: d > 0 ? 1 - 0.16 * Math.exp(-d * 9) * Math.cos(d * 30) : 1,
    };
    let proc: Actor;
    if (d < 0) {
      // Unaware with a register, then the head snaps round on the "and" (he sees it coming).
      const look = sp(t, b(10, 1.5), SNAP);
      proc = {
        id: "proctor", look: CAST.proctor, p: PROC0, yaw: -0.25, pose: { ...REST, armLX: 1.0, armRX: 0.9, armRZ: -0.25, headX: 0.35 * (1 - look) - 0.1 * look, headY: -1.1 * look },
        squash: 1 + 0.1 * Math.exp(-Math.max(0, t - b(10, 1.5)) * 12) * (t > b(10, 1.5) ? 1 : 0),
      };
    } else if (d < FLY) {
      const u = d / FLY;
      const p = lerp3(PROC0, SLAM, easeOut(u));
      p[1] += 0.7 * Math.sin(u * PI);
      proc = { id: "proctor", look: CAST.proctor, p, yaw: -0.25 - 1.6 * u, roll: 0.9 * u, pose: { ...REST, armLX: 2.8, armRX: 2.6, armLZ: -0.8, armRZ: 0.8, legL: -0.7, legR: 0.6, headX: -0.4 } };
    } else {
      // Pinned to the lockers (squash), then a slow comic slide down to a heap.
      const w = d - FLY;
      const slide = easeIn(clamp01((w - 0.2) / 0.3));
      const p: V3 = [SLAM[0], SLAM[1] * (1 - slide), SLAM[2]];
      const pose = slide < 1 ? { ...REST, armLX: 1.6 - slide * 1.2, armRX: 1.7 - slide * 1.3, armLZ: -1.5 + slide, armRZ: 1.5 - slide, legL: -0.35, legR: 0.3, headX: -0.25 } : { ...sitPose(1), armLX: 0.3, armRX: 0.2, armLZ: -0.5, armRZ: 0.5, headX: 0.5, headY: 0.3 * Math.sin(t * 9) };
      proc = { id: "proctor", look: CAST.proctor, p, yaw: PI + 0.2, roll: 0.28 * (1 - slide), pose, squash: 1 - 0.22 * Math.exp(-w * 10) * Math.cos(w * 34) };
    }
    return [proc, pusher];
  }
  if (s === "paper") {
    const throwAt = b(10, 3.5);
    const wind = sp(t, SHOT.paper[0], { stiffness: 300, damping: 18 });
    const release = sp(t, throwAt, { stiffness: 900, damping: 26 });
    const hero: Actor = {
      id: "hero", look: CAST.hero, p: [-2.3, 0, -0.1], yaw: -PI / 2 - 0.35,
      pose: { ...REST, armRX: lerp(0.2, 3.0, wind) - 2.4 * release, armRZ: 0.1, torsoX: 0.12 * wind - 0.3 * release, headX: 0.05 },
    };
    const hit = HIT.bonk;
    const dh = t - hit;
    const turn = sp(t, hit + BEAT * 0.3, { stiffness: 260, damping: 18 });
    const teacher: Actor = {
      id: "teacher", look: CAST.teacher, p: [3.3, 0, 1.95], yaw: PI - 2.6 * turn,
      pose: { ...REST, armLX: 1.1, armRX: 0.6, headX: dh > 0 ? 0.55 * Math.exp(-dh * 7) * Math.cos(dh * 26) : -0.12 },
      squash: dh > 0 ? 1 - 0.2 * Math.exp(-dh * 8) * Math.cos(dh * 28) : 1,
    };
    return [hero, teacher];
  }
  if (s === "spray") {
    const grab = sp(t, HIT.grab, { stiffness: 380, damping: 20 });
    const aim = sp(t, HIT.grab + 0.08, WOBBLE);
    const sprayOn = t > HIT.spray;
    const recoil = sprayOn ? 0.06 * Math.sin((t - HIT.spray) * 60) * Math.exp(-(t - HIT.spray) * 2) : 0;
    const hero: Actor = {
      id: "hero", look: CAST.hero, p: [1.35 - 0.25 * grab, 0, 1.75 - 0.3 * grab], yaw: PI - (PI / 2) * aim, hold: t >= HIT.grab,
      pose: { ...REST, armRX: lerp(0.9, 1.45, aim) + recoil, armLX: lerp(0.3, 1.25, aim), armLZ: lerp(-0.06, 0.25, aim), torsoX: -0.12 * aim, headX: 0.1 },
      squash: 1 + 0.1 * Math.exp(-Math.max(0, t - HIT.grab) * 12) * Math.cos((t - HIT.grab) * 30) * (t > HIT.grab ? 1 : 0),
    };
    // Staff charge in; the smoke stops them dead, they spin about, and on the alarm they run off.
    const run = (id: string, look: Look, z: number, x0: number, ph: number): Actor => {
      const stopAt = HIT.spray + 0.18 + ph * 0.04;
      const tt = Math.min(t, stopAt);
      const x = x0 + 5.2 * (tt - SHOT.spray[0]);
      const confused = t > stopAt;
      const flee = sp(t, HIT.alarm + ph * 0.05, { stiffness: 300, damping: 20 });
      const fleeX = t > HIT.alarm ? -3.2 * Math.max(0, t - HIT.alarm - 0.08) : 0;
      return {
        id, look, p: [x + fleeX, 0, z], yaw: -PI / 2 + (confused ? 0.8 * Math.sin((t - stopAt) * 9 + ph) : 0) + PI * flee,
        pose: !confused || t > HIT.alarm ? walkPose(t * 14 + ph, 1, 0, true) : { ...REST, armLX: 2.2, armRX: 1.9, armLZ: -0.4, armRZ: 0.5, torsoX: 0.2, headX: 0.35 * Math.sin((t - stopAt) * 22) },
      };
    };
    return [hero, run("guard", CAST.guard, 0.3, -7.4, 0), run("teacher", CAST.teacher, -0.8, -8.3, 1.4), run("npc2", { ...CAST.guard, skin: "#e0ac7e" }, 1.2, -9.4, 2.6)];
  }
  return [];
}

/** World position of the extinguisher's nozzle while the hero holds it. */
export function nozzle(t: number): V3 {
  const h = actors(t).find((a) => a.id === "hero");
  if (!h) return [0, 1.2, 0];
  const fx = -Math.sin(h.yaw), fz = -Math.cos(h.yaw);
  return [h.p[0] + fx * 0.85 + fz * -0.25, 1.15, h.p[2] + fz * 0.85 - fx * -0.25];
}

/** Screen pin for 2D overlays. */
export function pin(t: number, p: V3) {
  return toScreen(camAt(t), p);
}
export function headPin(t: number, id: string) {
  const a = actors(t).find((x) => x.id === id);
  return a ? pin(t, headTop(a)) : null;
}
export const EXT_WALL: V3 = [1.25, 1.12, 2.86];

// ------------------------------------------------------------------ moving props
const TROLLEY = trolley();
const PILE: V3[] = Array.from({ length: 10 }, (_, i) => [(i % 3 - 1) * 0.2 + (hash(i) - 0.5) * 0.06, 0.07 + Math.floor(i / 3) * 0.1, ((Math.floor(i / 3) % 2) - 0.5) * 0.24 + (hash(i + 4) - 0.5) * 0.1]);
const TRAY_Y = 0.62 * 1.4 + 0.05;

const Trolley: React.FC<{ t: number }> = ({ t }) => {
  const tx = trolleyX(t);
  const d = hitstop(t - HIT.trolley);
  // Tips onto its front wheels at the impact and rocks back.
  const tip = d > 0 ? 0.32 * Math.exp(-d * 7) * Math.cos(d * 16) : 0;
  const rattle = d < 0 ? 0.015 * Math.sin(t * 90) : 0;
  const front = 0.72;
  return (
    <>
      <G p={[tx + front, 0, TROLLEY_Z]} r={[0, 0, -tip]}>
        <G p={[-front, rattle, 0]} r={[0, PI / 2, 0]} s={1.4}>
          <Voxels boxes={TROLLEY} />
        </G>
        {d < 0
          ? PILE.map((o, i) => (
            <G key={i} p={[-front + o[0], TRAY_Y + o[1], o[2]]} r={[0, i * 0.7, 0]} s={1.2}>
              <Voxels boxes={SAMOSA_V} />
            </G>
          ))
          : null}
      </G>
      {d >= 0 ? <FlyingSamosas t={t} origin={[tx, TRAY_Y + 0.1, TROLLEY_Z]} /> : null}
    </>
  );
};

/** At the impact the whole pile launches at the lens; a few pass right by the camera. */
const FlyingSamosas: React.FC<{ t: number; origin: V3 }> = ({ t, origin }) => {
  const d = hitstop(t - HIT.trolley);
  const cam = camAt(t);
  return (
    <>
      {Array.from({ length: 11 }, (_, i) => {
        const o = PILE[i % PILE.length];
        const a = (i / 11) * PI * 2 + rand(i) * 0.4;
        const vx = 1.0 + Math.cos(a) * 3.2, vy = 2.4 + Math.sin(a) * 1.6 + rand(i + 5) * 0.8, vz = -(2.2 + rand(i + 9) * 3.6);
        const x = origin[0] + o[0] + vx * d, z = origin[2] + o[2] + vz * d;
        const y = Math.max(0.06, origin[1] + o[1] + vy * d - 4.9 * d * d);
        if (Math.hypot(x - cam.pos[0], y - cam.pos[1], z - cam.pos[2]) < 2.5 || z < cam.pos[2] + 0.3) return null;
        return (
          <G key={i} p={[x, y, z]} r={[d * (6 + (i % 5)) * (i % 2 ? 1 : -1), d * 5 + i, d * 3]} s={1.3}>
            <Voxels boxes={SAMOSA_V} />
          </G>
        );
      })}
    </>
  );
};

const PaperBall: React.FC<{ t: number }> = ({ t }) => {
  const a = b(10, 3.5), hit = HIT.bonk;
  if (t < a) return null;
  const from: V3 = [-2.0, 2.0, -0.05], to: V3 = [3.3, 1.86, 1.72];
  const u = clamp01((t - a) / (hit - a));
  let p: V3 = [lerp(from[0], to[0], u), lerp(from[1], to[1], u) + 0.75 * Math.sin(u * PI), lerp(from[2], to[2], u)];
  if (t > hit) {
    const d = hitstop(t - hit);
    p = [to[0] - 1.5 * d, Math.max(0.07, to[1] + 2.4 * d - 4.9 * d * d), to[2] - 1.1 * d];
  }
  return (
    <G p={p} r={[t * 19, t * 13, 0]} s={2.6}>
      <Voxels boxes={PAPER_BALL} />
    </G>
  );
};

/** Voxel smoke from the nozzle on 16ths, billowing down the corridor. */
const Smoke: React.FC<{ t: number }> = ({ t }) => {
  if (t < HIT.spray) return null;
  const n = 34;
  return (
    <>
      {Array.from({ length: n }, (_, i) => {
        const born = HIT.spray + i * (BEAT / 4) * 0.5;
        const d = t - born;
        if (d < 0) return null;
        const o = nozzle(born);
        const drag = (1 - Math.exp(-d * 2.2)) / 2.2;
        const sp0 = 7 + rand(i) * 5;
        const x = o[0] - sp0 * drag;
        const y = o[1] + (rand(i + 3) - 0.3) * 1.6 * drag + 0.25 * d;
        const z = o[2] + (rand(i + 7) - 0.5) * 3.2 * drag - 0.4 * drag;
        const size = 0.25 + (1.4 + rand(i + 11) * 1.4) * (1 - Math.exp(-d * 2.6));
        return (
          <G key={i} p={[x, y, z]} r={[rand(i + 2) * 3 + d * 0.8, rand(i + 5) * 3 + d, 0]} s={size}>
            <mesh>
              <boxGeometry args={[1, 1, 1]} />
              <meshBasicMaterial color={i % 3 ? "#f6f8fa" : "#e6ebf0"} transparent opacity={0.92} toneMapped={false} />
            </mesh>
            <mesh position={[0.2, 0.25, -0.15]}>
              <boxGeometry args={[0.72, 0.72, 0.72]} />
              <meshBasicMaterial color="#ffffff" toneMapped={false} />
            </mesh>
          </G>
        );
      })}
    </>
  );
};

// ------------------------------------------------------------------ the scene
export const ChaosScene: React.FC<{ t: number }> = ({ t }) => {
  const hall = useMemo(() => corridor(), []);
  const shell = useMemo(() => hallShell(), []);
  const s = shotAt(t);
  const cast = actors(t);
  const closed = s !== "trolley";
  const heroHolds = cast.find((a) => a.id === "hero")?.hold;
  return (
    <>
      <Voxels boxes={hall} />
      <Voxels boxes={shell.solid} />
      {closed ? <Voxels boxes={shell.open} shadow={false} /> : null}
      <G p={[EXT_WALL[0], EXT_WALL[1], EXT_WALL[2] + 0.02]}><Voxels boxes={WALL_BRACKET} /></G>
      {s === "spray" && !heroHolds ? <G p={EXT_WALL} r={[0, PI, 0]} s={1.25}><Voxels boxes={EXTINGUISHER} /></G> : null}
      {s === "trolley" ? <Trolley t={t} /> : null}
      {s === "paper" ? <PaperBall t={t} /> : null}
      {s === "spray" ? <Smoke t={t} /> : null}
      {cast.map((a) => (
        <Character key={a.id} look={a.look} pose={a.pose} p={a.p} yaw={a.yaw} roll={a.roll ?? 0} pitch={a.pitch ?? 0} squash={a.squash ?? 1}
          extra={a.hold ? { armR: EXT_HELD } : undefined} />
      ))}
    </>
  );
};

// Held in the right hand (arm-local: the hand is at y -0.47), pointing along the forearm.
const EXT_HELD: Box[] = EXTINGUISHER.map((bx) => ({ ...bx, c: [bx.c[0] * 1.1, -0.74 - bx.c[1] * 1.1, bx.c[2] * 1.1] as V3, s: [bx.s[0] * 1.1, bx.s[1] * 1.1, bx.s[2] * 1.1] as V3 }));
