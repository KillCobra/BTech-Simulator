// Per-act 3D camera: a pure function of t, shared by the three.js rig and by the 2D overlays
// (so speech bubbles and "!" marks pin to real heads).
import * as THREE from "three";
import { track, type SpringConfig } from "../kit/spring";
import { ACT, b, inAct } from "./cues";
import type { V3 } from "./voxel";

export type Cam = { pos: V3; look: V3; fov: number; roll?: number };
type Key = [time: number, pos: V3, look: V3, fov: number];

const HEAVY: SpringConfig = { stiffness: 90, damping: 20 };
const CRASH: SpringConfig = { stiffness: 900, damping: 42 };

function keyed(t: number, keys: Key[], cfg: SpringConfig = HEAVY): Cam {
  const ch = (f: (k: Key) => number) => track(t, keys.map((k) => [k[0], f(k)] as const), cfg);
  return {
    pos: [ch((k) => k[1][0]), ch((k) => k[1][1]), ch((k) => k[1][2])],
    look: [ch((k) => k[2][0]), ch((k) => k[2][1]), ch((k) => k[2][2])],
    fov: Math.exp(ch((k) => Math.log(k[3]))),
  };
}

const lin = (t: number, a: number, b_: number, p0: V3, p1: V3, e = (u: number) => u): V3 => {
  const u = e(Math.min(1, Math.max(0, (t - a) / (b_ - a))));
  return [p0[0] + (p1[0] - p0[0]) * u, p0[1] + (p1[1] - p0[1]) * u, p0[2] + (p1[2] - p0[2]) * u];
};
const smooth = (u: number) => u * u * (3 - 2 * u);

export function camAt(t: number): Cam {
  // 1. Classroom: wide push, then a close-up on the hero at bar 1.
  if (t < b(1)) {
    return { pos: lin(t, -0.3, b(1), [5.2, 3.9, 4.2], [2.9, 2.5, 2.3], smooth), look: lin(t, 0, b(1), [-0.6, 0.7, -1.2], [0.0, 0.95, -0.9], smooth), fov: 40 };
  }
  if (t < b(2, 0.5)) {
    const base = { pos: lin(t, b(1), b(2), [0.95, 1.45, 0.75], [0.7, 1.35, 0.35], smooth), look: lin(t, b(1), b(2), [0.0, 1.12, -0.9], [-0.1, 1.15, -0.9], smooth), fov: 34 };
    // Whip up and out on the "and" of beat 3 into the chapter stamp.
    const w = Math.min(1, Math.max(0, (t - b(1, 3.5)) / (b(2, 0.5) - b(1, 3.5))));
    const e = w * w * w;
    return { pos: [base.pos[0] + e * 2, base.pos[1] + e * 4, base.pos[2] - e * 3], look: [base.look[0], base.look[1] + e * 5, base.look[2] + e * 2], fov: base.fov + e * 20 };
  }
  // 3. Someone ruins it: wide from the back, crash-zoom to the teacher as they turn.
  if (inAct(t, ACT.ruin)) {
    return keyed(t, [
      [b(4) - 1, [-4.6, 3.3, -5.2], [0.9, 0.9, 1.0], 44],
      [b(4, 0), [-4.2, 3.1, -4.8], [0.9, 0.9, 1.0], 42],
      [b(4, 2), [-0.4, 1.85, 1.3], [0.6, 1.55, 3.7], 30],
    ], t < b(4, 2) ? HEAVY : CRASH);
  }
  if (inAct(t, ACT.cctv)) {
    return { pos: lin(t, b(5), b(6), [2.6, 1.7, -1.6], [2.0, 1.8, -1.1], smooth), look: [0.2, 2.35, 2.5], fov: 38 };
  }
  if (inAct(t, ACT.excuse)) {
    return { pos: lin(t, b(6), b(7), [2.4, 1.55, -2.9], [2.0, 1.5, -2.5], smooth), look: [-0.4, 1.35, 0.2], fov: 40 };
  }
  if (inAct(t, ACT.trolley)) {
    return { pos: lin(t, b(7), b(7, 2), [-0.8, 0.9, -3.6], [-1.4, 1.0, -4.0], (u) => 1 - Math.pow(1 - u, 3)), look: [0.9, 0.8, 0.2], fov: 38 };
  }
  if (inAct(t, ACT.paper)) {
    return { pos: [0.4, 1.7, -5.4], look: lin(t, b(7, 2), b(7, 3), [-0.6, 1.35, 0], [1.5, 1.45, 0]), fov: 40 };
  }
  if (inAct(t, ACT.spray) || inAct(t, ACT.test)) {
    return { pos: lin(t, b(7, 3), b(9), [1.4, 1.7, -2.9], [0.9, 1.6, -2.2], smooth), look: [0.2, 1.1, 0.8], fov: 40 };
  }
  if (inAct(t, ACT.panic)) {
    // Dolly back in front of the charging staff; freeze-zoom on the half beat before the drop.
    const pos = lin(t, b(9), b(9, 3.5), [-1.0, 1.2, -0.3], [-5.2, 1.1, -0.3]);
    const z = Math.min(1, Math.max(0, (t - b(9, 3.5)) / (b(10) - b(9, 3.5))));
    return { pos, look: [6, 1.25, -0.2], fov: 46 - 14 * z * z };
  }
  if (inAct(t, ACT.chase)) {
    const x = -14 + (t - b(10)) * 7.6;
    return { pos: [x + 1.2, 1.6, -5.4], look: [x + 1.8, 1.0, -8.5], fov: 44 };
  }
  if (t >= b(12) && t < b(13, 2)) {
    return { pos: lin(t, b(12), b(13, 2), [4.2, 2.0, 11.2], [3.4, 2.3, 12.4], smooth), look: [-0.4, 1.3, 2.2], fov: 40 };
  }
  // Logo island.
  return { pos: lin(t, b(13, 2), b(16), [7.6, 4.2, -8.4], [6.4, 3.5, -7.2], (u) => 1 - Math.pow(1 - u, 2)), look: [-1.4, 1.05, -1.9], fov: 32 };
}

const _cam = new THREE.PerspectiveCamera(40, 1920 / 1080, 0.05, 400);
const _v = new THREE.Vector3();
export function applyCam(camera: THREE.PerspectiveCamera, c: Cam) {
  camera.position.set(...c.pos);
  camera.up.set(0, 1, 0);
  camera.lookAt(...c.look);
  if (c.roll) camera.rotateZ(c.roll);
  camera.fov = c.fov;
  camera.aspect = 1920 / 1080;
  camera.near = 0.05;
  camera.far = 400;
  camera.updateProjectionMatrix();
  camera.updateMatrixWorld();
}

/** Screen position (px) of a world point for the camera at t. */
export function project(t: number, p: V3): { x: number; y: number; behind: boolean } {
  applyCam(_cam, camAt(t));
  _v.set(...p).project(_cam);
  return { x: (_v.x * 0.5 + 0.5) * 1920, y: (-_v.y * 0.5 + 0.5) * 1080, behind: _v.z > 1 };
}
