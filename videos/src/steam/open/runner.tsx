// Bars 4-5: the voxel hero sprinting over flat colour fields (transparent 3D over 2D stripes).
// Bar 4: drops in on 4.0, vaults a bench on 4.2, dashes out right on 4.3.5.
// Bar 5: runs back in from the left on 5.0, the teacher (5.1) and the guard (5.2) give chase.
import React, { useMemo } from "react";
import { step } from "../../kit/spring";
import type { Cam } from "../../launch/camera3d";
import { bench } from "../../launch/sets";
import { Character, G, Voxels } from "../../launch/three";
import { CAST, walkPose, type Box, type Pose, type V3 } from "../../launch/voxel";
import { b, BEAT } from "../cues";
import { ShadowFloor } from "./stage";

const PI = Math.PI;
const clamp01 = (v: number) => Math.min(1, Math.max(0, v));

export const SNEAK_CAM: Cam = { pos: [0, 1.3, 6.3], look: [0, 1.3, 0], fov: 30 };
export const CHASE_CAM: Cam = { pos: [0, 1.6, 7.3], look: [0, 1.6, 0], fov: 30 };

const RUN_YAW = -PI / 2 - 0.42; // running screen-right, turned a little toward camera

/** Sprint cycle with more lean and knee than the game's walk (it's a trailer). */
function sprint(t: number, rate = 17, amount = 1.25, lean = 0.32): Pose {
  const p = walkPose(t * rate, amount, 0, true);
  return { ...p, torsoX: -lean, headX: lean * 0.6, armLX: p.armLX * 1.25, armRX: p.armRX * 1.25, hipY: p.hipY + 0.03 };
}

// ---------------------------------------------------------------- bar 4
export const HERO4_X = 1.5;
const DROP = b(4) + 0.02; // feet hit the field just after the downbeat (reads as on it)
const VAULT = b(4, 2);
const DASH = b(4, 3.5);

export function hero4(t: number) {
  // drop in from above
  const fall = clamp01((t - (DROP - 0.16)) / 0.16);
  let y = t < DROP ? 3.2 * (1 - fall * fall) : 0;
  // vault: jump arc centred on VAULT
  const j = (t - (VAULT - 0.16)) / 0.42;
  if (j > 0 && j < 1) y += 1.0 * 4 * j * (1 - j);
  // squash on landings
  let sx = 1, sy = 1;
  for (const at of [DROP, VAULT + 0.26]) {
    const d = t - at;
    if (d >= 0 && d < 0.5) {
      const w = 0.32 * Math.exp(-d * 11) * Math.cos(d * 26);
      sx *= 1 + w * 0.7;
      sy *= 1 - w;
    }
  }
  if (t < DROP && t > DROP - 0.16) { sy *= 1.25; sx *= 0.85; } // stretch while falling
  // dash out right: expo, with a horizontal smear
  const dash = clamp01((t - DASH) / (BEAT / 2));
  const x = HERO4_X + 9 * dash * dash;
  if (dash > 0) { sx *= 1 + 0.9 * Math.sin(dash * PI * 0.5); sy *= 1 - 0.18 * dash; }
  return { p: [x, y, 0] as V3, sx, sy, air: (j > 0 && j < 1) || t < DROP };
}

/** Scroll speed (m/s of ground) and its integral, for the stripes and the bench. */
export const speed4 = (t: number) => 6 + 10 * clamp01((t - b(4, 3)) / (BEAT)) ** 2;
export function scroll4(t: number) {
  const d = Math.max(0, t - b(4));
  const r = Math.max(0, t - b(4, 3));
  return 6 * d + (10 / 3) * Math.min(r, BEAT) ** 3 / (BEAT * BEAT) + (r > BEAT ? 10 * (r - BEAT) : 0);
}

export const SneakScene: React.FC<{ t: number }> = ({ t }) => {
  const h = hero4(t);
  const benchBoxes = useMemo(() => { const L: Box[] = []; bench(L, 0, 0); return L; }, []);
  // the bench slides in at the ground speed and passes under the hero at VAULT
  const benchX = HERO4_X + (scroll4(VAULT) - scroll4(t)) + 0.2;
  let pose = sprint(t);
  if (h.air) pose = { ...pose, legL: 1.2, legR: -0.7, armLX: 2.0, armRX: 2.3, torsoX: -0.35 };
  if (t < DROP) pose = { ...pose, legL: 0.3, legR: -0.2, armLX: 2.8, armRX: 2.8, armLZ: -0.5, armRZ: 0.5, torsoX: 0 };
  return (
    <>
      <ShadowFloor opacity={0.22} />
      {benchX > -8 && benchX < 9 ? (
        <G p={[benchX, 0, 0.1]} r={[0, PI / 2, 0]}><Voxels boxes={benchBoxes} /></G>
      ) : null}
      <G p={h.p} s={[h.sx, h.sy, h.sx]}>
        <Character look={CAST.hero} pose={pose} yaw={RUN_YAW} />
      </G>
    </>
  );
};

// ---------------------------------------------------------------- bar 5
export const CHASE_HERO_X = 1.7;
export function chase5(t: number) {
  const enter = (at: number, from: number, to: number, len = 0.32) => {
    const u = clamp01((t - at) / len);
    return from + (to - from) * (1 - Math.pow(1 - u, 3));
  };
  const heroX = enter(b(5) - 0.08, -9, CHASE_HERO_X, 0.34) + 0.12 * Math.sin(t * 5);
  const lunge = step(t - b(5, 3), { stiffness: 500, damping: 16 });
  const teachX = enter(b(5, 1) - 0.06, -10, -0.5, 0.3) + 0.6 * lunge * Math.exp(-Math.max(0, t - b(5, 3)) * 3);
  const guardX = enter(b(5, 2) - 0.06, -11, -2.5, 0.3) + 0.08 * Math.sin(t * 4 + 1);
  // hero dodges the grab: a hop forward on 5.3
  const hj = (t - b(5, 3)) / 0.36;
  const heroY = hj > 0 && hj < 1 ? 0.55 * 4 * hj * (1 - hj) : 0;
  return { heroX: heroX + 0.7 * (t > b(5, 3) ? 1 - Math.exp(-(t - b(5, 3)) * 6) : 0), heroY, teachX, guardX, lunge };
}

export const ChaseScene: React.FC<{ t: number }> = ({ t }) => {
  const c = chase5(t);
  const hero = sprint(t, 18);
  // look back over the shoulder on 5.2
  hero.headY = -1.1 * (step(t - b(5, 2), { stiffness: 380, damping: 14 }) - step(t - b(5, 3), { stiffness: 380, damping: 14 }));
  const air = c.heroY > 0.01;
  const hp: Pose = air ? { ...hero, legL: 1.2, legR: -0.6, armLX: 2.2, armRX: -0.8 } : hero;
  const tp = sprint(t + 0.13, 16, 1.35, 0.36);
  tp.armRX = 1.45 + 0.25 * c.lunge; // reaching
  const gp = sprint(t + 0.27, 16.5, 1.35, 0.34);
  gp.armLX = 2.7; // arm up, "stop!"
  const heroSq = 1 + 0.2 * Math.exp(-Math.max(0, t - (b(5) + 0.26)) * 10) * Math.cos(Math.max(0, t - (b(5) + 0.26)) * 26) * (t > b(5) + 0.26 ? 1 : 0);
  return (
    <>
      <ShadowFloor opacity={0.25} />
      <G p={[c.heroX, c.heroY, 0.4]} s={[1 / Math.sqrt(heroSq), heroSq, 1 / Math.sqrt(heroSq)]}>
        <Character look={CAST.hero} pose={hp} yaw={RUN_YAW} />
      </G>
      <Character look={CAST.teacher} pose={tp} p={[c.teachX, 0, -0.1]} yaw={RUN_YAW + 0.1} />
      <Character look={CAST.guard} pose={gp} p={[c.guardX, 0, -0.6]} yaw={RUN_YAW + 0.15} />
    </>
  );
};
