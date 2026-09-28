// Act "chaos" (local bars 10-15, the busiest groove): CAUSE CHAOS! then three 3D gags cut on beats
// (trolley into the proctor, paper ball bonk, fire extinguisher smoke + FIRE ALARM) under a style
// score receipt; SURPRISE TEST! one paper at a time (bars 12-13); Pappu Uncle's canteen built one item
// per beat (14), buys + quest chain + merit badge (15), gold pixel cover handing off on 16.0. See videos/steam-brief.md.
import React from "react";
import { ACTS, b, BEAT, within } from "../cues";
import { Stage3D } from "../Stage3D";
import { Burst, Flash, PixelWipe, Shockwave } from "../../film/fxui";
import { clamp01, easeOut, expoIn, rand, shake, sp, WOBBLE } from "../../launch/juice";
import { ITEM_SVG } from "../../launch/icons";
import { C } from "../../launch/tokens";
import { Alert, Banner, Icon } from "../../launch/ui";
import { camAt, ChaosScene, EXT_WALL, headPin, HIT, nozzle, pin, shotAt, SHOT } from "../chaos/world";
import { Canteen, CANTEEN_OUT, CHAIN_DONE, Combos, Field, FIELD, GAME_COLS, Prompt, REACTOR_STOP, Slam, SORTED, SUMS_PRESS, Tests } from "../chaos/ui";

const HITS: [number, number][] = [
  [b(10), 30], [b(10, 0.5), 14], [HIT.trolley, 44], [HIT.trolley + 0.2, 20], [b(10, 3), 8], [HIT.bonk, 30],
  [b(11, 1), 8], [HIT.spray, 18], [b(11, 2.5), 12], [HIT.alarm, 16], [b(12), 26], [b(12, 0.5), 12],
  [b(12, 1), 16], [REACTOR_STOP, 8], [b(13), 16], [SUMS_PRESS, 8], [b(13, 2), 16], [SORTED, 14],
  [b(14), 26], [b(14, 1), 10], [b(14, 2), 10], [b(14, 3), 10], [b(15), 12], [CHAIN_DONE, 18], [b(15, 2), 10], [b(15, 3), 12],
];

/** A few frames of inverted, crushed silhouette on an impact (anime impact frame). */
const impactFilter = (t: number) => {
  for (const at of [HIT.trolley, HIT.bonk]) if (t >= at && t < at + 0.05) return "grayscale(1) contrast(9) invert(1)";
  return undefined;
};

const OpenTitle: React.FC<{ t: number }> = ({ t }) => {
  if (t >= b(10, 1) + 0.05) return null;
  const out = expoIn(clamp01((t - (b(10, 1) - 0.1)) / 0.15));
  return (
    <div style={{ position: "absolute", inset: 0, translate: `0 ${-out * 1150}px`, rotate: `${-out * 4}deg` }}>
      <Field t={t} color={FIELD.red}>
        <Burst t={t} at={b(10)} x={640} y={430} colors={GAME_COLS} seed={2} power={1500} size={24} n={20} />
        <Burst t={t} at={b(10, 0.5)} x={1200} y={650} colors={GAME_COLS} seed={7} power={1700} size={26} n={22} />
        <Shockwave t={t} at={b(10, 0.5)} x={960} y={620} color="#ffffff" r={1300} width={60} />
        <div style={{ position: "absolute", inset: 0, display: "grid", placeContent: "center", justifyItems: "center" }}>
          <Slam t={t} at={b(10)} text="CAUSE" size={230} color={C.white} tilt={-6} />
          <Slam t={t} at={b(10, 0.5)} text="CHAOS!" size={260} color={C.gold} tilt={7} from={1.7} />
        </div>
      </Field>
    </div>
  );
};

/** Pinned 2D over the 3D shots: alerts, the prompt and the extinguisher icon, the smoke flood, the alarm. */
const Overlay3D: React.FC<{ t: number }> = ({ t }) => {
  const s = shotAt(t);
  const nodes: React.ReactNode[] = [];
  if (s === "trolley" && t < HIT.trolley) {
    const p = headPin(t, "proctor");
    if (p) nodes.push(<Alert key="a1" t={t} at={b(10, 1.5)} x={p.x} y={p.y - 6} kind="!" size={190} />);
  }
  if (s === "trolley" && t >= HIT.trolley) {
    const p = pin(t, [0.9, 1.1, 0.7]);
    nodes.push(<Burst key="bt" t={t} at={HIT.trolley} x={p.x} y={p.y} colors={["#e0a050", "#c9853a", "#ffd24a", "#ffffff"]} seed={11} power={1700} size={26} n={20} />);
    nodes.push(<Shockwave key="st" t={t} at={HIT.trolley} x={p.x} y={p.y} color="#ffffff" r={900} width={50} dur={0.4} />);
  }
  if (s === "paper" && t >= HIT.bonk) {
    const p = headPin(t, "teacher");
    if (p) {
      nodes.push(<Shockwave key="sb" t={t} at={HIT.bonk} x={p.x} y={p.y + 120} color="#ffffff" r={600} width={40} dur={0.35} />);
      nodes.push(<Burst key="bb" t={t} at={HIT.bonk} x={p.x} y={p.y + 120} colors={["#fbf6e8", "#ffd24a", "#ffffff"]} seed={23} power={1300} size={22} n={16} />);
      nodes.push(<Alert key="a2" t={t} at={HIT.bonk + BEAT * 0.25} x={p.x + 30} y={p.y - 20} kind="?" size={230} />);
    }
  }
  if (s === "spray") {
    const w = pin(t, [EXT_WALL[0], EXT_WALL[1] + 0.5, EXT_WALL[2]]);
    void w;
    nodes.push(<Prompt key="pr" t={t} at={b(11, 1)} until={HIT.grab} x={880} y={130} />);
    // The item icon pops next to the prompt, then flies into the hero's hands on the grab.
    const ic = sp(t, b(11, 1) + 0.03, WOBBLE);
    const fly = easeOut(clamp01((t - HIT.grab) / 0.14));
    if (ic > 0.001 && fly < 1) {
      const hand = pin(t, nozzle(t));
      const x0 = 1560, y0 = 130;
      nodes.push(
        <div key="ic" style={{ position: "absolute", left: x0 + (hand.x - x0) * fly, top: y0 + (hand.y - y0) * fly, translate: "-50% -50%", scale: `${Math.max(0, ic) * (1 - fly * 0.85)}`, rotate: `${(1 - Math.min(1, ic)) * -90 - 10 + fly * 40}deg` }}>
          <Icon svg={ITEM_SVG.extinguisher} size={190} />
        </div>,
      );
    }
    if (t >= HIT.grab && t < HIT.grab + 0.4) {
      const hand = pin(t, nozzle(HIT.grab));
      nodes.push(<Burst key="bg" t={t} at={HIT.grab + 0.1} x={hand.x} y={hand.y} colors={["#e0524f", "#ffffff", C.gold]} seed={29} power={700} size={14} n={10} />);
    }
    // Staff lose you in the smoke.
    (["guard", "teacher"] as const).forEach((id, i) => {
      const p = headPin(t, id);
      if (p && !p.behind && t < HIT.alarm) nodes.push(<Alert key={`q${id}`} t={t} at={HIT.spray + 0.25 + i * 0.08} x={p.x} y={p.y - 4} kind="?" size={130} />);
    });
    // Siren light on 8ths once the alarm goes.
    if (t >= HIT.alarm) {
      const ph = Math.floor((t - HIT.alarm) / (BEAT / 2)) % 2;
      nodes.push(<div key="sir" style={{ position: "absolute", inset: 0, boxShadow: `inset ${ph ? 280 : -280}px 0 260px -60px ${ph ? "rgba(255,40,40,.6)" : "rgba(60,110,255,.5)"}` }} />);
    }
    nodes.push(<SmokeFlood key="sf" t={t} />);
    nodes.push(<Banner key="ban" t={t} at={HIT.alarm} color="#e0524f" text="FIRE ALARM!  Staff at the plaza" top={60} size={84} />);
  }
  return <>{nodes}</>;
};

/** 2D puffs from the nozzle that fill the frame white by 11.3.75 (cut to the test on 12.0). */
const SmokeFlood: React.FC<{ t: number }> = ({ t }) => {
  const from = HIT.spray + BEAT * 0.25;
  if (t < from) return null;
  const o = pin(t, nozzle(t));
  const white = clamp01((t - b(11, 3.55)) / (BEAT * 0.3));
  return (
    <>
      {Array.from({ length: 30 }, (_, i) => {
        const born = from + (i / 30) * BEAT * 1.9;
        const d = t - born;
        if (d < 0) return null;
        const ang = Math.PI + (rand(i) - 0.5) * 1.6;
        const dist = 120 + d * (900 + rand(i + 1) * 600);
        const r = 80 + d * (520 + rand(i + 2) * 420) * (i > 18 ? 1.6 : 1);
        const x = o.x + Math.cos(ang) * dist * 1.3, y = o.y + Math.sin(ang) * dist * 0.6 + (rand(i + 4) - 0.5) * 260;
        return <div key={i} style={{ position: "absolute", left: x - r, top: y - r, width: r * 2, height: r * 2, borderRadius: "50%", background: "#f4f6f8", opacity: 0.55 + 0.4 * clamp01(d * 3), boxShadow: "inset -30px -40px 0 rgba(200,210,220,.35)" }} />;
      })}
      {white > 0 ? <div style={{ position: "absolute", inset: 0, background: "#f4f6f8", opacity: white }} /> : null}
    </>
  );
};

export const Chaos: React.FC<{ t: number }> = ({ t }) => {
  if (!within(t, ACTS.chaos)) return null;
  const sh = shake(t, HITS);
  const show3D = t >= b(10, 0.8) && t < b(12);
  const s = shotAt(t) ?? "trolley";
  const alarm = t >= HIT.alarm && s === "spray";
  const ph = Math.floor((t - HIT.alarm) / (BEAT / 2)) % 2;
  const target = s === "trolley" ? [1.2, 0, 1.0] : s === "paper" ? [0.8, 0, 0.9] : [-1.5, 0, 0.8];
  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden", background: FIELD.ink }}>
      <div style={{ position: "absolute", inset: -40, translate: `${sh.x}px ${sh.y}px`, rotate: `${sh.r}deg` }}>
        <div style={{ position: "absolute", left: 40, top: 40, width: 1920, height: 1080, overflow: "hidden" }}>
          {show3D ? (
            <>
              <Stage3D cam={camAt(t)} bg="#e7d2aa" shadowTarget={target as [number, number, number]} shadowSize={9}
                tint={alarm ? (ph ? "#ff9a9a" : "#9ab8ff") : "#ffffff"} amb={alarm ? 1.2 : 1.0} sun={1.9}
                style={{ filter: impactFilter(t) }}>
                <ChaosScene t={t} />
              </Stage3D>
              <Overlay3D t={t} />
            </>
          ) : null}
          <OpenTitle t={t} />
          <Tests t={t} />
          <Canteen t={t} />
        </div>
      </div>
      <Combos t={t} />
      <Flash t={t} at={b(10)} dur={0.08} peak={0.35} />
      <Flash t={t} at={HIT.trolley} dur={0.12} peak={0.5} />
      <Flash t={t} at={b(12)} dur={0.08} peak={0.35} />
      <Flash t={t} at={b(14)} dur={0.08} peak={0.35} />
      <PixelWipe t={t} start={CANTEEN_OUT} dur={0.2} color={C.gold} mode="cover" cell={120} />
    </div>
  );
};
