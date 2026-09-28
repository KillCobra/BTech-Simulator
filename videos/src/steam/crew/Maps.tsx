// Bars 16-18: "ESCAPE THE WHOLE UNIVERSITY". The two lobby maps, rebuilt from the game's own captures:
//  16: FIRST DAY (plate c_air0) rains down as tiles onto a tabletop board; one step per beat: out of the class
//      window (16.1), through the broken back wall (16.2), to the chai stall (16.3, first_day.gd "Chai stall"). Held.
//  17: GRAND CAMPUS: c_low1 slams in as strips (17.1), flips over to the aerial c_air1 (17.2), the runner pops up
//      in the Old Quadrangle (17.3).
//  18: the four real ways out (grand_campus.gd exit_marker labels) on 8ths, held together, crash zoom onto the main gate on
//      18.3, freeze on 18.3.5 and an iris to ink for the drop on 19.0.
import React from "react";
import { staticFile } from "remotion";
import { clamp01, easeIn, easeInOut, easeOut, rand, shake, SNAP, sp, squash, WOBBLE } from "../../launch/juice";
import { b, BEAT } from "../cues";
import { cssOf, project, type Op } from "./css3d";
import { ExitIcon, GOLD, INK, Ring, Slam, StarBurst, txt } from "./ui";
import { outline } from "../../launch/ui";

const ORANGE = "#ff9a3c", ORANGE_D = "#f28a2c";
const RED = "#e0524f", RED_D = "#d24542";
const P = 1500;
const PO: [number, number] = [960, 480];

const FREEZE = b(18, 3.5);
const END = b(19);
const FD_OUT = b(17, 0.5); // First Day holds its three steps until here
const GC_IN = b(17, 1); // Grand Campus strips land

// ---------------------------------------------------------------- geometry
type Pt = [number, number];
/** Catmull-Rom through the points, `n` samples. */
function spline(pts: Pt[], n = 48): Pt[] {
  const out: Pt[] = [];
  for (let i = 0; i < n; i++) {
    const g = (i / (n - 1)) * (pts.length - 1);
    const k = Math.min(pts.length - 2, Math.floor(g));
    const u = g - k;
    const p0 = pts[Math.max(0, k - 1)], p1 = pts[k], p2 = pts[k + 1], p3 = pts[Math.min(pts.length - 1, k + 2)];
    const f = (a: number, b_: number, c: number, d: number) =>
      0.5 * (2 * b_ + (-a + c) * u + (2 * a - 5 * b_ + 4 * c - d) * u * u + (-a + 3 * b_ - 3 * c + d) * u * u * u);
    out.push([f(p0[0], p1[0], p2[0], p3[0]), f(p0[1], p1[1], p2[1], p3[1])]);
  }
  return out;
}
const along = (pts: Pt[], u: number): { p: Pt; a: number } => {
  const g = clamp01(u) * (pts.length - 1);
  const k = Math.min(pts.length - 2, Math.floor(g));
  const f = g - k;
  const p: Pt = [pts[k][0] + (pts[k + 1][0] - pts[k][0]) * f, pts[k][1] + (pts[k + 1][1] - pts[k][1]) * f];
  return { p, a: Math.atan2(pts[k + 1][1] - pts[k][1], pts[k + 1][0] - pts[k][0]) };
};

// ---------------------------------------------------------------- shared 2D bits
const Field: React.FC<{ t: number; color: string; stripe: string; speed: number; phase: number }> = ({ color, stripe, phase }) => (
  <div style={{ position: "absolute", inset: 0, background: color, overflow: "hidden" }}>
    <svg width={1920} height={1080} style={{ position: "absolute", inset: 0 }}>
      <g transform={`translate(${(phase % 180) - 180} 0) skewX(-28)`}>
        {Array.from({ length: 20 }, (_, k) => <rect key={k} x={k * 180} y={-10} width={80} height={1100} fill={stripe} />)}
      </g>
    </svg>
  </div>
);

/** A route line in screen space: ink under, dashed white over, drawn 0..`u`. */
const Route: React.FC<{ pts: { x: number; y: number }[]; u: number; color?: string; width?: number }> = ({ pts, u, color = "#ffffff", width = 9 }) => {
  if (u <= 0.001) return null;
  const n = Math.max(2, Math.round(pts.length * clamp01(u)));
  const d = pts.slice(0, n).map((p, i) => `${i ? "L" : "M"}${p.x.toFixed(1)} ${p.y.toFixed(1)}`).join(" ");
  return (
    <svg width={1920} height={1080} style={{ position: "absolute", inset: 0, overflow: "visible" }}>
      <path d={d} fill="none" stroke={INK} strokeWidth={width + 8} strokeLinecap="round" strokeLinejoin="round" />
      <path d={d} fill="none" stroke={color} strokeWidth={width} strokeLinecap="round" strokeLinejoin="round" strokeDasharray={`${width * 2.2} ${width * 1.5}`} />
    </svg>
  );
};

/** map_view.gd player arrow (gold over ink), screen space. */
const Arrow: React.FC<{ x: number; y: number; a: number; s: number }> = ({ x, y, a, s }) => (
  <svg width={1} height={1} style={{ position: "absolute", left: x, top: y, overflow: "visible" }}>
    <g transform={`rotate(${(a * 180) / Math.PI}) scale(${s})`}>
      <path d="M12 0 L-7 8 L-3 0 L-7 -8 Z" fill="#2a2230" transform="scale(1.35)" />
      <path d="M12 0 L-7 8 L-3 0 L-7 -8 Z" fill={GOLD} />
    </g>
  </svg>
);

type Side = "above" | "below" | "left" | "right";
/** A way out (or a waypoint) popping up with a ring and a label pill. */
const Marker: React.FC<{ t: number; at: number; x: number; y: number; label: string; side: Side; exit?: boolean; size?: number }> = ({ t, at, x, y, label, side, exit = true, size = 74 }) => {
  const u = sp(t, at, WOBBLE);
  if (u <= 0.001) return null;
  const [sx, sy] = squash(t, at + 0.1, 0.2, 20, 9);
  const lu = sp(t, at + 0.05, SNAP);
  const off = size * 0.62 + 12;
  const pos: Record<Side, React.CSSProperties> = {
    above: { left: 0, top: -off, translate: "-50% -100%", transformOrigin: "50% 100%" },
    below: { left: 0, top: off, translate: "-50% 0", transformOrigin: "50% 0" },
    left: { left: -off, top: 0, translate: "-100% -50%", transformOrigin: "100% 50%" },
    right: { left: off, top: 0, translate: "0 -50%", transformOrigin: "0 50%" },
  };
  return (
    <div style={{ position: "absolute", left: x, top: y }}>
      <div style={{ position: "absolute", translate: "-50% -50%", scale: `${u * sx} ${u * sy}` }}>
        {exit ? (
          <ExitIcon size={size} />
        ) : (
          <svg width={size * 0.8} height={size * 0.8} viewBox="-12 -12 24 24" style={{ display: "block", overflow: "visible" }}>
            <circle r={10} fill="#2a2230" />
            <circle r={8} fill="#ffd24a" />
            <circle r={3} fill="#2a2230" />
          </svg>
        )}
      </div>
      <div style={{ position: "absolute", ...pos[side], scale: `${Math.max(0, lu)}` }}>
        <div style={{ ...txt(48, exit ? "#ffffff" : INK), background: exit ? "rgba(26,89,46,0.96)" : "#ffd24a", borderRadius: 999, padding: "10px 24px 6px", boxShadow: `0 6px 0 ${exit ? "#123d20" : "#b8901a"}` }}>{label}</div>
      </div>
    </div>
  );
};

// ---------------------------------------------------------------- FIRST DAY board
const FD_Y0 = 330, FD_H = 750; // c_air0 crop: the ground below the horizon
const COLS = 8, ROWS = 4;
const TW = 1920 / COLS, TH = FD_H / ROWS;
const FD_CENTRE: [number, number] = [1000, 720];
const fdOps = (t: number): Op[] => {
  const out = easeIn(clamp01((t - FD_OUT) / (BEAT * 0.3)));
  const drift = clamp01((t - b(16)) / (FD_OUT - b(16)));
  return [["t", -out * 2600, -out * 120, 0], ["rx", 40 - drift * 4], ["rz", -7 + drift * 2 - out * 8], ["s", 0.76 + drift * 0.05]];
};
const fdLocal = (px: number, py: number): [number, number, number] => [px - 960, py - FD_Y0 - FD_H / 2, 0];
const tileAt = (c: number, r: number) => {
  const d = Math.hypot(c - (COLS - 1) / 2, (r - (ROWS - 1) / 2) * 1.6) / 5.3;
  return b(16) + 0.03 + d * 0.3 + rand(c * 7 + r * 13) * 0.05;
};

const FD_ROUTE = spline([[1228, 800], [1340, 880], [1520, 800], [1630, 600], [1600, 492], [1406, 458]]);
const FD_MARKS = [
  { at: b(16, 1), px: 1228, py: 800, label: "Back windows", side: "below" as Side, exit: false },
  { at: b(16, 2), px: 1636, py: 560, label: "Broken back wall", side: "right" as Side, exit: false },
  { at: b(16, 3), px: 1406, py: 458, label: "Chai stall", side: "above" as Side, exit: true },
];

const FirstDay: React.FC<{ t: number }> = ({ t }) => {
  if (t >= GC_IN + 0.02) return null;
  const ops = fdOps(t);
  const blur = easeIn(clamp01((t - FD_OUT) / (BEAT * 0.3))) * 22;
  const pr = (px: number, py: number) => project(ops, FD_CENTRE, P, PO, fdLocal(px, py));
  // One step per beat: the route draws out of the window to the wall (16.1 -> 16.2), then on to the chai (16.2 -> 16.3).
  const seg = (a: number, u0: number, u1: number) => u0 + (u1 - u0) * easeInOut(clamp01((t - a) / (BEAT * 0.8)));
  const routeU = t < b(16, 1) ? 0 : t < b(16, 2) ? seg(b(16, 1), 0, 0.66) : seg(b(16, 2), 0.66, 1);
  const pts = FD_ROUTE.map(([x, y]) => pr(x, y));
  const head = along(FD_ROUTE, routeU);
  const hs = pr(head.p[0], head.p[1]);
  const ahead = pr(head.p[0] + Math.cos(head.a) * 10, head.p[1] + Math.sin(head.a) * 10);
  const corner = pr(30, FD_Y0 + 30);
  const nameU = sp(t, b(16, 0.5), WOBBLE);
  const baseU = sp(t, b(16) - 0.02, { stiffness: 600, damping: 24 });
  return (
    <div style={{ position: "absolute", inset: 0, filter: blur > 0.5 ? `blur(${blur}px)` : undefined }}>
      <div style={{ position: "absolute", inset: 0, perspective: `${P}px`, perspectiveOrigin: `${PO[0]}px ${PO[1]}px` }}>
        <div style={{ position: "absolute", left: FD_CENTRE[0] - 960, top: FD_CENTRE[1] - FD_H / 2, width: 1920, height: FD_H, transformStyle: "preserve-3d", transform: cssOf(ops) }}>
          {/* the board: an ink slab the tiles land on */}
          <div style={{ position: "absolute", inset: -22, background: INK, borderRadius: 26, transform: `translateZ(-2px) scale(${baseU})`, boxShadow: "30px 40px 0 rgba(42,26,14,0.35)" }} />
          {Array.from({ length: COLS * ROWS }, (_, k) => {
            const c = k % COLS, r = Math.floor(k / COLS);
            const at = tileAt(c, r);
            const fall = 0.2;
            if (t < at - fall) return null;
            const u = clamp01((t - (at - fall)) / fall);
            const d = t - at;
            const z = d < 0 ? 900 * (1 - u * u) : 26 * Math.exp(-d * 13) * Math.abs(Math.sin(d * 26));
            const tumble = d < 0 ? (1 - u) * 34 : 0;
            const sgn = rand(k * 3.1) > 0.5 ? 1 : -1;
            const shadowO = 0.45 * clamp01(1 - z / 900);
            return (
              <React.Fragment key={k}>
                <div style={{ position: "absolute", left: c * TW + 10 + z * 0.04, top: r * TH + 14 + z * 0.05, width: TW, height: TH, background: "#000", opacity: shadowO * (d < 0 ? 1 : 0.0), transform: "translateZ(0.5px)" }} />
                <div style={{
                  position: "absolute", left: c * TW, top: r * TH, width: TW, height: TH, transformStyle: "preserve-3d",
                  transform: `translateZ(${z + 1}px) rotateX(${tumble * sgn}deg) rotateY(${tumble * -sgn * 0.6}deg)`,
                }}>
                  <div style={{ position: "absolute", inset: 0, backgroundImage: `url(${staticFile("plates/c_air0.jpg")})`, backgroundSize: "1920px 1080px", backgroundPosition: `${-c * TW}px ${-(FD_Y0 + r * TH)}px`, outline: `1.5px solid rgba(42,26,14,${0.5 * clamp01(1 - (d - 0.1) / 0.3)})` }} />
                  <div style={{ position: "absolute", left: 0, top: "100%", width: "100%", height: 16, background: "#3d6a2c", transformOrigin: "50% 0", transform: "rotateX(-90deg)" }} />
                  <div style={{ position: "absolute", left: "100%", top: 0, width: 16, height: "100%", background: "#4f7f38", transformOrigin: "0 50%", transform: "rotateY(90deg)" }} />
                </div>
              </React.Fragment>
            );
          })}
        </div>
      </div>
      <Route pts={pts} u={routeU} />
      {routeU > 0 && routeU < 1 ? <Arrow x={hs.x} y={hs.y} a={Math.atan2(ahead.y - hs.y, ahead.x - hs.x)} s={2.6} /> : null}
      {FD_MARKS.map((m, i) => {
        const s = pr(m.px, m.py);
        return (
          <React.Fragment key={i}>
            <Ring t={t} at={m.at} x={s.x} y={s.y} r={m.exit ? 150 : 90} color={m.exit ? "#7fe0a0" : "#ffd24a"} width={12} dur={0.4} />
            <Marker t={t} at={m.at} x={s.x} y={s.y} label={m.label} side={m.side} exit={m.exit} size={m.exit ? 84 : 58} />
            {m.exit ? <StarBurst t={t} at={m.at} x={s.x} y={s.y} n={11} seed={7} power={700} size={40} /> : null}
          </React.Fragment>
        );
      })}
      {nameU > 0.001 ? (
        <div style={{ position: "absolute", left: corner.x, top: corner.y, translate: "-6% -78%", scale: `${nameU}`, rotate: "-5deg", transformOrigin: "10% 90%" }}>
          <div style={{ ...txt(92, "#ffffff"), ...outline(6, INK), background: INK, borderRadius: 18, padding: "10px 26px 4px", boxShadow: "0 10px 0 rgba(0,0,0,0.25)" }}>FIRST DAY</div>
        </div>
      ) : null}
    </div>
  );
};

// ---------------------------------------------------------------- GRAND CAMPUS card
const STRIPS = 12;
const SW = 1920 / STRIPS;
const GC_CENTRE: [number, number] = [985, 628];
const GC_LAND = (i: number) => GC_IN - 0.05 + 0.1 * ((i * 5) % STRIPS) / (STRIPS - 1);
const GC_FLIP = (i: number) => b(17, 2) + i * 0.016;
const gcOps = (t: number): Op[] => {
  const drift = clamp01((t - GC_IN) / (FREEZE - GC_IN));
  return [["t", 0, 0, 0], ["rx", 7 - drift * 2], ["ry", -11 + drift * 5], ["rz", -1.5 + drift], ["s", 0.72 + drift * 0.03]];
};
const gcLocal = (px: number, py: number): [number, number, number] => [px - 960, py - 540, 0];

const QUAD: Pt = [905, 585];
const GC_EXITS = [
  { at: b(18, 1.5), px: 1300, py: 426, label: "Main gate (guarded)", side: "above" as Side, via: [[1060, 520], [1190, 470]] as Pt[] },
  { at: b(18, 0), px: 640, py: 412, label: "Fence hole (crouch)", side: "above" as Side, via: [[760, 520], [690, 460]] as Pt[] },
  { at: b(18, 0.5), px: 1848, py: 650, label: "Storm drain (crouch)", side: "left" as Side, via: [[1200, 640], [1560, 700]] as Pt[] },
  { at: b(18, 1), px: 990, py: 955, label: "Scaffolding", side: "left" as Side, via: [[860, 740], [920, 860]] as Pt[] },
];
const GC_ROUTES = GC_EXITS.map((e) => spline([QUAD, ...e.via, [e.px, e.py]], 40));
const RUN0 = b(18, 2.5), RUN1 = FREEZE;
const RUNNER = b(17, 3); // the player arrow pops up in the Old Quadrangle

const GrandCampus: React.FC<{ t: number }> = ({ t }) => {
  if (t < FD_OUT) return null;
  const ops = gcOps(t);
  const pr = (px: number, py: number) => project(ops, GC_CENTRE, P, PO, gcLocal(px, py));
  const flipped = (i: number) => sp(t, GC_FLIP(i), { stiffness: 420, damping: 24 });
  const frame = clamp01((t - GC_IN + 0.02) / 0.05);
  const run = along(GC_ROUTES[0], 0.08 + 0.72 * easeInOut(clamp01((t - RUN0) / (RUN1 - RUN0))));
  const rs = pr(run.p[0], run.p[1]);
  const ra = pr(run.p[0] + Math.cos(run.a) * 10, run.p[1] + Math.sin(run.a) * 10);
  const name = sp(t, GC_IN, WOBBLE);
  const corner = pr(24, 24);
  return (
    <div style={{ position: "absolute", inset: 0 }}>
      <div style={{ position: "absolute", inset: 0, perspective: `${P}px`, perspectiveOrigin: `${PO[0]}px ${PO[1]}px` }}>
        <div style={{ position: "absolute", left: GC_CENTRE[0] - 960, top: GC_CENTRE[1] - 540, width: 1920, height: 1080, transformStyle: "preserve-3d", transform: cssOf(ops) }}>
          <div style={{ position: "absolute", inset: -26, background: INK, borderRadius: 34, opacity: frame, transform: "translateZ(-2px)", boxShadow: "34px 44px 0 rgba(42,26,14,0.35)" }} />
          {Array.from({ length: STRIPS }, (_, i) => {
            const land = GC_LAND(i);
            const len = 0.15;
            if (t < land - len) return null;
            const dir = i % 2 ? 1 : -1;
            const u = clamp01((t - (land - len)) / len);
            const d = t - land;
            const y = d < 0 ? dir * 1500 * Math.pow(1 - u, 3) : -dir * 34 * Math.exp(-d * 14) * Math.sin(d * 34);
            const f = flipped(i);
            const face = (plate: string, back: boolean): React.CSSProperties => ({
              position: "absolute", inset: 0, backfaceVisibility: "hidden", backgroundImage: `url(${staticFile(`plates/${plate}.jpg`)})`,
              backgroundSize: "1920px 1080px", backgroundPosition: `${-i * SW}px 0`, transform: back ? "rotateY(180deg)" : undefined,
            });
            return (
              <div key={i} style={{ position: "absolute", left: i * SW, top: 0, width: SW + 0.6, height: 1080, transformStyle: "preserve-3d", transform: `translateY(${y}px) rotateY(${-f * 180}deg)` }}>
                <div style={face("c_low1", false)} />
                <div style={face("c_air1", true)} />
              </div>
            );
          })}
        </div>
      </div>
      {GC_EXITS.map((e, k) => {
        const u = clamp01((t - (e.at - 0.24)) / 0.24);
        return <Route key={k} pts={GC_ROUTES[k].map(([x, y]) => pr(x, y))} u={easeOut(u)} color={k === 0 ? GOLD : "#ffffff"} width={k === 0 ? 11 : 8} />;
      })}
      {t >= RUNNER ? <Ring t={t} at={RUNNER} x={rs.x} y={rs.y} r={120} color={GOLD} width={12} dur={0.4} /> : null}
      {t >= RUNNER ? <Arrow x={rs.x} y={rs.y} a={Math.atan2(ra.y - rs.y, ra.x - rs.x)} s={3.4 * sp(t, RUNNER, WOBBLE)} /> : null}
      {GC_EXITS.map((e, k) => {
        const s = pr(e.px, e.py);
        return (
          <React.Fragment key={k}>
            <Ring t={t} at={e.at} x={s.x} y={s.y} r={150} color="#7fe0a0" width={14} dur={0.4} />
            <StarBurst t={t} at={e.at} x={s.x} y={s.y} n={10} seed={11 + k} power={640} size={38} />
            <Marker t={t} at={e.at} x={s.x} y={s.y} label={e.label} side={e.side} size={80} />
          </React.Fragment>
        );
      })}
      {name > 0.001 ? (
        <div style={{ position: "absolute", left: corner.x, top: corner.y, translate: "-4% -80%", scale: `${name}`, rotate: "-4deg", transformOrigin: "10% 90%" }}>
          <div style={{ ...txt(140, GOLD), ...outline(9, INK), background: INK, borderRadius: 22, padding: "8px 30px 0", boxShadow: "0 12px 0 rgba(0,0,0,0.25)" }}>GRAND CAMPUS</div>
        </div>
      ) : null}
    </div>
  );
};

// ---------------------------------------------------------------- the act half
export const Maps: React.FC<{ t: number }> = ({ t: tRaw }) => {
  if (tRaw < b(16) || tRaw >= END) return null;
  // Freeze on 17.3.5: everything holds; only the iris keeps moving.
  const t = Math.min(tRaw, FREEZE);
  const inRed = tRaw >= GC_IN - 0.02;
  // Red slab sweeps in from the right over the last half beat of bar 16.
  const sweep = easeIn(clamp01((tRaw - FD_OUT) / (GC_IN - FD_OUT)));
  const roll = [0, 1, 2, 3, 4, 5, 6, 7].map((k) => [b(18, 2 + k * 0.25), 0.05 + k * 0.025] as [number, number]);
  const sh = shake(t, [[b(16), 0.5], [b(16, 0.5), 0.3], [GC_IN, 0.8], [b(18, 3), 1.2], ...roll]);
  // Crash zoom onto the runner at the main gate on 17.3.
  const zu = easeInOut(clamp01((t - b(18, 3) - 0.05) / (BEAT * 0.4)));
  const ops = gcOps(t);
  // Crash zoom onto the main gate (its label above it stays in frame and inside the iris).
  const gate = GC_EXITS[0];
  const target = project(ops, GC_CENTRE, P, PO, gcLocal(gate.px, gate.py));
  // The big title makes way for Grand Campus (its tab is the title for bars 17-18).
  const titleOut = easeIn(clamp01((t - (GC_IN - BEAT * 0.45)) / (BEAT * 0.35)));
  const Z = 1 + 1.35 * zu;
  const tx = (960 - target.x) * zu, ty = (680 - target.y) * zu;
  const stripePhase = (t - b(16)) * 70 + Math.pow(Math.max(0, t - b(18)), 2) * 900;
  // Iris to ink around the runner, 17.3.5 -> 18.0.
  const iu = clamp01((tRaw - FREEZE) / (END - FREEZE - 1 / 60));
  const irisR = 1250 * (1 - Math.pow(iu, 2.2));
  const freezeFlash = tRaw >= FREEZE ? Math.max(0, 1 - (tRaw - FREEZE) / 0.08) : 0;
  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden" }}>
      <Field t={t} color={inRed ? RED : ORANGE} stripe={inRed ? RED_D : ORANGE_D} speed={1} phase={stripePhase} />
      {sweep > 0 && !inRed ? (
        <div style={{ position: "absolute", top: -100, bottom: -100, left: 1920 * (1 - sweep) - 300, width: 2600, background: RED, transform: "skewX(-14deg)" }} />
      ) : null}
      <div style={{ position: "absolute", inset: 0, translate: `${sh.x + tx}px ${sh.y + ty}px`, rotate: `${sh.r}deg` }}>
        <div style={{ position: "absolute", inset: 0, scale: `${Z}`, transformOrigin: `${target.x}px ${target.y}px` }}>
          <FirstDay t={t} />
          <GrandCampus t={t} />
        </div>
      </div>
      {/* title: two lines, slammed on 16.0 and 16.0.5 */}
      <div style={{ position: "absolute", left: 66, top: 26, opacity: titleOut >= 1 ? 0 : 1, translate: `0 ${-titleOut * 420}px` }}>
        <Slam t={t} at={b(16)} text="ESCAPE THE" size={124} color="#ffffff" origin="0% 70%" tilt={-5} />
        <div style={{ marginTop: -8 }}>
          <Slam t={t} at={b(16, 0.5)} text="WHOLE UNIVERSITY" size={186} color={GOLD} origin="0% 60%" tilt={4} />
        </div>
      </div>
      {tRaw >= FREEZE ? (
        <>
          <div style={{ position: "absolute", inset: 0, border: `18px solid #ffffff`, opacity: 0.9 }} />
          <svg width={1920} height={1080} style={{ position: "absolute", inset: 0 }}>
            <defs>
              <mask id="crew-iris">
                <rect width={1920} height={1080} fill="#fff" />
                <circle cx={960} cy={560} r={Math.max(0, irisR)} fill="#000" />
              </mask>
            </defs>
            <rect width={1920} height={1080} fill={INK} mask="url(#crew-iris)" />
          </svg>
          <div style={{ position: "absolute", inset: 0, background: "#fff", opacity: freezeFlash * 0.7 }} />
        </>
      ) : null}
      {tRaw < b(16) + 0.1 ? <div style={{ position: "absolute", inset: 0, background: "#fff", opacity: 0.7 * (1 - (tRaw - b(16)) / 0.1) }} /> : null}
    </div>
  );
};
