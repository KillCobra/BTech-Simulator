// Bars 13-16: Pappu Uncle's canteen, the rank ladder, then the diorama builds itself and the logo lands.
import React from "react";
import { clamp01 } from "../../kit/time";
import { b, BEAT, DURATION } from "../cues";
import { ease, HEAVY, inCubic, inExpo, JELLY, lerp, noise1, outCubic, outExpo, POP, pulses, SNAP, sp, squash } from "../fx";
import { Burst, Flash, PixelWipe, Rays, Shockwave, slam } from "../fxui";
import { C, H, W } from "../tokens";
import { Badge, Button, font, ItemIcon, Outlined } from "../ui";
import { Cloud, Voxels, voxelBounds } from "../voxel";

// ---------------------------------------------------------------- bar 13: the canteen (hud.gd:1983, director.gd:56)
const ITEMS = [
  { icon: "samosa", name: "Samosa", price: 10 },
  { icon: "hall_pass", name: "Hall Pass", price: 40 },
  { icon: "medical_note", name: "Medical Note", price: 70 },
  { icon: "detention_ticket", name: "Detention Skip", price: 90 },
] as const;

export const Canteen: React.FC<{ t: number }> = ({ t }) => {
  if (t < b(13) || t >= b(14)) return null;
  const title = slam(t, b(13), 2.2, 0.26);
  const out = ease(t, b(13, 4, 0.6), 0.22, inExpo);
  let cash = 250;
  ITEMS.forEach((it, i) => (cash -= t > b(13, 1 + i, 0.5) ? it.price : 0));
  return (
    <div style={{ position: "absolute", inset: 0, background: C.cream, overflow: "hidden" }}>
      <div style={{ position: "absolute", inset: 36, border: `14px solid ${C.canteenRed}`, borderRadius: 44 }} />
      <svg width={W} height={H} style={{ position: "absolute", inset: 0, opacity: 0.08 }}>
        {Array.from({ length: 30 }, (_, i) => (
          <circle key={i} cx={(i * 263) % W} cy={((i * 181 + t * 90) % (H + 100)) - 50} r={28} fill={C.canteenRed} />
        ))}
      </svg>
      <div style={{ position: "absolute", left: 0, right: 0, top: 96, display: "flex", justifyContent: "center", scale: `${title}`, opacity: t >= b(13) ? 1 : 0 }}>
        <div style={{ ...font, fontSize: 132, color: C.canteenRed }}>PAPPU UNCLE'S CANTEEN</div>
      </div>
      <div style={{ position: "absolute", left: 0, right: 0, top: 262, display: "flex", justifyContent: "center", ...font, fontSize: 54, color: C.ink, opacity: clamp01((t - b(13)) / 0.1) }}>
        Your pocket money: Rs {cash}
      </div>
      {ITEMS.map((it, i) => (
        <Burst key={i} t={t} at={b(13, 1 + i, 0.5)} x={130 + 190 + i * ((W - 260 - 380) / 3)} y={880} colors={[C.gold, C.yellow, "#fff"]} seed={40 + i} power={700} n={10} size={12} />
      ))}
      <div style={{ position: "absolute", left: 130, right: 130, top: 380, display: "flex", justifyContent: "space-between", translate: `0 ${out * 1200}px` }}>
        {ITEMS.map((it, i) => {
          const at = b(13, 1 + i);
          const drop = sp(t, at, JELLY);
          const [sx, sy] = squash(t, at + 0.09, 0.3);
          const buy = t > at + BEAT * 0.5 ? Math.exp(-(t - at - BEAT * 0.5) / 0.1) : 0;
          const bought = t > at + BEAT * 0.5;
          return (
            <div key={it.name} style={{ width: 380, display: "flex", flexDirection: "column", alignItems: "center", opacity: t >= at ? 1 : 0 }}>
              <div style={{ translate: `0 ${(1 - drop) * -700}px`, scale: `${sx} ${sy}`, transformOrigin: "50% 100%", rotate: `${(1 - drop) * (i % 2 ? 25 : -25)}deg` }}>
                <ItemIcon name={it.icon} size={290} />
              </div>
              <div style={{ ...font, fontSize: 64, color: C.ink, marginTop: -6, opacity: clamp01(drop * 3) }}>{it.name}</div>
              <div style={{ marginTop: 18, scale: `${clamp01(drop)}` }}>
                <Button color={bought ? C.green : C.gold} k={2} pressed={buy} size={26}>{bought ? "BOUGHT!" : `BUY  Rs ${it.price}`}</Button>
              </div>
            </div>
          );
        })}
      </div>
      <PixelWipe t={t} start={b(13) - 0.01} dur={0.35} color={C.orange} mode="reveal" origin={[W / 2, H / 2]} />
    </div>
  );
};

// ---------------------------------------------------------------- bar 14: ranks (autoload/profile.gd:15)
const RANKS = [
  { name: "FRESHER", level: 1, color: "#e6e6e6", outline: "#000000", at: b(14, 1) },
  { name: "BACKBENCHER", level: 3, color: "#9fd8ff", outline: "#1a3a5a", at: b(14, 2) },
  { name: "PROXY KING", level: 6, color: "#7fe0a0", outline: "#1a4a2a", at: b(14, 3) },
  { name: "CANTEEN LEGEND", level: 10, color: "#d6a8ff", outline: "#3a1a5a", at: b(14, 3, 0.5) },
  { name: "BUNK MASTER", level: 15, color: "#ffd24a", outline: "#5a3a00", at: b(14, 4) },
];

export const Ranks: React.FC<{ t: number }> = ({ t }) => {
  if (t < b(14) || t >= b(15)) return null;
  let shown = 0;
  RANKS.forEach((r) => (shown += sp(t, r.at, SNAP)));
  const current = RANKS.filter((r) => t >= r.at).length - 1;
  const lvl = current >= 0 ? RANKS[current].level : 1;
  const xp = clamp01((t - b(14)) / (b(14, 4) - b(14)));
  const zoom = ease(t, b(14, 4, 0.6), b(15) - b(14, 4, 0.6), inExpo);
  const top = RANKS[4];
  const topHit = t >= top.at;
  return (
    <div style={{ position: "absolute", inset: 0, background: C.panel, overflow: "hidden" }}>
      {topHit && <Rays t={t} x={W / 2} y={H / 2 + 20} color="#ffd24a" o={0.14 + 0.1 * Math.exp(-(t - top.at) / 0.2)} spin={40} />}
      <Burst t={t} at={top.at} x={W / 2} y={H / 2} colors={[C.gold, C.yellow, "#fff", "#d6a8ff"]} seed={77} power={1800} n={26} size={22} />
      <div style={{ position: "absolute", inset: 0, scale: `${1 + zoom * 9}`, transformOrigin: `${W / 2}px ${H / 2 + 20}px`, opacity: 1 - clamp01((zoom - 0.6) / 0.4) }}>
        {/* the ladder: each new rank lands in the centre and pushes the old ones down */}
        {RANKS.map((r, i) => {
          if (t < r.at) return null;
          const u = sp(t, r.at, JELLY);
          const pos = shown - 1 - i; // 0 = the newest, in the middle
          const y = H / 2 + 20 + pos * 150;
          const isTop = i === 4;
          const size = isTop ? 200 : 130;
          return (
            <div key={r.name} style={{ position: "absolute", left: 0, right: 0, top: y, display: "flex", justifyContent: "center", translate: "0 -50%", scale: `${slam(t, r.at, 2.0, 0.22) * (1 - Math.min(pos, 3) * 0.18)}`, opacity: clamp01(u * 3) * (1 - clamp01(pos - 2.5)) * (topHit && !isTop ? 0.35 : 1) }}>
              <Outlined size={size} color={r.color} stroke={r.outline} strokeWidth={size * 0.13}>{r.name}</Outlined>
            </div>
          );
        })}
        <div style={{ position: "absolute", left: W / 2 - 400, top: 130, width: 800 }}>
          <div style={{ display: "flex", ...font, fontSize: 58, color: "#fff" }}>
            <span>LEVEL {lvl}</span>
            <span style={{ marginLeft: "auto", color: C.green }}>+{Math.round(xp * 1450)} XP</span>
          </div>
          <div style={{ height: 28, marginTop: 14, background: "rgba(255,255,255,0.12)" }}>
            <div style={{ width: `${outCubic(xp) * 100}%`, height: "100%", background: C.green }} />
          </div>
        </div>
        {topHit && (
          <>
            {[0, 1, 2, 3].map((s) => {
              const u = sp(t, top.at + 0.04 + s * 0.04, JELLY);
              const x = [150, 330, 1440, 1620][s];
              return (
                <div key={s} style={{ position: "absolute", left: x, top: H / 2 - 90 + (s % 3 === 0 ? 60 : -40), scale: `${u}`, rotate: `${(s < 2 ? -1 : 1) * (12 + Math.sin(t * 6 + s) * 6)}deg` }}>
                  <Badge subject={s} size={170} />
                </div>
              );
            })}
          </>
        )}
        {topHit && (
          <div style={{ position: "absolute", left: W / 2 + 330, top: H / 2 - 190, rotate: "12deg", scale: `${slam(t, top.at + 0.06, 2.6, 0.24)}` }}>
            <div style={{ ...font, fontSize: 64, color: C.ink, background: C.yellow, borderRadius: 14, padding: "8px 18px" }}>LEVEL UP!</div>
          </div>
        )}
      </div>
      <Flash t={t} at={b(14)} color={C.cream} dur={0.18} peak={0.8} />
      <Flash t={t} at={b(15) - 0.12} color="#ffffff" dur={0.3} peak={0} />
    </div>
  );
};

// ---------------------------------------------------------------- bars 15-16: the diorama and the logo
const A = 36; // cube half-width
const HERO_BOX = voxelBounds("hero", A);

export const Logo: React.FC<{ t: number }> = ({ t }) => {
  if (t < b(15)) return null;
  const T0 = b(15);
  const bunkAt = b(15, 3), masterAt = b(15, 4), finalAt = b(16);
  // arm pumps: voxels of the raised arm lift on these beats
  const pump = (at: number) => (t > at ? Math.exp(-(t - at) / 0.1) * Math.sin(Math.min(Math.PI, (t - at) * 16)) : 0);
  const armLift = (pump(masterAt) + pump(finalAt) + pump(b(16, 2))) * A * 0.9;
  const bob = Math.sin((t - T0) * Math.PI * 2 * (128 / 60) / 2) * 6;
  const anim = (x: number, y: number, z: number) => {
    // ground layers land on 15.1, the wall on 15.2, the student and tree on 15.2.5 -> 15.3
    const group = z <= 0 ? 0 : z <= 5 && !(y === 4 && z === 5 && false) ? 1 : 2;
    const base = [T0 - 0.02, b(15, 2) - 0.05, b(15, 2, 0.5)][group];
    const stagger = group === 0 ? ((x + y) / 20) * 0.28 : group === 1 ? (x / 12) * 0.25 + z * 0.02 : (z - 6) * 0.018 + (x > 7 ? 0.08 : 0);
    const at = base + stagger;
    if (t < at) return { o: 0 };
    const u = sp(t, at, { stiffness: 420, damping: 16 });
    const isArm = group === 2 && x >= 7 && x <= 8 && z >= 12 && y === 4;
    return { dy: (1 - u) * -700 - (isArm ? armLift * (z - 11) / 5 : 0), s: 0.5 + 0.5 * clamp01(u * 1.4) };
  };
  const cloudDrift = (t - T0) * 40;
  const kick = 1 + 0.02 * pulses(t, [b(15, 1), b(15, 2), b(15, 3), b(15, 4), b(16, 1)], 0.1);
  const tag = sp(t, finalAt, POP);
  const chips = [
    { text: "WINDOWS", color: C.orange, at: b(16, 1, 0.25) },
    { text: "MAC", color: C.purple, at: b(16, 1, 0.5) },
    { text: "ONLINE WITH FRIENDS", color: C.green, at: b(16, 1, 0.75) },
  ];
  const ringWob = t > b(16, 2) ? Math.sin((t - b(16, 2)) * 2 * Math.PI * 22) * 1.6 * Math.exp(-(t - b(16, 2)) / 0.5) : 0;
  const settle = ease(t, b(16, 2), DURATION - b(16, 2), (u) => u);
  return (
    <div style={{ position: "absolute", inset: 0, background: C.sky, overflow: "hidden" }}>
      <svg width={W} height={H} style={{ position: "absolute", inset: 0 }}>
        <Cloud a={34} w={5} x={260 - cloudDrift} y={140} />
        <Cloud a={24} w={4} x={1500 - cloudDrift * 0.6} y={110} o={0.9} />
        <Cloud a={18} w={3} x={1760 - cloudDrift * 0.4} y={300} o={0.8} />
        <Cloud a={28} w={4} x={1150 - cloudDrift * 0.8} y={40} />
      </svg>
      {/* ground shadow */}
      <div style={{ position: "absolute", left: 600 - 380, top: 890, width: 760, height: 110, borderRadius: "50%", background: "rgba(20,20,40,0.22)", filter: "blur(22px)", scale: `${clamp01((t - T0) / 0.3)}` }} />
      <div style={{ position: "absolute", left: 600 - HERO_BOX.w / 2 - 20, top: 560 - HERO_BOX.h / 2 + bob, scale: `${kick * (1 + 0.02 * settle)}` }}>
        <Voxels scene="hero" a={A} width={HERO_BOX.w + 40} height={HERO_BOX.h + 40} anim={anim} />
      </div>
      <Burst t={t} at={bunkAt} x={1250} y={280} colors={[C.gold, "#fff", C.orange]} seed={91} power={1300} n={16} size={18} />
      <Burst t={t} at={masterAt} x={1380} y={480} colors={[C.gold, "#fff", C.green, C.purple]} seed={92} power={1400} n={18} size={18} />
      {/* the title: BUNK on 15.3, MASTER on 15.4 */}
      <div style={{ position: "absolute", left: 1010, top: 150, rotate: `${ringWob}deg` }}>
        <div style={{ scale: `${slam(t, bunkAt, 3, 0.28)}`, transformOrigin: "30% 60%", rotate: `${t < bunkAt + 0.3 ? (1 - ease(t, bunkAt, 0.3)) * -14 : 0}deg` }}>
          <Outlined size={250} strokeWidth={40} style={{ letterSpacing: 4 }}>BUNK</Outlined>
        </div>
        <div style={{ marginTop: -40, scale: `${slam(t, masterAt, 3, 0.28)}`, transformOrigin: "30% 60%", rotate: `${t < masterAt + 0.3 ? (1 - ease(t, masterAt, 0.3)) * 12 : 0}deg` }}>
          <Outlined size={250} strokeWidth={40} style={{ letterSpacing: 4 }}>MASTER</Outlined>
        </div>
        <div style={{ ...font, fontSize: 70, color: C.ink, marginTop: 10, marginLeft: 10, opacity: clamp01(tag * 3), translate: `${(1 - tag) * 80}px 0` }}>
          sneak out. don't get caught.
        </div>
        <div style={{ display: "flex", gap: 22, marginTop: 38, marginLeft: 6 }}>
          {chips.map((c) => {
            const u = sp(t, c.at, JELLY);
            return (
              <div key={c.text} style={{ scale: `${u}`, opacity: u > 0 ? 1 : 0 }}>
                <Button color={c.color} k={1.9} size={22}>{c.text}</Button>
              </div>
            );
          })}
        </div>
      </div>
      <Shockwave t={t} at={T0} x={600} y={720} color="#ffffff" r={1200} width={60} dur={0.5} />
      <Shockwave t={t} at={bunkAt} x={1260} y={290} color={C.gold} r={900} width={40} dur={0.45} />
      <Shockwave t={t} at={masterAt} x={1360} y={490} color={C.gold} r={900} width={40} dur={0.45} />
      <Burst t={t} at={b(15, 2, 0.5) + 0.22} x={600} y={330} colors={["#f4f4f0", "#e0524f", "#2b3a67", "#ffc93c"]} seed={93} power={900} n={14} size={14} />
      <Flash t={t} at={T0} color="#ffffff" dur={0.3} />
    </div>
  );
};
