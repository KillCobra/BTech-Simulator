// Bars 22-23: the voxel island from art/icon.png rains together block by block (from 21.3.5, under the whip
// down from the sky), the hero lands on the wall on 22.0 and waves, BUNK / MASTER slam in (main.gd logo: GOLD,
// INK outline, drop shadow), the tagline word by word, the chips, COMING SOON pressed on 23.0, WISHLIST NOW,
// then a clean, alive end card (clouds drift, gentle beat pulse) that holds as the poster frame.
import React, { useMemo } from "react";
import { font, GameButton, outline } from "../../launch/ui";
import { C } from "../../launch/tokens";
import { island } from "../../launch/sets";
import { boxGeometry, Character, G, Voxels } from "../../launch/three";
import { CAST, REST, type Box, type V3 } from "../../launch/voxel";
import type { Cam } from "../../launch/camera3d";
import { step } from "../../kit/spring";
import { Burst, Shockwave } from "../../film/fxui";
import { b, BEAT, FINALE_END as DURATION } from "../cues";
import { Stage3D, toScreen } from "../Stage3D";
import { clamp01, Flash, InkText, lerp, lerp3, outCubic, PI, rnd, shake } from "./kit";

const WOBBLE = { stiffness: 380, damping: 11 };
const SNAP = { stiffness: 700, damping: 30 };
const POP = { stiffness: 520, damping: 20 };
const sp = (t: number, at: number, cfg = POP) => step(t - at, cfg);

export const LOGO_START = b(22, 3.5);
const LAND = b(23);
const HERO_P: V3 = [0.25, 1.135, 0.25];

// ------------------------------------------------------------------ camera
const REST_LOOK: V3 = [-1.5, 0.8, -2.1];
const REST_POS: V3 = [REST_LOOK[0] + 7.95 * 1.2, REST_LOOK[1] + 2.52 * 1.2, REST_LOOK[2] - 5.65 * 1.2];
const REST_FOV = 30;
export function logoCam(t: number): Cam {
  // Tilt down from the sky (continuing the whip up out of the scoreboard), settling on the downbeat.
  const u = clamp01((t - LOGO_START) / (LAND - LOGO_START));
  const e = 1 - Math.pow(1 - u, 3);
  const tilt = 1 - e;
  // After the slam, a slow drift around the island (a few degrees), so the end card stays alive.
  const drift = clamp01((t - LAND) / (DURATION - LAND));
  const ang = -0.06 * drift;
  const rx = REST_POS[0] - REST_LOOK[0], rz = REST_POS[2] - REST_LOOK[2];
  const pos: V3 = [REST_LOOK[0] + rx * Math.cos(ang) - rz * Math.sin(ang), REST_POS[1] + 0.25 * drift, REST_LOOK[2] + rx * Math.sin(ang) + rz * Math.cos(ang)];
  const kick = t > LAND ? 0.9 * Math.exp(-(t - LAND) * 7) * Math.cos((t - LAND) * 22) : 0;
  return { pos: [pos[0], pos[1] + 1.5 * tilt, pos[2]], look: [REST_LOOK[0], REST_LOOK[1] + 16 * tilt * tilt, REST_LOOK[2]], fov: REST_FOV + 10 * tilt + kick, roll: 0.12 * tilt };
}

// ------------------------------------------------------------------ the island
type Drop = { box: Box; at: number };
function drops(): { ground: Drop[]; wall: Drop[]; flowers: Box[] } {
  const isl = island();
  // Ground falls in a spiral from the middle out, bottom layer first; the wall stacks brick by brick after.
  const g = isl.ground.map((bx) => {
    const r = Math.hypot(bx.c[0], bx.c[2]);
    const layer = bx.c[1] < -0.5 ? 0 : bx.c[1] < -0.2 ? 1 : 2;
    return { box: bx, k: layer * 0.28 + r * 0.14 + rnd(bx.c[0] * 13 + bx.c[2] * 7 + layer) * 0.12 };
  });
  const kmax = Math.max(...g.map((x) => x.k));
  const g0 = LOGO_START - 0.02, g1 = b(22, 3.85);
  const ground = g.map((x) => ({ box: x.box, at: lerp(g0, g1, x.k / kmax) }));
  const wall = isl.wall.map((bx) => {
    const k = (bx.c[1] - 0.36) / 0.7 * 0.6 + (bx.c[0] + 0.75) / 2 * 0.4;
    return { box: bx, at: lerp(b(22, 3.7), LAND - 0.04, k) };
  });
  return { ground, wall, flowers: isl.flowers };
}

// Voxel clouds like the splash (flat stacked slabs), placed by where they sit in the resting frame.
const CLOUDS: [number, number, number, number][] = [
  // ndc x, ndc y, distance, width
  [-0.78, 0.76, 40, 3.0], [-0.08, 0.88, 50, 3.4], [-0.95, -0.2, 36, 3.0], [-0.3, -0.84, 44, 3.2], [0.96, -0.9, 40, 3.0], [0.93, 0.95, 46, 2.6],
];
function cloudBoxes(): Box[] {
  const L: Box[] = [];
  const f = norm(sub(REST_LOOK, REST_POS));
  const r = norm(cross(f, [0, 1, 0]));
  const u = cross(r, f);
  const tan = Math.tan((REST_FOV / 2) * PI / 180);
  CLOUDS.forEach(([nx, ny, dist, w], i) => {
    const c = add(add(add(REST_POS, mul(f, dist)), mul(r, nx * dist * tan * (16 / 9))), mul(u, ny * dist * tan));
    const [x, y, z] = c;
    // slabs laid along the camera's right vector so they read wide
    const ax: V3 = [r[0], 0, r[2]];
    const at = (k: number, dy: number, dz: number): V3 => [x + ax[0] * k - ax[2] * dz, y + dy, z + ax[2] * k + ax[0] * dz];
    const ang = Math.atan2(-ax[2], ax[0]);
    void ang;
    const sz = (a: number, h: number, d: number): V3 => [a * Math.abs(ax[0]) + d * Math.abs(ax[2]), h, a * Math.abs(ax[2]) + d * Math.abs(ax[0])];
    // unlit (like the splash's flat clouds): a pale underside slab, the white body, a smaller white top
    L.push({ c: at(0, -0.1, 0), s: sz(w * 1.02, 0.4, w * 0.5), col: "#dcebf6" });
    L.push({ c: at(0, 0.12, 0), s: sz(w, 0.5, w * 0.52), col: "#ffffff" });
    L.push({ c: at(w * 0.14, 0.5, 0.05), s: sz(w * 0.55, 0.4, w * 0.3), col: i % 2 ? "#ffffff" : "#f7fbff" });
    L.push({ c: at(w * 0.14, 0.34, 0.05), s: sz(w * 0.56, 0.1, w * 0.31), col: "#e8f2fa" });
  });
  return L;
}
const sub = (a: V3, c: V3): V3 => [a[0] - c[0], a[1] - c[1], a[2] - c[2]];
const add = (a: V3, c: V3): V3 => [a[0] + c[0], a[1] + c[1], a[2] + c[2]];
const mul = (a: V3, k: number): V3 => [a[0] * k, a[1] * k, a[2] * k];
const cross = (a: V3, c: V3): V3 => [a[1] * c[2] - a[2] * c[1], a[2] * c[0] - a[0] * c[2], a[0] * c[1] - a[1] * c[0]];
const norm = (a: V3): V3 => mul(a, 1 / Math.hypot(a[0], a[1], a[2]));

/** The leafy block behind the wall's far end (art/splash.png). */
function bushBoxes(): Box[] {
  const L: Box[] = [];
  const cols = ["#5fae4a", "#4e9a3e", "#86c95a", "#74b04e"];
  for (let i = 0; i < 3; i++)
    for (let j = 0; j < 3; j++)
      for (let k = 0; k < 4; k++) {
        if (k === 3 && (i + j) % 2 === 1) continue;
        L.push({ c: [-1.25 + i * 0.3, 0.26 + k * 0.3, 0.55 + j * 0.3], s: [0.3, 0.3, 0.3], col: cols[Math.floor(rnd(i * 9 + j * 3 + k) * 4)] });
      }
  return L;
}

const FlatBoxes: React.FC<{ boxes: Box[] }> = ({ boxes }) => {
  const geo = useMemo(() => boxGeometry(boxes), [boxes]);
  return (
    <mesh geometry={geo}>
      <meshBasicMaterial vertexColors toneMapped={false} fog={false} />
    </mesh>
  );
};

const IslandSet: React.FC<{ t: number }> = ({ t }) => {
  const d = useMemo(() => drops(), []);
  const cl = useMemo(() => cloudBoxes(), []);
  const bush = useMemo(() => bushBoxes(), []);
  const fall = (x: Drop, i: number) => {
    const dt = t - x.at;
    const H = 7;
    if (dt < -0.4) return null;
    const y = dt < 0 ? H * Math.pow(-dt / 0.4, 2) : 0.14 * Math.exp(-dt * 11) * Math.sin(dt * 34);
    const s = dt < 0 ? 1 : 1 + 0.18 * Math.exp(-dt * 12) * Math.cos(dt * 30);
    const spin = dt < 0 ? -dt * 5 * (rnd(i) - 0.5) : 0;
    return (
      <G key={i} p={[x.box.c[0], x.box.c[1] + y, x.box.c[2]]} r={[spin, spin * 0.7, 0]} s={[1 / Math.sqrt(s), s, 1 / Math.sqrt(s)]}>
        <Voxels boxes={[{ ...x.box, c: [0, 0, 0] }]} />
      </G>
    );
  };
  const drift = (t - LOGO_START) * 0.5;
  const bs = sp(t, b(23, 0.75), WOBBLE);
  return (
    <>
      <G p={[drift * 0.56, 0, drift * 0.83]}><FlatBoxes boxes={cl} /></G>
      {bs > 0.001 ? <G p={[-0.95, 0.11, 0.85]} s={[Math.max(0.001, bs), Math.max(0.001, bs), Math.max(0.001, bs)]}><G p={[0.95, -0.11, -0.85]}><Voxels boxes={bush} /></G></G> : null}
      {d.ground.map(fall)}
      {d.wall.map((x, i) => fall(x, i + 200))}
      {d.flowers.map((f, i) => {
        const s = sp(t, b(23, 1) + i * BEAT * 0.25, WOBBLE);
        return s > 0.001 ? (
          <G key={i} p={[f.c[0], f.c[1] - 0.1, f.c[2]]} s={Math.max(0.001, s)}>
            <Voxels boxes={[{ ...f, c: [0, 0.1, 0] }]} />
          </G>
        ) : null;
      })}
    </>
  );
};

/** The hero: falls onto the wall on 22.0 (stretch, squash), waves; hops when COMING SOON is pressed. */
function hero(t: number) {
  const fallU = clamp01((t - (LAND - 0.3)) / 0.3);
  const pre = t < LAND;
  const y = pre ? HERO_P[1] + 7 * (1 - fallU * fallU) : HERO_P[1];
  const sq = pre ? 1 + 0.25 * fallU : 1 - 0.34 * Math.exp(-(t - LAND) * 9) * Math.cos((t - LAND) * 24);
  const wave = sp(t, b(23, 0.75), WOBBLE);
  const hopD = t - PRESS;
  const hop = hopD > 0 && hopD < 0.36 ? 0.4 * Math.sin((hopD / 0.36) * PI) : 0;
  const land = pre ? 0 : Math.exp(-(t - LAND) * 6);
  const armW = 0.28 * Math.sin((t - b(23, 0.75)) * 2 * PI / BEAT);
  return {
    p: [HERO_P[0], y + hop, HERO_P[2]] as V3,
    squash: sq,
    pose: { ...REST, hipY: REST.hipY - 0.12 * land, legL: 0.4 * land, legR: 0.4 * land, torsoX: -0.3 * land, armLX: pre ? 2.8 * fallU : 0.3 * land, armRX: pre ? 2.9 * fallU : 2.95 * wave, armRZ: pre ? 0.4 : 0.22 * wave + armW * wave, armLZ: pre ? -0.4 : -0.06, headX: 0.12 - 0.2 * land },
  };
}

export const LogoWorld: React.FC<{ t: number }> = ({ t }) => {
  const cam = logoCam(t);
  const h = hero(t);
  return (
    <Stage3D cam={cam} bg="#8dd0ef" fog={[30, 70]} shadowTarget={[0, 0, 0]} shadowSize={5} sun={2.1}>
      <IslandSet t={t} />
      {t > LAND - 0.3 ? <Character look={CAST.hero} pose={h.pose} p={h.p} yaw={-0.8} squash={h.squash} /> : null}
    </Stage3D>
  );
};

// ------------------------------------------------------------------ the lockup
const X = 1400; // centre of the right-hand column
const LogoWord: React.FC<{ t: number; at: number; text: string; top: number; size: number; tilt: number }> = ({ t, at, text, top, size, tilt }) => {
  if (t < at - 0.16) return null;
  const pre = t < at;
  const fall = clamp01((t - (at - 0.16)) / 0.16);
  const d = t - at;
  const w = pre ? 0 : 0.3 * Math.exp(-d * 8) * Math.cos(d * 26);
  const [sx, sy] = pre ? [1 - 0.2 * fall, 1 + 0.35 * fall] : [1 + w, 1 - w];
  const y = pre ? -1000 * (1 - fall * fall) : 0;
  const rot = pre ? tilt : tilt * Math.exp(-d * 10) * Math.cos(d * 20);
  return (
    <div style={{ position: "absolute", left: X, top, translate: `-50% ${y}px`, scale: `${sx} ${sy}`, transformOrigin: "50% 100%", rotate: `${rot}deg` }}>
      <InkText text={text} size={size} stroke={0.1} shadow={0.1} spacing={size * 0.03} />
    </div>
  );
};

// On 8ths: "Sneak out of class." 23.2-23.3.5, a beat of air, "Don't get ... caught." 24.0-24.1.5.
const TAG: [string, number, number][] = [["Sneak", 23, 2], ["out", 23, 2.5], ["of", 23, 3], ["class.", 23, 3.5], ["Don't", 24, 0], ["get", 24, 0.5], ["caught.", 24, 1.5]];
const PRESS = b(25);
const CHIPS = ["UP TO 8 PLAYERS", "PROXIMITY VOICE", "WINDOWS & MAC"];

export const LogoOverlay: React.FC<{ t: number }> = ({ t }) => {
  const cam = logoCam(t);
  const feet = toScreen(cam, HERO_P);
  // Gentle beat pulse once the card is built, easing off as the music rings out.
  const beatPhase = ((t - PRESS) % BEAT + BEAT) % BEAT;
  const pulse = t > b(25, 1.5) ? 0.012 * Math.exp(-beatPhase * 8) * (1 - 0.6 * clamp01((t - b(25, 2)) / (DURATION - b(25, 2)))) : 0;
  const soonIn = sp(t, b(24, 3.75), { stiffness: 520, damping: 17 });
  const pressU = t - PRESS;
  const press = pressU > -0.06 && pressU < 0.24 ? (pressU < 0 ? 1 + pressU / 0.06 : pressU < 0.08 ? 1 : 1 - (pressU - 0.08) / 0.16) : 0;
  const pop = t > PRESS + 0.06 ? 0.07 * Math.exp(-(t - PRESS - 0.06) * 8) * Math.cos((t - PRESS - 0.06) * 24) : 0;
  const wish = sp(t, b(25, 1), WOBBLE);
  return (
    <>
      <Flash t={t} at={LAND} color="#ffffff" dur={0.22} peak={0.7} />
      <Shockwave t={t} at={LAND} x={feet.x} y={feet.y} color="#ffffff" r={900} width={46} dur={0.45} />
      <Burst t={t} at={LAND + 0.02} x={feet.x} y={feet.y - 20} colors={["#8cc45c", "#b95c43", "#e2c9a6", "#ffffff"]} seed={5} power={1200} n={18} size={20} />
      <Burst t={t} at={b(23) + 0.04} x={X} y={200} colors={[C.gold, "#ffffff", C.orange]} seed={91} power={1400} n={16} size={20} />
      <Burst t={t} at={b(23, 0.5) + 0.04} x={X} y={430} colors={[C.gold, "#ffffff", "#7fe0a0", C.purple]} seed={92} power={1500} n={18} size={20} />
      <Shockwave t={t} at={b(23, 0.5)} x={X} y={400} color={C.gold} r={800} width={36} dur={0.4} />
      <div style={{ position: "absolute", inset: 0, scale: `${1 + pulse}`, transformOrigin: `${X}px 420px` }}>
        <LogoWord t={t} at={b(23)} text="BUNK" top={46} size={250} tilt={-7} />
        <LogoWord t={t} at={b(23, 0.5)} text="MASTER" top={276} size={250} tilt={6} />
        <div style={{ position: "absolute", left: X, top: 548, translate: "-50% 0", display: "flex", gap: 4, whiteSpace: "nowrap" }}>
          {TAG.map(([w, bar, beat]) => {
            const at = b(bar, beat);
            const s = sp(t, at, POP);
            return (
              <span key={w} style={{ display: "inline-block", opacity: clamp01(s * 3), scale: `${Math.max(0, s)}`, translate: `0 ${(1 - Math.min(1, s)) * 36}px` }}><InkText text={w} size={66} color="#ffffff" stroke={0.12} shadow={0.08} /></span>
            );
          })}
        </div>
        <div style={{ position: "absolute", left: X, top: 650, translate: "-50% 0", display: "flex", gap: 16 }}>
          {CHIPS.map((c, i) => {
            const s = sp(t, b(24, 2 + i * 0.5), SNAP);
            return (
              <span key={c} style={{ ...font(38, C.white), background: C.card, borderRadius: 16, padding: "12px 20px 9px", scale: `${Math.max(0, s)}`, opacity: clamp01(s * 3), whiteSpace: "nowrap", rotate: `${(1 - Math.min(1, s)) * (i - 1) * 12}deg` }}>{c}</span>
            );
          })}
        </div>
        <div style={{ position: "absolute", left: X, top: 752, translate: "-50% 0", scale: `${Math.max(0, soonIn) * (1 + pop)}`, rotate: `${(1 - Math.min(1, soonIn)) * -12}deg` }}>
          <GameButton label="COMING SOON" color={C.gold} press={press} size={78} />
        </div>
        <div style={{ position: "absolute", left: X, top: 912, translate: "-50% 0", scale: `${Math.max(0, wish)}`, opacity: clamp01(wish * 3) }}>
          <GameButton label="WISHLIST NOW" color={C.purple} size={50} />
        </div>
      </div>
      <Burst t={t} at={PRESS + 0.06} x={X} y={830} colors={[C.gold, "#ffffff", "#ffd24a"]} seed={44} power={1300} n={16} size={16} />
    </>
  );
};

export const LOGO_HITS: [number, number][] = [[LAND, 1.2], [b(23, 0.5), 0.55], [PRESS, 0.3]];
export const logoShake = (t: number) => shake(t, LOGO_HITS);
void lerp3; void outCubic;
