// The open act's own 3D stage: like ../Stage3D but with a transparent option (so voxels can run over
// 2D colour fields) and a free sun direction (the clock is lit from the front).
import { ThreeCanvas } from "@remotion/three";
import { useThree } from "@react-three/fiber";
import React, { useMemo } from "react";
import * as THREE from "three";
import { applyCam, type Cam } from "../../launch/camera3d";
import type { V3 } from "../../launch/voxel";

const CamRig: React.FC<{ cam: Cam }> = ({ cam }) => {
  const camera = useThree((s) => s.camera) as THREE.PerspectiveCamera;
  applyCam(camera, cam);
  return null;
};

const Sun: React.FC<{ target: V3; dir: V3; tint: string; sun: number; amb: number; size: number }> = ({ target, dir, tint, sun, amb, size }) => {
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
  light.position.set(target[0] + dir[0], target[1] + dir[1], target[2] + dir[2]);
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

/** `bg: null` renders a transparent canvas (voxels over a 2D field). */
export const OStage: React.FC<{
  cam: Cam; bg?: string | null; dir?: V3; tint?: string; sun?: number; amb?: number; target?: V3; size?: number;
  style?: React.CSSProperties; children?: React.ReactNode;
}> = ({ cam, bg = null, dir = [9, 16, -11], tint = "#ffffff", sun = 1.9, amb = 1.0, target, size = 12, style, children }) => (
  <div style={{ position: "absolute", inset: 0, ...style }}>
    <ThreeCanvas width={1920} height={1080} flat shadows gl={{ antialias: true, preserveDrawingBuffer: true, alpha: true }} dpr={1}>
      <CamRig cam={cam} />
      {bg ? <color attach="background" args={[bg]} /> : null}
      <Sun target={target ?? cam.look} dir={dir} tint={tint} sun={sun} amb={amb} size={size} />
      {children}
    </ThreeCanvas>
  </div>
);

/** A floor that only shows the shadows cast on it (for voxels running over a flat colour field). */
export const ShadowFloor: React.FC<{ y?: number; opacity?: number; color?: string }> = ({ y = 0, opacity = 0.28, color = "#2a1a0e" }) => (
  <mesh position={[0, y, 0]} rotation={[-Math.PI / 2, 0, 0]} receiveShadow>
    <planeGeometry args={[80, 80]} />
    <shadowMaterial opacity={opacity} color={color} transparent />
  </mesh>
);
