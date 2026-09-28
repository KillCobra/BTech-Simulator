// Act "dodge": the 3D shots. Each is one <Stage3D> with its own camera (a pure function of t, exported so the
// 2D overlays can pin to heads with toScreen).
import React, { useMemo } from "react";
import * as THREE from "three";
import { track } from "../../kit/spring";
import type { Cam } from "../../launch/camera3d";
import { cctv, classroom, corridor } from "../../launch/sets";
import { Character, G, Voxels } from "../../launch/three";
import { P, type Box, type V3 } from "../../launch/voxel";
import { b, BEAT } from "../cues";
import { Stage3D } from "../Stage3D";
import {
  BLAME, CCTV_POS, CCTV_TILT, CUT_B, IRIS, cctvSweep, classActors, clamp01, CRASH, excuseActors, FRIEND_SEAT, heroShotAX, lerp, PI, shotAActors, shotBHero,
  SPIN, type Actor,
} from "./world";

const inExpo = (u: number) => (u <= 0 ? 0 : Math.pow(2, 10 * (clamp01(u) - 1)));
const smooth = (u: number) => {
  const x = clamp01(u);
  return x * x * (3 - 2 * x);
};
const mix3 = (a: V3, c: V3, u: number): V3 => [lerp(a[0], c[0], u), lerp(a[1], c[1], u), lerp(a[2], c[2], u)];

const Cast: React.FC<{ actors: Actor[] }> = ({ actors }) => (
  <>
    {actors.map((a) => (
      <Character key={a.id} look={a.look} pose={a.pose} p={a.p} yaw={a.yaw} squash={a.squash ?? 1} />
    ))}
  </>
);

// ------------------------------------------------------------------ corridor dressing shared by A, B and the excuse
const Hall: React.FC = () => {
  const hall = useMemo(() => corridor(), []);
  // Verandah pillars and a low parapet on the open side (campus_builder.gd verandah), a door into Class B.
  const extra = useMemo(() => {
    const L: Box[] = [];
    for (let i = 0; i < 8; i++) {
      const x = -10 + i * 4;
      L.push({ c: [x, 1.7, -3.05], s: [0.4, 3.4, 0.4], col: P.TRIM });
      L.push({ c: [x, 0.05, -3.05], s: [0.5, 0.1, 0.5], col: P.WALL_SHADE });
    }
    L.push({ c: [3, 3.3, -3.05], s: [26, 0.3, 0.45], col: P.WALL_SHADE });
    // Door frame between the locker runs.
    L.push({ c: [1.4, 1.1, 3.02], s: [1.2, 2.2, 0.06], col: "#c9703a" });
    L.push({ c: [1.8, 1.15, 2.98], s: [0.06, 0.06, 0.12], col: P.METAL });
    L.push({ c: [1.4, 2.35, 3.0], s: [1.4, 0.12, 0.1], col: P.WOOD_DARK });
    return L;
  }, []);
  return (
    <>
      <Voxels boxes={hall} />
      <Voxels boxes={extra} />
    </>
  );
};

/** The game's CCTV (campus_builder.gd add_cctv): mount, body tilted down, a red LED blinking on the 8ths, its view cone. */
const CCTVRig: React.FC<{ t: number; cone?: number; scale?: number }> = ({ t, cone = 1, scale = 1.6 }) => {
  const parts = useMemo(() => cctv(), []);
  const yaw = cctvSweep(t);
  const blink = Math.floor(t / (BEAT / 2)) % 2 === 0;
  const len = 5.2, rad = len * Math.tan(0.22);
  return (
    <G p={CCTV_POS}>
      <Voxels boxes={[{ c: [0, 0.3, 0.12], s: [0.08, 0.5, 0.08], col: P.METAL_DARK }]} />
      <G s={scale}>
        <Voxels boxes={parts.mount} />
      </G>
      <G r={[0, yaw, 0]}>
        <G r={[CCTV_TILT, 0, 0]}>
          <G s={scale}>
            <Voxels boxes={parts.body} />
            <mesh position={[0.06, 0.05, -0.306]}>
              <boxGeometry args={[0.035, 0.035, 0.012]} />
              <meshBasicMaterial color={blink ? "#ff3030" : "#4a1010"} toneMapped={false} />
            </mesh>
          </G>
          {cone > 0 ? (
            <mesh position={[0, -0.02, -0.5 * scale - len / 2]} rotation={[PI / 2, 0, 0]}>
              <coneGeometry args={[rad, len, 40, 1, true]} />
              <meshBasicMaterial color="#ff4a4a" transparent opacity={0.11 * cone} depthWrite={false} toneMapped={false} side={THREE.DoubleSide} />
            </mesh>
          ) : null}
        </G>
      </G>
    </G>
  );
};

/** Where the CCTV's view lands on the floor: a soft red spot that sweeps with it (reads with no sound). */
const CctvSpot: React.FC<{ t: number }> = ({ t }) => {
  const yaw = cctvSweep(t);
  const d = CCTV_POS[1] / Math.tan(-CCTV_TILT);
  const x = CCTV_POS[0] - Math.sin(yaw) * d, z = CCTV_POS[2] - Math.cos(yaw) * d;
  const r = (CCTV_POS[1] / Math.sin(-CCTV_TILT)) * Math.tan(0.22);
  return (
    <mesh position={[x, 0.02, z]} rotation={[-PI / 2, 0, 0]}>
      <circleGeometry args={[r * 1.35, 48]} />
      <meshBasicMaterial color="#ff3030" transparent opacity={0.34} depthWrite={false} toneMapped={false} />
    </mesh>
  );
};

// ------------------------------------------------------------------ shot A: crouch-walking behind her back (6.3.5 - 7.2)
export function camA(t: number): Cam {
  const hx = heroShotAX(t);
  const u = clamp01((t - IRIS) / (CUT_B - IRIS));
  // Low, three-quarter from behind the hero; drifts in as he closes on her back.
  return {
    pos: [hx - 1.7 + 0.7 * u, 0.85 + 0.05 * u, -3.0 + 0.35 * u],
    look: [hx + 0.95, 0.9, 0.35],
    fov: 44 - 4 * smooth(u),
  };
}
export const ShotA: React.FC<{ t: number }> = ({ t }) => (
  <Stage3D cam={camA(t)} bg="#e7d2aa" fog={[10, 30]} shadowTarget={[heroShotAX(t) + 1, 0, 0.5]} shadowSize={9}>
    <Hall />
    <Cast actors={shotAActors(t)} />
  </Stage3D>
);

// ------------------------------------------------------------------ shot B: under the CCTV (7.2 - 8.0)
export function camB(t: number): Cam {
  const base: Cam = {
    pos: mix3([12.4, 0.95, 0.1], [11.6, 1.0, 0.3], smooth((t - CUT_B) / (BEAT * 1.5))),
    look: [5.6, 1.45, 1.3],
    fov: 46,
  };
  // Handoff: the last half beat dives into the lens.
  const w = inExpo((t - b(7, 3.5)) / (BEAT * 0.5));
  if (w <= 0) return base;
  const yaw = cctvSweep(t);
  const lens: V3 = [CCTV_POS[0] - Math.sin(yaw) * 0.75, CCTV_POS[1] - 0.45, CCTV_POS[2] - Math.cos(yaw) * 0.75];
  return { pos: mix3(base.pos, lens, w), look: mix3(base.look, [CCTV_POS[0], CCTV_POS[1] - 0.1, CCTV_POS[2]], w), fov: lerp(46, 30, w) };
}
export const ShotB: React.FC<{ t: number }> = ({ t }) => (
  <Stage3D cam={camB(t)} bg="#e7d2aa" fog={[12, 34]} shadowTarget={[7, 0, 0.5]} shadowSize={10}>
    <Hall />
    <CCTVRig t={t} />
    <CctvSpot t={t} />
    <Cast actors={[shotBHero(t)]} />
  </Stage3D>
);

// ------------------------------------------------------------------ classroom: who's talking?! (8.0 - 9.0)
export function camClass(t: number): Cam {
  if (t < b(8, 2)) {
    const wide: V3 = [2.6, 3.1, -5.7];
    return {
      pos: [
        track(t, [[0, wide[0]], [SPIN, 0.1]], CRASH),
        track(t, [[0, wide[1]], [SPIN, 1.72]], CRASH),
        track(t, [[0, wide[2]], [SPIN, 0.6]], CRASH),
      ],
      look: [
        track(t, [[0, 0.3], [SPIN, -0.4]], CRASH),
        track(t, [[0, 0.55], [SPIN, 1.62]], CRASH),
        track(t, [[0, 0.7], [SPIN, 3.85]], CRASH),
      ],
      fov: track(t, [[0, 48], [SPIN, 34]], CRASH) - 4 * smooth((t - SPIN - 0.15) / (BEAT * 1.6)),
    };
  }
  // 8.2: the two of them from the front, a slow push; 8.3.5 whips up and out.
  const u = smooth((t - b(8, 2)) / (BEAT * 1.6));
  const w = 0; // 9.0 is a hard cut to the title
  // each word of the claim punches the lens in a touch
  const punch = [0, 0.25, 0.5, 0.75].reduce((a, k) => a + (t > b(8, 2 + k) ? Math.exp(-(t - b(8, 2 + k)) / 0.07) : 0), 0);
  return {
    pos: [0.62, lerp(1.25, 1.2, u) + w * 1.2, lerp(-0.45, -0.85, u)],
    look: [0.6, 1.14 + w * 3.5, -2.66],
    fov: lerp(44, 40, u) - 1.6 * punch + w * 20,
  };
}

/** Voice rings on the floor: the whisper (1.5 m) and the laugh (8 m). */
const VoiceRings: React.FC<{ t: number }> = ({ t }) => {
  const c: V3 = [FRIEND_SEAT[0], 0.03, FRIEND_SEAT[2]];
  const rings: React.ReactNode[] = [];
  // Whisper: small ripples on the 16ths, capped at 1.5 m.
  for (let k = 0; k < 3; k++) {
    const start = b(8) - 0.1 + k * (BEAT / 4);
    const d = t - start;
    if (d < 0 || t > b(8, 0.5) + 0.25) continue;
    const r = Math.min(1.5, 0.2 + d * 6);
    const o = 0.9 * Math.max(0, 1 - Math.max(0, t - b(8, 0.5)) * 4);
    rings.push(
      <mesh key={`w${k}`} position={c} rotation={[-PI / 2, 0, 0]}>
        <ringGeometry args={[Math.max(0.01, r - 0.05), r + 0.05, 64]} />
        <meshBasicMaterial color="#7fe0a0" transparent opacity={o} depthWrite={false} toneMapped={false} side={THREE.DoubleSide} />
      </mesh>,
    );
  }
  // Laugh: fat rings racing out to 8 m, the first one reaching the teacher on the spin.
  for (let k = 0; k < 4; k++) {
    const start = b(8, 0.5) + k * (BEAT / 4);
    const d = t - start;
    if (d < 0) continue;
    const r = 0.3 + (d / (SPIN - b(8, 0.5))) * 7.7;
    if (r > 8.6) continue;
    const o = r > 8 ? Math.max(0, 1 - (r - 8) / 0.6) : 0.85;
    rings.push(
      <mesh key={`l${k}`} position={c} rotation={[-PI / 2, 0, 0]}>
        <ringGeometry args={[Math.max(0.01, r - 0.09), r + 0.09, 96]} />
        <meshBasicMaterial color="#ff6a5a" transparent opacity={o * (1 - k * 0.18)} depthWrite={false} toneMapped={false} side={THREE.DoubleSide} />
      </mesh>,
    );
  }
  return <>{rings}</>;
};

const Board: React.FC = () => {
  // A few chalk strokes on the board (the lesson she's writing).
  const chalk = useMemo(() => {
    const L: Box[] = [];
    const cols = "#f3f6ee";
    const words = [[-1.4, 2.15, 0.9], [-0.35, 2.15, 0.6], [0.45, 2.15, 0.7], [-1.35, 1.85, 0.5], [-0.7, 1.85, 1.1], [0.55, 1.85, 0.4], [-1.4, 1.55, 0.8]];
    for (const [x, y, w] of words) L.push({ c: [x + w / 2, y, 4.52], s: [w, 0.06, 0.01], col: cols });
    return L;
  }, []);
  return <Voxels boxes={chalk} shadow={false} />;
};

export const ShotClass: React.FC<{ t: number }> = ({ t }) => {
  const room = useMemo(() => classroom(), []);
  return (
    <Stage3D cam={camClass(t)} bg="#f3e3c3" shadowTarget={[0, 0, 0.5]} shadowSize={9}>
      <Voxels boxes={room} />
      <Board />
      <VoiceRings t={t} />
      <Cast actors={classActors(t)} />
    </Stage3D>
  );
};

// ------------------------------------------------------------------ the excuse (9.0 - 10.0)
export function camExcuse(t: number): Cam {
  const u = smooth((t - b(10)) / (BEAT * 6));
  const toFriend = track(t, [[0, 0], [BLAME, 1]], CRASH);
  const whip = inExpo((t - b(11, 3.5)) / (b(12) - b(11, 3.5)));
  return {
    pos: [lerp(0.15, 0.0, u) - 0.45 * toFriend, 1.45, lerp(-3.9, -3.5, u) + 0.5 * toFriend],
    look: [lerp(0.05, 0.0, u) - 0.8 * toFriend + whip * 7, 1.28 + 0.28 * toFriend, 0.6],
    fov: lerp(40, 38, u) - 3 * toFriend + whip * 10,
  };
}
export const ShotExcuse: React.FC<{ t: number }> = ({ t }) => (
  <Stage3D cam={camExcuse(t)} bg="#e7d2aa" fog={[10, 30]} shadowTarget={[0, 0, 0.6]} shadowSize={8}>
    <Hall />
    <Cast actors={excuseActors(t)} />
  </Stage3D>
);
