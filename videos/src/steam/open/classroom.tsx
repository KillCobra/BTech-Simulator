// Bars 2-3: the classroom, first person from the hero's seat (the game's POV: board ahead, desk and
// hands below). The teacher chalks, the hero stands, classmates turn, the teacher spins round.
import React, { useMemo } from "react";
import * as THREE from "three";
import { step, track, type SpringConfig } from "../../kit/spring";
import type { Cam } from "../../launch/camera3d";
import { WOBBLE } from "../../launch/juice";
import { classroom, seat } from "../../launch/sets";
import { Character, G, Voxels } from "../../launch/three";
import { CAST, mixPose, P, REST, sitPose, type Box, type Look, type Pose, type V3 } from "../../launch/voxel";
import { b, BEAT } from "../cues";
import { hands } from "./clock";

const PI = Math.PI;
const lerp = (a: number, c: number, u: number) => a + (c - a) * u;
const lerp3 = (a: V3, c: V3, u: number): V3 => [lerp(a[0], c[0], u), lerp(a[1], c[1], u), lerp(a[2], c[2], u)];

// ---------------------------------------------------------------- timing (all on the grid)
export const T = {
  portal: b(1, 3.5), // the classroom opens inside the clock face
  land: b(2), // POV lands
  prompt: b(2, 2), // [E] Stand up
  press: b(2, 3), // E pressed, the hero stands
  step: b(3), // into the aisle, suspicion card in
  glance1: b(3, 0.5),
  glance2: b(3, 1),
  spot: b(3, 2), // teacher spins, "!"
  run: b(3, 3), // RUN!
};

export const TEACHER_P: V3 = [-0.85, 0.08, 3.85];
const HERO_SEAT = seat(3, 0);
export const AISLE: V3 = [1.35, 1.76, -1.55];
const HEAVY: SpringConfig = { stiffness: 120, damping: 22 };
const CRASH: SpringConfig = { stiffness: 620, damping: 34 };

/** Where the hero's eyes are, what they look at. */
export function classCam(t: number): Cam {
  const sit: V3 = [HERO_SEAT[0], 1.3, HERO_SEAT[2] - 0.08];
  const stand: V3 = [HERO_SEAT[0] + 0.05, 1.76, HERO_SEAT[2] - 0.22];
  const aisle: V3 = AISLE;
  const keys: [number, V3, V3][] = [
    [0, sit, [-0.25, 1.36, 4.6]],
    [T.press, stand, [-0.3, 1.5, 4.6]],
    [T.step, aisle, [-0.2, 1.35, 4.4]],
  ];
  const ch = (f: (k: [number, V3, V3]) => number) => track(t, keys.map((k) => [k[0], f(k)] as const), HEAVY);
  // a slow creep toward the board while seated (the room breathes), undone as the hero stands
  const creep = Math.max(0, Math.min(1, (t - T.land) / (T.press - T.land))) * (1 - step(t - T.press, HEAVY));
  let pos: V3 = [ch((k) => k[1][0]), ch((k) => k[1][1]) + 0.03 * creep, ch((k) => k[1][2]) + 0.35 * creep];
  let look: V3 = [ch((k) => k[2][0]), ch((k) => k[2][1]), ch((k) => k[2][2])];
  // standing up: a quick overshoot on the rise
  const rise = step(t - T.press, { stiffness: 260, damping: 14 }) - step(t - T.press, HEAVY);
  pos = [pos[0], pos[1] + rise * 0.12, pos[2]];
  // walking: head bob on 8ths between the step and the spot
  const walking = t > T.step && t < T.spot + 0.1 ? Math.min(1, (t - T.step) / 0.1) * (t > T.spot ? Math.max(0, 1 - (t - T.spot) / 0.1) : 1) : 0;
  const ph = ((t - T.step) / (BEAT / 2)) * PI;
  pos = [pos[0], pos[1] + walking * 0.05 * Math.abs(Math.sin(ph)), pos[2]];
  // the whip to the teacher (crash zoom)
  const w = step(t - T.spot, CRASH);
  const tHead: V3 = [TEACHER_P[0] + 0.1, 1.5, TEACHER_P[2]];
  look = lerp3(look, tHead, Math.min(1.05, w));
  pos = lerp3(pos, [1.2, 1.74, -1.2], Math.min(1, w));
  // fov: through-the-clock zoom out on the portal, crash in on the spot, punch on RUN!
  const fov0 = track(t, [[0, 24], [T.portal, 24], [T.portal + 0.001, 50], [T.press, 56]], { stiffness: 240, damping: 30 });
  const runPunch = t >= T.run ? 3 * Math.exp(-(t - T.run) / 0.12) : 0;
  const fov = lerp(fov0, 30, w) - runPunch;
  // shake on the spot and on RUN!
  let sh = 0;
  for (const [at, a] of [[T.spot, 0.03], [T.run, 0.06]] as const) if (t >= at) sh += a * Math.exp(-(t - at) / 0.18);
  const n = (k: number) => Math.sin(t * 61 + k * 1.7) * Math.cos(t * 37 + k);
  const roll = walking * 0.015 * Math.sin(ph) + sh * 0.6 * n(3) + (t > T.press && t < T.step ? -0.02 * (1 - step(t - T.press - 0.3, HEAVY)) : 0);
  return { pos: [pos[0] + sh * n(1), pos[1] + sh * n(2), pos[2]], look, fov, roll };
}

// ---------------------------------------------------------------- the room
function chalkTexture(lines: string[]) {
  const c = document.createElement("canvas");
  c.width = 1000;
  c.height = 340;
  const g = c.getContext("2d")!;
  g.fillStyle = "#f3f6ee";
  g.font = "110px Jersey10";
  g.textAlign = "center";
  g.textBaseline = "middle";
  lines.forEach((l, i) => g.fillText(l, 500, 90 + i * 150));
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 8;
  return tex;
}

const bx = (list: Box[], c: V3, s: V3, col: string) => list.push({ c, s, col });
function extras() {
  const ceil: Box[] = [], lamps: Box[] = [], fanHub: Box[] = [], fanBlades: Box[] = [];
  bx(ceil, [0, 3.45, 0], [12.4, 0.1, 10.2], "#ece2cc");
  for (const x of [-3, 3]) for (const z of [-1.5, 2.2]) bx(lamps, [x, 3.37, z], [0.14, 0.06, 1.7], "#fffbea");
  bx(fanHub, [0, 3.22, 0], [0.05, 0.42, 0.05], "#d8d8d2");
  bx(fanHub, [0, 3.0, 0], [0.26, 0.1, 0.26], "#ececE6");
  for (let i = 0; i < 4; i++) {
    const a = (i * PI) / 2;
    bx(fanBlades, [Math.cos(a) * 0.72, 3.0, Math.sin(a) * 0.72], [Math.abs(Math.cos(a)) * 1.1 + 0.22, 0.03, Math.abs(Math.sin(a)) * 1.1 + 0.22], "#f2f2ee");
  }
  // a window-side poster and the notice card on the right wall like the game's classroom
  bx(ceil, [5.99, 2.0, -0.8], [0.03, 0.9, 1.3], "#ffd24a");
  bx(ceil, [5.99, 1.75, 1.2], [0.03, 0.55, 0.8], "#7fd0ea");
  return { ceil, lamps, fanHub, fanBlades };
}

// The wall clock hands (the classroom clock at [0, 2.9, 4.54], seen from -Z): 9:00, second hand ticking.
const WALL_HOUR: Box[] = [{ c: [0.07, 0, 0], s: [0.15, 0.035, 0.012], col: "#2a2230" }];
const WALL_MIN: Box[] = [{ c: [0, 0.1, 0], s: [0.025, 0.2, 0.012], col: "#2a2230" }];
const WALL_SEC: Box[] = [{ c: [0, 0.07, 0], s: [0.012, 0.2, 0.01], col: "#e0524f" }];

const HANDS_POV: Box[] = [
  { c: [0, 0, 0], s: [0.13, 0.1, 0.2], col: P.SHIRT },
  { c: [0, -0.005, 0.16], s: [0.11, 0.08, 0.16], col: "#c68a5c" },
  { c: [0, -0.01, 0.27], s: [0.11, 0.07, 0.08], col: "#b67d52" },
];

type Actor = { id: string; look: Look; pose: Pose; p: V3; yaw: number; squash?: number };

const writing = (t: number): Pose => ({ ...REST, armRX: 2.2 + 0.14 * Math.sin((t * 2 * PI) / (BEAT / 2)), armRZ: -0.3, headX: -0.12, headY: 0.1 * Math.sin(t * 3) });

/** Face-the-camera yaw for a seated student (split between body and head). */
function turnTo(p: V3, cam: V3) {
  const dx = cam[0] - p[0], dz = cam[2] - p[2];
  let th = Math.atan2(-dx, -dz);
  while (th - PI > PI) th -= 2 * PI;
  while (th - PI < -PI) th += 2 * PI;
  return th - PI;
}

export function classActors(t: number): Actor[] {
  const seatedAt = (id: string, look: Look, i: number, side: 0 | 1, turnAt?: number): Actor => {
    const s = seat(i, side);
    const a: Actor = { id, look, pose: { ...sitPose(1) }, p: [s[0], 0, s[2]], yaw: PI };
    // idle: small head drift so nobody is frozen
    a.pose.headY = 0.12 * Math.sin(t * 1.3 + i * 2 + side);
    a.pose.headX = 0.05 * Math.sin(t * 1.7 + i);
    if (turnAt !== undefined) {
      const u = step(t - turnAt, WOBBLE);
      const want = turnTo(a.p, [AISLE[0], 0, AISLE[2]]);
      a.yaw = PI + want * 0.28 * u;
      a.pose.headY = a.pose.headY * (1 - Math.min(1, u)) + Math.max(-1.35, Math.min(1.35, want * 0.72)) * u;
      a.pose.headX = -0.1 * u;
      a.squash = 1 + 0.08 * Math.exp(-Math.max(0, t - turnAt) * 10) * Math.sin(Math.max(0, t - turnAt) * 30);
    }
    return a;
  };
  const spin = step(t - T.spot, WOBBLE);
  const face = turnTo(TEACHER_P, [AISLE[0], 0, AISLE[2]]);
  const teacher: Actor = {
    id: "teacher", look: CAST.teacher, p: TEACHER_P, yaw: PI + face * spin,
    pose: t < T.spot ? writing(t) : mixPose(writing(t), { ...REST, armRX: 1.55, armRZ: 0.1, armLX: 0.5, headX: 0.12 }, Math.min(1, (t - T.spot) / 0.12)),
    squash: t < T.spot ? 1 : 1 + 0.16 * Math.exp(-(t - T.spot) * 9) * Math.sin((t - T.spot) * 28),
  };
  return [
    teacher,
    seatedAt("npc1", CAST.npc1, 0, 0, T.glance2 + BEAT / 4),
    seatedAt("npc2", CAST.npc2, 0, 1, T.glance2),
    seatedAt("friendB", CAST.friendB, 1, 1, T.glance1),
    seatedAt("friendA", CAST.friendA, 2, 1, T.glance1 + BEAT / 4),
    seatedAt("npc4", CAST.npc4, 2, 0),
    seatedAt("npc3", CAST.npc3, 4, 1),
    seatedAt("friendC", CAST.friendC, 5, 0),
  ];
}
export const headTopOf = (a: Actor): V3 => [a.p[0], a.p[1] + (a.pose.hipY + 1.08) * (a.squash ?? 1), a.p[2]];

export const ClassroomScene: React.FC<{ t: number }> = ({ t }) => {
  const room = useMemo(() => classroom(), []);
  const ex = useMemo(extras, []);
  const chalk = useMemo(() => chalkTexture(["Thermodynamics", "Attendance: 9:05"]), []);
  const cast = classActors(t);
  const cam = classCam(t);
  const sec = hands(t).second;
  // the POV hands push on the desk as the hero stands, then drop out of view
  const stand = step(t - T.press, { stiffness: 200, damping: 20 });
  const handY = 0.815 - 0.05 * Math.min(1, stand * 3) * (1 - stand) - 1.2 * Math.max(0, stand - 0.4);
  return (
    <>
      <Voxels boxes={room} />
      <Voxels boxes={ex.ceil} shadow={false} />
      <Voxels boxes={ex.lamps} shadow={false} />
      <G p={[0, 0, 1.2]}>
        <Voxels boxes={ex.fanHub} shadow={false} />
        <G p={[0, 0, 0]} r={[0, t * 5.5, 0]}><G p={[0, 0, 0]}><Voxels boxes={ex.fanBlades} shadow={false} /></G></G>
      </G>
      <mesh position={[0.72, 1.8, 4.49]} rotation={[0, PI, 0]}>
        <planeGeometry args={[2.1, 0.714]} />
        <meshBasicMaterial map={chalk} transparent opacity={0.92} toneMapped={false} alphaTest={0.01} />
      </mesh>
      <G p={[0, 2.9, 4.51]}>
        <G r={[0, 0, 0]}><Voxels boxes={WALL_HOUR} shadow={false} /></G>
        <Voxels boxes={WALL_MIN} shadow={false} />
        <G p={[0, 0, -0.01]} r={[0, 0, sec]}><Voxels boxes={WALL_SEC} shadow={false} /></G>
      </G>
      {cast.map((a) => (
        <Character key={a.id} look={a.look} pose={a.pose} p={a.p} yaw={a.yaw} squash={a.squash ?? 1} />
      ))}
      {stand < 1.3 && handY > 0 ? (
        <>
          <G p={[HERO_SEAT[0] - 0.2, handY, cam.pos[2] + 0.55]} r={[0, 0.22, 0]}><Voxels boxes={HANDS_POV} shadow={false} /></G>
          <G p={[HERO_SEAT[0] + 0.24, handY, cam.pos[2] + 0.55]} r={[0, -0.22, 0]}><Voxels boxes={HANDS_POV} shadow={false} /></G>
        </>
      ) : null}
    </>
  );
};
