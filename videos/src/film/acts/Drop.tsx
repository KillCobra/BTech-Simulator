// Bars 5-8, the first drop: kinetic words, the minimap, style combos, the BunkFone.
import React from "react";
import { Img, staticFile } from "remotion";
import { clamp01 } from "../../kit/time";
import { b, BEAT } from "../cues";
import { ease, HEAVY, inCubic, inExpo, JELLY, lerp, noise1, outCubic, outExpo, POP, pulses, SNAP, SOFT, sp } from "../fx";
import { Burst, Flash, PixelWipe, Rays, Shockwave, slam } from "../fxui";
import { C, H, W } from "../tokens";
import { APPS, ExitMarker, font, Glyph, NameTag, Outlined, PlayerArrow, StaffDot, Star, Wedge } from "../ui";

const GAME = [C.gold, C.classA, C.classB, C.green, C.purple, C.orange, "#ffffff"];

// ---------------------------------------------------------------- bar 5: SNEAK OUT OF CLASS. DON'T GET CAUGHT.
const Word: React.FC<{ t: number; at: number; children: string; size: number; color: string; stroke?: string; tilt?: number }> = ({
  t, at, children, size, color, stroke, tilt = -7,
}) => {
  const s = slam(t, at, 2.6, 0.26);
  const visible = t >= at;
  return (
    <div style={{ opacity: visible ? 1 : 0, scale: `${visible ? s : 1}`, rotate: `${visible ? tilt * (s - 1) : 0}deg`, display: "inline-block" }}>
      {stroke ? (
        <Outlined size={size} color={color} stroke={stroke} strokeWidth={size * 0.13}>{children}</Outlined>
      ) : (
        <div style={{ ...font, fontSize: size, color }}>{children}</div>
      )}
    </div>
  );
};

export const Words: React.FC<{ t: number }> = ({ t }) => {
  if (t < b(5) || t >= b(6)) return null;
  const flip = t >= b(5, 3);
  const up = ease(t, b(5, 3), 0.25, outExpo);
  const zoomOut = ease(t, b(5, 4, 0.6), 0.25, inExpo);
  const kick = 1 + 0.03 * pulses(t, [b(5, 1), b(5, 2), b(5, 3), b(5, 4)], 0.1);
  return (
    <div style={{ position: "absolute", inset: 0, background: C.gold, overflow: "hidden" }}>
      {/* diagonal stripes drifting — the gold card gets texture */}
      <svg width={W} height={H} style={{ position: "absolute", inset: 0, opacity: 0.12 }}>
        {Array.from({ length: 24 }, (_, i) => (
          <rect key={i} x={-600 + i * 160 + ((t * 240) % 160)} y={-200} width={60} height={1600} fill={C.ink} transform={`rotate(20 ${W / 2} ${H / 2})`} />
        ))}
      </svg>
      <Burst t={t} at={b(5, 1)} x={W / 2 - 330} y={420} colors={GAME} seed={3} power={1300} size={20} n={16} />
      <Burst t={t} at={b(5, 4)} x={W / 2} y={620} colors={GAME} seed={9} power={1600} size={24} n={22} />
      <Shockwave t={t} at={b(5, 4)} x={W / 2} y={620} r={1300} width={60} color="#ffffff" />
      <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 0, translate: `0 ${-up * 900}px`, scale: `${kick}` }}>
        <div style={{ display: "flex", gap: 60 }}>
          <Word t={t} at={b(5, 1)} size={300} color={C.ink}>SNEAK</Word>
          <Word t={t} at={b(5, 1, 0.5)} size={300} color={C.ink}>OUT</Word>
        </div>
        <div style={{ display: "flex", gap: 60, marginTop: -40 }}>
          <Word t={t} at={b(5, 2)} size={300} color={C.ink} tilt={6}>OF</Word>
          <Word t={t} at={b(5, 2, 0.5)} size={300} color={C.ink} tilt={6}>CLASS.</Word>
        </div>
      </div>
      {flip && (
        <div style={{ position: "absolute", inset: 0 }}>
          <div
            style={{
              position: "absolute", inset: 0, background: C.red,
              clipPath: `polygon(${lerp(120, -20, ease(t, b(5, 3), 0.14, outCubic))}% 0, 120% 0, 120% 100%, ${lerp(140, 0, ease(t, b(5, 3), 0.14, outCubic))}% 100%)`,
            }}
          />
          <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", scale: `${kick * (1 + zoomOut * 6)}`, opacity: 1 - zoomOut }}>
            <div style={{ display: "flex", gap: 60 }}>
              <Word t={t} at={b(5, 3)} size={250} color="#ffffff" stroke={C.ink}>DON'T</Word>
              <Word t={t} at={b(5, 3, 0.5)} size={250} color="#ffffff" stroke={C.ink}>GET</Word>
            </div>
            <div style={{ marginTop: -20 }}>
              <Word t={t} at={b(5, 4)} size={360} color={C.gold} stroke={C.ink} tilt={-10}>CAUGHT.</Word>
            </div>
          </div>
        </div>
      )}
      <Flash t={t} at={b(5)} color="#ffffff" dur={0.25} />
    </div>
  );
};

// ---------------------------------------------------------------- bar 6: the minimap (map_view.gd)
type Pt = [number, number];
// The player's route out of the academic block, in map pixels (disc centre = 0,0).
const ROUTE: Pt[] = [[-150, -95], [-40, -30], [60, 40], [150, 150], [210, 280]];
function routeAt(u: number): { p: Pt; dir: number } {
  const segs = ROUTE.length - 1;
  const x = Math.min(segs - 1e-6, Math.max(0, u * segs));
  const i = Math.floor(x), f = x - i;
  const a = ROUTE[i], c = ROUTE[i + 1];
  return { p: [lerp(a[0], c[0], f), lerp(a[1], c[1], f)], dir: Math.atan2(c[1] - a[1], c[0] - a[0]) };
}

const Building: React.FC<{ x: number; y: number; w: number; h: number; color?: string; label?: string }> = ({ x, y, w, h, color = C.building, label }) => (
  <g>
    <rect x={x + 5} y={y + 7} width={w} height={h} fill="rgba(0,0,0,0.28)" rx={3} />
    <rect x={x} y={y} width={w} height={h} fill={color} stroke="#6f6350" strokeWidth={3} rx={3} />
    <rect x={x + 4} y={y + 4} width={w - 8} height={h - 8} fill="none" stroke="rgba(255,255,255,0.35)" strokeWidth={2} rx={2} />
    {label && (
      <text x={x + w / 2} y={y + h / 2 + 8} textAnchor="middle" fontFamily="Jersey10" fontSize={26} fill={C.mapInk}>{label}</text>
    )}
  </g>
);

export const Minimap: React.FC<{ t: number }> = ({ t }) => {
  if (t < b(6) || t >= b(7)) return null;
  const R = 430;
  const cx = 660, cy = 560;
  const inS = sp(t, b(6), JELLY);
  const out = ease(t, b(6, 4, 0.55), 0.25, inCubic);
  // the player hops forward on every beat
  let u = 0;
  for (let k = 0; k < 4; k++) u += 0.25 * sp(t, b(6, 1 + k, 0.1), SNAP);
  const me = routeAt(clamp01(u));
  const guardAlert = t > b(6, 3) ? 2 : t > b(6, 2) ? 1 : 0;
  const wedgeCol = ["#ffdb4d", "#ff8c33", "#ff3833"];
  const staff = [
    { x: -120, y: -170, a: Math.PI * 0.5 + Math.sin(t * 3) * 0.6, label: "Ms. Okafor", col: 0, at: b(6, 2) },
    { x: 150, y: 70, a: Math.PI + Math.sin(t * 2.2 + 1) * 0.8, label: "Sergei (Guard)", col: guardAlert, at: b(6, 3) },
    { x: 20, y: 150, a: -Math.PI * 0.25 + Math.sin(t * 4) * 0.9, label: "CCTV", col: 0, at: b(6, 4) },
  ];
  const labels = [
    { text: "TEACHERS", at: b(6, 2), color: "#d94a4a" },
    { text: "GUARDS", at: b(6, 3), color: C.orangeSoft },
    { text: "CCTV", at: b(6, 4), color: C.yellow },
  ];
  const dodge = slam(t, b(6, 1), 2.4, 0.3);
  return (
    <div style={{ position: "absolute", inset: 0, background: C.panel, overflow: "hidden" }}>
      <svg width={W} height={H} style={{ position: "absolute", inset: 0, opacity: 0.35 }}>
        {Array.from({ length: 30 }, (_, i) => <line key={i} x1={i * 70 - ((t * 40) % 70)} y1={0} x2={i * 70 - ((t * 40) % 70)} y2={H} stroke="#23233a" strokeWidth={2} />)}
        {Array.from({ length: 17 }, (_, i) => <line key={`h${i}`} x1={0} y1={i * 70} x2={W} y2={i * 70} stroke="#23233a" strokeWidth={2} />)}
      </svg>
      <svg width={W} height={H} style={{ position: "absolute", inset: 0, scale: `${inS * (1 - out)}`, rotate: `${(1 - inS) * -40 + out * 30}deg`, transformOrigin: `${cx}px ${cy}px` }}>
        <defs>
          <clipPath id="disc"><circle cx={cx} cy={cy} r={R} /></clipPath>
        </defs>
        <circle cx={cx} cy={cy} r={R + 10} fill="rgba(0,0,0,0.4)" transform="translate(0 16)" />
        <g clipPath="url(#disc)">
          <g transform={`translate(${cx} ${cy}) rotate(${-8 + Math.sin(t * 1.5) * 3}) scale(1.35)`}>
            <rect x={-500} y={-500} width={1000} height={1000} fill={C.mapOutside} />
            <rect x={-300} y={-280} width={560} height={520} fill={C.grass} />
            {/* road with centre dashes */}
            <rect x={-500} y={250} width={1000} height={60} fill={C.road} stroke="#3e4049" strokeWidth={3} />
            {Array.from({ length: 16 }, (_, i) => <rect key={i} x={-500 + i * 70} y={277} width={36} height={6} fill="rgba(244,241,230,0.8)" />)}
            {/* paths */}
            <rect x={-30} y={-40} width={36} height={290} fill={C.path} />
            <rect x={-240} y={-10} width={420} height={34} fill={C.path} />
            {/* academic block and the rest of campus */}
            <Building x={-250} y={-200} w={360} h={120} label="Class A   Class B" />
            <Building x={140} y={-220} w={100} h={90} color="#d9a8a0" label="Lab" />
            <Building x={100} y={80} w={120} h={90} color="#f0a070" label="Court" />
            <Building x={-250} y={70} w={140} h={80} label="Canteen" />
            {/* the class you're meant to be in */}
            <rect x={-240} y={-192} width={150} height={104} fill="rgba(255,107,92,0.3)" stroke="#ff5a4a" strokeWidth={2.5} />
            {/* wall */}
            <rect x={-300} y={-280} width={560} height={520} fill="none" stroke="#b95c43" strokeWidth={9} />
            {staff.map((s, i) => (
              <Wedge key={`w${i}`} x={s.x} y={s.y} angle={s.a} r={150} color={wedgeCol[s.col]} alpha={0.34} />
            ))}
            {staff.map((s, i) => (
              <StaffDot key={`s${i}`} x={s.x} y={s.y} color={["#d94a4a", "#ff9a4a", "#ff3b3b"][s.col]} s={2.1 * (1 + 0.5 * Math.exp(-Math.max(0, t - s.at) / 0.1) * (t > s.at ? 1 : 0))} ring={s.col === 2 ? 1 + Math.sin(t * 20) : 0} />
            ))}
            {/* route trail */}
            <polyline points={ROUTE.map((p) => p.join(",")).join(" ")} fill="none" stroke="#ffffff" strokeWidth={10} strokeLinecap="round" strokeLinejoin="round" opacity={0.9} strokeDasharray="1" pathLength={1} strokeDashoffset={1 - clamp01(u)} />
            <polyline points={ROUTE.map((p) => p.join(",")).join(" ")} fill="none" stroke={C.purple} strokeWidth={5.5} strokeLinecap="round" strokeLinejoin="round" pathLength={1} strokeDasharray="1" strokeDashoffset={1 - clamp01(u)} />
            <g transform={`translate(${210} ${280})`}>
              <g transform={`scale(${sp(t, b(6, 4, 0.5), JELLY) * 2.4})`}>
                <circle r={11} fill={C.mapInk} />
                <circle r={9.5} fill="#2fa85a" />
                <path d="M-3 6 L-3 -6" stroke="#fff" strokeWidth={1.8} />
                <path d="M-3 -6 L5 -3.5 L-3 -1 Z" fill="#fff" />
              </g>
            </g>
            <path d={`M${me.p[0]} ${me.p[1]} L${me.p[0] + Math.cos(me.dir - 0.55) * 50} ${me.p[1] + Math.sin(me.dir - 0.55) * 50} A50 50 0 0 1 ${me.p[0] + Math.cos(me.dir + 0.55) * 50} ${me.p[1] + Math.sin(me.dir + 0.55) * 50} Z`} fill="rgba(255,217,77,0.22)" />
            <PlayerArrow x={me.p[0]} y={me.p[1]} angle={me.dir} s={2.4} />
          </g>
        </g>
        <circle cx={cx} cy={cy} r={R} fill="none" stroke={C.mapInk} strokeWidth={16} />
        <circle cx={cx} cy={cy} r={R - 10} fill="none" stroke="rgba(255,255,255,0.35)" strokeWidth={3} />
        {(["N", "E", "S", "W"] as const).map((d, i) => {
          const a = -Math.PI / 2 + (i * Math.PI) / 2;
          return (
            <g key={d} transform={`translate(${cx + Math.cos(a) * R} ${cy + Math.sin(a) * R})`}>
              <circle r={24} fill={C.mapInk} />
              <text y={11} textAnchor="middle" fontFamily="Jersey10" fontSize={34} fill={d === "N" ? "#ff5a4a" : "#fff"}>{d}</text>
            </g>
          );
        })}
      </svg>
      {/* name tags that pop as each one is called out */}
      {staff.map((s, i) => {
        const k = sp(t, s.at, JELLY);
        if (k <= 0) return null;
        const rot = (-8 + Math.sin(t * 1.5) * 3) * (Math.PI / 180);
        const mx = s.x * 1.35, my = s.y * 1.35;
        const x = cx + mx * Math.cos(rot) - my * Math.sin(rot);
        const y = cy + mx * Math.sin(rot) + my * Math.cos(rot);
        return (
          <div key={i} style={{ position: "absolute", left: x, top: y - 70, translate: "-50% 0", scale: `${k * (1 - out)}` }}>
            <NameTag k={2.4} bg="rgba(115,20,20,0.85)">{s.label}</NameTag>
          </div>
        );
      })}
      {/* right column */}
      <div style={{ position: "absolute", left: 1180, top: 250, display: "flex", flexDirection: "column", gap: 10, translate: `${out * 900}px 0` }}>
        <div style={{ scale: `${dodge}`, transformOrigin: "0 50%", opacity: t >= b(6) ? 1 : 0 }}>
          <Outlined size={190}>DODGE</Outlined>
        </div>
        {labels.map((l, i) => {
          const k = sp(t, l.at, POP);
          return (
            <div key={i} style={{ display: "flex", alignItems: "center", gap: 26, opacity: clamp01(k * 4), translate: `${(1 - k) * 260}px 0` }}>
              <div style={{ width: 36, height: 36, borderRadius: 999, background: l.color, border: `6px solid ${C.mapInk}`, scale: `${k}` }} />
              <div style={{ ...font, fontSize: 118, color: "#fff" }}>{l.text}</div>
            </div>
          );
        })}
      </div>
      <PixelWipe t={t} start={b(6) - 0.01} dur={0.4} color={C.red} mode="reveal" origin={[W / 2, H * 0.6]} />
    </div>
  );
};

// ---------------------------------------------------------------- bar 7: style combos (hud.gd:2188)
const POPS = [
  { text: "CLOSE CALL  +50", at: b(7, 1), color: "#ffffff" },
  { text: "SILENT  +30   x2", at: b(7, 2), color: "#ffd24a" },
  { text: "SHOOK THEM OFF  +60   x3", at: b(7, 3), color: "#ffb040" },
  { text: "PROXY  +20   x4", at: b(7, 4), color: "#ff7a3a" },
];

export const Style: React.FC<{ t: number }> = ({ t }) => {
  if (t < b(7) - 0.1 || t >= b(8) + 0.9) return null;
  const x5 = b(7, 4, 0.5);
  const push = ease(t, b(7) - 0.1, BEAT * 5, (u) => u);
  const bgIn = ease(t, b(7) - 0.1, 0.24, outCubic);
  const phase = t >= b(8) ? ease(t, b(8), 0.4, outCubic) : 0;
  const shakeX = noise1(t * 25, 3) * 24 * Math.exp(-Math.max(0, t - x5) / 0.15) * (t > x5 ? 1 : 0);
  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden", background: C.panel }}>
      <Img
        src={staticFile("plates/c_air0.jpg")}
        style={{
          position: "absolute", inset: 0, width: W, height: H, objectFit: "cover",
          scale: `${1.25 - 0.12 * push + 0.03 * pulses(t, POPS.map((p) => p.at), 0.1)}`,
          rotate: `${lerp(-3, 2, push)}deg`,
          translate: `${lerp(80, -40, push) + shakeX}px 0`,
          filter: `blur(${phase * 16}px) brightness(${1 - phase * 0.45})`,
          clipPath: `circle(${bgIn * 120}% at 50% 50%)`,
        }}
      />
      <div style={{ position: "absolute", inset: 0, background: "linear-gradient(90deg, rgba(10,10,20,0) 30%, rgba(10,10,20,0.55) 100%)", opacity: 1 - phase }} />
      <div style={{ position: "absolute", right: 90, top: 700, width: 1400, height: 0, opacity: 1 - phase }}>
        {POPS.map((p, i) => {
          if (t < p.at) return null;
          const later = POPS.filter((q) => t >= q.at).length - 1 - i; // how many came after
          const s = slam(t, p.at, 1.9, 0.22);
          const lift = later * 150;
          const liftAnim = POPS.slice(i + 1).reduce((acc, q) => acc + 150 * sp(t, q.at, SNAP), 0);
          void lift;
          const size = 96 + Math.min(i + 1, 5) * 10;
          return (
            <div key={i} style={{ position: "absolute", right: 0, top: -liftAnim, scale: `${s}`, transformOrigin: "100% 50%", rotate: `${(s - 1) * -12}deg`, opacity: 1 - 0.18 * later }}>
              <Outlined size={size} color={p.color} stroke="#000" strokeWidth={size * 0.14}>{p.text}</Outlined>
            </div>
          );
        })}
      </div>
      <Burst t={t} at={x5} x={W / 2} y={380} colors={["#ff4a8a", C.gold, "#ffffff", C.orange]} seed={21} power={1500} size={22} n={24} />
      <Shockwave t={t} at={x5} x={W / 2} y={380} color="#ff4a8a" r={1200} width={50} />
      {t >= x5 && (
        <div style={{ position: "absolute", inset: 0, opacity: 1 - phase }}>
          <Rays t={t} x={W / 2} y={H / 2} color="#ff4a8a" o={0.28 * (1 - ease(t, x5 + 0.3, 0.4))} spin={30} />
        </div>
      )}
      {t >= x5 && (
        <div
          style={{
            position: "absolute", left: 0, right: 0, top: 150, display: "flex", justifyContent: "center",
            scale: `${slam(t, x5, 3.4, 0.26) * (1 - phase * 0.4)}`, rotate: `${-8 + noise1(t * 6, 4) * 3}deg`,
            translate: `${phase * -620}px ${phase * -300}px`, opacity: 1 - phase,
          }}
        >
          <Outlined size={420} color="#ff4a8a" stroke="#000" strokeWidth={46}>x5</Outlined>
        </div>
      )}
    </div>
  );
};

// ---------------------------------------------------------------- bar 8: the BunkFone (hud.gd:1371)
const TILE_AT = Array.from({ length: 7 }, (_, i) => b(8, 1, 0.25 + 0.5 * i));
const CALLOUTS = [
  { text: "TRACK THE STAFF", tile: 4, at: b(8, 3, 0.25), side: -1 },
  { text: "FIND THE WAY OUT", tile: 5, at: b(8, 3, 0.75), side: 1 },
  { text: "HELP YOUR FRIENDS", tile: 6, at: b(8, 4, 0.25), side: -1 },
];

export const Phone: React.FC<{ t: number }> = ({ t }) => {
  if (t < b(8) - 0.05 || t >= b(9) + 0.4) return null;
  const k = 1.75;
  const pw = 320 * k, ph = 520 * k;
  const rise = sp(t, b(8), HEAVY);
  const tilt = (1 - sp(t, b(8), JELLY)) * -14;
  const px = W / 2 - pw / 2, py = (H - ph) / 2 + (1 - rise) * 1100;
  const beatBump = 1 + 0.02 * pulses(t, [b(8, 1), b(8, 2), b(8, 3), b(8, 4)], 0.1);
  // the Navigate tile (index 5) becomes the next scene: it grows until it fills the frame
  const growAt = b(8, 4, 0.55);
  const grow = ease(t, growAt, b(9) - growAt, inExpo);
  // tile geometry inside the phone (measured from the layout below, in phone px before k)
  const col = 5 % 3, row = Math.floor(5 / 3);
  const gridX = 12 + 12 + (296 - 12 * 2 - (82 * 3 + 20)) / 2; // bezel margin + screen margin + centring
  const tileCx = px + (gridX + col * 92 + 41) * k;
  const tileCy = py + (12 + 12 + 18 + 8 + 48 + 8 + 30 + 10 + 10 + row * 98 + 27) * k;
  const minutes = "4:32";
  return (
    <div style={{ position: "absolute", inset: 0 }}>
      {CALLOUTS.map((c, i) => {
        const u = sp(t, c.at, POP);
        if (u <= 0) return null;
        const out = ease(t, growAt - 0.1, 0.2, inCubic);
        const x = c.side < 0 ? px - 60 : px + pw + 60;
        const y = 300 + i * 190;
        return (
          <div key={i} style={{ position: "absolute", left: x, top: y, translate: `${c.side < 0 ? "-100%" : "0"} 0`, opacity: clamp01(u * 3) * (1 - out) }}>
            <div style={{ scale: `${u}`, transformOrigin: c.side < 0 ? "100% 50%" : "0 50%", display: "flex", flexDirection: "column", alignItems: c.side < 0 ? "flex-end" : "flex-start" }}>
              <Outlined size={96} color={APPS[c.tile].color} stroke="#000" strokeWidth={14}>{c.text}</Outlined>
              <div style={{ ...font, fontSize: 44, color: "#fff", opacity: 0.8, marginTop: 6 }}>{APPS[c.tile].name} app</div>
            </div>
          </div>
        );
      })}
      <div style={{ position: "absolute", left: px, top: py, width: pw, height: ph, rotate: `${tilt}deg`, scale: `${beatBump}` }}>
        <div style={{ position: "absolute", inset: 0, background: C.phoneBezel, borderRadius: 26 * k, border: `${4 * k}px solid ${C.phoneBorder}`, boxShadow: "0 40px 80px rgba(0,0,0,0.5)" }} />
        <div style={{ position: "absolute", left: 12 * k, top: 12 * k, right: 12 * k, bottom: 12 * k, background: C.phoneScreen, borderRadius: 16 * k, padding: 12 * k, display: "flex", flexDirection: "column", alignItems: "center" }}>
          <div style={{ display: "flex", width: "100%", ...font, fontSize: 12 * k * 1.35, color: "#fff", height: 18 * k }}>
            <span style={{ opacity: 0.6 }}>BunkFone</span>
            <span style={{ marginLeft: "auto", opacity: 0.8 }}>{minutes}</span>
          </div>
          <div style={{ ...font, fontSize: 48 * k * 1.35, color: C.yellow, marginTop: 8 * k, height: 48 * k, display: "flex", alignItems: "center", scale: `${sp(t, b(8, 1, 0.1), JELLY)}` }}>{minutes}</div>
          <div style={{ ...font, fontSize: 12 * k * 1.35, color: "#fff", opacity: 0.65, textAlign: "center", marginTop: 8 * k, height: 30 * k, lineHeight: 1.15 }}>
            until the final bell{"\n"}Thermodynamics · Class A
          </div>
          <div style={{ height: 10 * k }} />
          <div style={{ display: "grid", gridTemplateColumns: `repeat(3, ${82 * k}px)`, columnGap: 10 * k, rowGap: 12 * k }}>
            {APPS.map((app, i) => {
              const u = sp(t, TILE_AT[i], JELLY);
              const draw = ease(t, TILE_AT[i] + 0.06, 0.28, outCubic);
              const hot = CALLOUTS.find((c) => c.tile === i);
              const hotPulse = hot && t > hot.at ? 1 + 0.12 * Math.exp(-(t - hot.at) / 0.12) : 1;
              const isNav = i === 5;
              return (
                <div key={app.name} style={{ width: 82 * k, height: 86 * k, display: "flex", flexDirection: "column", alignItems: "center", opacity: isNav && grow > 0 ? 0 : 1 }}>
                  <div style={{ width: 54 * k, height: 54 * k, borderRadius: 14 * k, background: app.color, display: "flex", alignItems: "center", justifyContent: "center", scale: `${u * hotPulse}`, rotate: `${(1 - u) * 30}deg` }}>
                    <Glyph glyph={app.glyph} size={54 * k} draw={draw} />
                  </div>
                  <div style={{ ...font, fontSize: 12 * k * 1.35, color: "#fff", marginTop: 4 * k, opacity: clamp01(u * 2) }}>{app.name}</div>
                </div>
              );
            })}
          </div>
        </div>
      </div>
      {/* the traveller: Navigate's purple square grows into the next scene */}
      {grow > 0 && (
        <div
          style={{
            position: "absolute",
            left: lerp(tileCx - 27 * k, -200, grow),
            top: lerp(tileCy - 27 * k, -200, grow),
            width: lerp(54 * k, W + 400, grow),
            height: lerp(54 * k, H + 400, grow),
            borderRadius: lerp(14 * k, 0, grow),
            background: C.purple,
            display: "flex", alignItems: "center", justifyContent: "center",
          }}
        >
          <div style={{ opacity: 1 - clamp01(grow * 3) }}>
            <Glyph glyph="route" size={54 * k * (1 + grow * 4)} />
          </div>
        </div>
      )}
    </div>
  );
};
