// Act "dodge": who stands where at time t. Pure functions shared by the 3D shots, the minimap and the
// 2D overlays, so the map and the 3D always agree. World = the corridor from launch/sets.ts corridor():
// x runs down the corridor, z across it (lockers and the wall at +z, the open verandah at -z), metres.
import { step, track, type SpringConfig } from "../../kit/spring";
import { CAST, mixPose, REST, sitPose, walkPose, type Look, type Pose, type V3 } from "../../launch/voxel";
import { seat } from "../../launch/sets";
import { b, BEAT } from "../cues";

export const PI = Math.PI;
export const clamp01 = (v: number) => Math.min(1, Math.max(0, v));
export const lerp = (a: number, c: number, u: number) => a + (c - a) * u;

export const SNAP: SpringConfig = { stiffness: 700, damping: 30 };
export const DART: SpringConfig = { stiffness: 520, damping: 26 };
export const POP: SpringConfig = { stiffness: 520, damping: 17 };
export const JELLY: SpringConfig = { stiffness: 380, damping: 11 };
export const WOBBLE: SpringConfig = { stiffness: 380, damping: 13 };
export const SOFT: SpringConfig = { stiffness: 160, damping: 22 };
export const CRASH: SpringConfig = { stiffness: 900, damping: 42 };
export const sp = (t: number, at: number, cfg: SpringConfig = POP) => step(t - at, cfg);

export type Actor = { id: string; look: Look; pose: Pose; p: V3; yaw: number; squash?: number };
/** Top of an actor's head (for "!" marks and speech). */
export const headTop = (a: Actor): V3 => [a.p[0], a.p[1] + (a.pose.hipY + 0.56 + 0.5) * (a.squash ?? 1), a.p[2]];

// Footfalls on the beat: sin(phase) crosses zero once per beat.
const stepPhase = (t: number, from: number) => ((t - from) * PI) / BEAT;

/** A map marker for a watcher: world position, facing yaw (game convention: dir = (-sin, -cos)), cone. */
export type Watcher = { id: string; x: number; z: number; yaw: number; fov: number; reach: number; alert: number; kind: "staff" | "cctv"; label: string };

// ------------------------------------------------------------------ the teacher walking down the corridor
export const TEACHER_V = 0.95;
/** Bar 7 beats: the map zooms into the 3D (IRIS), she glances back (GLANCE), cut to the CCTV (CUT_B). */
export const IRIS = b(7, 1);
export const GLANCE = b(7, 1.5);
export const CUT_B = b(7, 2.5);
export const teacherX = (t: number) => -1.0 + TEACHER_V * (t - IRIS);
export const TEACHER_Z = 0.7;
export const HERO_Z = -0.05;
/** 7.1: she glances back over her shoulder; 7.1.5 back to the front. */
export const glance = (t: number) => sp(t, GLANCE, WOBBLE) - sp(t, GLANCE + BEAT * 0.8, WOBBLE);

export function teacherWalker(t: number): Actor {
  const g = glance(t);
  const pose = walkPose(stepPhase(t, b(6)), 0.55 * (1 - 0.8 * g));
  return {
    id: "teacher", look: CAST.teacher, p: [teacherX(t), 0, TEACHER_Z], yaw: -PI / 2,
    pose: { ...pose, headY: 1.05 * g, armLX: 0.35 },
  };
}

// ------------------------------------------------------------------ the hero on the map (bar 6): darts on the 8ths
type Key = [t: number, x: number, z: number];
const ROUTE: Key[] = [
  [b(6, 0), -15.2, -1.9],
  [b(6, 1.5), -12.9, -1.3],
  [b(6, 2), -11.0, 1.9],
  [b(6, 2.5), -7.9, 2.0],
  [b(6, 3), -5.6, 1.4],
  [b(6, 3.5), -4.6, 0.5],
  [b(7, 0), -3.9, 0.1],
];
/** Where shot A (3D) picks the hero up: right behind the teacher. */
export const heroGap = (t: number) => 1.6 + 0.35 * (sp(t, GLANCE, SNAP) - sp(t, GLANCE + BEAT * 0.8, DART));
export const heroShotAX = (t: number) => teacherX(t) - heroGap(t);

const yawOf = (dx: number, dz: number) => Math.atan2(-dx, -dz);

export function heroMap(t: number): { x: number; z: number; yaw: number } {
  // A hand-off key at 6.3.5 lands exactly where shot A starts, so the map and the 3D agree at the cut.
  const keys: Key[] = [...ROUTE, [IRIS, heroShotAX(IRIS), HERO_Z]];
  if (t >= IRIS) return { x: heroShotAX(t), z: HERO_Z, yaw: -PI / 2 };
  const x = track(t, keys.map((k) => [k[0], k[1]] as const), DART);
  const z = track(t, keys.map((k) => [k[0], k[2]] as const), DART);
  // Heading: towards the next key, eased (the minimap turns with you).
  const yk = keys.map((k, i) => {
    const n = keys[Math.min(keys.length - 1, i + 1)];
    const p = keys[Math.max(0, i - 1)];
    const dx = i < keys.length - 1 ? n[1] - k[1] : k[1] - p[1];
    const dz = i < keys.length - 1 ? n[2] - k[2] : k[2] - p[2];
    return [k[0] - BEAT * 0.25, yawOf(dx, dz)] as const;
  });
  const yaw = track(t, [[yk[0][0] - 1, yk[0][1]], ...yk], SOFT);
  return { x, z, yaw };
}

// ------------------------------------------------------------------ the guard and the CCTV
export const GUARD = { x: -9.5, z: -6.1 };
/** Sweeps across the corridor, missing the hero's line on the wall side; swings over the spot he left. */
export const guardYaw = (t: number) => PI + 0.8 * Math.cos((PI * (t - b(6, 1.5))) / (2 * BEAT) * 0.9);

export const CCTV_POS: V3 = [7.0, 2.95, 2.85];
export const CCTV_TILT = -0.62;
/** Shot B: s = 0 looks straight across the corridor; + swings to -x (the side the hero waits on). */
export function cctvSweep(t: number) {
  if (t < CUT_B) return 0.45 * Math.sin((t - b(6)) * 1.9);
  // 7.2: pointing at the floor ahead of him; swings onto his spot on 7.2.5 (he's gone), across by 7.3.
  return track(t, [[CUT_B - 1, 0.55], [CUT_B, 0.55], [b(7, 3), -0.55]], { stiffness: 110, damping: 16 });
}

export function watchers(t: number): Watcher[] {
  const g = glance(t);
  return [
    { id: "teacher", x: teacherX(t), z: TEACHER_Z, yaw: -PI / 2 + 1.05 * g, fov: 100, reach: 6.2, alert: g > 0.3 ? 1 : 0, kind: "staff", label: "Ms. Okafor" },
    { id: "guard", x: GUARD.x, z: GUARD.z, yaw: guardYaw(t), fov: 88, reach: 7.4, alert: 0, kind: "staff", label: "Sergei (Guard)" },
    { id: "cctv", x: CCTV_POS[0], z: CCTV_POS[2], yaw: cctvSweep(t), fov: 60, reach: 6.5, alert: 0, kind: "cctv", label: "CCTV" },
  ];
}

// ------------------------------------------------------------------ shot A: crouch-walking behind her back
export function shotAActors(t: number): Actor[] {
  const tch = teacherWalker(t);
  const freeze = sp(t, GLANCE, SNAP) - sp(t, GLANCE + BEAT * 0.8, SNAP);
  const x = heroShotAX(t);
  const walk = walkPose(stepPhase(t, b(6)) + 0.6, 0.85 * (1 - freeze), 1);
  const hero: Actor = {
    id: "hero", look: CAST.hero, p: [x, 0, HERO_Z], yaw: -PI / 2,
    pose: { ...walk, hipY: walk.hipY - 0.06 * freeze, headX: walk.headX + 0.25 * freeze, armLX: walk.armLX + 0.5 * freeze, armRX: walk.armRX + 0.5 * freeze },
    squash: 1 - 0.1 * freeze + (t > GLANCE ? 0.06 * Math.exp(-(t - GLANCE) * 10) * Math.cos((t - GLANCE) * 34) : 0),
  };
  return [tch, hero];
}

// ------------------------------------------------------------------ shot B: under the CCTV
const B_PATH: Key[] = [
  [CUT_B - 1, 4.6, 1.95],
  [CUT_B, 4.6, 1.95],
  [b(7, 3), 7.2, 1.95],
  [b(7, 3.5), 9.0, 1.9],
];
export function shotBHero(t: number): Actor {
  const x = track(t, B_PATH.map((k) => [k[0], k[1]] as const), DART);
  const z = track(t, B_PATH.map((k) => [k[0], k[2]] as const), DART);
  // Waits for the sweep (7.2), creeps under the camera's blind spot, freezes as it swings over his head (7.3).
  const hold = t < CUT_B + 0.03 || (t > b(7, 3) - 0.04 && t < b(7, 3) + 0.14);
  const pose = walkPose(t * 13, hold ? 0.1 : 0.9, 1);
  const up = t > b(7, 3) - 0.04 && t < b(7, 3.5) ? sp(t, b(7, 3) - 0.04, WOBBLE) - sp(t, b(7, 3.25), SNAP) : 0;
  return {
    id: "hero", look: CAST.hero, p: [x, 0, z], yaw: -PI / 2,
    pose: { ...pose, headX: pose.headX - 0.45 * up, headY: t < CUT_B ? 0.45 : 0 },
    squash: 1 - 0.06 * up,
  };
}
export function shotBTeacher(t: number): Actor {
  // Far down the corridor, still walking away.
  return { ...teacherWalker(t), p: [teacherX(t) + 9.2, 0, TEACHER_Z] };
}

// ------------------------------------------------------------------ classroom (bar 8): who's talking?!
export const CLASS_TEACHER: V3 = [-0.4, 0.08, 3.85];
export const SPIN = b(8, 1);
const writing = (t: number): Pose => ({ ...REST, armRX: 2.1 + 0.12 * Math.sin((t * 2 * PI) / (BEAT / 2)), armRZ: -0.25, headX: -0.15 });
const seated = (id: string, look: Look, s: V3, headY = 0): Actor => ({ id, look, pose: { ...sitPose(1), headY }, p: [s[0], 0, s[2]], yaw: PI });

export const HERO_SEAT = seat(5, 0);
export const FRIEND_SEAT = seat(5, 1);
export const FRIEND_NAME = "Arjun";

export function classActors(t: number): Actor[] {
  const turn = sp(t, SPIN, WOBBLE);
  const spun = t >= SPIN;
  const teacher: Actor = {
    id: "teacher", look: CAST.teacher, p: CLASS_TEACHER, yaw: PI - PI * turn,
    pose: spun ? mixPose(writing(t), { ...REST, armLX: 0.35, armRX: 1.6, armRZ: 0.25, headX: 0.12 }, clamp01((t - SPIN) / 0.12)) : writing(t),
    squash: spun ? 1 + 0.16 * Math.exp(-(t - SPIN) * 9) * Math.sin((t - SPIN) * 26) : 1,
  };
  // The friend leans in and whispers (8.0), then laughs out loud (8.0.5), then freezes (8.1).
  const lean = sp(t, b(8) - 0.12, SNAP) - sp(t, b(8, 0.5), SNAP);
  const laugh = t > b(8, 0.5) && t < SPIN ? Math.abs(Math.sin((t - b(8, 0.5)) * 26)) : 0;
  const freeze = sp(t, SPIN + 0.05, SNAP);
  const fr = seated("friend", CAST.friendB, FRIEND_SEAT);
  fr.pose = { ...fr.pose, torsoX: -0.12 * lean + 0.1 * laugh * (1 - freeze), headY: -0.7 * lean + 0.35 * freeze, headX: -0.25 * laugh * (1 - freeze) + 0.15 * freeze, armRX: 0.5 + 1.9 * lean * (1 - freeze), armLX: 0.5 + 0.3 * laugh };
  fr.yaw = PI + 0.35 * lean;
  fr.squash = 1 + 0.08 * laugh * (1 - freeze) - 0.06 * freeze;
  // 8.2.5: whistles, looking anywhere but the teacher.
  const innocent = sp(t, b(8, 2.5), WOBBLE);
  fr.pose.headX += -0.3 * innocent;
  fr.pose.headY += 0.45 * innocent;
  const hero = seated("hero", CAST.hero, HERO_SEAT);
  hero.pose = { ...hero.pose, headY: 0.55 * lean - 0.45 * sp(t, b(8, 0.5), SNAP) + 0.45 * sp(t, SPIN, SNAP) - 0.75 * sp(t, b(8, 3), WOBBLE), headX: 0.12 * sp(t, b(8, 2), SNAP) };
  hero.squash = 1 - 0.07 * freeze;
  return [
    teacher, hero, fr,
    seated("npc1", CAST.npc1, seat(0, 0)), seated("npc2", CAST.npc2, seat(0, 1), 0.3 * sp(t, SPIN + 0.1)),
    seated("friendA", CAST.friendA, seat(2, 1), -0.8 * sp(t, b(8, 0.6))), seated("friendC", CAST.friendC, seat(1, 0)),
    seated("npc3", CAST.npc3, seat(4, 1), 0.9 * sp(t, b(8, 0.7))), seated("npc4", CAST.npc4, seat(3, 0), -0.5 * sp(t, b(8, 0.8))),
  ];
}

// ------------------------------------------------------------------ the excuse (bar 9)
export const PICK = b(11, 1);
export const BLAME = b(11, 2);
export function excuseActors(t: number): Actor[] {
  const lean = sp(t, b(10), WOBBLE);
  const toFriend = sp(t, BLAME, SNAP);
  const teacher: Actor = {
    id: "teacher", look: CAST.teacher, p: [1.05, 0, 0.35], yaw: PI / 2 - 0.35 - 0.35 * toFriend,
    pose: { ...REST, torsoX: -0.16 * lean, armLX: 1.1 * (1 - toFriend) + 0.35 * toFriend, armRX: 1.1 * (1 - toFriend) + 1.75 * toFriend, armLZ: 0.55 * (1 - toFriend), armRZ: -0.55 * (1 - toFriend) + 0.3 * toFriend, headY: -0.25 * toFriend },
  };
  const point = sp(t, PICK, SNAP);
  const hero: Actor = {
    id: "hero", look: CAST.hero, p: [0.0, 0, 0.2], yaw: -PI / 2 + 0.55 + 0.45 * point,
    // Pleading hands while he picks, then the finger: his left arm swings out at the friend.
    pose: { ...REST, armRX: 0.3 + 0.35 * Math.sin(t * 12) * (1 - point), armLX: 0.4 * (1 - point) + 0.25 * point, armLZ: -0.06 - 1.45 * point, headY: 0.5 * point },
  };
  const hit = sp(t, BLAME, WOBBLE);
  const friend: Actor = {
    id: "friend", look: CAST.friendB, p: [-1.35, 0, 1.15], yaw: -PI / 2 + 0.9,
    pose: { ...REST, armLX: 2.5 * hit, armRX: 2.5 * hit, armLZ: -0.5 * hit, armRZ: 0.5 * hit, headX: -0.12 * hit, headY: -0.3 * (1 - hit) },
    squash: t > BLAME ? 1 - 0.22 * Math.exp(-(t - BLAME) * 9) * Math.cos((t - BLAME) * 30) : 1,
  };
  return [teacher, hero, friend];
}
