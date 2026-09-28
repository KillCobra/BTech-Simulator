// three.js twin of scripts/voxel.gd + shaders/voxel.gdshader: every box becomes 6 faces with vertex
// colour, and the fragment lightens a soft band along each face edge (bevel width 0.06 m, light 0.4),
// so blocks read as the same chunky toy pieces as in the game. Everything is a pure function of props.
import React, { useMemo } from "react";
import * as THREE from "three";
import { buildCharacter, PIVOT, type Box, type Look, type Pose, type V3 } from "./voxel";

const FACES: { n: V3; u: V3; v: V3; su: 0 | 1 | 2; sv: 0 | 1 | 2 }[] = [
  { n: [1, 0, 0], u: [0, 0, -1], v: [0, 1, 0], su: 2, sv: 1 },
  { n: [-1, 0, 0], u: [0, 0, 1], v: [0, 1, 0], su: 2, sv: 1 },
  { n: [0, 1, 0], u: [1, 0, 0], v: [0, 0, -1], su: 0, sv: 2 },
  { n: [0, -1, 0], u: [1, 0, 0], v: [0, 0, 1], su: 0, sv: 2 },
  { n: [0, 0, 1], u: [1, 0, 0], v: [0, 1, 0], su: 0, sv: 1 },
  { n: [0, 0, -1], u: [-1, 0, 0], v: [0, 1, 0], su: 0, sv: 1 },
];

const colorCache = new Map<string, THREE.Color>();
const col = (hex: string) => {
  let c = colorCache.get(hex);
  if (!c) {
    c = new THREE.Color(hex);
    colorCache.set(hex, c);
  }
  return c;
};

export function boxGeometry(boxes: readonly Box[]) {
  const n = boxes.length * 24;
  const pos = new Float32Array(n * 3), nor = new Float32Array(n * 3), rgb = new Float32Array(n * 3);
  const fuv = new Float32Array(n * 2), fsz = new Float32Array(n * 2);
  const idx: number[] = [];
  let vi = 0;
  for (const bx of boxes) {
    const [cx, cy, cz] = bx.c;
    // voxel.gd grows every box a hair to stop z-fighting between touching faces.
    const grow = 0.0008;
    const s = [bx.s[0] + grow, bx.s[1] + grow, bx.s[2] + grow];
    const c = col(bx.col);
    for (const f of FACES) {
      const w = s[f.su], h = s[f.sv];
      for (let k = 0; k < 4; k++) {
        const a = k === 1 || k === 2 ? 1 : 0, bb = k >= 2 ? 1 : 0;
        const du = (a - 0.5) * w, dv = (bb - 0.5) * h;
        const x = cx + f.n[0] * s[0] / 2 + f.u[0] * du + f.v[0] * dv;
        const y = cy + f.n[1] * s[1] / 2 + f.u[1] * du + f.v[1] * dv;
        const z = cz + f.n[2] * s[2] / 2 + f.u[2] * du + f.v[2] * dv;
        pos.set([x, y, z], (vi + k) * 3);
        nor.set(f.n, (vi + k) * 3);
        rgb.set([c.r, c.g, c.b], (vi + k) * 3);
        fuv.set([a * w, bb * h], (vi + k) * 2);
        fsz.set([w, h], (vi + k) * 2);
      }
      idx.push(vi, vi + 1, vi + 2, vi, vi + 2, vi + 3);
      vi += 4;
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.BufferAttribute(pos, 3));
  g.setAttribute("normal", new THREE.BufferAttribute(nor, 3));
  g.setAttribute("color", new THREE.BufferAttribute(rgb, 3));
  g.setAttribute("faceUv", new THREE.BufferAttribute(fuv, 2));
  g.setAttribute("faceSize", new THREE.BufferAttribute(fsz, 2));
  g.setIndex(idx);
  return g;
}

function makeVoxelMaterial(emissive = 0) {
  const m = new THREE.MeshLambertMaterial({ vertexColors: true });
  if (emissive) m.emissive = new THREE.Color(emissive);
  m.onBeforeCompile = (sh) => {
    sh.vertexShader = sh.vertexShader
      .replace("#include <common>", "#include <common>\nattribute vec2 faceUv;\nattribute vec2 faceSize;\nvarying vec2 vFaceUv;\nvarying vec2 vFaceSize;")
      .replace("#include <begin_vertex>", "#include <begin_vertex>\nvFaceUv = faceUv;\nvFaceSize = faceSize;");
    sh.fragmentShader = sh.fragmentShader
      .replace("#include <common>", "#include <common>\nvarying vec2 vFaceUv;\nvarying vec2 vFaceSize;")
      .replace(
        "#include <color_fragment>",
        `#include <color_fragment>
        vec2 te = min(vFaceUv, vFaceSize - vFaceUv);
        float dist = min(te.x, te.y);
        float width = min(0.06, 0.3 * min(vFaceSize.x, vFaceSize.y));
        float px = max(max(fwidth(vFaceUv.x), fwidth(vFaceUv.y)), 1e-5);
        float soft = max(width, px * 1.5);
        float edge = 1.0 - smoothstep(0.0, soft, dist);
        edge *= clamp((width / px - 1.5) / 2.0, 0.0, 1.0);
        diffuseColor.rgb = mix(diffuseColor.rgb, diffuseColor.rgb * 1.3 + 0.025, edge * 0.4);`,
      );
  };
  return m;
}
export const VOXEL_MAT = makeVoxelMaterial();

export const Voxels: React.FC<{ boxes: readonly Box[]; shadow?: boolean }> = ({ boxes, shadow = true }) => {
  const geo = useMemo(() => boxGeometry(boxes), [boxes]);
  return <mesh geometry={geo} material={VOXEL_MAT} castShadow={shadow} receiveShadow />;
};

type TRS = { p?: V3; r?: V3; s?: number | V3 };
export const G: React.FC<TRS & { children?: React.ReactNode }> = ({ p = [0, 0, 0], r = [0, 0, 0], s = 1, children }) => (
  <group position={p} rotation={new THREE.Euler(r[0], r[1], r[2], "YXZ")} scale={typeof s === "number" ? [s, s, s] : s}>
    {children}
  </group>
);

const partsCache = new Map<Look, ReturnType<typeof buildCharacter>>();
const parts = (look: Look) => {
  let p = partsCache.get(look);
  if (!p) {
    p = buildCharacter(look);
    partsCache.set(look, p);
  }
  return p;
};

/** A character (student_model.gd) at `p`, facing yaw `yaw` (0 = facing -Z), posed. `squash` scales y around the feet. */
export const Character: React.FC<{ look: Look; pose: Pose; p?: V3; yaw?: number; roll?: number; pitch?: number; squash?: number; scale?: number; extra?: { armR?: Box[] } }> = ({
  look, pose, p = [0, 0, 0], yaw = 0, roll = 0, pitch = 0, squash = 1, scale = 1, extra,
}) => {
  const q = parts(look);
  const s = scale * (look.height ?? 1);
  const w = scale / Math.sqrt(Math.max(0.2, squash));
  return (
    <group position={p} rotation={new THREE.Euler(pitch, yaw, roll, "YXZ")} scale={[w, s * squash, w]}>
      <group position={[0, pose.hipY, 0]}>
        <G p={PIVOT.legL} r={[pose.legL, 0, 0]}><Voxels boxes={q.legL} /></G>
        <G p={PIVOT.legR} r={[pose.legR, 0, 0]}><Voxels boxes={q.legR} /></G>
        <G r={[pose.torsoX, 0, 0]}>
          <Voxels boxes={q.torso} />
          <G p={PIVOT.armL} r={[pose.armLX, 0, pose.armLZ]}><Voxels boxes={q.armL} /></G>
          <G p={PIVOT.armR} r={[pose.armRX, 0, pose.armRZ]}>
            <Voxels boxes={q.armR} />
            {extra?.armR ? <Voxels boxes={extra.armR} /> : null}
          </G>
          <G p={PIVOT.head} r={[pose.headX, pose.headY, 0]}><Voxels boxes={q.head} /></G>
        </G>
      </group>
    </group>
  );
};
