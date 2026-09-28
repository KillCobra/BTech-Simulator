// A transparent three.js stage for the lobby lineup: the colour field and stripes are painted in 2D behind it,
// the voxel students stand on an invisible floor that only catches their shadows (so they sit on the field).
// Camera / light rig copied from ../Stage3D.tsx; the character is ../../launch/three.tsx's Character, fed our parts.
import { ThreeCanvas } from "@remotion/three";
import { useThree } from "@react-three/fiber";
import React, { useMemo } from "react";
import * as THREE from "three";
import { applyCam, type Cam } from "../../launch/camera3d";
import { G, Voxels } from "../../launch/three";
import { PIVOT, type Box, type Pose, type V3 } from "../../launch/voxel";
import { crewParts, type CrewLook } from "./looks";

const CamRig: React.FC<{ cam: Cam }> = ({ cam }) => {
  const camera = useThree((s) => s.camera) as THREE.PerspectiveCamera;
  applyCam(camera, cam);
  return null;
};

const Sun: React.FC<{ target: V3; size: number }> = ({ target, size }) => {
  const light = useMemo(() => {
    const l = new THREE.DirectionalLight("#fff4e0", 1.9);
    l.castShadow = true;
    l.shadow.mapSize.set(2048, 2048);
    l.shadow.bias = -0.0004;
    l.shadow.normalBias = 0.02;
    return l;
  }, []);
  const c = light.shadow.camera as THREE.OrthographicCamera;
  c.left = -size; c.right = size; c.top = size; c.bottom = -size; c.near = 0.5; c.far = 60;
  c.updateProjectionMatrix();
  // Key light from camera-left and above, so shadows fall back and to the right on the field.
  light.position.set(target[0] + 6, target[1] + 14, target[2] - 9);
  light.target.position.set(...target);
  light.target.updateMatrixWorld();
  return (
    <>
      <hemisphereLight args={["#ffffff", "#b8a888", 1.05]} />
      <primitive object={light} />
      <primitive object={light.target} />
    </>
  );
};

export const CrewStage: React.FC<{ cam: Cam; shadow?: number; style?: React.CSSProperties; children?: React.ReactNode }> = ({ cam, shadow = 0.28, style, children }) => (
  <div style={{ position: "absolute", inset: 0, ...style }}>
    <ThreeCanvas width={1920} height={1080} flat shadows gl={{ antialias: true, alpha: true, preserveDrawingBuffer: true }} dpr={1}>
      <CamRig cam={cam} />
      <Sun target={[cam.look[0], 0, cam.look[2]]} size={8} />
      <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, 0, 0]} receiveShadow>
        <planeGeometry args={[60, 60]} />
        <shadowMaterial color="#2a1a0e" opacity={shadow} />
      </mesh>
      {children}
    </ThreeCanvas>
  </div>
);

const partsCache = new Map<CrewLook, ReturnType<typeof crewParts>>();
const partsOf = (look: CrewLook) => {
  let p = partsCache.get(look);
  if (!p) partsCache.set(look, (p = crewParts(look)));
  return p;
};

/** launch/three.tsx Character, for crew looks (mohawk, beanie, sling). `squash` scales y around the feet. */
export const CrewCharacter: React.FC<{ look: CrewLook; pose: Pose; p: V3; yaw?: number; roll?: number; squash?: number }> = ({ look, pose, p, yaw = 0, roll = 0, squash = 1 }) => {
  const q = partsOf(look);
  const s = look.height ?? 1;
  const w = 1 / Math.sqrt(Math.max(0.2, squash));
  return (
    <group position={p} rotation={new THREE.Euler(0, yaw, roll, "YXZ")} scale={[w, s * squash, w]}>
      <group position={[0, pose.hipY, 0]}>
        <G p={PIVOT.legL} r={[pose.legL, 0, 0]}><Voxels boxes={q.legL} /></G>
        <G p={PIVOT.legR} r={[pose.legR, 0, 0]}><Voxels boxes={q.legR} /></G>
        <G r={[pose.torsoX, 0, 0]}>
          <Voxels boxes={q.torso} />
          <G p={PIVOT.armL} r={[pose.armLX, 0, pose.armLZ]}><Voxels boxes={q.armL} /></G>
          <G p={PIVOT.armR} r={[pose.armRX, 0, pose.armRZ]}><Voxels boxes={q.armR} /></G>
          <G p={PIVOT.head} r={[pose.headX, pose.headY, 0]}><Voxels boxes={q.head} /></G>
        </G>
      </group>
    </group>
  );
};

// One unit cube per colour (geometry built once), placed and scaled per frame.
const cubeCache = new Map<string, Box[]>();
const unit = (col: string) => {
  let c = cubeCache.get(col);
  if (!c) cubeCache.set(col, (c = [{ c: [0, 0, 0], s: [1, 1, 1], col }]));
  return c;
};
export const Cube: React.FC<{ p: V3; s: number; col: string; r?: V3 }> = ({ p, s, col, r = [0, 0, 0] }) =>
  s <= 0.001 ? null : (
    <G p={p} r={r} s={s}>
      <Voxels boxes={unit(col)} shadow={false} />
    </G>
  );

/** A flat ring on the floor (the proximity voice radius). `w` is the band width as a share of the radius. */
export const FloorRing: React.FC<{ p: V3; r: number; w: number; color: string; opacity: number }> = ({ p, r, w, color, opacity }) =>
  opacity <= 0.01 || r <= 0.01 ? null : (
    <mesh position={[p[0], 0.015, p[2]]} rotation={[-Math.PI / 2, 0, 0]} scale={[r, r, 1]}>
      <ringGeometry args={[1 - w, 1, 64]} />
      <meshBasicMaterial color={color} transparent opacity={opacity} depthWrite={false} />
    </mesh>
  );
