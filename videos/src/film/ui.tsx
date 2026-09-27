// Frame-driven twins of Bunk Master's HUD (scenes/ui/hud.gd, scenes/ui/map_view.gd, scenes/main.gd).
// Same colours, radii and copy; sizes are the game's multiplied by `k` so they read at 1080p.
import React from "react";
import { Img } from "remotion";
import icons from "./icons.json";
import { C, FONT } from "./tokens";

export const font: React.CSSProperties = { fontFamily: FONT, fontWeight: 400, lineHeight: 1, whiteSpace: "pre" };

export function shadeHex(hex: string, k: number) {
  const n = parseInt(hex.slice(1), 16);
  const ch = (v: number) => Math.max(0, Math.min(255, Math.round(v * k)));
  const r = ch((n >> 16) & 255), g = ch((n >> 8) & 255), b = ch(n & 255);
  return `#${((1 << 24) | (r << 16) | (g << 8) | b).toString(16).slice(1)}`;
}
export function mixHex(a: string, b: string, u: number) {
  const x = parseInt(a.slice(1), 16), y = parseInt(b.slice(1), 16);
  const c = (s: number) => Math.round(((x >> s) & 255) + ((((y >> s) & 255) - ((x >> s) & 255)) * Math.min(1, Math.max(0, u))));
  return `#${((1 << 24) | (c(16) << 16) | (c(8) << 8) | c(0)).toString(16).slice(1)}`;
}

/** The title treatment: gold fill, thick ink outline, soft drop shadow (main.gd:1304). */
export const Outlined: React.FC<{
  size: number;
  color?: string;
  stroke?: string;
  strokeWidth?: number;
  shadow?: boolean;
  style?: React.CSSProperties;
  children: React.ReactNode;
}> = ({ size, color = C.gold, stroke = C.ink, strokeWidth, shadow = true, style, children }) => (
  <div
    style={{
      ...font,
      fontSize: size,
      color,
      WebkitTextStroke: `${strokeWidth ?? size * 0.16}px ${stroke}`,
      paintOrder: "stroke fill",
      textShadow: shadow ? `0 ${size * 0.08}px ${size * 0.05}px rgba(0,0,0,0.35)` : undefined,
      ...style,
    }}
  >
    {children}
  </div>
);

/** HUD card: rgba(.08,.08,.14,.72), radius 12, padding 12 (hud.gd:439). */
export const Card: React.FC<{ k?: number; style?: React.CSSProperties; bg?: string; children: React.ReactNode }> = ({ k = 1, style, bg, children }) => (
  <div style={{ background: bg ?? "rgba(20,20,36,0.82)", borderRadius: 12 * k, padding: 12 * k, ...style }}>{children}</div>
);

/** Menu button: colour fill, radius 12, 6 px darker bottom edge; pressed = 2 px edge (main.gd:1373). */
export const Button: React.FC<{ color: string; k?: number; pressed?: number; w?: number; children: React.ReactNode; size?: number }> = ({
  color, k = 1, pressed = 0, w, children, size = 20,
}) => {
  const edge = (6 - 4 * pressed) * k;
  return (
    <div style={{ paddingTop: 4 * pressed * k }}>
      <div
        style={{
          ...font,
          width: w,
          fontSize: size * k,
          color: C.ink,
          background: color,
          borderRadius: 12 * k,
          boxShadow: `0 ${edge}px 0 ${shadeHex(color, 0.65)}`,
          padding: `${12 * k}px ${22 * k}px`,
          textAlign: "center",
        }}
      >
        {children}
      </div>
    </div>
  );
};

/** Class chip next to the player name: class colour, radius 6 (hud.gd:453). */
export const Chip: React.FC<{ color: string; k?: number; children: React.ReactNode; text?: string; size?: number }> = ({ color, k = 1, children, text = "#fff", size = 18 }) => (
  <span style={{ ...font, fontSize: size * k * 1.35, background: color, color: text, borderRadius: 6 * k, padding: `${3 * k}px ${8 * k}px`, display: "inline-block" }}>{children}</span>
);

/** Pill name tag (map_view.gd:217). */
export const NameTag: React.FC<{ bg?: string; color?: string; outline?: string; k?: number; children: React.ReactNode; size?: number }> = ({
  bg = "rgba(26,20,31,0.8)", color = "#fff", outline, k = 1, children, size = 14,
}) => (
  <div
    style={{
      ...font,
      fontSize: size * k,
      color,
      background: bg,
      borderRadius: 999,
      padding: `${4 * k}px ${10 * k}px`,
      WebkitTextStroke: outline ? `${size * k * 0.14}px ${outline}` : undefined,
      paintOrder: "stroke fill",
      display: "inline-block",
    }}
  >
    {children}
  </div>
);

/** The game's own item and badge art (scripts/icons.gd), as the SVG it rasterises. */
export const ItemIcon: React.FC<{ name: keyof typeof icons.items; size: number; style?: React.CSSProperties }> = ({ name, size, style }) => (
  <Img src={`data:image/svg+xml;utf8,${encodeURIComponent(icons.items[name])}`} style={{ width: size, height: size, ...style }} />
);
export const Badge: React.FC<{ subject: number; size: number; style?: React.CSSProperties }> = ({ subject, size, style }) => (
  <Img src={`data:image/svg+xml;utf8,${encodeURIComponent(icons.badges[subject])}`} style={{ width: size, height: size, ...style }} />
);

// ---- Phone app glyphs (hud.gd:35-77): drawn in a 54 box, centre (27,27), ink #2a1a0e, stroke 3.
// `draw` 0..1 strokes them on.
const glyphPaths: Record<string, React.ReactNode> = {
  clock: (
    <>
      <circle cx={0} cy={0} r={15} fill="none" pathLength={1} />
      <path d="M0 0 L0 -10 M0 0 L7 3" fill="none" pathLength={1} />
    </>
  ),
  calendar: (
    <>
      <rect x={-15} y={-12} width={30} height={27} fill="none" pathLength={1} />
      <rect x={-15} y={-12} width={30} height={7} data-fill />
      {[0, 1, 2].flatMap((i) => [0, 1].map((j) => <rect key={`${i}${j}`} x={-10 + 8 * i - 2} y={7 * j - 1} width={4} height={4} data-fill />))}
    </>
  ),
  wallet: (
    <>
      <rect x={-16} y={-10} width={32} height={22} fill="none" pathLength={1} />
      <rect x={4} y={-3} width={12} height={8} data-fill />
      <path d="M-14 -10 L8 -17" fill="none" pathLength={1} />
    </>
  ),
  trade: (
    <>
      <path d="M-14 -6 L12 -6 M14 7 L-12 7" fill="none" pathLength={1} />
      <path d="M15 -6 L8 -12 L8 0 Z M-15 7 L-8 1 L-8 13 Z" data-fill />
    </>
  ),
  radar: (
    <>
      <circle r={15} fill="none" pathLength={1} />
      <circle r={8} fill="none" strokeWidth={2} pathLength={1} />
      <path d="M0 0 L11 -11" fill="none" pathLength={1} />
      <circle cx={-6} cy={6} r={2.5} data-fill />
    </>
  ),
  help: (
    <>
      <rect x={-16} y={-14} width={32} height={22} fill="none" pathLength={1} />
      <path d="M-8 8 L-2 8 L-10 15 Z" data-fill />
      <circle cx={-4} cy={-5} r={4} data-fill />
      <circle cx={4} cy={-5} r={4} data-fill />
      <path d="M-8 -4 L8 -4 L0 5 Z" data-fill />
    </>
  ),
  route: (
    <>
      <path d="M-13 13 L-13 2 L4 2 L4 -8" fill="none" pathLength={1} />
      <circle cx={-13} cy={13} r={3.5} data-fill />
      <circle cx={10} cy={-10} r={6} data-fill />
      <path d="M5 -7 L15 -7 L10 1 Z" data-fill />
      <circle cx={10} cy={-10} r={2.2} fill="#fff" data-keep />
    </>
  ),
};

export const APPS = [
  { name: "Today", color: C.yellow, glyph: "clock" },
  { name: "Timetable", color: C.cyan, glyph: "calendar" },
  { name: "Wallet", color: C.green, glyph: "wallet" },
  { name: "Trade", color: C.orange, glyph: "trade" },
  { name: "Tracker", color: C.pink, glyph: "radar" },
  { name: "Navigate", color: C.purple, glyph: "route" },
  { name: "Help Out", color: C.teal, glyph: "help" },
] as const;

export const Glyph: React.FC<{ glyph: string; size: number; draw?: number }> = ({ glyph, size, draw = 1 }) => {
  const kids = React.Children.map(glyphPaths[glyph] as React.ReactElement, (x) => x);
  const flat: React.ReactElement<any>[] = [];
  const walk = (node: React.ReactNode) =>
    React.Children.forEach(node, (c) => {
      if (!React.isValidElement(c)) return;
      if (c.type === React.Fragment) walk((c.props as { children: React.ReactNode }).children);
      else flat.push(c as React.ReactElement<any>);
    });
  walk(kids);
  return (
    <svg width={size} height={size} viewBox="-27 -27 54 54" style={{ overflow: "visible" }}>
      <g stroke={C.ink} strokeWidth={3} strokeLinecap="round" strokeLinejoin="round">
        {flat.map((el, i) => {
          const p = el.props as Record<string, unknown>;
          if (p["data-keep"]) return React.cloneElement(el, { key: i, stroke: "none", opacity: draw > 0.9 ? 1 : 0 });
          if (p["data-fill"]) return React.cloneElement(el, { key: i, fill: C.ink, stroke: "none", opacity: Math.max(0, (draw - 0.55) / 0.45) });
          return React.cloneElement(el, { key: i, strokeDasharray: 1, strokeDashoffset: 1 - draw });
        })}
      </g>
    </svg>
  );
};

/** Staff vision wedge: 9-point fan at 0.22 alpha (map_view.gd:258). */
export const Wedge: React.FC<{ x: number; y: number; angle: number; spread?: number; r: number; color: string; alpha?: number }> = ({
  x, y, angle, spread = 0.7, r, color, alpha = 0.3,
}) => {
  const pts = [`${x},${y}`];
  for (let i = 0; i <= 8; i++) {
    const a = angle - spread + (2 * spread * i) / 8;
    pts.push(`${x + Math.cos(a) * r},${y + Math.sin(a) * r}`);
  }
  return <polygon points={pts.join(" ")} fill={color} opacity={alpha} />;
};

/** Staff dot: ink ring r7.5, colour r6, white "!" (map_view.gd:313). */
export const StaffDot: React.FC<{ x: number; y: number; color: string; s?: number; ring?: number }> = ({ x, y, color, s = 1, ring = 0 }) => (
  <g transform={`translate(${x} ${y}) scale(${s})`}>
    {ring > 0 && <circle r={10 + 3 * ring} fill="none" stroke="rgba(255,51,51,0.7)" strokeWidth={2} />}
    <circle r={7.5} fill={C.mapInk} />
    <circle r={6} fill={color} />
    <rect x={-1.2} y={-4} width={2.4} height={5} fill="#fff" />
    <rect x={-1.2} y={2.2} width={2.4} height={2} fill="#fff" />
  </g>
);

/** Player arrow: tip +12, back corners -7 +/-8, notch -3; gold with ink outline (map_view.gd:303). */
export const PlayerArrow: React.FC<{ x: number; y: number; angle: number; s?: number }> = ({ x, y, angle, s = 1 }) => {
  const d = "M12 0 L-7 8 L-3 0 L-7 -8 Z";
  return (
    <g transform={`translate(${x} ${y}) rotate(${(angle * 180) / Math.PI}) scale(${s})`}>
      <path d="M-40 0 A 40 40 0 0 1 -40 0" />
      <path d={d} fill={C.mapInk} transform="scale(1.3)" />
      <path d={d} fill={C.gold} />
    </g>
  );
};

/** Exit marker: ink r11, green #2fa85a r9.5, white flag (map_view.gd:348). */
export const ExitMarker: React.FC<{ s?: number }> = ({ s = 1 }) => (
  <svg width={24 * s} height={24 * s} viewBox="-12 -12 24 24" style={{ overflow: "visible" }}>
    <circle r={11} fill={C.mapInk} />
    <circle r={9.5} fill="#2fa85a" />
    <path d="M-3 6 L-3 -6" stroke="#fff" strokeWidth={1.8} strokeLinecap="round" />
    <path d="M-3 -6 L5 -3.5 L-3 -1 Z" fill="#fff" />
  </svg>
);

/** 10-point star, radii 8 / 3.6, gold over ink (map_view.gd:336). */
export const Star: React.FC<{ size: number; fill?: string }> = ({ size, fill = C.yellow }) => {
  const pts = (ro: number, ri: number) =>
    Array.from({ length: 10 }, (_, i) => {
      const a = -Math.PI / 2 + (i * Math.PI) / 5;
      const r = i % 2 ? ri : ro;
      return `${Math.cos(a) * r},${Math.sin(a) * r}`;
    }).join(" ");
  return (
    <svg width={size} height={size} viewBox="-10 -10 20 20" style={{ overflow: "visible" }}>
      <polygon points={pts(9.6, 4.6)} fill={C.mapInk} />
      <polygon points={pts(8, 3.6)} fill={fill} />
    </svg>
  );
};
