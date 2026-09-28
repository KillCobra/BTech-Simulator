// Act "open" (bars 0-6, 0 to 11.25 s): the cold open. Trailer 1's opening, rebuilt in the game's own 3D.
//  bar 0   dark ink field, a voxel alarm clock RINGS on 0.0 (hops on 0.1, 0.2), hands whip to 9:00 on 0.3
//  bar 1   the HUD period card assembles on 8ths beside it; 1.3.5 the classroom opens inside the clock face
//  bar 2   first person from the hero's seat: Ms. Okafor chalks, "Surprise test!", [E] Stand up, the hero rises
//  bar 3   into the aisle, suspicion fills on 8ths, classmates turn, 3.2 the teacher spins "!", 3.3 RUN!
//  bar 4   DROP 1: yellow striped field, SNEAK OUT / OF CLASS., the voxel hero vaults a bench and dashes out
//  bar 5   red field, DON'T GET / CAUGHT., teacher and guard give chase; 5.3.5 ink pixel wipe hands off to 6.0
import React from "react";
import { step, track } from "../../kit/spring";
import { Burst, PixelWipe, Rays, Shockwave } from "../../film/fxui";
import { Alert } from "../../launch/ui";
import { ACTS, b, BEAT, within } from "../cues";
import { toScreen } from "../Stage3D";
import { AlarmClock, R as CLOCK_R, ringing } from "../open/clock";
import { classActors, classCam, ClassroomScene, headTopOf, T } from "../open/classroom";
import { CHASE_CAM, chase5, ChaseScene, hero4, scroll4, SNEAK_CAM, SneakScene } from "../open/runner";
import { OStage } from "../open/stage";
import { DialogCard, GOLD, INK, mixHex, PeriodCard, Prompt, RED, Riiing, RunBanner, Slam, SpeedLines, Stripes, SuspicionCard, YELLOW } from "../open/ui";
import type { Cam } from "../../launch/camera3d";
import type { V3 } from "../../launch/voxel";

const W = 1920, H = 1080;
const clamp01 = (v: number) => Math.min(1, Math.max(0, v));
const lerp = (a: number, c: number, u: number) => a + (c - a) * u;
const noise = (t: number, k: number) => Math.sin(t * 57.3 + k * 1.7) * 0.6 + Math.sin(t * 91.1 + k * 4.3) * 0.4;

/** 2D shake from decaying hits: [at, px]. */
function shake2(t: number, hits: [number, number][]) {
  let a = 0;
  for (const [at, px] of hits) if (t >= at && t < at + 0.6) a += px * Math.exp(-(t - at) / 0.12);
  return { x: a * noise(t, 1), y: a * noise(t, 2), r: a * 0.02 * noise(t, 3) };
}

// ====================================================================== bars 0-1: the clock
const clockY = (t: number) => lerp(-0.85, -0.5, step(t - b(1), { stiffness: 260, damping: 22 }));
function clockX(t: number) {
  return lerp(0, -1.5, step(t - b(1), { stiffness: 260, damping: 22 }));
}
function clockCam(t: number): Cam {
  const cx = clockX(t);
  const base: Cam = { pos: [1.0 + cx * 0.25, 0.3, 5.2], look: [cx * 0.35 - 0.05, -0.2, 0], fov: 30 };
  // slow push through bar 0, bump on each ring
  const push = 0.35 * clamp01(t / b(1));
  let pos: V3 = [base.pos[0], base.pos[1], base.pos[2] - push];
  let look = base.look;
  // the dive into the face (the portal), inCubic from 1.3.5 to 2.0
  const u = clamp01((t - T.portal) / (T.land - T.portal));
  const e = u * u * u;
  if (u > 0) {
    const face: V3 = [cx, clockY(t), 0.2];
    pos = [lerp(pos[0], face[0], e), lerp(pos[1], face[1], e), lerp(pos[2], face[2] + 0.35, e)];
    look = [lerp(look[0], face[0], Math.min(1, u * 3)), lerp(look[1], face[1], Math.min(1, u * 3)), 0];
  }
  const kick = [0, 1, 2].reduce((s, k) => s + (t >= b(0, k) - 0.06 ? Math.exp(-(t - b(0, k) + 0.06) / 0.1) : 0), 0) + (t >= b(0, 3) ? 1.4 * Math.exp(-(t - b(0, 3)) / 0.08) : 0);
  return { pos: [pos[0] + kick * 0.03 * noise(t, 4), pos[1] + kick * 0.03 * noise(t, 5), pos[2]], look, fov: base.fov + kick * 1.2, roll: kick * 0.02 * noise(t, 6) };
}

const ClockLayer: React.FC<{ t: number }> = ({ t }) => {
  const cam = clockCam(t);
  const cx = clockX(t);
  const c = toScreen(cam, [cx, clockY(t), 0]);
  const ring = ringing(t);
  const tickPulse = [1, 1.5, 2, 2.5, 3].reduce((s, k) => s + (t >= b(1, k - 1) ? Math.exp(-(t - b(1, k - 1)) / 0.07) : 0), 0);
  const scale = 1 + 0.03 * Math.min(1, tickPulse);
  const lettersOut = Math.max(0, t - b(1)) / 0.35;
  return (
    <div style={{ position: "absolute", inset: 0, background: INK }}>
      {/* sunburst behind the ringing clock (film/fxui Rays), gold at low alpha */}
      <div style={{ position: "absolute", inset: 0, opacity: 0.06 * (0.2 + ring) * (1 - clamp01((t - b(1)) / 0.3)) }}>
        <Rays t={t} x={c.x} y={c.y} color={GOLD} n={16} spin={18} />
      </div>
      <OStage cam={cam} bg={null} dir={[4, 6, 10]} sun={1.6} amb={1.25} target={[cx, 0, 0]} size={4}>
        <AlarmClock t={t} p={[cx, clockY(t), 0]} s={scale} />
      </OStage>
      {/* rings on each ring of the bell */}
      {[0, 1, 2].map((k) => (
        <React.Fragment key={k}>
          <Shockwave t={t} at={b(0, k) - 0.07} x={c.x} y={c.y - 60} color={GOLD} r={1150} width={46} dur={0.55} />
          <Shockwave t={t} at={b(0, k) + 0.02} x={c.x} y={c.y - 60} color="#ffffff" r={800} width={14} dur={0.45} />
        </React.Fragment>
      ))}
      <Shockwave t={t} at={b(0, 3)} x={c.x} y={c.y} color={GOLD} r={520} width={26} dur={0.35} />
      <Burst t={t} at={b(0, 3)} x={c.x} y={c.y - 40} colors={[GOLD, "#ffffff", RED]} n={14} seed={4} power={900} size={14} />
      {/* RIIIING! */}
      {t < b(1) + 0.9 ? (
        <div style={{ position: "absolute", left: 0, right: 0, top: 6, display: "flex", justifyContent: "center", translate: `${(c.x - W / 2) * 0.6}px 0` }}>
          <Riiing t={t} at={-0.08} ring={ring} out={lettersOut} size={196} />
        </div>
      ) : null}
    </div>
  );
};

/** Where the clock face is on screen (for the portal clip). */
function facePortal(t: number) {
  const cam = clockCam(t);
  const cx = clockX(t);
  const c = toScreen(cam, [cx, clockY(t), 0.2]);
  const e = toScreen(cam, [cx + (CLOCK_R - 0.14), clockY(t), 0.2]);
  const e2 = toScreen(cam, [cx, clockY(t) + (CLOCK_R - 0.14), 0.2]);
  const u = clamp01((t - T.portal) / (T.land - T.portal));
  // the face swells past the screen a couple of frames before the downbeat
  return { x: c.x, y: c.y, r: Math.max(Math.hypot(e.x - c.x, e.y - c.y), Math.hypot(e2.x - c.x, e2.y - c.y)) * (1 + 6 * u ** 4) };
}

// ====================================================================== the period card, bar 1 -> HUD
const ROWS = [b(1) + 0.03, b(1, 0.5), b(1, 1), b(1, 1.5)];
function secsLeft(t: number) {
  return 300 - Math.max(0, Math.floor((t - b(1, 1)) / BEAT));
}
const CardLayer: React.FC<{ t: number; shake: { x: number; y: number } }> = ({ t, shake }) => {
  if (t < b(1) - 0.05 || t >= b(3, 3.5) + 0.25) return null;
  const fly = step(t - T.portal, { stiffness: 420, damping: 30 });
  const sBig = 1.0, sHud = 0.6;
  const x = lerp(940, 32, fly), y = lerp(372, 32, fly);
  const s = lerp(sBig, sHud, fly);
  const slideIn = step(t - b(1), { stiffness: 420, damping: 24 });
  const leave = clamp01((t - b(3, 3.5)) / 0.2);
  const tickAt = t >= b(1, 1) ? b(1, 1) + Math.floor((t - b(1, 1)) / BEAT) * BEAT : undefined;
  const flying = fly > 0.02 && fly < 0.97;
  return (
    <div style={{
      position: "absolute", left: x + (1 - slideIn) * 900 + shake.x * fly, top: y + shake.y * fly - leave * 500, scale: `${s}`, transformOrigin: "0 0",
      rotate: `${(1 - slideIn) * 10 + (flying ? -4 * Math.sin(fly * Math.PI) : 0)}deg`,
    }}>
      <PeriodCard t={t} k={3} panelAt={b(1) - 0.02} at={ROWS} secs={secsLeft(t)} tickAt={tickAt} />
    </div>
  );
};

// ====================================================================== bars 2-3: the classroom
const SUS: [number, number][] = [[T.step, 0], [T.step + 0.05, 12], [b(3, 0.5), 24], [b(3, 1), 37], [b(3, 1.5), 51], [T.spot, 78], [b(3, 2.5), 90], [T.run, 100]];
const susAt = (t: number) => Math.min(100, Math.max(0, track(t, SUS, { stiffness: 700, damping: 26 })));

const ClassLayer: React.FC<{ t: number }> = ({ t }) => {
  const cam = classCam(t);
  const cast = classActors(t);
  const head = (id: string) => {
    const a = cast.find((x) => x.id === id)!;
    return toScreen(cam, headTopOf(a));
  };
  const sh = shake2(t, [[T.spot, 10], [T.run, 26]]);
  const sus = susAt(t);
  const cardIn = step(t - T.step, { stiffness: 420, damping: 22 });
  const redFlash = t >= T.run ? Math.exp(-(t - T.run) / 0.16) : 0;
  const susHit = [b(3, 0.5), b(3, 1), b(3, 1.5), T.spot, b(3, 2.5), T.run].reduce((s, at) => s + (t >= at ? Math.exp(-(t - at) / 0.08) : 0), 0);
  const glances: [string, number][] = [["friendA", T.glance1 + BEAT / 4], ["npc2", T.glance2], ["npc1", T.glance2 + BEAT / 4]];
  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden", background: "#f3e3c3" }}>
      <OStage cam={cam} bg="#f3e3c3" target={[0, 0, 1]} size={8} amb={1.05}>
        <ClassroomScene t={t} />
      </OStage>
      {/* the room goes hot as suspicion rises (the game's red warning edge) */}
      <div style={{ position: "absolute", inset: 0, boxShadow: `inset 0 0 ${140 + 160 * sus / 100}px ${30 + 50 * sus / 100}px rgba(255,59,59,${0.32 * (sus / 100) ** 2})` }} />
      <div style={{ position: "absolute", inset: 0, translate: `${sh.x}px ${sh.y}px`, rotate: `${sh.r}deg` }}>
        {glances.map(([id, at]) => {
          const p = head(id);
          return !p.behind && t > at - 0.02 && t < T.spot + 0.15 ? <Alert key={id} t={t} at={at} x={p.x} y={p.y} kind="?" size={120} /> : null;
        })}
        {(() => {
          const p = head("teacher");
          return t >= T.spot - 0.02 ? <Alert t={t} at={T.spot + 0.03} x={p.x} y={p.y - 10} kind="!" size={230} /> : null;
        })()}
        <DialogCard t={t} at={T.land} out={T.press} who="MS. OKAFOR" chunks={[["Surprise test!", T.land + 0.03], ["Pens out,", b(2, 0.5)], ["eyes down!", b(2, 1)]]} />
        <div style={{ position: "absolute", left: 0, right: 0, top: 640, display: "flex", justifyContent: "center" }}>
          <Prompt t={t} at={T.prompt} press={T.press} out={T.step - 0.1} />
        </div>
        {t >= T.step - 0.05 ? (
          <div style={{ position: "absolute", right: 36, top: 36, translate: `${(1 - cardIn) * 1000}px ${noise(t, 8) * 8 * Math.min(1, susHit)}px`, scale: `${1 + 0.04 * Math.min(1, susHit)}`, transformOrigin: "100% 0" }}>
            <SuspicionCard t={t} value={sus} seenAt={T.spot} k={3} />
          </div>
        ) : null}
      </div>
      <Shockwave t={t} at={T.run} x={W / 2} y={H / 2} color="#ffffff" r={1300} width={70} dur={0.45} />
      <div style={{ position: "absolute", inset: 0, background: "#ff4a4a", opacity: 0.55 * redFlash }} />
    </div>
  );
};

// ====================================================================== bar 4: SNEAK OUT OF CLASS.
const PX_PER_M = 320;
const SneakLayer: React.FC<{ t: number }> = ({ t }) => {
  const h = hero4(t);
  const feet = toScreen(SNEAK_CAM, [h.p[0], 0, 0]);
  const sh = shake2(t, [[b(4) + 0.02, 24], [b(4, 1), 14], [b(4, 2) + 0.26, 10], [b(4, 3), 8]]);
  const zoom = 1 + 0.03 * [b(4), b(4, 1), b(4, 2), b(4, 3)].reduce((s, at) => s + (t >= at ? Math.exp(-(t - at) / 0.1) : 0), 0);
  const out = clamp01((t - b(4, 3.5)) / 0.2);
  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden" }}>
      <Stripes bg={YELLOW} stripe={GOLD} offset={scroll4(t) * PX_PER_M * 0.6} width={80} period={180} angle={28} />
      <SpeedLines t={t} color="#ffffff" n={12} speed={2600 + 2600 * clamp01((t - b(4, 3)) / BEAT)} y0={560} y1={1040} o={0.7} />
      <div style={{ position: "absolute", inset: 0, scale: `${zoom}`, translate: `${sh.x}px ${sh.y}px` }}>
        <OStage cam={SNEAK_CAM} bg={null} dir={[-6, 14, 9]} target={[1.5, 0, 0]} size={7} amb={1.15}>
          <SneakScene t={t} />
        </OStage>
        <Burst t={t} at={b(4) + 0.02} x={feet.x} y={feet.y - 10} colors={["#ffffff", "#fbf1dc", GOLD]} n={14} seed={2} power={700} size={16} />
        <Burst t={t} at={b(4, 2) + 0.26} x={feet.x} y={feet.y - 10} colors={["#ffffff", "#fbf1dc"]} n={10} seed={7} power={560} size={13} />
        <div style={{ position: "absolute", left: 100, top: 230, display: "flex", flexDirection: "column", gap: 0, rotate: `${sh.r}deg`, translate: `${-out * 300}px 0`, opacity: 1 - out }}>
          <Slam t={t} at={b(4)} text="SNEAK OUT" size={270} tilt={-4} origin="0% 60%" />
          <div style={{ marginTop: -20, marginLeft: 60 }}>
            <Slam t={t} at={b(4, 1)} text="OF CLASS." size={270} color={GOLD} tilt={3} origin="0% 60%" />
          </div>
        </div>
      </div>
      <div style={{ position: "absolute", inset: 0, background: "#ffffff", opacity: t >= b(4) && t < b(4) + 0.05 ? 0.55 * (1 - (t - b(4)) / 0.05) : 0 }} />
    </div>
  );
};

// ====================================================================== bar 5: DON'T GET CAUGHT.
const ChaseLayer: React.FC<{ t: number }> = ({ t }) => {
  const c = chase5(t);
  const sh = shake2(t, [[b(5), 24], [b(5, 2), 30], [b(5, 3), 14]]);
  const zoom = 1 + 0.03 * [b(5), b(5, 1), b(5, 2), b(5, 3)].reduce((s, at) => s + (t >= at ? Math.exp(-(t - at) / 0.1) : 0), 0);
  const tHead = toScreen(CHASE_CAM, [c.teachX, 1.95, -0.1]);
  const gHead = toScreen(CHASE_CAM, [c.guardX, 1.95, -0.6]);
  const offset = (t - b(4, 3.5)) * 7.5 * 270 * 0.6;
  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden" }}>
      <Stripes bg={RED} stripe="#c4492f" offset={offset} width={80} period={180} angle={28} />
      <SpeedLines t={t} color="#ffffff" n={12} speed={3200} y0={620} y1={1060} o={0.45} />
      <div style={{ position: "absolute", inset: 0, scale: `${zoom}`, translate: `${sh.x}px ${sh.y}px` }}>
        <OStage cam={CHASE_CAM} bg={null} dir={[-6, 14, 9]} target={[0, 0, 0]} size={9} amb={1.15}>
          <ChaseScene t={t} />
        </OStage>
        {t < b(5, 2) + 0.02 ? <Alert t={t} at={b(5, 1) + 0.12} x={tHead.x} y={tHead.y - 30} kind="!" size={200} /> : null}
        <Alert t={t} at={b(5, 2) + 0.12} x={gHead.x} y={gHead.y - 30} kind="!" size={200} />
        <div style={{ position: "absolute", left: 0, right: 0, top: 12, display: "flex", flexDirection: "column", alignItems: "center", rotate: `${sh.r}deg` }}>
          <Slam t={t} at={b(5)} text="DON'T GET" size={230} tilt={-3} />
          <div style={{ marginTop: -26 }}>
            <Slam t={t} at={b(5, 2)} text="CAUGHT." size={300} color={GOLD} tilt={4} />
          </div>
        </div>
      </div>
      <div style={{ position: "absolute", inset: 0, background: "#ffffff", opacity: t >= b(5) && t < b(5) + 0.05 ? 0.5 * (1 - (t - b(5)) / 0.05) : 0 }} />
    </div>
  );
};

// ====================================================================== the act
export const Open: React.FC<{ t: number }> = ({ t }) => {
  if (!within(t, ACTS.open)) return null;
  const portal = facePortal(t);
  const inPortal = t >= T.portal && t < T.land;
  // bar 3.3.5 -> 4.0: yellow diagonal wipe from the right; 4.3.5 -> 5.0: red wipe chasing from the left
  const wipeY = clamp01((t - b(3, 3.5)) / (T.land - T.portal));
  const wipeR = clamp01((t - b(4, 3.5)) / (BEAT / 2));
  const ey = wipeY * wipeY * (3 - 2 * wipeY);
  const er = wipeR * wipeR * (3 - 2 * wipeR);
  const yEdge = lerp(W + 700, -700, ey);
  const rEdge = lerp(-700, W + 700, er);
  const heroOut = chase5(t);
  const handFrom = toScreen(CHASE_CAM, [heroOut.heroX, 1.0, 0.4]);
  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden", background: INK }}>
      {t < T.land + 0.02 ? <ClockLayer t={t} /> : null}
      {t >= T.portal && t < b(4) ? (
        <div style={{ position: "absolute", inset: 0, clipPath: inPortal ? `circle(${portal.r}px at ${portal.x}px ${portal.y}px)` : undefined }}>
          <ClassLayer t={t} />
        </div>
      ) : null}
      {inPortal ? (
        <svg width={W} height={H} style={{ position: "absolute", inset: 0 }}>
          <circle cx={portal.x} cy={portal.y} r={portal.r} fill="none" stroke="#ffffff" strokeWidth={10 * (1 - (t - T.portal) / (T.land - T.portal))} />
        </svg>
      ) : null}
      <CardLayer t={t} shake={shake2(t, [[T.spot, 10], [T.run, 26]])} />
      {t >= b(3, 3.5) && t < b(5) ? (
        <div style={{ position: "absolute", inset: 0, clipPath: t < b(4) ? `polygon(${yEdge + 300}px 0, ${W + 800}px 0, ${W + 800}px ${H}px, ${yEdge - 300}px ${H}px)` : undefined }}>
          <SneakLayer t={t} />
        </div>
      ) : null}
      {t >= b(3, 3.5) && t < b(4) ? (
        <svg width={W} height={H} style={{ position: "absolute", inset: 0 }}>
          {[0, 1].map((k) => (
            <polygon key={k} points={`${yEdge + 300 - 60 - k * 110},0 ${yEdge + 300 - k * 110},0 ${yEdge - 300 - k * 110},${H} ${yEdge - 300 - 60 - k * 110},${H}`} fill={k ? YELLOW : GOLD} />
          ))}
        </svg>
      ) : null}
      {t >= T.run && t < b(4) + 0.15 ? (() => {
        const sh = shake2(t, [[T.run, 26]]);
        return (
          <div style={{ position: "absolute", inset: 0, display: "grid", placeItems: "center", translate: `${sh.x}px ${sh.y}px` }}>
            <RunBanner t={t} at={T.run} out={b(4) - 0.11} />
          </div>
        );
      })() : null}
      {t >= b(4, 3.5) ? (
        <div style={{ position: "absolute", inset: 0, clipPath: t < b(5) ? `polygon(-800px 0, ${rEdge + 300}px 0, ${rEdge - 300}px ${H}px, -800px ${H}px)` : undefined }}>
          <ChaseLayer t={t} />
        </div>
      ) : null}
      {t >= b(4, 3.5) && t < b(5) ? (
        <svg width={W} height={H} style={{ position: "absolute", inset: 0 }}>
          {[0, 1].map((k) => (
            <polygon key={k} points={`${rEdge + 300 + k * 110},0 ${rEdge + 360 + k * 110},0 ${rEdge - 240 + k * 110},${H} ${rEdge - 300 + k * 110},${H}`} fill={k ? mixHex(RED, "#ffffff", 0.25) : "#ffffff"} />
          ))}
        </svg>
      ) : null}
      {/* hand-off: ink pixel wipe from the hero, covered exactly on 6.0 */}
      <PixelWipe t={t} start={b(5, 3.5)} dur={(BEAT / 2) / 1.8} color={INK} mode="cover" cell={120} origin={[handFrom.x, handFrom.y]} />
      {t >= b(6) - 1.5 / 60 ? <div style={{ position: "absolute", inset: 0, background: INK }} /> : null}
    </div>
  );
};
