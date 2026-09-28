// Act "dodge" (bars 6-9): DODGE (teachers, guards, CCTV on the round minimap, then the same world in 3D:
// crouch-walking behind a teacher, slipping under a CCTV), then TALK YOUR WAY OUT (proximity voice: the
// teacher hears how loud, "Who's talking?!"; the excuse picker; blame a friend). Brief: videos/steam-brief.md.
import React from "react";
import { Burst, Flash, Shockwave } from "../../film/fxui";
import { Alert, Speech } from "../../launch/ui";
import { FONT } from "../../launch/tokens";
import { ACTS, b, BEAT, within } from "../cues";
import { toScreen } from "../Stage3D";
import { MiniMap } from "../dodge/Minimap";
import { VoiceBuild } from "../dodge/Voice";
import { camA, camB, camClass, camExcuse, ShotA, ShotB, ShotClass, ShotExcuse } from "../dodge/scenes";
import { ExcusePicker, GOLD, INK, Key, MicMeter, Pill, slam, SlamWord, TitleText } from "../dodge/ui";
import {
  BLAME, clamp01, CLASS_TEACHER, CUT_B, GLANCE, IRIS, classActors, excuseActors, FRIEND_SEAT, headTop, heroMap, heroShotAX, JELLY, lerp, PI, PICK, POP, shotAActors,
  shotBHero, shotBTeacher, HERO_Z, SNAP, sp, SPIN, TEACHER_Z, teacherX, watchers, type Watcher,
} from "../dodge/world";

const W = 1920, H = 1080;
const YELLOW = "#ffd24a", PURPLE = "#b07cff", RED = "#e0524f";
const inExpo = (u: number) => (u <= 0 ? 0 : Math.pow(2, 10 * (clamp01(u) - 1)));
const outExpo = (u: number) => (u >= 1 ? 1 : 1 - Math.pow(2, -10 * clamp01(u)));
const outCubic = (u: number) => 1 - Math.pow(1 - clamp01(u), 3);
const ease = (t: number, at: number, len: number, f = outExpo) => f(clamp01((t - at) / len));

const hash = (n: number) => {
  const x = Math.sin(n * 127.1 + 311.7) * 43758.5453;
  return (x - Math.floor(x)) * 2 - 1;
};
const noise = (x: number, seed: number) => {
  const i = Math.floor(x), f = x - i, u = f * f * (3 - 2 * f);
  return lerp(hash(i + seed * 57), hash(i + 1 + seed * 57), u);
};
function shake(t: number, hits: [number, number][]) {
  let k = 0;
  for (const [at, a] of hits) if (t >= at) k += a * Math.exp(-(t - at) / 0.2);
  k = Math.min(1.3, k);
  const q = k * k;
  return { x: noise(t * 24, 1) * 28 * q, y: noise(t * 24, 2) * 22 * q, r: noise(t * 24, 3) * 1.4 * q };
}

/** Diagonal stripes drifting over a flat colour field (trailer 1's gold card). */
const Stripes: React.FC<{ t: number; color: string; o?: number }> = ({ t, color, o = 0.1 }) => (
  <svg width={W} height={H} style={{ position: "absolute", inset: 0, opacity: o }}>
    {Array.from({ length: 26 }, (_, i) => (
      <rect key={i} x={-700 + i * 160 + ((t * 220) % 160)} y={-300} width={62} height={1700} fill={color} transform={`rotate(22 ${W / 2} ${H / 2})`} />
    ))}
  </svg>
);

const GAME = ["#ffc93c", "#e0524f", "#4f86e0", "#7fe0a0", "#b07cff", "#ff9a3c", "#ffffff"];

// =================================================================== bar 6: DODGE + the round minimap
const MAP = { cx: 590, cy: 520, R: 380, zoom: 25 };
const CORNER = { cx: 1718, cy: 818, R: 150, zoom: 9.5 };
const heroScreenA = (t: number) => {
  const a = shotAActors(t)[1];
  return toScreen(camA(t), [a.p[0], 0.75, a.p[2]]);
};

const LIST = [
  { text: "TEACHERS", at: b(6, 1), dot: "#d94a4a", id: "teacher" },
  { text: "GUARDS", at: b(6, 2), dot: "#ff9a4a", id: "guard" },
  { text: "CCTV", at: b(6, 3), dot: "#ff3030", id: "cctv" },
];

const DodgeTitleCard: React.FC<{ t: number }> = ({ t }) => {
  if (t >= IRIS) return null;
  const move = sp(t, b(6, 0.5), SNAP);
  const out = ease(t, b(7, 0.5), BEAT * 0.5, inExpo);
  // centre -> the right column
  const x = lerp(W / 2, 1480, move), y = lerp(H / 2, 190, move), s = lerp(1, 0.5, move);
  const bump = 1 + 0.05 * LIST.map((l) => l.at).reduce((acc, a) => acc + (t > a ? Math.exp(-(t - a) / 0.08) : 0), 0);
  return (
    <>
      <div style={{ position: "absolute", left: x + out * 900, top: y, translate: "-50% -50%", scale: `${s * bump}` }}>
        <SlamWord t={t} at={b(6)} size={410} color="#ffffff" from={2.8} tilt={-8}>DODGE</SlamWord>
      </div>
      <div style={{ position: "absolute", left: 1210, top: 350, display: "flex", flexDirection: "column", gap: 26, translate: `${out * 900}px 0` }}>
        {LIST.map((l, i) => {
          const k = sp(t, l.at, POP);
          const on = t >= l.at;
          return (
            <div key={i} style={{ display: "flex", alignItems: "center", gap: 30, opacity: on ? 1 : 0, translate: `${(1 - Math.min(1, k)) * 300}px 0`, rotate: `${(1 - Math.min(1, k)) * 8}deg` }}>
              <div style={{ width: 54, height: 54, borderRadius: 999, background: l.dot, border: `9px solid ${INK}`, scale: `${Math.max(0, k)}`, flex: "none" }} />
              <TitleText size={150} color="#ffffff" style={{ scale: `${slam(t, l.at, 1.5, 0.2)}`, transformOrigin: "0 60%" }}>{l.text}</TitleText>
            </div>
          );
        })}
      </div>
    </>
  );
};

const Field: React.FC<{ t: number }> = ({ t }) =>
  t < b(7, 2) ? (
    <div style={{ position: "absolute", inset: 0, background: YELLOW }}>
      <Stripes t={t} color={INK} o={0.1} />
    </div>
  ) : null;

const BarSix: React.FC<{ t: number }> = ({ t }) => {
  if (t >= IRIS) return null;
  const me = heroMap(t);
  const inS = sp(t, b(6, 0.5), JELLY);
  // the disc bumps on each of the arrow's darts (the 8ths)
  const hop = 1 + 0.035 * [b(6, 1.5), b(6, 2), b(6, 2.5), b(6, 3), b(6, 3.5), b(7)].reduce((a, k) => a + (t > k ? Math.exp(-(t - k) / 0.07) : 0), 0);
  // 7.0.5: zoom into the arrow; it lands on the 3D hero's screen spot on 7.1 (IRIS).
  const zin = ease(t, b(7, 0.5), BEAT * 0.5, (u) => u * u);
  const target = heroScreenA(IRIS);
  const cx = lerp(MAP.cx, target.x, zin), cy = lerp(MAP.cy, target.y, zin);
  const R = MAP.R * (1 + 0.25 * zin);
  const zoom = MAP.zoom * (1 + 2.2 * zin);
  const w = watchers(t);
  const show = Object.fromEntries(LIST.map((l) => [l.id, sp(t, l.at, JELLY)]));
  return (
    <>
      {inS > 0.001 ? (
        <div style={{ position: "absolute", inset: 0, scale: `${inS * hop}`, rotate: `${(1 - inS) * -50}deg`, transformOrigin: `${MAP.cx}px ${MAP.cy}px` }}>
          <MiniMap
            t={t} cx={cx} cy={cy} R={R} zoom={zoom} center={{ x: me.x, z: me.z }} rot={me.yaw} me={me} watchers={w} show={show}
            caption={"GROUND FLOOR   ·   [M] map"} captionScale={1 - zin}
          />
        </div>
      ) : null}
      <DodgeTitleCard t={t} />
      <Burst t={t} at={b(6)} x={W / 2} y={H / 2} colors={GAME} seed={4} power={1500} size={24} n={22} />
      <Shockwave t={t} at={b(6)} x={W / 2} y={H / 2} r={1300} width={70} color="#ffffff" />
      <Flash t={t} at={b(6)} color="#ffffff" dur={0.16} peak={0.85} />
    </>
  );
};

// =================================================================== bar 7: the same world in 3D, the HUD minimap in the corner
const cornerMap = (t: number) => {
  // 6.3.5 -> 7.0: the big disc shrinks into the HUD corner as the 3D opens up behind it.
  const u = ease(t, IRIS, BEAT * 1.4, outExpo);
  const land = sp(t, IRIS + BEAT * 0.6, { stiffness: 600, damping: 16 });
  const from = heroScreenA(IRIS);
  const k = u;
  return {
    cx: lerp(from.x, CORNER.cx, k), cy: lerp(from.y, CORNER.cy, k),
    R: lerp(MAP.R * 1.25, CORNER.R, k) * (t >= IRIS + BEAT * 0.6 ? 1 + 0.08 * (1 - land) : 1),
    zoom: lerp(MAP.zoom * 3.2, CORNER.zoom, k),
  };
};

const BarSeven: React.FC<{ t: number }> = ({ t }) => {
  if (t < IRIS || t >= b(8)) return null;
  const shotA = t < CUT_B;
  const iris = ease(t, IRIS, BEAT * 1.2, outCubic);
  const hs = heroScreenA(IRIS);
  const rIris = Math.hypot(W, H) * 1.05 * iris;
  // Who the HUD shows: you, and staff close by (hud.gd _map_markers: within 14 m). No cameras on the game's map.
  let me: { x: number; z: number; yaw: number };
  let w: Watcher[];
  if (shotA) {
    me = { x: heroShotAX(t), z: HERO_Z, yaw: -PI / 2 };
    w = watchers(t).filter((x) => x.kind === "staff");
  } else {
    const h = shotBHero(t);
    me = { x: h.p[0], z: h.p[2], yaw: -PI / 2 };
    const tch = shotBTeacher(t);
    w = [{ id: "teacher", x: tch.p[0], z: TEACHER_Z, yaw: -PI / 2, fov: 100, reach: 6.2, alert: 0, kind: "staff", label: "Ms. Okafor" }];
  }
  const m = cornerMap(t);
  const tch = shotAActors(t)[0];
  const tp = toScreen(camA(t), headTop(tch));
  const lensBlack = ease(t, b(7, 3.85), BEAT * 0.15, (u) => u);
  return (
    <>
      <div style={{ position: "absolute", inset: 0, clipPath: iris < 1 ? `circle(${rIris}px at ${hs.x}px ${hs.y}px)` : undefined }}>
        {shotA ? <ShotA t={t} /> : <ShotB t={t} />}
        {shotA ? <Alert t={t} at={GLANCE} x={tp.x} y={tp.y - 6} kind="?" size={170} /> : null}
        <div style={{ position: "absolute", inset: 0, background: "#16161c", opacity: lensBlack }} />
      </div>
      {/* the minimap: the big disc from bar 6 lands in the HUD corner */}
      <div style={{ position: "absolute", inset: 0, opacity: 1 - lensBlack }}>
        <MiniMap
          t={t} cx={m.cx} cy={m.cy} R={m.R} zoom={m.zoom} center={{ x: me.x, z: me.z }} rot={me.yaw} me={me} watchers={w}
          show={{ teacher: 1, guard: 1 }} caption={"GROUND FLOOR   ·   [M] map"} captionScale={ease(t, IRIS + BEAT * 0.6, 0.25, outCubic)}
        />
      </div>
    </>
  );
};

// =================================================================== bar 8: proximity voice, "Who's talking?!"
const BarEight: React.FC<{ t: number }> = ({ t }) => {
  if (t < b(8) || t >= b(9)) return null;
  const cam = camClass(t);
  const cast = classActors(t);
  const teacher = cast[0];
  const tp = toScreen(cam, headTop(teacher));
  const wide = t < SPIN;
  // The laugh's ring edge, riding towards her: the "~8 m" pill travels with it.
  const fx = FRIEND_SEAT[0], fz = FRIEND_SEAT[2];
  const dx = CLASS_TEACHER[0] - fx, dz = CLASS_TEACHER[2] - fz, dl = Math.hypot(dx, dz);
  const r = Math.min(8, 0.3 + ((t - b(8, 0.5)) / (SPIN - b(8, 0.5))) * 7.7);
  const edge = toScreen(cam, [fx + (dx / dl) * r, 0.05, fz + (dz / dl) * r]);
  const whisper = toScreen(cam, [fx + 1.5, 0.05, fz - 0.2]);
  const words = ["THEY", "HEAR", "HOW", "LOUD."];
  return (
    <>
      <ShotClass t={t} />
      {wide ? <Pill t={t} at={b(8) + 0.02} out={b(8, 0.5)} x={whisper.x + 60} y={whisper.y + 10} bg="#2f8f5a" size={56}>whisper: 1-2 m</Pill> : null}
      {wide && t >= b(8, 0.5) ? <Pill t={t} at={b(8, 0.5)} out={SPIN - 0.02} x={edge.x} y={edge.y - 30} bg="#c83a32" size={60}>talking: ~8 m</Pill> : null}
      {t >= SPIN && t < b(8, 2) ? <Speech t={t} at={SPIN} x={tp.x} y={tp.y - 20} text="Who's talking?!" size={104} /> : null}
      <MicMeter t={t} at={b(8)} out={b(8, 2) - 0.12} radius={t < b(8, 0.5) ? 1.5 : 8} size={58} />
      {/* the claim, in words, for everyone watching muted */}
      {t >= b(8, 2) ? (
        <div style={{ position: "absolute", left: 0, right: 0, top: 60, display: "flex", flexDirection: "column", alignItems: "center", gap: 18 }}>
          <div style={{ display: "flex", gap: 40 }}>
            {words.map((wd, i) => (
              <SlamWord key={i} t={t} at={b(8, 2 + i * 0.25)} size={200} color={i === 3 ? GOLD : "#ffffff"} from={2.2} tilt={i % 2 ? 5 : -5}>{wd}</SlamWord>
            ))}
          </div>
          <div style={{ opacity: clamp01(sp(t, b(8, 3), POP) * 2), scale: `${Math.max(0, sp(t, b(8, 3), POP))}` }}>
            <div style={{ fontFamily: FONT, fontSize: 92, lineHeight: 1, color: "#ffffff", background: INK, borderRadius: 999, padding: "14px 48px 10px", whiteSpace: "nowrap" }}>never what you say</div>
          </div>
        </div>
      ) : null}
      <div style={{ position: "absolute", left: 60, top: 56, scale: `${Math.max(0, sp(t, b(8), POP))}`, transformOrigin: "0 0", opacity: 1 - ease(t, b(8, 2) - 0.1, 0.12, (u) => u) }}>
        <div style={{ fontFamily: FONT, fontSize: 56, lineHeight: 1, color: INK, background: GOLD, borderRadius: 16, padding: "12px 26px 8px", whiteSpace: "nowrap", boxShadow: `0 8px 0 ${INK}` }}>PROXIMITY VOICE</div>
      </div>
      <Flash t={t} at={SPIN} color="#ffffff" dur={0.12} peak={0.5} />
      <Flash t={t} at={b(8, 2)} color="#ffffff" dur={0.1} peak={0.35} />
    </>
  );
};

// =================================================================== bar 9: TALK YOUR WAY OUT, the excuse picker, blame a friend
const ROWS = [b(10, 1), b(10, 2), b(10, 3), b(11)];

const BarNine: React.FC<{ t: number }> = ({ t }) => {
  if (t < b(10) || t >= b(12)) return null;
  // 9.0: hard cut to the purple field; 9.0.5 it lifts off the top to reveal the corridor.
  const lift = ease(t, b(10, 0.5), BEAT * 0.6, (u) => outCubic(u));
  const top = -lift * H;
  const titleMove = sp(t, b(10, 0.5), SNAP);
  const titleOut = ease(t, PICK - 0.02, 0.16, inExpo);
  const cam = camExcuse(t);
  const cast = excuseActors(t);
  const fr = cast[2];
  const fp = toScreen(cam, headTop(fr));
  const whip = ease(t, b(11, 3.5), b(12) - b(11, 3.5), inExpo);
  // behind the big picker the scene steps back a little
  const dim = ease(t, b(10, 0.5), 0.3, outCubic) * (1 - ease(t, PICK + 0.1, 0.2, outCubic));
  return (
    <>
      {t >= b(10) ? (
        <div style={{ position: "absolute", inset: 0, filter: whip > 0.02 ? `blur(${whip * 26}px)` : undefined }}>
          <ShotExcuse t={t} />
          <div style={{ position: "absolute", inset: 0, background: "#1a0d0d", opacity: 0.35 * dim }} />
          <Alert t={t} at={BLAME} x={fp.x} y={fp.y - 4} kind="!" size={240} />
          <ExcusePicker t={t} at={b(10, 0.5)} rows={ROWS} pick={PICK} chosen={3} timerFrom={b(10, 0.5)} />
          <Key t={t} at={PICK} label="4" x={1790} y={640} show={1 - ease(t, PICK + 0.25, 0.12, (u) => u)} />
          {/* what he shouts (director.gd: everyone close by hears your excuse), held to the whip */}
          {t >= PICK + 0.06 ? <Speech t={t} at={PICK + 0.06} x={W / 2} y={1030} text={"It was Arjun! They made me do it!"} size={96} /> : null}
        </div>
      ) : null}
      {t < b(10, 0.5) + BEAT * 0.7 ? (
        <div style={{ position: "absolute", left: 0, right: 0, top, height: H, background: PURPLE, overflow: "hidden" }}>
          <Stripes t={t} color="#ffffff" o={0.13} />
        </div>
      ) : null}
      {/* the title: slams on 9.0 on the field, then rides up to the top over the scene */}
      <div style={{ position: "absolute", left: W / 2, top: lerp(H / 2 + 10, 118, titleMove) - titleOut * 400, translate: "-50% -50%", scale: `${lerp(1, 0.5, titleMove)}` }}>
        <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 0 }}>
          <div style={{ display: "flex", gap: 50 }}>
            <SlamWord t={t} at={b(10)} size={250} color="#ffffff" tilt={-7}>TALK YOUR</SlamWord>
          </div>
          <div style={{ display: "flex", gap: 50, marginTop: -10 }}>
            <SlamWord t={t} at={b(10, 0.25)} size={300} color={GOLD} tilt={6} from={1.9}>WAY OUT</SlamWord>
          </div>
        </div>
      </div>
      <Burst t={t} at={b(10)} x={W / 2} y={H / 2} colors={GAME} seed={11} power={1600} size={24} n={24} />
      <Shockwave t={t} at={b(10)} x={W / 2} y={H / 2} r={1300} width={70} color="#ffffff" />
      <Flash t={t} at={b(10)} color="#ffffff" dur={0.14} peak={0.7} />
      <Flash t={t} at={BLAME} color={RED} dur={0.14} peak={0.25} />
    </>
  );
};

export const Dodge: React.FC<{ t: number }> = ({ t }) => {
  if (!within(t, ACTS.dodge)) return null;
  const sh = shake(t, [[b(6), 1.0], [IRIS + BEAT * 0.6, 0.3], [SPIN, 0.75], [b(9), 0.5], [b(9, 1), 0.2], [b(9, 2), 0.35], [b(10), 1.0], [PICK, 0.3], [BLAME, 0.6], [b(8, 2), 0.3]]);
  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden", background: INK }}>
      <div style={{ position: "absolute", inset: -40, translate: `${sh.x}px ${sh.y}px`, rotate: `${sh.r}deg` }}>
        <div style={{ position: "absolute", left: 40, top: 40, width: W, height: H, overflow: "hidden" }}>
          <Field t={t} />
          <BarSeven t={t} />
          <BarSix t={t} />
          <BarEight t={t} />
          <VoiceBuild t={t} />
          <BarNine t={t} />
        </div>
      </div>
    </div>
  );
};
