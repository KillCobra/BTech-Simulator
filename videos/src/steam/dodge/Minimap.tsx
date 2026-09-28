// The game's round minimap (scenes/ui/hud.gd setup_map + scenes/ui/map_view.gd), redrawn as SVG and driven by
// the same world as the 3D shots (world.ts). Centred on you, turned so your view points up (rot = your yaw),
// staff dots with their vision wedges, a compass ring, a floor caption pill underneath.
// Sizes are the game's (240 px disc) times k = R / 120.
import React from "react";
import { FONT } from "../../launch/tokens";
import type { Watcher } from "./world";

const OUTSIDE = "#4a7f41", GRASS = "#7cbf5a", INK = "#2a2230", WALL_INK = "#3a2d26";
const TINT = ["#ffdb4d", "#ff8c33", "#ff3833"]; // map_view.gd wedge tints by alert (1,.86,.3 / 1,.55,.2 / 1,.22,.2)
const DOT = ["#d94a4a", "#ff9a4a", "#ff3b3b"];

type R4 = [x0: number, z0: number, x1: number, z1: number];
const rect = (r: R4, fill: string, extra: React.SVGProps<SVGRectElement> = {}) => (
  <rect x={r[0]} y={r[1]} width={r[2] - r[0]} height={r[3] - r[1]} fill={fill} {...extra} />
);

// The block the act plays in: a verandah corridor, lockers on the wall, classrooms behind, a courtyard in front.
const ROOM_LIST: { r: R4; label: string }[] = [
  { r: [-21, 3.35, -8.5, 11.5], label: "Class A" },
  { r: [-8.5, 3.35, 3.8, 11.5], label: "Class B" },
  { r: [3.8, 3.35, 16.2, 11.5], label: "Lab" },
  { r: [16.2, 3.35, 28.5, 11.5], label: "Class C" },
];
const TREES: [number, number, number][] = [[-17, -9, 1.6], [-4, -11, 1.9], [3.5, -7.5, 1.4], [12, -10, 1.8], [-13, -15, 1.5], [20, -8, 1.6], [7, -15, 1.7]];

const MapWorld: React.FC<{ zoom: number }> = ({ zoom }) => {
  const lw = (px: number) => px / zoom; // a screen-px line width inside the scaled group
  return (
    <g>
      {rect([-80, -80, 80, 80], OUTSIDE)}
      {rect([-44, -26, 44, 22], GRASS)}
      {/* courtyard paths */}
      {rect([-10.8, -26, -8.2, -3], "#ecdfc2", { stroke: "#b8a88a", strokeWidth: lw(1.5) })}
      {rect([-40, -14.5, 40, -12.3], "#ecdfc2", { stroke: "#b8a88a", strokeWidth: lw(1.5) })}
      {/* sports court */}
      {rect([14, -24, 30, -16.5], "#f0a070")}
      <rect x={14.8} y={-23.2} width={14.4} height={5.9} fill="none" stroke="rgba(255,255,255,0.8)" strokeWidth={lw(2)} />
      {TREES.map(([x, z, r], i) => (
        <g key={i}>
          <rect x={x - r + lw(3)} y={z - r + lw(4)} width={r * 2} height={r * 2} fill="rgba(0,0,0,0.25)" rx={r * 0.5} />
          <rect x={x - r} y={z - r} width={r * 2} height={r * 2} fill={i % 2 ? "#4e9a3e" : "#5fae4a"} rx={r * 0.5} stroke="#3f7a35" strokeWidth={lw(1.5)} />
        </g>
      ))}
      {/* the corridor (verandah): floor, pillars, the wall with lockers */}
      {rect([-44, -3.1, 44, 3.1], "#efe4cc")}
      {Array.from({ length: 22 }, (_, i) => rect([-42 + i * 4 - 0.3, -3.3, -42 + i * 4 + 0.3, -2.7], "#c8704f"))}
      {Array.from({ length: 9 }, (_, i) => rect([-6 + i * 0.78 - 0.37, 2.42, -6 + i * 0.78 + 0.37, 2.98], "#5f8fb8", { stroke: "#2a3a4a", strokeWidth: lw(1) }))}
      {Array.from({ length: 11 }, (_, i) => rect([-6 + (i + 9) * 0.78 + 4.2 - 0.37, 2.42, -6 + (i + 9) * 0.78 + 4.2 + 0.37, 2.98], "#5f8fb8", { stroke: "#2a3a4a", strokeWidth: lw(1) }))}
      {/* rooms behind the wall */}
      {ROOM_LIST.map((r, i) => (
        <g key={i}>
          {rect(r.r, "#e7d2aa", { stroke: WALL_INK, strokeWidth: lw(2.4) })}
          {/* benches, as the big map draws furniture: small wood blocks */}
          {Array.from({ length: 6 }, (_, j) => rect([r.r[0] + 2.2 + (j % 3) * 3.4, r.r[1] + 2.2 + Math.floor(j / 3) * 2.6, r.r[0] + 4.0 + (j % 3) * 3.4, r.r[1] + 2.8 + Math.floor(j / 3) * 2.6], "#b0703e"))}
          {/* door gap onto the corridor */}
          {rect([r.r[2] - 2.6, 3.1, r.r[2] - 1.4, 3.6], "#efe4cc")}
        </g>
      ))}
      {/* your class right now: tinted and outlined (map_view.gd "room" marker) */}
      {rect(ROOM_LIST[0].r, "rgba(255,107,92,0.3)", { stroke: "#ff5a4a", strokeWidth: lw(3) })}
      {rect([-44, 3.05, 44, 3.4], WALL_INK)}
    </g>
  );
};

/** 9-point fan (map_view.gd "staff" wedge). World units. */
const wedge = (w: Watcher, grow: number) => {
  const fov = (w.fov * Math.PI) / 180;
  const pts = [`${w.x},${w.z}`];
  for (let k = 0; k <= 8; k++) {
    const a = w.yaw - fov / 2 + (fov * k) / 8;
    pts.push(`${w.x - Math.sin(a) * w.reach * grow},${w.z - Math.cos(a) * w.reach * grow}`);
  }
  return pts.join(" ");
};

export type MiniMapProps = {
  t: number;
  cx: number; cy: number; R: number;
  /** px per metre */
  zoom: number;
  center: { x: number; z: number };
  rot: number;
  me: { x: number; z: number; yaw: number };
  watchers: Watcher[];
  /** 0..1+ pop scale per watcher id (0 = hidden) */
  show: Record<string, number>;
  /** name tags per watcher id (0..1 pop) */
  tags?: Record<string, number>;
  caption?: string;
  captionScale?: number;
  opacity?: number;
  /** extra glow ring on the disc edge (for the big hero shot) */
  shadow?: boolean;
  /** room name tags (map_view.gd shape labels) */
  roomTags?: number;
};

export const MiniMap: React.FC<MiniMapProps> = ({ t, cx, cy, R, zoom, center, rot, me, watchers, show, tags = {}, caption, captionScale = 1, opacity = 1, shadow = true, roomTags = 0 }) => {
  const k = R / 120;
  const deg = (rot * 180) / Math.PI;
  const cos = Math.cos(rot), sin = Math.sin(rot);
  const toScreen = (x: number, z: number) => {
    const dx = (x - center.x) * zoom, dz = (z - center.z) * zoom;
    return { x: cx + dx * cos - dz * sin, y: cy + dx * sin + dz * cos };
  };
  const id = `mm${Math.round(cx)}_${Math.round(cy)}_${Math.round(R)}`;
  const meS = toScreen(me.x, me.z);
  const meDir = me.yaw; // screen angle of the arrow: dir (-sin yaw, -cos yaw) rotated by rot
  const dx = -Math.sin(meDir), dz = -Math.cos(meDir);
  const sdx = dx * cos - dz * sin, sdy = dx * sin + dz * cos;
  const arrowAng = Math.atan2(sdy, sdx);
  const coneR = 34 * k;
  const cone = [`${meS.x},${meS.y}`];
  for (let i = 0; i <= 8; i++) {
    const a = arrowAng - 0.55 + (i * 1.1) / 8;
    cone.push(`${meS.x + Math.cos(a) * coneR},${meS.y + Math.sin(a) * coneR}`);
  }
  const ringR = R - 4 * k;
  return (
    <div style={{ position: "absolute", inset: 0, opacity, pointerEvents: "none" }}>
      <svg width={1920} height={1080} style={{ position: "absolute", inset: 0, overflow: "visible" }}>
        <defs>
          <clipPath id={id}><circle cx={cx} cy={cy} r={R - 1} /></clipPath>
        </defs>
        {shadow ? <circle cx={cx} cy={cy + 10 * k} r={R + 2 * k} fill="rgba(42,26,14,0.35)" /> : null}
        <circle cx={cx} cy={cy} r={R - 1} fill="rgba(20,20,36,0.9)" />
        <g clipPath={`url(#${id})`}>
          <g transform={`translate(${cx} ${cy}) rotate(${deg}) scale(${zoom}) translate(${-center.x} ${-center.z})`}>
            <MapWorld zoom={zoom} />
            {watchers.map((w) => {
              const s = show[w.id] ?? 0;
              if (s <= 0.001) return null;
              const tint = w.kind === "cctv" ? "#ff3833" : TINT[Math.min(2, w.alert)];
              return <polygon key={w.id} points={wedge(w, Math.min(1.15, s))} fill={tint} opacity={0.42} />;
            })}
          </g>
          {/* you: view cone and the gold arrow (map_view.gd draw_icon_arrow) */}
          <polygon points={cone.join(" ")} fill="rgba(255,217,77,0.22)" />
          {watchers.map((w) => {
            const s = show[w.id] ?? 0;
            if (s <= 0.001) return null;
            const p = toScreen(w.x, w.z);
            if (w.kind === "cctv") {
              // (the trailer's own marker for a camera: a little voxel CCTV body with its LED)
              const blink = Math.floor(t / 0.117) % 2 === 0;
              return (
                <g key={w.id} transform={`translate(${p.x} ${p.y}) scale(${k * s})`}>
                  <rect x={-10} y={-7.5} width={20} height={15} rx={3} fill={INK} />
                  <rect x={-8} y={-5.5} width={13} height={11} rx={2} fill="#e8e6e0" />
                  <rect x={5} y={-3.5} width={4} height={7} fill="#22232b" />
                  <circle cx={-3} cy={0} r={2.4} fill={blink ? "#ff3030" : "#6a1a1a"} />
                </g>
              );
            }
            const col = DOT[Math.min(2, w.alert)];
            return (
              <g key={w.id} transform={`translate(${p.x} ${p.y}) scale(${k * s})`}>
                {w.alert === 2 ? <circle r={10 + Math.sin(t * 10) * 2} fill="none" stroke="rgba(255,51,51,0.7)" strokeWidth={2} /> : null}
                <circle r={7.5} fill={INK} />
                <circle r={6} fill={col} />
                <rect x={-1.2} y={-4} width={2.4} height={5} fill="#fff" />
                <rect x={-1.2} y={2.2} width={2.4} height={2} fill="#fff" />
              </g>
            );
          })}
          <g transform={`translate(${meS.x} ${meS.y}) rotate(${(arrowAng * 180) / Math.PI}) scale(${k})`}>
            <path d="M12 0 L-7 8 L-3 0 L-7 -8 Z" fill={INK} transform="scale(1.3)" />
            <path d="M12 0 L-7 8 L-3 0 L-7 -8 Z" fill="#ffc93c" />
          </g>
        </g>
        {/* ring + compass (map_view.gd _round_frame) */}
        <circle cx={cx} cy={cy} r={ringR + 1 * k} fill="none" stroke={INK} strokeWidth={5 * k} />
        <circle cx={cx} cy={cy} r={ringR - 1 * k} fill="none" stroke="rgba(255,255,255,0.35)" strokeWidth={1.5 * k} />
        {([["N", 0], ["E", Math.PI / 2], ["S", Math.PI], ["W", -Math.PI / 2]] as const).map(([name, a]) => {
          const ang = rot + a;
          // Vector2(0, -1).rotated(ang) = (sin ang, -cos ang)
          const px = cx + Math.sin(ang) * (ringR - 2 * k), py = cy - Math.cos(ang) * (ringR - 2 * k);
          return (
            <g key={name} transform={`translate(${px} ${py})`}>
              <circle r={8 * k} fill={INK} />
              <text y={4.6 * k} textAnchor="middle" fontFamily={FONT} fontSize={13 * k} fill={name === "N" ? "#ff5a4a" : "#fff"}>{name}</text>
            </g>
          );
        })}
      </svg>
      {roomTags > 0
        ? ROOM_LIST.map((r, i) => {
            const p = toScreen((r.r[0] + r.r[2]) / 2, (r.r[1] + r.r[3]) / 2);
            if (Math.hypot(p.x - cx, p.y - cy) > R - 40 * k) return null;
            return (
              <div key={i} style={{ position: "absolute", left: p.x, top: p.y, translate: "-50% -50%", opacity: roomTags }}>
                <div style={{ fontFamily: FONT, fontSize: Math.max(10 * k, 24), lineHeight: 1, color: "#fff", background: "rgba(26,20,31,0.72)", borderRadius: 999, padding: "4px 12px 3px", whiteSpace: "nowrap" }}>{r.label}</div>
              </div>
            );
          })
        : null}
      {/* callout tags over the dots (trailer: named as each is called out) */}
      {watchers.map((w) => {
        const s = tags[w.id] ?? 0;
        if (s <= 0.001) return null;
        const p = toScreen(w.x, w.z);
        if (Math.hypot(p.x - cx, p.y - cy) > R - 14 * k) return null;
        return (
          <div key={w.id} style={{ position: "absolute", left: p.x, top: p.y - 17 * k, translate: "-50% -100%", scale: `${s}`, transformOrigin: "50% 100%" }}>
            <div style={{ fontFamily: FONT, fontSize: 30, lineHeight: 1, color: "#fff", background: "rgba(115,20,20,0.9)", borderRadius: 999, padding: "5px 16px 4px", whiteSpace: "nowrap", boxShadow: "0 4px 0 rgba(42,26,14,0.45)" }}>{w.label}</div>
          </div>
        );
      })}
      {caption ? (
        <div style={{ position: "absolute", left: cx, top: cy + R - 6 * k, translate: "-50% 0", scale: `${captionScale}`, transformOrigin: "50% 0" }}>
          <div style={{ background: "rgba(20,20,36,0.85)", borderRadius: 10 * k, padding: `${5 * k}px ${12 * k}px`, minWidth: 160 * k, textAlign: "center", fontFamily: FONT, fontSize: Math.max(13 * k, 26), lineHeight: 1, color: "#fff", whiteSpace: "pre" }}>{caption}</div>
        </div>
      ) : null}
    </div>
  );
};
