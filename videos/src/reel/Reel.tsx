import React from "react";
import { AbsoluteFill, Audio, Img, Sequence, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { Button, Card, Chip, ItemIcon, Outlined, font } from "../film/ui";
import { Cube, Voxels, voxelBounds } from "../film/voxel";
import { hash, impulse, JELLY, lerp, outCubic, outExpo, POP, sp } from "../film/fx";
import { slam } from "../film/fxui";
import { C } from "../film/tokens";
import { BEAT, FPS, ITEMS, ReelSpec, Scene, THEMES, sceneFrames } from "./spec";

type Ctx = { t: number; d: number; w: number; h: number; s: number; th: (typeof THEMES)[keyof typeof THEMES] };
const SLAM_COLORS = [C.gold, C.red, C.green, C.blue, C.purple, C.orange, C.pink];

const Backdrop: React.FC<Ctx> = ({ t, w, h, s, th }) => {
  const cell = 180 * s;
  const off = (t * 40 * s) % (cell * 2);
  return (
    <AbsoluteFill style={{ background: `linear-gradient(${th.bg2}, ${th.bg})` }}>
      <div
        style={{
          position: "absolute", inset: -cell * 2, opacity: 0.1,
          backgroundImage: `linear-gradient(45deg, ${th.stripe} 25%, transparent 25%, transparent 75%, ${th.stripe} 75%), linear-gradient(45deg, ${th.stripe} 25%, transparent 25%, transparent 75%, ${th.stripe} 75%)`,
          backgroundSize: `${cell * 2}px ${cell * 2}px`, backgroundPosition: `${off}px ${off}px, ${off + cell}px ${off + cell}px`,
        }}
      />
      <div style={{ position: "absolute", inset: 0, background: "radial-gradient(ellipse at center, transparent 55%, rgba(0,0,0,0.28))" }} />
    </AbsoluteFill>
  );
};

/** Voxel cubes bursting from a point (deterministic). */
const Cubes: React.FC<{ t: number; at: number; x: number; y: number; w: number; h: number; s: number; n?: number; seed?: number }> = ({ t, at, x, y, w, h, s, n = 16, seed = 1 }) => {
  const u = t - at;
  if (u < 0 || u > 1.2) return null;
  return (
    <svg width={w} height={h} style={{ position: "absolute", inset: 0 }}>
      {Array.from({ length: n }, (_, i) => {
        const a = hash(seed * 97 + i) * Math.PI, sp2 = (0.5 + Math.abs(hash(seed * 31 + i * 7))) * 900 * s;
        const dir = hash(seed + i * 13) > 0 ? 1 : -1;
        const px = x + Math.cos(a) * sp2 * u * dir, py = y - Math.sin(a) * sp2 * u + 1800 * s * u * u;
        return <Cube key={i} a={(10 + Math.abs(hash(i * 5 + seed)) * 14) * s} color={SLAM_COLORS[i % SLAM_COLORS.length]} x={px} y={py} rot={u * 360 * dir} o={1 - u / 1.2} />;
      })}
    </svg>
  );
};

const Sub: React.FC<{ t: number; at: number; s: number; children: React.ReactNode; color?: string }> = ({ t, at, s, children, color = C.ink }) => {
  const k = sp(t, at, POP);
  if (k <= 0) return null;
  return (
    <div style={{ transform: `scale(${k})` }}>
      <div style={{ ...font, fontSize: 44 * s, color, background: "rgba(255,255,255,0.92)", padding: `${12 * s}px ${26 * s}px`, borderRadius: 16 * s, borderBottom: `${6 * s}px solid rgba(0,0,0,0.25)` }}>
        {children}
      </div>
    </div>
  );
};

const lines = (text?: string) => (text ?? "").split(/\\n|\n/);

const Title: React.FC<Ctx & { sc: Scene }> = (c) => {
  const { t, w, h, s, sc, th } = c;
  const ls = lines(sc.text);
  const longest = Math.max(...ls.map((l) => l.length), 4);
  const size = Math.min(230 * s, (w * 0.9) / (longest * 0.5));
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", gap: 30 * s, flexDirection: "column" }}>
      {ls.map((l, i) => {
        const k = slam(t, 0.05 + i * 0.12, 2.6);
        return (
          <div key={i} style={{ transform: `scale(${k}) rotate(${(i % 2 ? 1 : -1) * 2 * (1 - Math.min(1, k))}deg)` }}>
            <Outlined size={size} color={i === ls.length - 1 && ls.length > 1 ? th.accent : C.gold}>{l}</Outlined>
          </div>
        );
      })}
      {sc.sub && <div style={{ marginTop: 30 * s }}><Sub t={t} at={0.05 + ls.length * 0.12 + 0.1} s={s}>{sc.sub}</Sub></div>}
      <Cubes t={t} at={0.05} x={w / 2} y={h / 2} w={w} h={h} s={s} seed={3} />
    </AbsoluteFill>
  );
};

const Words: React.FC<Ctx & { sc: Scene }> = ({ t, w, h, s, sc }) => {
  const words = sc.items?.length ? sc.items : ["..."];
  const per = Math.max(1, Math.round(sc.beats / words.length)) * BEAT || BEAT;
  const i = Math.min(words.length - 1, Math.floor(t / per));
  const lt = t - i * per;
  const word = words[i];
  const size = Math.min(320 * s, (w * 0.92) / (word.length * 0.5));
  const k = slam(lt, 0, 2.2, 0.2);
  const col = SLAM_COLORS[i % SLAM_COLORS.length];
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", background: i % 2 ? "rgba(0,0,0,0.18)" : "transparent" }}>
      <div style={{ transform: `scale(${k}) rotate(${(i % 2 ? 3 : -3) * (1 - Math.min(1, k))}deg)` }}>
        <Outlined size={size} color={col}>{word}</Outlined>
      </div>
      <Cubes t={lt} at={0} x={w / 2} y={h / 2} w={w} h={h} s={s} n={12} seed={i + 5} />
    </AbsoluteFill>
  );
};

const Plate: React.FC<Ctx & { sc: Scene }> = ({ t, d, w, h, s, sc, th }) => {
  const portrait = h > w;
  const fw = portrait ? w * 0.9 : w * 0.82, fh = portrait ? h * 0.56 : h * 0.66;
  const enter = sp(t, 0, { stiffness: 260, damping: 22 });
  const zoom = lerp(1.04, 1.22, t / Math.max(d, 0.1));
  const panX = lerp(-2.5, 2.5, t / Math.max(d, 0.1));
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: portrait ? "flex-start" : "center", paddingTop: portrait ? h * 0.08 : 0 }}>
      <div style={{ width: fw, height: fh, transform: `translateY(${(1 - enter) * 120 * s}px) rotate(${(1 - enter) * -3}deg) scale(${lerp(0.85, 1, enter)})`, opacity: Math.min(1, enter * 2), position: "relative" }}>
        <div style={{ position: "absolute", inset: 0, borderRadius: 28 * s, overflow: "hidden", border: `${10 * s}px solid ${C.ink}`, boxShadow: `0 ${20 * s}px ${40 * s}px rgba(0,0,0,0.4)` }}>
          <Img src={staticFile(`plates/${sc.plate ?? "fp0"}.jpg`)} style={{ width: "100%", height: "100%", objectFit: "cover", transform: `scale(${zoom}) translateX(${panX}%)` }} />
        </div>
        {sc.sub && (
          <div style={{ position: "absolute", left: 24 * s, top: -26 * s, transform: `rotate(-3deg) scale(${sp(t, 0.25, JELLY)})` }}>
            <Chip color={th.accent} text={C.ink} k={s * 1.6} size={26}>{sc.sub}</Chip>
          </div>
        )}
      </div>
      {sc.text && (
        <div style={{ position: portrait ? "relative" : "absolute", marginTop: portrait ? 60 * s : 0, bottom: portrait ? undefined : 50 * s, transform: `scale(${slam(t, 0.3, 2, 0.25)})`, textAlign: "center", padding: `0 ${40 * s}px` }}>
          <Outlined size={(portrait ? 100 : 84) * s} color="#fff" style={{ whiteSpace: "normal", lineHeight: 1.05 }}>{sc.text}</Outlined>
        </div>
      )}
    </AbsoluteFill>
  );
};

const Voxel: React.FC<Ctx & { sc: Scene }> = ({ t, w, h, s, sc }) => {
  const variant = sc.variant ?? "hero";
  const b1 = voxelBounds(variant, 1);
  const a = Math.min((w * 0.92) / b1.w, (h * 0.58) / b1.h);
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
      <div style={{ position: "absolute", top: h * 0.32 }}>
        <Voxels
          scene={variant} a={a} width={w} height={h * 0.62}
          anim={(x, y, z, i) => {
            const at = 0.05 + (x + y) * 0.012 + z * 0.02 + (i % 7) * 0.004;
            const k = sp(t, at, { stiffness: 300, damping: 18 });
            if (k <= 0.001) return null;
            return { dy: (1 - k) * -h * 0.3, s: Math.min(1.15, 0.3 + k * 0.7), o: Math.min(1, k * 3) };
          }}
        />
      </div>
      <div style={{ position: "absolute", top: h * 0.06, width: w, display: "flex", justifyContent: "center", transform: `scale(${slam(t, 0.1, 2, 0.28)})`, padding: `0 ${40 * s}px`, boxSizing: "border-box", textAlign: "center" }}>
        <Outlined size={124 * s} style={{ whiteSpace: "normal", lineHeight: 1.05 }}>{sc.text}</Outlined>
      </div>
    </AbsoluteFill>
  );
};

const Icons: React.FC<Ctx & { sc: Scene }> = ({ t, w, h, s, sc }) => {
  const items = (sc.items ?? []).filter((x) => x in ITEMS);
  const portrait = h > w;
  const cols = portrait ? Math.min(2, items.length || 1) : Math.min(3, items.length || 1);
  const size = Math.min((w * 0.9) / cols / 1.15, 360 * s);
  const per = (sc.beats * BEAT * 0.7) / Math.max(1, items.length);
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", flexDirection: "column", gap: 40 * s }}>
      <div style={{ transform: `scale(${slam(t, 0.05, 2, 0.28)})`, textAlign: "center", padding: `0 ${40 * s}px` }}>
        <Outlined size={96 * s} style={{ whiteSpace: "normal", lineHeight: 1.05 }}>{sc.text}</Outlined>
      </div>
      <div style={{ display: "flex", flexWrap: "wrap", justifyContent: "center", width: w * 0.95, gap: 20 * s }}>
        {items.map((it, i) => {
          const at = 0.25 + i * per;
          const k = sp(t, at, JELLY);
          return (
            <div key={it} style={{ width: size * 1.1, display: "flex", flexDirection: "column", alignItems: "center", transform: `scale(${k}) rotate(${(1 - Math.min(1, k)) * 25 + Math.sin(t * 2 + i) * 3}deg)`, opacity: k > 0 ? 1 : 0 }}>
              <ItemIcon name={it as any} size={size} style={{ filter: "drop-shadow(0 12px 10px rgba(0,0,0,0.3))" }} />
              <Outlined size={44 * s} color="#fff" strokeWidth={7 * s}>{ITEMS[it]}</Outlined>
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

const Alert: React.FC<Ctx & { sc: Scene }> = ({ t, d, w, h, s, sc }) => {
  const blink = impulse(t % (BEAT * 2), 0, 0.12);
  const kick = impulse(t % BEAT, 0, 0.09);
  const fill = outCubic(Math.min(1, t / (d * 0.8)));
  const size = Math.min(380 * s, (w * 0.9) / (Math.max(3, (sc.text ?? "RUN!").length) * 0.5));
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", flexDirection: "column", gap: 50 * s, background: `linear-gradient(${blink > 0.4 ? "#ff5a4a" : "#e0403c"}, #a82424)` }}>
      <div style={{ transform: `scale(${slam(t, 0, 2.6, 0.22) * (1 + kick * 0.05)}) translate(${Math.sin(t * 60) * 5 * s * kick}px, ${Math.cos(t * 55) * 5 * s * kick}px)`, background: C.red, padding: `${20 * s}px ${60 * s}px`, borderRadius: 24 * s, border: `${10 * s}px solid ${C.ink}`, borderBottomWidth: 22 * s }}>
        <Outlined size={size} color="#fff" stroke={C.ink} strokeWidth={size * 0.05} shadow={false}>{sc.text}</Outlined>
      </div>
      <div style={{ width: w * 0.8, transform: `scale(${sp(t, 0.25, POP)})` }}>
        <Card k={s * 1.6}>
          <div style={{ ...font, color: C.yellow, fontSize: 22 * s * 1.6, marginBottom: 8 * s }}>SUSPICION</div>
          <div style={{ height: 30 * s, borderRadius: 15 * s, background: "rgba(255,255,255,0.15)", overflow: "hidden" }}>
            <div style={{ width: `${fill * 100}%`, height: "100%", background: `linear-gradient(90deg, ${C.yellow}, ${C.redHot})` }} />
          </div>
        </Card>
      </div>
      {sc.sub && <Sub t={t} at={0.4} s={s}>{sc.sub}</Sub>}
    </AbsoluteFill>
  );
};

const Cta: React.FC<Ctx & { sc: Scene }> = ({ t, w, h, s, sc, th }) => {
  const size = Math.min(230 * s, (w * 0.9) / 5.2);
  const chips = sc.items ?? [];
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", flexDirection: "column", gap: 34 * s }}>
      <div style={{ transform: `scale(${slam(t, 0.05, 2.4, 0.3)})`, textAlign: "center" }}>
        <Outlined size={size}>BUNK</Outlined>
        <Outlined size={size} style={{ marginTop: -size * 0.1 }}>MASTER</Outlined>
      </div>
      {sc.text && (
        <div style={{ transform: `scale(${sp(t, 0.35, POP)})`, padding: `0 ${50 * s}px`, textAlign: "center" }}>
          <Outlined size={56 * s} color="#fff" strokeWidth={9 * s} style={{ whiteSpace: "normal", lineHeight: 1.1 }}>{sc.text}</Outlined>
        </div>
      )}
      <div style={{ display: "flex", gap: 24 * s }}>
        {chips.map((c, i) => (
          <div key={i} style={{ transform: `scale(${sp(t, 0.55 + i * 0.1, JELLY)})` }}>
            <Chip color={C.ink} k={s * 2} size={24}>{c}</Chip>
          </div>
        ))}
      </div>
      <div style={{ transform: `scale(${sp(t, 0.9, JELLY) * (1 + 0.04 * impulse(t % BEAT, 0, 0.1))})`, marginTop: 20 * s }}>
        <Button color={C.orange} k={s * 2.2} size={34}>COMING SOON</Button>
      </div>
    </AbsoluteFill>
  );
};

const BY_KIND: Record<Scene["kind"], React.FC<Ctx & { sc: Scene }>> = { title: Title, words: Words, plate: Plate, voxel: Voxel, icons: Icons, alert: Alert, cta: Cta };

const SceneView: React.FC<{ sc: Scene; spec: ReelSpec; frames: number }> = ({ sc, spec, frames }) => {
  const frame = useCurrentFrame();
  const { width: w, height: h } = useVideoConfig();
  const t = frame / FPS;
  const ctx: Ctx = { t, d: frames / FPS, w, h, s: Math.min(w, h) / 1080, th: THEMES[spec.theme] };
  const Body = BY_KIND[sc.kind];
  const bump = 1 + 0.012 * impulse(t % BEAT, 0, 0.08);
  return (
    <AbsoluteFill style={{ overflow: "hidden" }}>
      <Backdrop {...ctx} />
      <AbsoluteFill style={{ transform: `scale(${bump})` }}>
        <Body {...ctx} sc={sc} />
      </AbsoluteFill>
      {sc.flash !== false && t < 0.2 && <AbsoluteFill style={{ background: "#fff", opacity: 0.85 * (1 - t / 0.2) }} />}
    </AbsoluteFill>
  );
};

export const Reel: React.FC<{ spec: ReelSpec }> = ({ spec }) => {
  const frames = sceneFrames(spec);
  return (
    <AbsoluteFill style={{ background: "#000" }}>
      {spec.scenes.map((sc, i) => (
        <Sequence key={sc.id} from={frames[i].from} durationInFrames={frames[i].frames} layout="none">
          <SceneView sc={sc} spec={spec} frames={frames[i].frames} />
        </Sequence>
      ))}
      {spec.music === "trailer" && (
        <Audio src={staticFile("audio/trailer.wav")} startFrom={Math.round(spec.musicStartBar * 4 * BEAT * FPS)} volume={0.9} />
      )}
    </AbsoluteFill>
  );
};
