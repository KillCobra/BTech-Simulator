// A self-contained 3D stage for one act: its own ThreeCanvas, camera, lights, sky/fog.
// Reuses the game-accurate voxel renderer from ../launch/three.tsx (Voxels, Character, G).
import { ThreeCanvas } from "@remotion/three";
import { useThree } from "@react-three/fiber";
import React, { useMemo } from "react";
import * as THREE from "three";
import { applyCam, type Cam } from "../launch/camera3d";
import type { V3 } from "../launch/voxel";

const CamRig: React.FC<{ cam: Cam }> = ({ cam }) => {
  const camera = useThree((s) => s.camera) as THREE.PerspectiveCamera;
  applyCam(camera, cam);
  return null;
};

const Lights: React.FC<{ target: V3; tint: string; sun: number; amb: number; size: number }> = ({ target, tint, sun, amb, size }) => {
  const light = useMemo(() => {
    const l = new THREE.DirectionalLight("#fff4e0", sun);
    l.castShadow = true;
    l.shadow.mapSize.set(2048, 2048);
    l.shadow.bias = -0.0004;
    l.shadow.normalBias = 0.02;
    return l;
  }, []);
  light.intensity = sun;
  const c = light.shadow.camera as THREE.OrthographicCamera;
  c.left = -size; c.right = size; c.top = size; c.bottom = -size; c.near = 0.5; c.far = 90;
  c.updateProjectionMatrix();
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

/**
 * <Stage3D cam={...} bg="#8dd0ef" fog={[near, far]}>...voxels...</Stage3D>
 * `cam`: { pos, look, fov, roll? } for this frame (a pure function of t in the act).
 * `blur`: CSS blur px on the whole canvas (for type over 3D).
 */
export const Stage3D: React.FC<{
  cam: Cam; bg?: string; fog?: [number, number]; tint?: string; sun?: number; amb?: number; shadowTarget?: V3; shadowSize?: number;
  blur?: number; style?: React.CSSProperties; children?: React.ReactNode;
}> = ({ cam, bg = "#8dd0ef", fog, tint = "#ffffff", sun = 1.9, amb = 1.0, shadowTarget, shadowSize = 14, blur = 0, style, children }) => (
  <div style={{ position: "absolute", inset: 0, filter: blur > 0.05 ? `blur(${blur}px)` : undefined, ...style }}>
    <ThreeCanvas width={1920} height={1080} flat shadows gl={{ antialias: true, preserveDrawingBuffer: true }} dpr={1}>
      <CamRig cam={cam} />
      <color attach="background" args={[bg]} />
      {fog ? <fog attach="fog" args={[bg, fog[0], fog[1]]} /> : null}
      <Lights target={shadowTarget ?? cam.look} tint={tint} sun={sun} amb={amb} size={shadowSize} />
      {children}
    </ThreeCanvas>
  </div>
);

/** Screen position (px, 1920x1080) of a world point for a camera (for pinning 2D UI to 3D heads). */
const _cam = new THREE.PerspectiveCamera(40, 1920 / 1080, 0.05, 400);
const _v = new THREE.Vector3();
export function toScreen(cam: Cam, p: V3) {
  applyCam(_cam, cam);
  _v.set(...p).project(_cam);
  return { x: (_v.x * 0.5 + 0.5) * 1920, y: (-_v.y * 0.5 + 0.5) * 1080, behind: _v.z > 1 };
}
