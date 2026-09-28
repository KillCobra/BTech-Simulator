// Bars 9-12: one big university per bar (the real maps, filmed in the game), whip-cut on the downbeat.
import React from "react";
import { Img, staticFile } from "remotion";
import { clamp01 } from "../../kit/time";
import { b } from "../cues";
import { ease, HEAVY, inCubic, JELLY, lerp, noise1, outCubic, outExpo, POP, pulses, SNAP, sp } from "../fx";
import { Burst, Iris, slam } from "../fxui";
import { C, H, W } from "../tokens";
import { ExitMarker, font, NameTag, Outlined } from "../ui";

// Exits come from README.md ("Maps"). Positions are in plate pixels (1920x1080 captures).
const MAPS = [
  {
    bar: 9, plate: "c_air1", name: "GRAND CAMPUS", venue: "The Old Quadrangle", bg: C.purple,
    exits: [
      { label: "Main gate", x: 330, y: 700 },
      { label: "Storm drain", x: 1180, y: 1000 },
      { label: "Scaffolding", x: 1640, y: 520 },
    ],
  },
  {
    bar: 10, plate: "c_air2", name: "WHISPERING PINES", venue: "Pinewood Lodges", bg: C.green,
    exits: [
      { label: "Rope bridge", x: 1500, y: 470 },
      { label: "Logging gate", x: 300, y: 820 },
      { label: "Creek culvert", x: 1760, y: 700 },
    ],
  },
  {
    bar: 11, plate: "c_air3", name: "LAGOON ISLAND", venue: "The Marine Institute", bg: C.cyan,
    exits: [
      { label: "The bridge", x: 1350, y: 930 },
      { label: "Ferry", x: 1720, y: 560 },
      { label: "Fishing boat", x: 180, y: 760 },
    ],
  },
  {
    bar: 12, plate: "c_air4", name: "DOWNTOWN CAMPUS", venue: "Quibble Towers", bg: C.orange,
    exits: [{ label: "Metro", x: 700, y: 900 }],
  },
] as const;

const FRIENDS = ["Riya", "Kenji", "Amara", "Mateo", "Zoe", "Omar", "Lin", "Sam"];
const FRIEND_COLORS = [C.classA, C.classB, C.classC, C.lab, C.orange, C.teal, C.pink, C.yellow];

const CARD_W = 1280, CARD_H = 720;

const MapCard: React.FC<{ t: number; m: (typeof MAPS)[number]; i: number }> = ({ t, m, i }) => {
  const start = b(m.bar);
  const end = b(m.bar + 1);
  const enterFrom = i === 0 ? 0 : 1;
  // whip: the incoming card lands on the downbeat; the outgoing one leaves on the same downbeat
  const inU = i === 0 ? sp(t, start, JELLY) : ease(t, start - 0.12, 0.26, outExpo);
  const outU = m.bar === 12 ? 0 : ease(t, end - 0.12, 0.2, inCubic);
  const vx = enterFrom ? (1 - inU) * 2300 : 0;
  const ox = -outU * 2600;
  const smear = Math.abs((1 - inU) * enterFrom) + outU; // stretch while moving fast
  const drift = clamp01((t - start) / (end - start));
  const kick = 1 + 0.015 * pulses(t, [b(m.bar, 1), b(m.bar, 2), b(m.bar, 3), b(m.bar, 4)], 0.09);
  const scale0 = i === 0 ? lerp(0.2, 1, inU) : 1;
  return (
    <div
      style={{
        position: "absolute", left: 560, top: 230, width: CARD_W, height: CARD_H,
        translate: `${vx + ox}px 0`,
        scale: `${scale0 * kick * (1 + smear * 0.25)} ${scale0 * kick * (1 - smear * 0.12)}`,
        transform: `perspective(2400px) rotateY(${-13 + drift * 5}deg) rotateX(${5}deg) rotateZ(${-2 + drift * 1.5}deg)`,
        filter: smear > 0.05 ? `blur(${smear * 12}px)` : undefined,
      }}
    >
      <div style={{ position: "absolute", inset: 0, translate: "22px 30px", borderRadius: 30, background: C.ink, opacity: 0.35 }} />
      <div style={{ position: "absolute", inset: 0, borderRadius: 30, overflow: "hidden", border: `10px solid ${C.ink}` }}>
        <Img src={staticFile(`plates/${m.plate}.jpg`)} style={{ position: "absolute", width: CARD_W, height: CARD_H, objectFit: "cover", objectPosition: "50% 100%", scale: `${1.3 + drift * 0.08}`, translate: `${-drift * 30}px ${-90}px` }} />
        {m.exits.map((e, j) => {
          const at = b(m.bar, 2 + j);
          const u = sp(t, at, JELLY);
          if (u <= 0) return null;
          // plate px -> card px (cover crop, then the same zoom as the image)
          const z = 1.3 + drift * 0.08;
          const x = (e.x * (CARD_W / 1920) - CARD_W / 2) * z + CARD_W / 2 - drift * 30;
          const y = (e.y * (CARD_H / 1080) - CARD_H / 2) * z + CARD_H / 2 - 90;
          const ring = clamp01((t - at) / 0.5);
          return (
            <div key={j} style={{ position: "absolute", left: x, top: y }}>
              <div style={{ position: "absolute", left: -90 * ring, top: -90 * ring, width: 180 * ring, height: 180 * ring, borderRadius: 999, border: `${8 * (1 - ring)}px solid #2fa85a`, opacity: 1 - ring }} />
              <div style={{ position: "absolute", translate: "-50% -50%", scale: `${u}` }}>
                <ExitMarker s={3.2} />
              </div>
              <div style={{ position: "absolute", top: 46, translate: "-50% 0", scale: `${u}`, transformOrigin: "50% 0" }}>
                <NameTag k={2.3} bg="rgba(26,89,46,0.92)">{e.label}</NameTag>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};

const Title: React.FC<{ t: number; m: (typeof MAPS)[number] }> = ({ t, m }) => {
  const start = b(m.bar);
  const end = b(m.bar + 1);
  if (t < start - 0.02 || t >= end - 0.02 || (m.bar === 12 && t >= b(12, 3))) return null;
  const letters = m.name.split("");
  const venue = sp(t, start + 0.18, POP);
  const num = sp(t, start + 0.08, JELLY);
  return (
    <div style={{ position: "absolute", left: 90, bottom: 80 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 20, marginBottom: 6, scale: `${num}`, transformOrigin: "0 50%" }}>
        <div style={{ ...font, fontSize: 52, color: "#fff", background: C.ink, borderRadius: 14, padding: "10px 20px" }}>MAP {m.bar - 7}/5</div>
      </div>
      <div style={{ display: "flex" }}>
        {letters.map((ch, j) => {
          const u = sp(t, start + j * 0.018, JELLY);
          return (
            <div key={j} style={{ translate: `0 ${(1 - u) * -260}px`, opacity: clamp01(u * 4), scale: `${0.6 + 0.4 * u}`, width: ch === " " ? 44 : undefined }}>
              <Outlined size={168} color="#fff" stroke={C.ink} strokeWidth={26}>{ch}</Outlined>
            </div>
          );
        })}
      </div>
      <div style={{ ...font, fontSize: 64, color: C.ink, marginTop: 4, opacity: clamp01(venue * 3), translate: `${(1 - venue) * -120}px 0` }}>{m.venue}</div>
    </div>
  );
};

export const Maps: React.FC<{ t: number }> = ({ t }) => {
  if (t < b(9) || t >= b(13) + 0.05) return null;
  const idx = Math.min(3, Math.floor((t - b(9)) / (b(10) - b(9))));
  const prevBg = idx === 0 ? C.purple : MAPS[idx - 1].bg;
  const head = sp(t, b(9), SNAP);
  const friendsAt = b(12, 3);
  const leave = ease(t, b(13) - 0.1, 0.15, inCubic);
  return (
    <div style={{ position: "absolute", inset: 0, background: prevBg, overflow: "hidden" }}>
      <Iris t={t} at={b(MAPS[idx].bar) - 0.04} x={W + 100} y={H / 2} color={MAPS[idx].bg} dur={0.3} />
      {/* pixel grid texture drifting */}
      <svg width={W} height={H} style={{ position: "absolute", inset: 0, opacity: 0.1 }}>
        {Array.from({ length: 12 }, (_, i) =>
          Array.from({ length: 22 }, (_, j) => {
            const s = 14 + 10 * (0.5 + 0.5 * Math.sin(t * 3 + i * 0.7 + j * 0.4));
            return <rect key={`${i}-${j}`} x={j * 92 - ((t * 60) % 92) + 46 - s / 2} y={i * 92 + 46 - s / 2} width={s} height={s} fill={C.ink} />;
          }),
        )}
      </svg>
      <div style={{ position: "absolute", left: 90, top: 60, display: "flex", gap: 24, scale: `${head}`, transformOrigin: "0 0", opacity: 1 - leave }}>
        <div style={{ ...font, fontSize: 84, color: C.ink }}>ESCAPE THE</div>
        <div style={{ ...font, fontSize: 84, color: "#fff", background: C.ink, padding: "0 18px", borderRadius: 12 }}>WHOLE UNIVERSITY</div>
      </div>
      {MAPS.map((m, i) => (t >= b(m.bar) - 0.15 && t < b(m.bar + 1) + 0.1 ? <MapCard key={m.name} t={t} m={m} i={i} /> : null))}
      {MAPS.map((m) => <Title key={m.name} t={t} m={m} />)}
      {/* friends online */}
      {t >= friendsAt && (
        <div style={{ position: "absolute", inset: 0, opacity: 1 - leave }}>
          <div style={{ position: "absolute", inset: 0, background: C.panel, opacity: 0.94 * ease(t, friendsAt, 0.12, outCubic) }} />
          {FRIENDS.map((name, i) => {
            const at = b(12, 3, 0.25 * i);
            const u = sp(t, at, JELLY);
            if (u <= 0) return null;
            const a = -Math.PI / 2 + (i / FRIENDS.length) * Math.PI * 2;
            const R = 380;
            const x = W / 2 + Math.cos(a) * R * 1.55;
            const y = H / 2 + 30 + Math.sin(a) * R * 0.95 + noise1(t * 2, i) * 8;
            return (
              <div key={name} style={{ position: "absolute", left: x, top: y, translate: "-50% -50%", scale: `${u}`, display: "flex", alignItems: "center", gap: 14 }}>
                <svg width={84} height={84} viewBox="-8 -8 16 16">
                  <circle r={7.5} fill={C.mapInk} />
                  <circle r={6} fill={FRIEND_COLORS[i]} />
                  <text y={3.6} textAnchor="middle" fontFamily="Jersey10" fontSize={10} fill={C.ink}>{name[0]}</text>
                </svg>
                <NameTag k={3.6} bg="rgba(26,77,115,0.92)">{name}</NameTag>
              </div>
            );
          })}
          <div style={{ position: "absolute", left: 0, right: 0, top: H / 2 - 120, display: "flex", flexDirection: "column", alignItems: "center", scale: `${slam(t, friendsAt, 2.4, 0.26)}` }}>
            <Outlined size={120} color="#fff" stroke="#000" strokeWidth={16}>PLAY WITH</Outlined>
            <Outlined size={170} color={C.gold} stroke="#000" strokeWidth={22}>UP TO 8 FRIENDS</Outlined>
          </div>
        </div>
      )}
      <Burst t={t} at={b(9)} x={W / 2} y={H / 2} colors={[C.purple, C.gold, "#fff", C.green]} seed={5} power={1500} n={20} size={20} />
    </div>
  );
};
