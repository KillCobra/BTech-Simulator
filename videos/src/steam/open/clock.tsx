// A chunky voxel alarm clock (twin bells, hammer, feet) that rings on 0.0 and whips its hands to 9:00.
// Built from boxes like the game's props, rendered with the game's bevelled voxel material.
import React, { useMemo } from "react";
import { step } from "../../kit/spring";
import * as THREE from "three";
import { boxGeometry, G, Voxels } from "../../launch/three";
import type { Box, V3 } from "../../launch/voxel";
import { b, BEAT } from "../cues";

const bx = (list: Box[], c: V3, s: V3, col: string) => list.push({ c, s, col });

const RED = "#e0524f", RED_DARK = "#b23e3b", GOLD = "#ffc93c", GOLD_DARK = "#e0a52a", FACE = "#f4f4f0", INK = "#2a2230", METAL = "#9aa3ad";
export const R = 0.62; // casing radius (m)
const STEP = 0.08;

/** A voxel disc in the XY plane: one box per row, widths snapped to the grid. */
function disc(list: Box[], r: number, z: number, depth: number, col: string, colEdge?: string) {
  for (let y = -r + STEP / 2; y < r - 1e-6; y += STEP) {
    const w = Math.max(STEP, Math.round((2 * Math.sqrt(Math.max(0, r * r - y * y))) / STEP) * STEP);
    bx(list, [0, y, z], [w, STEP, depth], colEdge && Math.abs(y) > r - STEP * 1.5 ? colEdge : col);
  }
}

const FLAT = new THREE.MeshLambertMaterial({ vertexColors: true });
/** Boxes without the bevel (a clean clock face: the bevel would stripe every voxel row). */
const Flat: React.FC<{ boxes: readonly Box[] }> = ({ boxes }) => {
  const geo = useMemo(() => boxGeometry(boxes), [boxes]);
  return <mesh geometry={geo} material={FLAT} receiveShadow />;
};

function build() {
  const face: Box[] = [];
  const body: Box[] = [], bell: Box[] = [], hammer: Box[] = [], feet: Box[] = [], ticks: Box[] = [];
  disc(body, R, 0, 0.36, RED, RED_DARK);
  disc(body, R - 0.1, 0.17, 0.04, RED_DARK);
  disc(face, R - 0.14, 0.19, 0.02, FACE);
  // back plate and key
  disc(body, R - 0.2, -0.2, 0.04, RED_DARK);
  bx(body, [0, 0, -0.28], [0.06, 0.06, 0.12], METAL);
  bx(body, [0, 0, -0.35], [0.24, 0.1, 0.03], METAL);
  // top handle stub between the bells
  bx(body, [0, R + 0.02, 0], [0.14, 0.08, 0.12], METAL);
  // one bell, local: base at y 0, dome up
  bx(bell, [0, 0.02, 0], [0.08, 0.1, 0.08], METAL);
  bx(bell, [0, 0.1, 0], [0.4, 0.08, 0.4], GOLD_DARK);
  bx(bell, [0, 0.18, 0], [0.36, 0.08, 0.36], GOLD);
  bx(bell, [0, 0.26, 0], [0.28, 0.08, 0.28], GOLD);
  bx(bell, [0, 0.33, 0], [0.16, 0.06, 0.16], GOLD);
  bx(bell, [0, 0.38, 0], [0.06, 0.05, 0.06], GOLD_DARK);
  // hammer, local: pivot at y 0
  bx(hammer, [0, 0.14, 0], [0.04, 0.26, 0.04], METAL);
  bx(hammer, [0, 0.3, 0], [0.12, 0.08, 0.12], METAL);
  // feet, local: hang down from pivot
  bx(feet, [0, -0.08, 0], [0.1, 0.18, 0.12], METAL);
  bx(feet, [0, -0.19, 0], [0.16, 0.05, 0.16], "#6b737d");
  // 12 marks on the face
  for (let i = 0; i < 12; i++) {
    const a = (i / 12) * Math.PI * 2, long = i % 3 === 0;
    const r = R - 0.24;
    ticks.push({ c: [Math.sin(a) * r, Math.cos(a) * r, 0.205], s: long ? [0.05, 0.05, 0.02] : [0.035, 0.035, 0.02], col: long ? INK : "#8a8f99" });
  }
  return { body, face, bell, hammer, feet, ticks };
}

const HOUR: Box[] = [{ c: [0, 0.11, 0], s: [0.07, 0.24, 0.025], col: INK }];
const MINUTE: Box[] = [{ c: [0, 0.16, 0], s: [0.05, 0.36, 0.025], col: INK }];
const SECOND: Box[] = [{ c: [0, 0.14, 0], s: [0.022, 0.42, 0.02], col: RED }, { c: [0, -0.04, 0], s: [0.05, 0.08, 0.02], col: RED }];
const CAP: Box[] = [{ c: [0, 0, 0], s: [0.09, 0.09, 0.04], col: GOLD }];

// ---- the animation (pure functions of t)
const WOB = { stiffness: 380, damping: 11 };
const RINGS = [b(0, 0), b(0, 1), b(0, 2)];
/** 0..1 ringing intensity (bursts on beats 0-2, stops dead on the clunk at 0.3). */
export function ringing(t: number) {
  let e = 0;
  for (const at of RINGS) if (t >= at - 0.06) e = Math.max(e, Math.exp(-Math.max(0, t - at) / 0.55));
  return t >= b(0, 3) ? 0 : e;
}
/** Hop height (m) and landing squash for each ring. */
export function hop(t: number) {
  let y = 0, sq = 1;
  for (const at of RINGS) {
    const d = t - at + 0.06; // frame 0 is already airborne
    const air = BEAT * 0.62;
    if (d > 0 && d < air) {
      const u = d / air;
      y = Math.max(y, 0.24 * 4 * u * (1 - u));
      sq = 1 + 0.12 * (1 - Math.abs(2 * u - 1)); // stretch in the air
    } else if (d >= air && d < air + 0.3) sq = Math.min(sq, 1 - 0.22 * Math.exp(-(d - air) * 14) * Math.cos((d - air) * 30));
  }
  // the clunk on 0.3: squash down hard
  const c = t - b(0, 3);
  if (c >= 0) sq *= 1 - 0.2 * Math.exp(-c * 11) * Math.cos(c * 26);
  return { y, sq };
}
/** Hands: minute whips two turns to 12, hour sweeps 7 -> 9; second hand ticks on beats from bar 1. */
export function hands(t: number) {
  const u = Math.min(1, Math.max(0, t / b(0, 3)));
  const whip = 1 - Math.pow(1 - u, 2.2);
  const settle = step(t - b(0, 3), WOB);
  // radians, clockwise positive (we rotate by -a about z)
  const minute = t < b(0, 3) ? -Math.PI * 4 * (1 - whip) - 0.35 : -0.35 * (1 - settle);
  const hour = t < b(0, 3) ? (7 / 12) * Math.PI * 2 + ((9 - 7) / 12) * Math.PI * 2 * whip - 0.05 : (9 / 12) * Math.PI * 2 - 0.05 * (1 - settle);
  let ticks = 0;
  for (let k = 0; k < 64; k++) {
    const at = b(0, 3) + k * BEAT;
    if (t < at) break;
    ticks += step(t - at, { stiffness: 900, damping: 18 });
  }
  const second = (ticks * Math.PI * 2) / 60 + (t < b(0, 3) ? t * 30 : 0);
  return { minute, hour, second };
}

export const AlarmClock: React.FC<{ t: number; p?: V3; r?: V3; s?: number }> = ({ t, p = [0, 0, 0], r = [0, 0, 0], s = 1 }) => {
  const parts = useMemo(build, []);
  const ring = ringing(t);
  const { y, sq } = hop(t);
  const h = hands(t);
  // Shiver while ringing: fast, crunchy, changes every 1/32 note.
  const q = Math.floor(t / (BEAT / 8));
  const jit = (k: number) => Math.sin(q * 12.9898 + k * 78.233) * 43758.5453 % 1;
  const shiver = ring * 0.09;
  const rollZ = jit(1) * shiver * 1.2;
  const hammer = ring > 0.02 ? Math.sin(t * 2 * Math.PI * 16) * 0.55 * Math.min(1, ring * 1.5) : 0;
  return (
    <G p={[p[0] + jit(2) * shiver * 0.3, p[1] + y, p[2]]} r={r} s={s}>
      {/* squash about the feet */}
      <G p={[0, -R - 0.2, 0]} s={[1 / Math.sqrt(sq), sq, 1 / Math.sqrt(sq)]}>
        <G p={[0, R + 0.2, 0]} r={[0, 0, rollZ]}>
          <Voxels boxes={parts.body} />
          <Flat boxes={parts.face} />
          <Voxels boxes={parts.ticks} shadow={false} />
          <G p={[0, 0, 0.215]} r={[0, 0, -h.hour]}><Voxels boxes={HOUR} shadow={false} /></G>
          <G p={[0, 0, 0.235]} r={[0, 0, -h.minute]}><Voxels boxes={MINUTE} shadow={false} /></G>
          <G p={[0, 0, 0.255]} r={[0, 0, -h.second]}><Voxels boxes={SECOND} shadow={false} /></G>
          <G p={[0, 0, 0.27]}><Voxels boxes={CAP} shadow={false} /></G>
          {[-1, 1].map((side) => (
            <G key={side} p={[side * Math.sin(0.62) * (R - 0.02), Math.cos(0.62) * (R - 0.02), 0]} r={[0, 0, -side * (0.62 + ring * 0.08 * Math.sin(t * 90 + side))]}>
              <Voxels boxes={parts.bell} />
            </G>
          ))}
          <G p={[0, R + 0.04, 0.02]} r={[0, 0, hammer]}><Voxels boxes={parts.hammer} /></G>
          {[-1, 1].map((side) => (
            <G key={side} p={[side * 0.36, -R + 0.1, 0]} r={[0, 0, side * 0.45]}>
              <Voxels boxes={parts.feet} />
            </G>
          ))}
        </G>
      </G>
    </G>
  );
};
