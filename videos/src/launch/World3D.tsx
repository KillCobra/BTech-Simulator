// The film's single 3D layer. Sets and actors switch by act; the camera comes from camAt(t).
import { ThreeCanvas } from "@remotion/three";
import { useThree } from "@react-three/fiber";
import React, { useMemo } from "react";
import * as THREE from "three";
import { step } from "../kit/spring";
import { ACT, b, BEAT, inAct } from "./cues";
import { applyCam, camAt } from "./camera3d";
import { clamp01, rand, WOBBLE } from "./juice";
import { CHAI_GLASS, classroom, clouds, corridor, cctv, hash, island, outside, PAPER_BALL, SAMOSA, trolley } from "./sets";
import { actors } from "./stage";
import { Character, G, Voxels } from "./three";
import type { Box, V3 } from "./voxel";

const PI = Math.PI;
const SKY = "#8dd0ef";

const CamRig: React.FC<{ t: number }> = ({ t }) => {
  const camera = useThree((s) => s.camera) as THREE.PerspectiveCamera;
  applyCam(camera, camAt(t));
  return null;
};

function textTexture(text: string, opts: { w: number; h: number; size: number; color: string; bg?: string; font?: string }) {
  const c = document.createElement("canvas");
  c.width = opts.w;
  c.height = opts.h;
  const g = c.getContext("2d")!;
  if (opts.bg) {
    g.fillStyle = opts.bg;
    g.fillRect(0, 0, opts.w, opts.h);
  }
  g.fillStyle = opts.color;
  g.font = `${opts.size}px ${opts.font ?? "Jersey10"}`;
  g.textAlign = "center";
  g.textBaseline = "middle";
  g.fillText(text, opts.w / 2, opts.h / 2 + opts.size * 0.05);
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 8;
  return tex;
}

const Label: React.FC<{ text: string; p: V3; w: number; h: number; yaw?: number; color: string; bg?: string; px?: number }> = ({ text, p, w, h, yaw = 0, color, bg, px = 140 }) => {
  const tex = useMemo(() => textTexture(text, { w: Math.round(w * 200), h: Math.round(h * 200), size: px, color, bg }), [text, w, h, color, bg, px]);
  return (
    <mesh position={p} rotation={[0, yaw, 0]}>
      <planeGeometry args={[w, h]} />
      <meshBasicMaterial map={tex} transparent toneMapped={false} />
    </mesh>
  );
};

const Lights: React.FC<{ target: V3; tint?: string; sun?: number; amb?: number; size?: number }> = ({ target, tint = "#ffffff", sun = 1.9, amb = 1.0, size = 14 }) => {
  const light = useMemo(() => {
    const l = new THREE.DirectionalLight("#fff4e0", sun);
    l.castShadow = true;
    l.shadow.mapSize.set(2048, 2048);
    l.shadow.bias = -0.0004;
    l.shadow.normalBias = 0.02;
    return l;
  }, []);
  light.intensity = sun;
  const cam = light.shadow.camera as THREE.OrthographicCamera;
  cam.left = -size; cam.right = size; cam.top = size; cam.bottom = -size; cam.near = 0.5; cam.far = 80;
  cam.updateProjectionMatrix();
  light.position.set(target[0] + 9, target[1] + 16, target[2] - 11);
  light.target.position.set(...target);
  light.target.updateMatrixWorld();
  return (
    <>
      <hemisphereLight args={[tint, "#b8a888", amb]} />
      <primitive object={light} />
      <primitive object={light.target} />
    </>
  );
};

// ---------- props that move
const Samosas: React.FC<{ t: number; at: number; origin: V3 }> = ({ t, at, origin }) => {
  const d = t - at;
  if (d < 0) return null;
  return (
    <>
      {Array.from({ length: 7 }, (_, i) => {
        const vx = (rand(i) - 0.5) * 3.2 + 1.2, vy = 3.2 + rand(i + 5) * 2.2, vz = (rand(i + 9) - 0.5) * 2.6;
        let y = origin[1] + vy * d - 4.9 * d * d;
        const land = y < 0.05;
        y = Math.max(0.05, y);
        return (
          <G key={i} p={[origin[0] + vx * d, y, origin[2] + vz * d]} r={land ? [0, i, 0] : [d * 11 * (i % 2 ? 1 : -1), d * 7, d * 5]} s={1.6}>
            <Voxels boxes={SAMOSA} />
          </G>
        );
      })}
    </>
  );
};

const VoiceRings: React.FC<{ t: number; at: number; until: number; p: V3 }> = ({ t, at, until, p }) => {
  if (t < at || t > until + 0.6) return null;
  return (
    <>
      {[0, 1, 2, 3, 4].map((k) => {
        const start = at + k * (BEAT / 2);
        const d = t - start;
        if (d < 0 || start > until) return null;
        const r = 0.3 + d * 7.5;
        const o = Math.max(0, 0.75 - d * 0.9);
        return (
          <mesh key={k} position={p} rotation={[-PI / 2, 0, 0]}>
            <ringGeometry args={[r, r + 0.07, 64]} />
            <meshBasicMaterial color="#ffd24a" transparent opacity={o} depthWrite={false} toneMapped={false} side={THREE.DoubleSide} />
          </mesh>
        );
      })}
    </>
  );
};

const Confetti: React.FC<{ t: number; at: number; origin: V3 }> = ({ t, at, origin }) => {
  const d = t - at;
  const boxes = useMemo(() => {
    const cols = ["#e0524f", "#4f86e0", "#48b06a", "#9a62d6", "#ffd24a", "#ffffff", "#ff9a3c"];
    return Array.from({ length: 70 }, (_, i) => [{ c: [0, 0, 0] as V3, s: [0.16, 0.16, 0.05] as V3, col: cols[i % cols.length] }]);
  }, []);
  if (d < 0 || d > 2.4) return null;
  return (
    <>
      {boxes.map((bx, i) => {
        const a = rand(i) * PI * 2, sp = 3 + rand(i + 3) * 6;
        const vx = Math.cos(a) * sp * 0.7, vz = Math.sin(a) * sp * 0.5 + 2.5, vy = 6 + rand(i + 7) * 6;
        const drag = (1 - Math.exp(-d * 2.2)) / 2.2;
        const y = origin[1] + vy * drag - 2.2 * d * d;
        if (y < 0) return null;
        return (
          <G key={i} p={[origin[0] + vx * drag, y, origin[2] + vz * drag]} r={[d * (5 + rand(i) * 9), d * 6, d * 4]}>
            <Voxels boxes={bx} shadow={false} />
          </G>
        );
      })}
    </>
  );
};

// ---------- scenes
const ClassroomSet: React.FC<{ t: number }> = ({ t }) => {
  const room = useMemo(() => classroom(), []);
  const chalk = useMemo(() => textTexture("Thermodynamics", { w: 740, h: 200, size: 120, color: "#f3f6ee" }), []);
  // "Thermodynamics" writes itself left to right while the teacher chalks it (bars 0-1).
  const reveal = clamp01(0.35 + t / (b(2) * 0.8));
  chalk.offset.set(0, 0);
  return (
    <>
      <Voxels boxes={room} />
      <mesh position={[-1.85 * (1 - reveal) * 0 + 0, 1.93, 4.52]} rotation={[0, PI, 0]}>
        <planeGeometry args={[3.0, 0.8]} />
        <meshBasicMaterial map={chalk} transparent opacity={0.9} toneMapped={false} alphaTest={0.01} />
      </mesh>
    </>
  );
};

const CCTVRig: React.FC<{ t: number; p: V3 }> = ({ t, p }) => {
  const parts = useMemo(() => cctv(), []);
  // Sweeps, then snaps onto us on beat 1 of bar 5.
  const sweep = 0.9 * Math.sin((t - b(5)) * 3.2) * (1 - step(t - b(5, 1), WOBBLE));
  const yaw = PI + 0.55 + sweep - 0.55 * step(t - b(5, 1), WOBBLE);
  const blink = Math.floor((t - b(5)) / (BEAT / 2)) % 2 === 0;
  const hot = t > b(5, 1);
  return (
    <G p={p}>
      <Voxels boxes={parts.mount} />
      <G r={[0, yaw, 0]} s={1.7}>
        <G r={[-0.35 + 0.1 * step(t - b(5, 1), WOBBLE), 0, 0]}>
          <Voxels boxes={parts.body} />
          <mesh position={[0.06, 0.05, -0.305]}>
            <boxGeometry args={[0.035, 0.035, 0.012]} />
            <meshBasicMaterial color={blink || hot ? "#ff3030" : "#5a1010"} toneMapped={false} />
          </mesh>
          {hot ? (
            <mesh position={[0, -0.02, -0.33 - 1.6]} rotation={[PI / 2, 0, 0]}>
              <coneGeometry args={[0.9, 3.2, 32, 1, true]} />
              <meshBasicMaterial color="#ff4a4a" transparent opacity={0.13 + 0.05 * (blink ? 1 : 0)} depthWrite={false} toneMapped={false} side={THREE.DoubleSide} />
            </mesh>
          ) : null}
        </G>
      </G>
    </G>
  );
};

const CorridorSet: React.FC<{ t: number; siren?: boolean }> = ({ t }) => {
  const hall = useMemo(() => corridor(), []);
  return <Voxels boxes={hall} />;
};

const OutsideSet: React.FC<{ t: number }> = () => {
  const out = useMemo(() => outside(), []);
  return (
    <>
      <Voxels boxes={out} />
      <Label text="ROYAL ACADEMY OF UNNECESSARY SCIENCES" p={[0, 3.35, 2.29]} w={5.4} h={0.6} yaw={PI} color="#ffd24a" px={86} />
      <Label text="CHAI · SUTTA · MAGGI" p={[-7, 1.6, 11.25]} w={2.5} h={0.46} yaw={PI} color="#ffffff" px={70} />
    </>
  );
};

const IslandSet: React.FC<{ t: number }> = ({ t }) => {
  const isl = useMemo(() => island(), []);
  const cl = useMemo(() => clouds(), []);
  // Blocks drop in on 16ths from the "and" of bar 13 beat 2, the wall after, flowers pop on 14.1.
  const t0 = b(13, 2);
  const drop = (list: Box[], base: number, spread: number, seed: number) =>
    list.map((bx, i) => {
      const at = base + hash(i * 3.1 + seed) * spread;
      const d = t - at;
      if (d < -0.35) return null;
      const u = clamp01((d + 0.35) / 0.35);
      const y = d < 0 ? 6 * (1 - u * u) : 0.12 * Math.exp(-d * 10) * Math.sin(d * 30);
      return (
        <G key={i} p={[0, y, 0]}>
          <Voxels boxes={[bx]} />
        </G>
      );
    });
  const drift = (t - b(13)) * 0.35;
  return (
    <>
      <G p={[drift, 0, 0]}><Voxels boxes={cl} shadow={false} /></G>
      {drop(isl.ground, t0, BEAT * 1.2, 1)}
      {drop(isl.wall, t0 + BEAT * 0.9, BEAT * 0.9, 7)}
      {isl.flowers.map((f, i) => {
        const s = step(t - (b(14, 1) + i * BEAT * 0.25), WOBBLE);
        return s > 0.001 ? (
          <G key={i} p={[f.c[0], f.c[1] - 0.1, f.c[2]]} s={Math.max(0.001, s)}>
            <Voxels boxes={[{ ...f, c: [0, 0.1, 0] }]} />
          </G>
        ) : null;
      })}
    </>
  );
};

const Scene: React.FC<{ t: number }> = ({ t }) => {
  const cast = actors(t);
  const inClass = t < b(2, 0.5) || (t >= b(4) - 0.5 && t < b(5)) || (t >= b(7, 3) && t < b(9));
  const inHall = inAct(t, ACT.cctv) || inAct(t, ACT.excuse) || inAct(t, ACT.trolley) || inAct(t, ACT.paper) || inAct(t, ACT.panic);
  const outdoors = inAct(t, ACT.chase) || (t >= b(12) && t < b(13, 2));
  const logo = t >= b(13, 2);
  const bg = logo || outdoors ? SKY : inHall ? "#e7d2aa" : "#f3e3c3";
  const panic = inAct(t, ACT.panic);
  const sirenRed = panic && Math.floor((t - b(9)) / (BEAT / 2)) % 2 === 0;
  const target: V3 = outdoors ? (inAct(t, ACT.chase) ? [camAt(t).pos[0], 0, -8] : [0, 0, 4]) : logo ? [0.5, 0, 0] : [0, 0, 0];
  return (
    <>
      <CamRig t={t} />
      <color attach="background" args={[bg]} />
      {outdoors ? <fog attach="fog" args={[SKY, 28, 70]} /> : null}
      <Lights target={target} tint={panic ? (sirenRed ? "#ff9a9a" : "#9ab8ff") : "#ffffff"} amb={panic ? 1.25 : 1.0} sun={logo ? 2.2 : 1.9} size={outdoors ? 22 : 12} />
      {inClass ? <ClassroomSet t={t} /> : null}
      {inHall ? <CorridorSet t={t} /> : null}
      {inAct(t, ACT.cctv) ? <CCTVRig t={t} p={[0, 2.75, 2.75]} /> : null}
      {inAct(t, ACT.trolley) ? (
        <>
          <G p={[-0.35 + 1.6 * (1 - Math.exp(-(t - b(7)) * 4)), 0, 0.2]} r={[0, PI / 2, 0.05 * Math.sin((t - b(7)) * 40) * Math.exp(-(t - b(7)) * 5)]} s={1.1}>
            <Voxels boxes={trolleyBoxes} />
          </G>
          <Samosas t={t} at={b(7)} origin={[0.6, 1.0, 0.2]} />
        </>
      ) : null}
      {inAct(t, ACT.paper) ? <PaperBall t={t} /> : null}
      {outdoors ? <OutsideSet t={t} /> : null}
      {logo ? <IslandSet t={t} /> : null}
      {inAct(t, ACT.ruin) ? <VoiceRings t={t} at={b(4, 1)} until={b(4, 2)} p={[0.15, 0.03, -2.66]} /> : null}
      {t >= b(12) && t < b(13, 2) ? <Confetti t={t} at={b(12, 2)} origin={[0, 1.5, 4.5]} /> : null}
      {cast.map((a) => (
        <Character key={a.id} look={a.look} pose={a.pose} p={a.p} yaw={a.yaw} roll={a.roll ?? 0} pitch={a.pitch ?? 0} squash={a.squash ?? 1} extra={a.chai ? { armR: CHAI_GLASS } : undefined} />
      ))}
    </>
  );
};

const trolleyBoxes = trolley();

const PaperBall: React.FC<{ t: number }> = ({ t }) => {
  const a = b(7, 2) + 0.02, hit = b(7, 2) + 0.3;
  const u = clamp01((t - a) / (hit - a));
  const from: V3 = [-1.45, 1.95, 0.1], to: V3 = [2.2, 1.55, 0.3];
  let p: V3 = [from[0] + (to[0] - from[0]) * u, from[1] + (to[1] - from[1]) * u + 0.9 * Math.sin(u * PI), from[2] + (to[2] - from[2]) * u];
  if (t > hit) {
    const d = t - hit;
    p = [to[0] - 1.2 * d, Math.max(0.06, to[1] + 2.2 * d - 4.9 * d * d), to[2] - 0.4 * d];
  }
  if (t < a) return null;
  return (
    <G p={p} r={[t * 17, t * 11, 0]} s={2.2}>
      <Voxels boxes={PAPER_BALL} />
    </G>
  );
};

export const World3D: React.FC<{ t: number; blur?: number }> = ({ t, blur = 0 }) => (
  <div style={{ position: "absolute", inset: 0, filter: blur > 0.05 ? `blur(${blur}px)` : undefined }}>
    <ThreeCanvas width={1920} height={1080} flat shadows gl={{ antialias: true, preserveDrawingBuffer: true }} dpr={1}>
      <Scene t={t} />
    </ThreeCanvas>
  </div>
);
