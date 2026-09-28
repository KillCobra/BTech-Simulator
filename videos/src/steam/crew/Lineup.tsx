// Bars 14-15: "PLAY WITH / UP TO 8 FRIENDS". Eight voxel students drop into a lobby lineup one per 8th
// (squash, dust, name tag pop), a proximity-voice whisper between Sam and Riya, the READY
// ticks rippling on 16ths, a hop on the beat, a pose, then a whip into the maps.
import React from "react";
import { track } from "../../kit/spring";
import type { Cam } from "../../launch/camera3d";
import { clamp01, easeIn, easeOut, rand, shake, SNAP, sp, squash, WOBBLE } from "../../launch/juice";
import { HIP_HEIGHT, REST, walkPose, type Pose, type V3 } from "../../launch/voxel";
import { b, BEAT } from "../cues";
import { toScreen } from "../Stage3D";
import { CrewCharacter, CrewStage, Cube, FloorRing } from "./CrewStage";
import { CLASS_COLORS, FRIENDS } from "./looks";
import { GOLD, GREEN, INK, Ring, Slam, StarBurst, Tag } from "./ui";

const PURPLE = "#b07cff";
const PURPLE_D = "#a06cf0";
const PI = Math.PI;

const N = FRIENDS.length;
// Solved so the name tags sit an even 222 px apart on screen (camera looks down +Z, so +x is screen left).
const SLOT_X = [3.275, 2.15, 1.215, 0.392, -0.392, -1.215, -2.15, -3.275];
const slotX = (i: number) => SLOT_X[i];
// A V: Sam and Riya up front, the outer friends further back (a group photo), so all eight fit big.
const slotZ = (i: number) => 1.4 * Math.pow((i - 3.5) / 3.5, 2);
const slotYaw = (i: number) => 0.28 * (slotX(i) / 3.275);

// Landing order: Sam on the downbeat in the middle, then out to both sides, one per 8th.
const ORDER = [3, 4, 2, 5, 1, 6, 0, 7];
export const LAND = FRIENDS.map((_, i) => b(14, ORDER.indexOf(i) * 0.5));
const READY = FRIENDS.map((_, i) => b(15, 0.5 + i * 0.25));
const HOP1 = b(15);
const POSE = b(15, 3);
const WHIP = b(15, 3.5);
const TALK = b(15, 2);
const SAM = 3, RIYA = 4;

// ---------------------------------------------------------------- camera
export function lineupCam(t: number): Cam {
  const H = { stiffness: 60, damping: 16 };
  const x = track(t, [[b(14) - 1, 0.46], [b(14), 0.46], [b(14, 2), -0.3], [b(15), 0], [POSE, 0]], H);
  const z = track(t, [[b(14) - 1, -6.9], [b(14), -6.9], [b(14, 2), -7.4], [b(15), -7.1], [POSE, -6.9]], H);
  let fov = track(t, [[b(14) - 1, 30], [b(14), 30], [b(15), 30], [POSE, 29.5]], H);
  fov -= 1.6 * Math.exp(-Math.max(0, t - HOP1) / 0.12) * (t >= HOP1 ? 1 : 0);
  const sh = shake(t, [[b(14), 0.05], [HOP1 + 0.3, 0.06], [POSE, 0.04]]);
  // Whip: the camera yaws hard to the right over the last half beat.
  const w = easeIn(clamp01((t - WHIP) / (b(16) - WHIP)));
  const look: V3 = [x * 0.85 - w * 9, 1.5 + sh.y * 0.004, 0];
  return { pos: [x + sh.x * 0.004, 1.62 + sh.y * 0.004, z], look, fov: fov + w * 8, roll: sh.r * 0.02 - w * 0.12 };
}

// ---------------------------------------------------------------- bodies
const tuck: Pose = { ...REST, legL: -0.5, legR: 0.35, armLX: 2.7, armRX: 2.5, armLZ: -0.5, armRZ: 0.5 };
const cheer: Pose = { ...REST, armLX: PI, armRX: PI, armLZ: -0.42, armRZ: 0.42, headX: -0.15 };

const POSES: ((t: number) => Pose)[] = [
  () => ({ ...cheer }), // Mateo: V
  () => ({ ...REST, armRX: PI, armRZ: 0.15, armLX: 0.2, armLZ: -0.75, headY: -0.2 }), // Lin: fist up, hand on hip
  () => ({ ...REST, armRX: 1.55, armRZ: -0.1, torsoX: -0.1, headX: 0.05 }), // Amara: points at you
  () => ({ ...cheer, legL: -0.5, legR: 0.4, armLZ: -0.6, armRZ: 0.6 }), // Sam: star jump (airborne)
  () => ({ ...REST, armLX: 0.4, armLZ: -2.5, armRX: 0.1, armRZ: 0.2, headY: 0.25, headX: 0.1 }), // Riya: wave out to the side
  () => ({ ...REST, armLX: 1.35, armRX: 1.35, armLZ: 0.55, armRZ: -0.55, torsoX: 0.05, headX: 0.12 }), // Omar: arms folded, cool
  () => ({ ...REST, hipY: HIP_HEIGHT - 0.1, legL: -0.25, legR: 0.25, torsoX: -0.12, armRX: 2.55, armRZ: 0.55, armLX: 0.5, armLZ: -0.3, headX: 0.12, headY: -0.25 }), // Zoe: "shh", sneaky
  () => ({ ...walkPose(PI / 2, 1, 0, true), torsoX: -0.25, headX: 0.2 }), // Kenji: already running (side on)
];

const hop = (t: number, at: number, h = 0.5, air = 0.33) => {
  const u = (t - at) / air;
  return u < 0 || u > 1 ? 0 : 4 * h * u * (1 - u);
};

type Body = { pose: Pose; p: V3; yaw: number; squash: number; visible: boolean; head: V3 };

function body(i: number, t: number): Body {
  const land = LAND[i];
  const x = slotX(i), z = slotZ(i);
  let yaw = slotYaw(i);
  const fallLen = 0.2;
  const hgt = FRIENDS[i].look.height ?? 1;
  if (t < land - fallLen) return { pose: REST, p: [x, 20, z], yaw, squash: 1, visible: false, head: [x, 20, z] };
  let y = 0, sq = 1;
  let pose: Pose = { ...REST };
  if (t < land) {
    const u = clamp01((t - (land - fallLen)) / fallLen);
    y = 5.5 * (1 - u * u);
    sq = 1.28;
    pose = { ...tuck };
    yaw += (1 - u) * (i % 2 ? 0.6 : -0.6);
  } else {
    // Landing: squash, a knee dip, arms settle with a wobble.
    const [, sy] = squash(t, land, 0.34, 17, 8);
    sq = sy;
    const settle = sp(t, land, WOBBLE);
    pose = { ...REST, armLZ: -0.06 - (1 - settle) * 0.5, armRZ: 0.06 + (1 - settle) * 0.5 };
    // Groove: a knee dip and head nod on every beat after landing.
    const beatPhase = ((t - b(14)) / BEAT) % 1;
    const dip = Math.exp(-beatPhase * 7) * (t > land + 0.1 ? 1 : 0);
    pose.hipY = HIP_HEIGHT - 0.035 * dip;
    pose.headX = 0.12 * dip;
    // Hops on 15.0 and 15.2 (15.2 as a wave), anticipation crouch just before.
    const antic = (at: number) => Math.max(0, 1 - Math.abs(t - (at - 0.06)) / 0.07);
    pose.hipY -= 0.12 * antic(HOP1);
    const air = hop(t, HOP1, 0.26, 0.3);
    y = air;
    if (air > 0) {
      pose = { ...pose, ...cheer, legL: -0.3, legR: 0.2, hipY: HIP_HEIGHT };
      sq = 1.08;
    }
    for (const at of [HOP1 + 0.3]) if (t >= at) sq *= squash(t, at, 0.22, 20, 9)[1];
    // Voice: Sam turns to Riya and whispers; she leans in.
    if (i === SAM || i === RIYA) {
      const turn = sp(t, TALK - 0.05, SNAP) - sp(t, POSE - 0.12, SNAP);
      const dir = i === SAM ? 1 : -1;
      yaw += dir * 0.75 * turn;
      pose.headY = dir * 0.35 * turn;
      pose.torsoX += -0.08 * turn;
      if (i === SAM) pose.armRX += 1.2 * turn, pose.armRZ += -0.3 * turn;
    }
    // Strike a pose on 15.3 (Sam in the air).
    if (t >= POSE - 0.02) {
      const u = sp(t, POSE - 0.02, SNAP);
      const target = POSES[i](t);
      for (const k of Object.keys(pose) as (keyof Pose)[]) pose[k] = pose[k] + (target[k] - pose[k]) * Math.min(1, u);
      if (i === SAM) y = 0.45 * easeOut(clamp01((t - POSE + 0.02) / 0.16));
      if (i === 6) yaw += 0.5 * u;
      if (i === 7) yaw += -1.35 * u;
      sq *= squash(t, POSE, 0.1, 20, 9)[1];
    }
  }
  const head: V3 = [x, y + (pose.hipY + 0.56 + 0.62) * sq * hgt, z];
  return { pose, p: [x, y, z], yaw, squash: sq, visible: true, head };
}

// Dust kicked up on each landing: pale cubes out along the floor.
const Dust: React.FC<{ t: number }> = ({ t }) => (
  <>
    {FRIENDS.flatMap((_, i) => {
      const d = t - LAND[i];
      if (d < 0 || d > 0.5) return [];
      return Array.from({ length: 7 }, (_, k) => {
        const a = (k / 7) * PI * 2 + rand(i * 7 + k) * 0.8;
        const v = 1.2 + rand(i * 13 + k) * 1.2;
        const r = v * (1 - Math.exp(-d * 7)) / 7 * 1.9;
        const y = Math.max(0.03, 0.05 + (1.5 + rand(k + i) * 1.2) * d - 6 * d * d);
        const s = 0.1 * (0.6 + rand(k * 3 + i)) * (1 - clamp01((d - 0.15) / 0.35));
        return <Cube key={`${i}-${k}`} p={[slotX(i) + Math.cos(a) * (0.25 + r), y, slotZ(i) + Math.sin(a) * (0.2 + r) * 0.6]} s={s} col={k % 2 ? "#fbf1dc" : "#d9c2ff"} r={[d * 9, d * 7, 0]} />;
      });
    })}
  </>
);

// ---------------------------------------------------------------- 2D
const Stripes: React.FC<{ t: number; shift: number }> = ({ t, shift }) => {
  const off = ((t - b(14)) * 60 + shift) % 160;
  return (
    <svg width={1920} height={1080} style={{ position: "absolute", inset: 0 }}>
      <g transform={`translate(${off - 160} 0) skewX(-28)`}>
        {Array.from({ length: 22 }, (_, k) => <rect key={k} x={k * 160} y={-10} width={70} height={1100} fill={PURPLE_D} />)}
      </g>
    </svg>
  );
};

/** Voice arcs ")))" flying from the speaker's mouth toward the listener, on 16ths. */
const VoiceArcs: React.FC<{ t: number; at: number; from: { x: number; y: number }; to: { x: number; y: number }; flip?: boolean }> = ({ t, at, from, to, flip }) => {
  const dx = to.x - from.x, dy = to.y - from.y;
  const ang = Math.atan2(dy, dx) * 180 / PI;
  return (
    <>
      {[0, 1, 2, 3].map((k) => {
        const d = t - (at + k * BEAT * 0.25);
        if (d < 0 || d > 0.42) return null;
        const u = d / 0.42;
        const px = from.x + dx * 0.8 * easeOut(u), py = from.y + dy * 0.8 * easeOut(u);
        const r = 30 + 46 * u;
        return (
          <svg key={k} width={200} height={200} viewBox="-100 -100 200 200" style={{ position: "absolute", left: px - 100, top: py - 100, rotate: `${ang}deg`, opacity: 1 - u * u, overflow: "visible" }}>
            <path d={`M ${-r * 0.35} ${-r} A ${r} ${r} 0 0 1 ${-r * 0.35} ${r}`} fill="none" stroke={INK} strokeWidth={20} strokeLinecap="round" transform={flip ? "scale(-1 1)" : undefined} />
            <path d={`M ${-r * 0.35} ${-r} A ${r} ${r} 0 0 1 ${-r * 0.35} ${r}`} fill="none" stroke={GREEN} strokeWidth={11} strokeLinecap="round" transform={flip ? "scale(-1 1)" : undefined} />
          </svg>
        );
      })}
    </>
  );
};

export const Lineup: React.FC<{ t: number }> = ({ t }) => {
  if (t < b(14) || t >= b(16)) return null;
  const cam = lineupCam(t);
  const bodies = FRIENDS.map((_, i) => body(i, t));
  const whip = easeIn(clamp01((t - WHIP) / (b(16) - WHIP)));
  const talkOn = t >= TALK - 0.05 && t < POSE - 0.1;
  const samS = toScreen(cam, [bodies[SAM].head[0], bodies[SAM].head[1] - 0.35, bodies[SAM].head[2]]);
  const riyaS = toScreen(cam, [bodies[RIYA].head[0], bodies[RIYA].head[1] - 0.35, bodies[RIYA].head[2]]);
  const flash = t < b(14) + 0.12 ? 1 - (t - b(14)) / 0.12 : 0;
  return (
    <div style={{ position: "absolute", inset: 0, background: PURPLE, overflow: "hidden" }}>
      <Stripes t={t} shift={-cam.pos[0] * 90 + whip * 900} />
      <div style={{ position: "absolute", inset: 0, filter: whip > 0.05 ? `blur(${whip * 18}px)` : undefined }}>
        <CrewStage cam={cam}>
          {bodies.map((bd, i) => (bd.visible ? <CrewCharacter key={i} look={FRIENDS[i].look} pose={bd.pose} p={bd.p} yaw={bd.yaw} squash={bd.squash} /> : null))}
          <Dust t={t} />
          {[0, 1].map((k) => {
            const at = TALK + k * BEAT * 0.5;
            const u = clamp01((t - at) / 0.55);
            return u > 0 && u < 1 ? <FloorRing key={k} p={[slotX(SAM) - 0.1, 0, slotZ(SAM)]} r={0.35 + 1.5 * easeOut(u)} w={0.12} color={GREEN} opacity={0.9 * (1 - u)} /> : null;
          })}
        </CrewStage>
        {READY.map((r, i) => {
          const s = toScreen(cam, bodies[i].head);
          return <Ring key={i} t={t} at={r + 0.06} x={s.x} y={s.y - 30} r={110} color={GREEN} width={12} dur={0.4} />;
        })}
        {/* name tags pinned to heads */}
        {bodies.map((bd, i) => {
          if (!bd.visible) return null;
          const s = toScreen(cam, bd.head);
          // Tags clear away on the pose (staggered from the centre out) so the pose frame is clean.
          const gone = clamp01((t - (POSE - 0.08 + Math.abs(i - 3.5) * 0.012)) / 0.1);
          if (gone >= 1) return null;
          return <Tag key={i} t={t} at={LAND[i] + 0.04} readyAt={READY[i]} name={FRIENDS[i].name} cls={CLASS_COLORS[FRIENDS[i].cls]} x={s.x} y={s.y} scale={1 - easeIn(gone)} />;
        })}
        {talkOn ? <VoiceArcs t={t} at={TALK} from={samS} to={riyaS} /> : null}
        {talkOn ? <VoiceArcs t={t} at={TALK + BEAT * 0.75} from={riyaS} to={samS} /> : null}
      </div>
      <StarBurst t={t} at={POSE} x={960} y={420} n={14} seed={3} power={900} size={42} colors={[GOLD, GREEN, "#ffffff", "#ff9a3c"]} />
      {/* titles */}
      <div style={{ position: "absolute", left: 0, right: 0, top: 34, display: "flex", justifyContent: "center", translate: `${-whip * 700}px 0` }}>
        <Slam t={t} at={b(14)} text="PLAY WITH" size={210} color="#ffffff" out={HOP1} tilt={-6} />
        <Slam t={t} at={HOP1} text="UP TO 8 FRIENDS" size={220} color={GOLD} tilt={5} />
      </div>
      {flash > 0 ? <div style={{ position: "absolute", inset: 0, background: "#fff", opacity: flash * 0.4 }} /> : null}
    </div>
  );
};
