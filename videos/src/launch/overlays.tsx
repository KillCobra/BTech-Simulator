// Per-act 2D layers over the 3D world. Every value is a function of t and the beat sheet.
import React from "react";
import { step } from "../kit/spring";
import { ACT, b, BAR, BEAT, CHAPTERS, inAct } from "./cues";
import { project } from "./camera3d";
import { backOut, clamp01, easeIn, easeInOut, easeOut, expoIn, expoOut, HEAVY, lerp, POP, prog, rand, SNAP, SOFT, sp, squash, WOBBLE } from "./juice";
import { actors, headTop } from "./stage";
import { C, FONT } from "./tokens";
import { ITEM_SVG, badgeSvg } from "./icons";
import { Alert, Banner, Card, font, GameButton, Icon, outline, Plate, PopWords, Speech } from "./ui";

const PI = Math.PI;
const headOf = (t: number, id: string) => {
  const a = actors(t).find((x) => x.id === id);
  return a ? project(t, headTop(a)) : null;
};
const mmss = (s: number) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`;

// ============================================================== chapter stamps
export const Stamps: React.FC<{ t: number }> = ({ t }) => (
  <>
    {CHAPTERS.map((ch, i) => {
      const first = ch.words[0][1];
      if (t < first - 0.05 || t > ch.out + 0.3) return null;
      const leave = clamp01((t - ch.out) / 0.2);
      const dim = clamp01((t - first + 0.05) / 0.08) * (1 - leave);
      const lines = ch.words;
      const size = lines.length === 1 ? 260 : 210;
      return (
        <div key={i} style={{ position: "absolute", inset: 0 }}>
          <div style={{ position: "absolute", inset: 0, background: `radial-gradient(ellipse at center, rgba(42,26,14,${0.55 * dim}) 0%, rgba(42,26,14,${0.25 * dim}) 70%)` }} />
          <div style={{ position: "absolute", left: 0, right: 0, top: "50%", translate: `0 -50%`, display: "grid", justifyItems: "center", gap: 0 }}>
            {lines.map(([word, at], k) => {
              const s = step(t - at, { stiffness: 900, damping: 26 });
              if (t < at - 0.02) return <div key={k} style={{ height: size * 0.92 }} />;
              const [sx, sy] = squash(t, at + 0.05, 0.22, 26, 10);
              const inScale = lerp(2.8, 1, s);
              const rot = (k % 2 ? 1 : -1) * (3 + 6 * (1 - s));
              return (
                <div key={k} style={{
                  ...font(size, ch.accent ?? C.gold), ...outline(14), height: size * 0.92, display: "flex", alignItems: "center",
                  scale: `${inScale * sx * (1 + leave * 0.25)} ${inScale * sy * (1 + leave * 0.25)}`, rotate: `${rot}deg`,
                  opacity: clamp01(s * 4) * (1 - leave), filter: leave > 0 ? `blur(${leave * 16}px)` : undefined,
                  textShadow: "0 16px 0 rgba(0,0,0,.35)", whiteSpace: "nowrap", letterSpacing: 4,
                }}>{word}</div>
              );
            })}
          </div>
        </div>
      );
    })}
  </>
);

// ============================================================== act 1: classroom
export const ClassroomUI: React.FC<{ t: number }> = ({ t }) => {
  if (t > b(2, 0.5)) return null;
  const inCard = sp(t, b(0, 1), { stiffness: 380, damping: 20 });
  const leave = easeIn(clamp01((t - b(1, 3.5)) / 0.18));
  const secs = 300 - Math.max(0, Math.floor((t - b(0, 1)) / BEAT));
  // Lower third: the school's name, flipping in letter by letter on 32nds.
  const name = "ROYAL ACADEMY OF UNNECESSARY SCIENCES";
  const nameAt = b(0, 2);
  const marks: React.ReactNode[] = [];
  const pos = (id: string) => headOf(t, id);
  if (t >= b(1)) {
    const heads: [string, number, "?" | "!"][] = [["friendA", b(1, 0), "?"], ["friendC", b(1, 1), "?"], ["friendB", b(1, 2), "?"], ["hero", b(1, 3), "!"]];
    heads.forEach(([id, at, k]) => {
      const p = pos(id);
      if (p && !p.behind) marks.push(<Alert key={id} t={t} at={at} x={p.x} y={p.y - 10} kind={k} size={k === "!" ? 190 : 130} />);
    });
  }
  return (
    <div style={{ position: "absolute", inset: 0, opacity: 1 - leave }}>
      {marks}
      <div style={{ position: "absolute", left: 48, top: 44, translate: `${(1 - inCard) * -620}px 0`, rotate: `${(1 - inCard) * -8}deg` }}>
        <Card style={{ width: 560 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
            <span style={font(46, C.white)}>YOU</span>
            <span style={{ ...font(30, C.white), background: C.classes[0], borderRadius: 12, padding: "6px 14px 4px" }}>Class A</span>
          </div>
          <div style={{ ...font(34, C.white), marginTop: 14 }}>Final bell in {mmss(secs)}</div>
          <div style={{ ...font(30, C.info), marginTop: 10, lineHeight: 1.15 }}>Period 1/3 · Thermodynamics<br />Class A, Ground Floor</div>
          <div style={{ ...font(32, C.warn), marginTop: 12 }}>Pocket money: Rs 30</div>
        </Card>
      </div>
      <div style={{ position: "absolute", left: 60, bottom: 64, display: "flex", flexDirection: "column", gap: 10 }}>
        <div style={{ height: 8, width: 380 * easeOut(prog(t, nameAt - 0.1, 0.35)), background: C.gold, borderRadius: 4 }} />
        <div style={{ display: "flex", ...font(52, C.white), ...outline(5) }}>
          {name.split("").map((ch, i) => {
            const s = sp(t, nameAt + i * 0.012, SNAP);
            return <span key={i} style={{ display: "inline-block", minWidth: ch === " " ? 16 : undefined, opacity: clamp01(s * 2), translate: `0 ${(1 - s) * 40}px`, rotate: `${(1 - s) * 40}deg` }}>{ch}</span>;
          })}
        </div>
        <div style={{ ...font(30, C.info), opacity: clamp01((t - nameAt - 0.35) / 0.2) }}>First period. Nobody wants to be here.</div>
      </div>
    </div>
  );
};

// ============================================================== act 2: make a plan (Grand Campus big map)
const ROUTE: [number, number][] = [[905, 590], [820, 640], [700, 690], [560, 770], [420, 850], [250, 940], [150, 985]];
const FRIENDS: { name: string; col: string; x: number; y: number }[] = [
  { name: "YOU", col: C.classes[0], x: 880, y: 560 }, { name: "PRIYA", col: C.classes[1], x: 960, y: 520 },
  { name: "ARJUN", col: C.classes[2], x: 1000, y: 600 }, { name: "MEERA", col: C.classes[3], x: 830, y: 510 },
];

export const PlanMap: React.FC<{ t: number }> = ({ t }) => {
  const start = b(2, 0.5);
  if (t < start || t >= b(4)) return null;
  const cols = 8, rows = 5, tw = 1920 / cols, th = 1080 / rows;
  // Map push-in over bar 3, then a fast zoom through into the classroom.
  const exitU = expoIn(clamp01((t - b(3, 3.25)) / (b(4) - b(3, 3.25))));
  const zoom = lerp(1, 1.1, easeInOut(prog(t, b(3), BEAT * 3))) * (1 + exitU * 5);
  const blur = exitU * 18;
  return (
    <div style={{ position: "absolute", inset: 0, background: C.ink, overflow: "hidden" }}>
      <div style={{ position: "absolute", inset: 0, scale: `${zoom}`, transformOrigin: "905px 590px", filter: blur ? `blur(${blur}px)` : undefined, perspective: 1600 }}>
        {Array.from({ length: cols * rows }, (_, i) => {
          const cx = i % cols, cy = Math.floor(i / cols);
          const dist = Math.hypot(cx - 3.5, (cy - 2) * 1.4) / 5;
          const at = b(2, 1.5) + dist * BEAT * 1.6 + rand(i) * 0.06;
          const s = step(t - at, { stiffness: 320, damping: 19 });
          if (t < at - 0.01) return null;
          return (
            <div key={i} style={{ position: "absolute", left: cx * tw, top: cy * th, width: tw, height: th, overflow: "hidden", transformOrigin: "50% 50%", rotate: `${(rand(i + 3) - 0.5) * 40 * (1 - s)}deg`, transform: `rotateX(${(1 - s) * 80}deg) translateZ(${(1 - s) * 300}px)`, opacity: clamp01(s * 3), outline: s < 0.98 ? `3px solid ${C.ink}` : undefined }}>
              <Plate name="c_air1" style={{ left: -cx * tw, top: -cy * th }} />
            </div>
          );
        })}
        <RouteAndPins t={t} />
      </div>
      <QuestChain t={t} leave={exitU} />
    </div>
  );
};

const RouteAndPins: React.FC<{ t: number }> = ({ t }) => {
  const draw = easeInOut(prog(t, b(3, 2), BEAT * 1.0));
  const d = ROUTE.map(([x, y], i) => `${i ? "L" : "M"}${x} ${y}`).join(" ");
  const len = ROUTE.reduce((acc, p, i) => (i ? acc + Math.hypot(p[0] - ROUTE[i - 1][0], p[1] - ROUTE[i - 1][1]) : 0), 0);
  const star = sp(t, b(3, 3), WOBBLE);
  const [ex, ey] = ROUTE[ROUTE.length - 1];
  const march = -(t * 120) % 48;
  return (
    <>
      <svg width={1920} height={1080} style={{ position: "absolute", inset: 0 }}>
        <path d={d} fill="none" stroke={C.ink} strokeWidth={22} strokeLinecap="round" strokeLinejoin="round" strokeDasharray={`${len * draw} ${len}`} opacity={0.35} />
        <path d={d} fill="none" stroke={C.gold} strokeWidth={14} strokeLinecap="round" strokeLinejoin="round" strokeDasharray={`${len * draw} ${len}`} />
        <path d={d} fill="none" stroke={C.ink} strokeWidth={5} strokeDasharray="18 30" strokeDashoffset={march} strokeLinecap="round" opacity={draw > 0 ? 0.55 : 0} style={{ clipPath: "none" }} mask="url(#routeMask)" />
        <defs>
          <mask id="routeMask"><path d={d} fill="none" stroke="#fff" strokeWidth={16} strokeDasharray={`${len * draw} ${len}`} strokeLinecap="round" /></mask>
        </defs>
        {star > 0.001 ? (
          <g transform={`translate(${ex} ${ey}) scale(${star}) rotate(${(1 - Math.min(1, star)) * -90})`}>
            <circle r={70 + 30 * (1 - clamp01((t - b(3, 3)) / 0.5))} fill={C.good} opacity={0.35 * (1 - clamp01((t - b(3, 3)) / 0.5))} />
            <path d={starPath(52, 22)} fill="#48b06a" stroke={C.ink} strokeWidth={7} strokeLinejoin="round" />
          </g>
        ) : null}
      </svg>
      {star > 0.001 ? (
        <div style={{ position: "absolute", left: ex + 70, top: ey - 34, ...font(56, C.white), ...outline(6), scale: `${star}`, transformOrigin: "0 50%", whiteSpace: "nowrap" }}>FENCE HOLE <span style={{ color: C.good }}>(crouch)</span></div>
      ) : null}
      {FRIENDS.map((f, i) => {
        const at = b(3, i * 0.5);
        const s = sp(t, at, WOBBLE);
        if (s <= 0.001) return null;
        const bob = Math.sin((t - at) * 6 + i) * 4;
        return (
          <div key={f.name} style={{ position: "absolute", left: f.x, top: f.y + bob, translate: "-50% -100%", scale: `${s}`, transformOrigin: "50% 100%", display: "grid", justifyItems: "center" }}>
            <div style={{ ...font(34, C.white), background: C.card, borderRadius: 10, padding: "6px 12px 4px", marginBottom: 6, whiteSpace: "nowrap" }}>{f.name}</div>
            <svg width={56} height={70} viewBox="0 0 56 70">
              <path d="M28 68 C18 50 4 40 4 26 A24 24 0 0 1 52 26 C52 40 38 50 28 68 Z" fill={f.col} stroke={C.ink} strokeWidth={5} />
              <circle cx={28} cy={26} r={10} fill="#fff" />
            </svg>
          </div>
        );
      })}
    </>
  );
};

export const starPath = (R: number, r: number) =>
  Array.from({ length: 10 }, (_, i) => {
    const a = -PI / 2 + (i * PI) / 5, rad = i % 2 ? r : R;
    return `${i ? "L" : "M"}${(Math.cos(a) * rad).toFixed(1)} ${(Math.sin(a) * rad).toFixed(1)}`;
  }).join(" ") + "Z";

const QuestChain: React.FC<{ t: number; leave: number }> = ({ t, leave }) => {
  const at = b(2, 2.5);
  const s = sp(t, at, { stiffness: 380, damping: 22 });
  if (t < at - 0.05) return null;
  // director.gd QUESTS: real quest lines.
  const rows = ["Answer the register, then slip out of class", "Steal the exam paper from the staff room", "Eat a samosa from the canteen"];
  return (
    <div style={{ position: "absolute", left: 48, top: 44, translate: `${(1 - s) * -700 - leave * 700}px 0` }}>
      <Card style={{ width: 720 }}>
        <div style={{ ...font(32, C.white), opacity: 0.7 }}>QUEST CHAIN&nbsp;&nbsp;0/3</div>
        {rows.map((r, i) => {
          const rs = sp(t, at + 0.12 + i * BEAT * 0.5, SNAP);
          return (
            <div key={i} style={{ ...font(32, i === 0 ? C.warn : "rgba(255,255,255,.55)"), marginTop: 12, opacity: clamp01(rs * 2), translate: `${(1 - rs) * -40}px 0`, whiteSpace: "nowrap" }}>
              {i === 0 ? "> 1." : `   ${i + 1}.`}&nbsp;&nbsp;{r}
            </div>
          );
        })}
      </Card>
    </div>
  );
};

// ============================================================== act 3: someone ruins it
export const RuinUI: React.FC<{ t: number }> = ({ t }) => {
  if (!inAct(t, ACT.ruin)) return null;
  const tp = headOf(t, "teacher");
  const fb = headOf(t, "friendB");
  return (
    <>
      {fb && t < b(4, 2) ? <Speech t={t} at={b(4, 1)} x={fb.x} y={fb.y - 10} text="Psst! This way!" size={64} /> : null}
      {tp ? <Alert t={t} at={b(4, 2)} x={tp.x} y={tp.y - 20} kind="!" size={230} /> : null}
      {tp ? <Speech t={t} at={b(4, 3)} x={tp.x + 40} y={tp.y + 150} text="Who's talking?!" size={120} /> : null}
      <VoiceMeter t={t} />
    </>
  );
};

/** "The HUD shows how far you can be heard right now." */
const VoiceMeter: React.FC<{ t: number }> = ({ t }) => {
  const s = sp(t, b(4, 1), SNAP);
  if (s <= 0.001) return null;
  const level = t < b(4, 2) ? 0.5 + 0.45 * Math.abs(Math.sin((t - b(4, 1)) * 13)) : Math.max(0, 0.5 - (t - b(4, 2)) * 3);
  const heard = Math.round(2 + level * 10);
  return (
    <div style={{ position: "absolute", left: "50%", bottom: 60, translate: `-50% ${(1 - s) * 200}px` }}>
      <Card style={{ display: "flex", alignItems: "center", gap: 24, padding: "18px 30px" }}>
        <svg width={40} height={52} viewBox="0 0 40 52"><rect x={10} y={2} width={20} height={32} rx={10} fill={C.white} /><path d="M4 24 a16 16 0 0 0 32 0 M20 40 v10" stroke={C.white} strokeWidth={4} fill="none" /></svg>
        <div style={{ width: 360, height: 20, background: "rgba(255,255,255,.12)", borderRadius: 10, overflow: "hidden" }}>
          <div style={{ width: `${level * 100}%`, height: "100%", background: level > 0.7 ? C.alarm : C.warn, borderRadius: 10 }} />
        </div>
        <div style={font(40, C.white)}>Heard {heard} m away</div>
      </Card>
    </div>
  );
};

// ============================================================== act 3b: CCTV + suspicion
export const CctvUI: React.FC<{ t: number }> = ({ t }) => {
  if (!inAct(t, ACT.cctv)) return null;
  const s = sp(t, b(5, 0), { stiffness: 420, damping: 22 });
  const fill = easeIn(prog(t, b(5, 1), BEAT * 2));
  const pct = Math.round(fill * 100);
  const col = mix(C.warn, C.alarmDeep, fill);
  const heat = t < b(5, 2) ? 1 : t < b(5, 3) ? 2 : 3;
  const seenBlink = t > b(5, 1) && Math.floor((t - b(5, 1)) / (BEAT / 2)) % 2 === 0;
  const red = t > b(5, 3) ? 0.45 * Math.exp(-(t - b(5, 3)) * 2) : 0;
  return (
    <>
      <div style={{ position: "absolute", inset: 0, boxShadow: `inset 0 0 240px rgba(255,40,40,${red + fill * 0.25})` }} />
      <div style={{ position: "absolute", right: 48, top: 44, translate: `${(1 - s) * 700}px 0` }}>
        <Card style={{ width: 600 }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <span style={font(34, C.white)}>SUSPICION</span>
            <span style={{ ...font(34, C.alarm), opacity: seenBlink ? 1 : 0 }}>SEEN!</span>
            <span style={font(34, C.white)}>{pct}%</span>
          </div>
          <div style={{ marginTop: 14, height: 28, background: "rgba(255,255,255,.12)", borderRadius: 8, overflow: "hidden" }}>
            <div style={{ width: `${fill * 100}%`, height: "100%", background: col }} />
          </div>
          <div style={{ ...font(34, C.white), marginTop: 16 }}>CCTV · First floor balcony</div>
          <div style={{ ...font(32, [C.good, C.warn, "#ff9a4a", "#ff5a5a"][heat - 1]), marginTop: 12, scale: `${1 + 0.25 * Math.exp(-Math.max(0, t - (heat === 2 ? b(5, 2) : b(5, 3))) * 10)}`, transformOrigin: "0 50%" }}>HEAT {heat}/4</div>
        </Card>
      </div>
      <Banner t={t} at={b(5, 3)} color="#ff4a4a" text="RUN!  You've been spotted!" top={700} size={84} />
    </>
  );
};

export function mix(a: string, c: string, u: number) {
  const pa = parseInt(a.slice(1), 16), pc = parseInt(c.slice(1), 16);
  const ch = (s: number) => Math.round(((pa >> s) & 255) * (1 - u) + ((pc >> s) & 255) * u);
  return `rgb(${ch(16)},${ch(8)},${ch(0)})`;
}

// ============================================================== act 4: improvise
export const ExcuseUI: React.FC<{ t: number }> = ({ t }) => {
  if (!inAct(t, ACT.excuse)) return null;
  const s = sp(t, b(6, 0.75), { stiffness: 420, damping: 24 });
  const pick = b(6, 3);
  const picked = t >= pick;
  const opts: { k: string; text: string; col: string; icon?: string }[] = [
    { k: "1", text: "I've got a hall pass, look!", col: C.good, icon: "hall_pass" },
    { k: "2", text: "Medical emergency! Here's my note.", col: C.good, icon: "medical_note" },
    { k: "3", text: "Just coming back from the washroom!", col: C.white },
    { k: "4", text: "It was Arjun! They made me do it!", col: C.snitch },
  ];
  const timer = 1 - prog(t, b(6, 1), BAR);
  const pp = headOf(t, "proctor");
  return (
    <>
      {pp ? <Alert t={t} at={b(6, 0.5)} x={pp.x} y={pp.y - 10} kind="!" size={170} /> : null}
      <div style={{ position: "absolute", left: "50%", bottom: 50, translate: `-50% ${(1 - s) * 700}px`, rotate: `${(1 - s) * 6}deg` }}>
        <div style={{ background: "rgba(26,13,13,0.94)", borderRadius: 32, padding: "30px 40px", width: 1240 }}>
          <div style={{ ...font(44, "#ff9a7a"), whiteSpace: "nowrap" }}>PROCTOR STOPPED YOU!&nbsp;&nbsp;Talk your way out:</div>
          {opts.map((o, i) => {
            const at = b(6, 1 + i * 0.5);
            const os = sp(t, at, SNAP);
            const chosen = picked && i === 3;
            const pop = chosen ? 1 + 0.12 * Math.exp(-(t - pick) * 7) * Math.cos((t - pick) * 30) : 1;
            return (
              <div key={o.k} style={{ display: "flex", alignItems: "center", gap: 18, marginTop: 14, opacity: clamp01(os * 2) * (picked && !chosen ? 0.35 : 1), translate: `${(1 - os) * 80}px 0`, scale: `${pop}`, transformOrigin: "0 50%", background: chosen ? "rgba(255,106,138,.18)" : undefined, borderRadius: 14, padding: "6px 12px" }}>
                <span style={{ ...font(40, C.ink), background: chosen ? C.snitch : "rgba(255,255,255,.85)", borderRadius: 10, padding: "4px 12px 2px" }}>{o.k}</span>
                <span style={{ ...font(42, o.col), whiteSpace: "nowrap" }}>{o.text}</span>
                {o.icon ? <Icon svg={ITEM_SVG[o.icon]} size={58} /> : null}
              </div>
            );
          })}
          <div style={{ marginTop: 20, height: 12, background: "rgba(255,255,255,.1)", borderRadius: 6 }}>
            <div style={{ width: `${timer * 100}%`, height: "100%", background: "#ff6a5a", borderRadius: 6 }} />
          </div>
        </div>
      </div>
    </>
  );
};

export const PaperUI: React.FC<{ t: number }> = ({ t }) => {
  if (!inAct(t, ACT.paper)) return null;
  const tp = headOf(t, "teacher");
  return tp ? <Alert t={t} at={b(7, 2) + 0.3} x={tp.x} y={tp.y - 10} kind="?" size={170} /> : null;
};

// Fire extinguisher: prompt, the item flies in, smoke floods the frame.
export const SprayUI: React.FC<{ t: number }> = ({ t }) => {
  if (t < b(7, 3) - 0.05 || t >= b(8, 1)) return null;
  const at = b(7, 3);
  const s = sp(t, at, WOBBLE);
  const clear = easeOut(clamp01((t - b(8)) / (BEAT * 0.9)));
  const puffs = Array.from({ length: 26 }, (_, i) => {
    const born = at + 0.08 + (i / 26) * BEAT * 0.9;
    const d = t - born;
    if (d < 0) return null;
    const ang = -0.35 + (rand(i) - 0.5) * 0.9;
    const dist = 260 + d * (900 + rand(i + 1) * 700);
    const r = 60 + d * (700 + rand(i + 2) * 400);
    const x = 780 + Math.cos(ang) * dist, y = 450 + Math.sin(ang) * dist * 0.7 + (rand(i + 4) - 0.5) * 200;
    return <div key={i} style={{ position: "absolute", left: x - r, top: y - r, width: r * 2, height: r * 2, borderRadius: "50%", background: "radial-gradient(circle at 40% 35%, #ffffff 0%, #f1f4f6 55%, rgba(233,238,242,0) 72%)", opacity: 1 - clear }} />;
  });
  return (
    <>
      {puffs}
      <div style={{ position: "absolute", left: 560, top: 520, translate: `-50% -50% ${0}`, scale: `${s * (1 + 0.2 * clear)}`, rotate: `${-18 + (1 - Math.min(1, s)) * -120}deg`, opacity: 1 - clear }}>
        <Icon svg={ITEM_SVG.extinguisher} size={520} />
      </div>
      <div style={{ position: "absolute", left: "50%", bottom: 120, translate: "-50% 0", opacity: 1 - clear }}>
        <PopWords t={t} words={[["[E]", at], ["Take", at + 0.05], ["the", at + 0.1], ["fire", at + 0.15], ["extinguisher", at + 0.2]]} size={64} color={C.white} stroke={6} />
      </div>
    </>
  );
};

// ============================================================== surprise test (exam_game.gd)
export const TestUI: React.FC<{ t: number }> = ({ t }) => {
  if (!inAct(t, ACT.test)) return null;
  const at = b(8);
  const s = step(t - at, { stiffness: 520, damping: 18 });
  const flip = easeInOut(clamp01((t - (b(8, 2) - 0.12)) / 0.24));
  const page = flip < 0.5 ? 0 : 1;
  const raise = sp(t, b(8, 3), { stiffness: 480, damping: 20 });
  return (
    <>
      <div style={{ position: "absolute", left: "50%", top: "50%", translate: `-50% -50%`, scale: `${lerp(1.8, 1, s)}`, rotate: `${lerp(-24, -3, s)}deg`, opacity: clamp01(s * 4), perspective: 2000 }}>
        <div style={{ transform: `rotateY(${flip * 180 * (page ? -1 : 1) + (page ? 180 : 0)}deg)` }}>
          <div style={{ width: 1060, height: 700, background: C.paper, border: `12px solid ${C.paperEdge}`, borderRadius: 28, padding: 40, boxSizing: "border-box", boxShadow: "0 30px 0 rgba(0,0,0,.25)" }}>
            {page === 0 ? <Reactor t={t} /> : <Sums t={t} />}
          </div>
        </div>
      </div>
      {raise > 0.001 ? (
        <div style={{ position: "absolute", right: 70, bottom: 60, scale: `${raise}`, rotate: `${(1 - Math.min(1, raise)) * 20 + 3}deg`, transformOrigin: "100% 100%" }}>
          <div style={{ background: "rgba(18,18,31,0.95)", borderRadius: 32, padding: "28px 34px", width: 760 }}>
            <div style={font(40, C.warn)}>RAISE YOUR HAND&nbsp;&nbsp;·&nbsp;&nbsp;CHEMISTRY</div>
            <div style={{ display: "flex", gap: 14, marginTop: 18 }}>
              {[["INTELLIGENT", C.good], ["QUIRKY", "#7fd0ea"], ["MISCHIEVOUS", "#ff9a6a"]].map(([l, c], i) => (
                <span key={l} style={{ ...font(30, C.ink), background: c, borderRadius: 16, padding: "8px 14px 6px", outline: i === 1 ? `4px solid ${C.white}` : undefined }}>{l}</span>
              ))}
            </div>
            <div style={{ ...font(40, C.white), marginTop: 18 }}>"Do pigeons have to attend lectures?"</div>
          </div>
        </div>
      ) : null}
    </>
  );
};

const Reactor: React.FC<{ t: number }> = ({ t }) => {
  const settle = step(t - b(8, 1), { stiffness: 260, damping: 9 });
  const wander = 0.5 + 0.45 * Math.sin((t - b(8)) * 11);
  const needle = t < b(8, 1) ? wander : lerp(wander, 0.56, settle);
  const good = t > b(8, 1) + 0.1;
  return (
    <>
      <div style={{ display: "flex", justifyContent: "space-between" }}>
        <span style={font(48, C.paperTitle)}>THERMODYNAMICS&nbsp;&nbsp;·&nbsp;&nbsp;REACTOR CONTROL</span>
        <span style={font(44, C.paperInk)}>{Math.max(0, 12 - Math.floor((t - b(8)) * 4))}s</span>
      </div>
      <div style={{ ...font(36, C.paperInk), marginTop: 30 }}>Keep the needle in the green zone.</div>
      <div style={{ position: "relative", marginTop: 90, height: 60, background: "#3a3d47", borderRadius: 30 }}>
        <div style={{ position: "absolute", left: "44%", width: "24%", top: 0, bottom: 0, background: "#48b06a", borderRadius: 8 }} />
        <div style={{ position: "absolute", left: "53%", width: "6%", top: 0, bottom: 0, background: "#7fe0a0" }} />
        <div style={{ position: "absolute", left: `${needle * 100}%`, top: -40, width: 16, height: 140, background: "#e0524f", borderRadius: 8, translate: "-50% 0", boxShadow: "0 6px 0 rgba(0,0,0,.25)" }} />
      </div>
      <div style={{ display: "flex", justifyContent: "space-between", marginTop: 60 }}>
        <span style={font(44, "#4f86e0")}>COLD</span>
        <span style={{ ...font(56, "#48b06a"), opacity: good ? 1 : 0, scale: `${good ? 1 + 0.3 * Math.exp(-(t - b(8, 1) - 0.1) * 9) : 1}` }}>STABLE!</span>
        <span style={font(44, "#e0524f")}>HOT</span>
      </div>
    </>
  );
};

const Sums: React.FC<{ t: number }> = ({ t }) => {
  const press = b(8, 2);
  const p = t > press ? Math.exp(-(t - press) * 12) : 0;
  const right = t > press;
  const badge = sp(t, press + 0.08, WOBBLE);
  return (
    <div style={{ position: "relative", height: "100%" }}>
      <div style={{ display: "flex", justifyContent: "space-between" }}>
        <span style={font(48, C.paperTitle)}>ENGINEERING MATHS&nbsp;&nbsp;·&nbsp;&nbsp;QUICK SUMS</span>
        <span style={font(44, C.paperInk)}>7s</span>
      </div>
      <div style={{ ...font(150, C.ink), textAlign: "center", marginTop: 70 }}>7 × 8 = {right ? <span style={{ color: "#48b06a" }}>56</span> : "?"}</div>
      <div style={{ display: "flex", gap: 40, justifyContent: "center", marginTop: 60 }}>
        {["54", "56", "63"].map((n) => (
          <GameButton key={n} label={n} color={n === "56" && right ? C.good : C.gold} press={n === "56" ? (right ? 1 - p * 0 : 0) * (t > press ? 1 : 0) : 0} size={56} />
        ))}
      </div>
      {badge > 0.001 ? (
        <div style={{ position: "absolute", right: -60, top: 60, scale: `${badge}`, rotate: `${(1 - Math.min(1, badge)) * 180 + 12}deg` }}>
          <Icon svg={badgeSvg(1)} size={220} />
          <div style={{ ...font(64, C.good), ...outline(6), textAlign: "center", marginTop: -10 }}>+100</div>
        </div>
      ) : null}
    </div>
  );
};

// ============================================================== panic
export const PanicUI: React.FC<{ t: number }> = ({ t }) => {
  if (!inAct(t, ACT.panic)) return null;
  const phase = Math.floor((t - b(9)) / (BEAT / 2)) % 2;
  const marks: React.ReactNode[] = [];
  (["guard", "proctor", "teacher"] as const).forEach((id, i) => {
    const p = headOf(t, id);
    if (p && !p.behind) marks.push(<Alert key={id} t={t} at={b(9, 1 + i)} x={p.x} y={p.y - 10} kind="!" size={150} />);
  });
  const freeze = t >= b(9, 3.5);
  return (
    <>
      <div style={{ position: "absolute", inset: 0, boxShadow: `inset ${phase ? 260 : -260}px 0 260px -80px ${phase ? "rgba(255,40,40,.55)" : "rgba(60,110,255,.5)"}` }} />
      {marks}
      <div style={{ position: "absolute", right: 48, top: 44 }}>
        <Card style={{ width: 600 }}>
          <div style={{ display: "flex", justifyContent: "space-between" }}>
            <span style={font(34, C.white)}>SUSPICION</span><span style={{ ...font(34, C.alarm), opacity: phase ? 1 : 0.2 }}>SEEN!</span><span style={font(34, C.white)}>100%</span>
          </div>
          <div style={{ marginTop: 14, height: 28, background: C.alarmDeep, borderRadius: 8 }} />
          <div style={{ ...font(32, "#ff5a5a"), marginTop: 16 }}>HEAT 4/4</div>
        </Card>
      </div>
      {freeze ? <div style={{ position: "absolute", inset: 0, background: "rgba(255,255,255,.12)", mixBlendMode: "screen" }} /> : null}
    </>
  );
};

// ============================================================== chase (the drop)
export const ChaseUI: React.FC<{ t: number }> = ({ t }) => {
  if (!inAct(t, ACT.chase)) return null;
  const lines = Array.from({ length: 22 }, (_, i) => {
    const y = 80 + rand(i) * 920;
    const speed = 2600 + rand(i + 1) * 2200;
    const len = 180 + rand(i + 2) * 420;
    const x = 2100 - (((t - b(10)) * speed + rand(i + 3) * 3000) % 3200);
    return <div key={i} style={{ position: "absolute", left: x, top: y, width: len, height: 5 + rand(i + 4) * 5, background: "rgba(255,255,255,.75)", borderRadius: 4 }} />;
  });
  const goal = sp(t, b(10), { stiffness: 700, damping: 22 });
  const [sx, sy] = squash(t, b(10) + 0.05, 0.25, 24, 8);
  return (
    <>
      {lines}
      <div style={{ position: "absolute", left: "50%", top: 70, translate: "-50% 0", scale: `${lerp(3, 1, goal) * sx} ${lerp(3, 1, goal) * sy}`, opacity: clamp01(goal * 3), ...font(120, C.gold), ...outline(12), textShadow: "0 12px 0 rgba(0,0,0,.3)", whiteSpace: "nowrap" }}>ESCAPE THE UNIVERSITY!</div>
    </>
  );
};

// ============================================================== maps (the two lobby maps, their ways out)
export const MapsUI: React.FC<{ t: number }> = ({ t }) => {
  if (!inAct(t, ACT.maps)) return null;
  const cards: { plate: string; at: number; title: string; sub: string }[] = [
    { plate: "c_air0", at: b(11, 0), title: "FIRST DAY", sub: "The small school. Learn the ropes." },
    { plate: "c_low1", at: b(11, 1), title: "GRAND CAMPUS", sub: "The Old Quadrangle. Four ways out." },
  ];
  const exits: [string, number, number, number][] = [["MAIN GATE", b(11, 2), 520, 640], ["FENCE HOLE", b(11, 2.25), 1340, 520], ["STORM DRAIN", b(11, 2.5), 700, 860], ["SCAFFOLDING", b(11, 2.75), 1480, 820]];
  const out = expoIn(clamp01((t - b(11, 3.4)) / (b(12) - b(11, 3.4))));
  return (
    <div style={{ position: "absolute", inset: 0, background: C.ink, overflow: "hidden" }}>
      {cards.map((c, ci) => {
        if (t < c.at - 0.02) return null;
        const slices = 5;
        const zoom = lerp(1.08, 1.0, easeOut(prog(t, c.at, BEAT * 2))) * (ci === 1 ? 1 + 0.12 * easeInOut(prog(t, b(11, 2), BEAT * 2)) + out * 2 : 1);
        return (
          <div key={ci} style={{ position: "absolute", inset: 0, scale: `${zoom}`, filter: out && ci === 1 ? `blur(${out * 14}px)` : undefined }}>
            {Array.from({ length: slices }, (_, k) => {
              const s = step(t - (c.at + k * 0.035), { stiffness: 520, damping: 30 });
              const dir = k % 2 ? 1 : -1;
              const w = 1920 / slices;
              return (
                <div key={k} style={{ position: "absolute", left: k * w - 2, top: 0, width: w + 4, height: 1080, overflow: "hidden", translate: `0 ${(1 - s) * 1100 * dir}px` }}>
                  <Plate name={c.plate} style={{ left: -k * w + 2 }} />
                </div>
              );
            })}
          </div>
        );
      })}
      {cards.map((c, ci) => {
        if (t < c.at + 0.05 || (ci === 0 && t >= cards[1].at + 0.1)) return null;
        return (
          <div key={`t${ci}`} style={{ position: "absolute", left: 70, bottom: 70, translate: `${(1 - sp(t, c.at + 0.12, SNAP)) * -1100}px 0`, opacity: 1 - out }}>
            <div style={{ ...font(150, C.gold), ...outline(12), textShadow: "0 12px 0 rgba(0,0,0,.3)" }}>{c.title}</div>
            <div style={{ ...font(46, C.white), ...outline(5), marginTop: 6 }}>{c.sub}</div>
          </div>
        );
      })}
      {exits.map(([label, at, x, y]) => {
        const s = sp(t, at, WOBBLE);
        if (s <= 0.001) return null;
        return (
          <div key={label} style={{ position: "absolute", left: x, top: y, scale: `${s * (1 - out)}`, display: "flex", alignItems: "center", gap: 12, translate: "-50% -50%" }}>
            <svg width={90} height={90} viewBox="-50 -50 100 100"><path d={starPath(44, 19)} fill="#48b06a" stroke={C.ink} strokeWidth={7} strokeLinejoin="round" /></svg>
            <span style={{ ...font(54, C.white), ...outline(6), whiteSpace: "nowrap" }}>{label}</span>
          </div>
        );
      })}
    </div>
  );
};

// ============================================================== escape + final bell
export const EscapeUI: React.FC<{ t: number }> = ({ t }) => {
  if (t < b(12) || t >= b(13, 2)) return null;
  const g = headOf(t, "guard");
  return (
    <>
      {g && t < b(13) ? <Alert t={t} at={b(12, 3)} x={g.x} y={g.y - 10} kind="?" size={150} /> : null}
      {t < b(13) ? <Banner t={t} at={b(12, 2)} out={b(13) - 0.12} color="#48b06a" text="YOU ESCAPED THE UNIVERSITY!" sub="THE WHOLE CLASS ESCAPED!  +50% for everyone" top={560} size={92} /> : null}
    </>
  );
};

export const FinalBellUI: React.FC<{ t: number }> = ({ t }) => {
  if (t < b(13) - 0.05 || t > b(13, 3.3)) return null;
  const s = step(t - b(13), { stiffness: 480, damping: 22 });
  const leave = expoIn(clamp01((t - b(13, 2.5)) / (BEAT * 0.8)));
  const rows = [["YOU", 1250, "ESCAPED in 3:42"], ["PRIYA", 980, "ESCAPED in 4:05"], ["MEERA", 640, "caught twice"], ["ARJUN", 410, "in detention"]] as const;
  const awards: [string, string, number][] = [["BIGGEST SNITCH", "Arjun", b(13, 1)], ["SMOOTH TALKER", "You", b(13, 1.5)], ["MOST BETRAYED", "Meera", b(13, 2)]];
  return (
    <div style={{ position: "absolute", left: "50%", top: "50%", translate: `-50% ${-50 + (1 - s) * 60 - leave * 140}%`, scale: `${lerp(0.6, 1, s) * (1 - leave * 0.3)}`, rotate: `${(1 - s) * -6 + leave * 8}deg`, opacity: 1 - leave }}>
      <div style={{ background: "rgba(20,20,36,0.96)", borderRadius: 44, padding: "44px 60px", width: 1320 }}>
        <div style={{ ...font(120, C.gold), textAlign: "center", ...outline(6) }}>FINAL BELL!</div>
        {rows.map(([n, pts, note], i) => {
          const rs = sp(t, b(13, 0.25) + i * 0.06, SNAP);
          const count = Math.round(pts * easeOut(prog(t, b(13, 0.25) + i * 0.06, 0.5)));
          return (
            <div key={n} style={{ ...font(i === 0 ? 50 : 42, i === 0 ? C.gold : C.white), marginTop: 14, display: "flex", gap: 20, opacity: clamp01(rs * 2), translate: `${(1 - rs) * 120}px 0`, whiteSpace: "nowrap" }}>
              <span style={{ width: 60 }}>{i + 1}.</span><span style={{ width: 200 }}>{n}</span><span style={{ width: 280 }}>{count.toLocaleString("en-US")} pts</span><span style={{ opacity: 0.8 }}>({note})</span>
            </div>
          );
        })}
        <div style={{ display: "flex", gap: 20, marginTop: 28 }}>
          {awards.map(([title, who, at]) => {
            const as = sp(t, at, WOBBLE);
            return (
              <div key={title} style={{ flex: 1, background: "rgba(255,255,255,.07)", borderRadius: 20, padding: "16px 18px", scale: `${Math.max(0, as)}`, opacity: clamp01(as * 3) }}>
                <div style={font(36, "#ff9a7a")}>{title}</div>
                <div style={{ ...font(34, C.white), marginTop: 6 }}>{who}</div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
};

// ============================================================== logo lockup
export const LogoUI: React.FC<{ t: number }> = ({ t }) => {
  if (t < b(14) - 0.3) return null;
  const word = (text: string, at: number, size: number) => {
    const fall = clamp01((t - (at - 0.18)) / 0.18);
    const pre = t < at;
    const [sx, sy] = pre ? [1 - 0.18 * fall, 1 + 0.3 * fall] : squash(t, at, 0.3, 20, 6);
    const y = pre ? -900 * (1 - fall * fall) : 0;
    if (t < at - 0.18) return <div style={{ height: size * 0.95 }} />;
    return (
      <div style={{ ...font(size, C.gold), ...outline(size * 0.075), height: size * 0.95, display: "flex", alignItems: "center", translate: `0 ${y}px`, scale: `${sx} ${sy}`, transformOrigin: "50% 100%", textShadow: `0 ${size * 0.1}px 0 rgba(0,0,0,.45)`, letterSpacing: size * 0.02 }}>{text}</div>
    );
  };
  const glint = prog(t, b(14, 1.5), 0.5);
  const soon = b(15);
  const soonIn = sp(t, soon - 0.2, { stiffness: 500, damping: 18 });
  const press = t >= soon ? Math.max(0, 1 - (t - soon) * 5) * (t < soon + 0.2 ? 1 : 0) : 0;
  const chips = ["1-8 PLAYERS", "PROXIMITY VOICE", "WINDOWS & MAC"];
  return (
    <div style={{ position: "absolute", left: 1010, top: 110, width: 860, display: "grid", justifyItems: "center", scale: `${t > b(14, 2) ? 1 + 0.018 * Math.exp(-(((t - b(14, 2)) % BEAT) * 9)) : 1}` }}>
      <div style={{ position: "relative" }}>
        {word("BUNK", b(14), 250)}
        {word("MASTER", b(14, 0.5), 250)}
        <div style={{ position: "absolute", inset: 0, background: `linear-gradient(105deg, transparent ${glint * 140 - 30}%, rgba(255,255,255,.55) ${glint * 140 - 20}%, transparent ${glint * 140 - 10}%)`, mixBlendMode: "overlay", pointerEvents: "none", opacity: glint > 0 && glint < 1 ? 1 : 0 }} />
      </div>
      <div style={{ marginTop: 20 }}>
        <PopWords t={t} words={[["Sneak", b(14, 2)], ["out", b(14, 2.125)], ["of", b(14, 2.25)], ["class.", b(14, 2.375)], ["Don't", b(14, 2.75)], ["get", b(14, 2.875)], ["caught.", b(14, 3)]]} size={62} color={C.white} stroke={6} />
      </div>
      <div style={{ display: "flex", gap: 14, marginTop: 30 }}>
        {chips.map((c, i) => {
          const s = sp(t, b(14, 3.25) + i * 0.07, SNAP);
          return <span key={c} style={{ ...font(34, C.white), background: C.card, borderRadius: 14, padding: "10px 16px 8px", scale: `${Math.max(0, s)}`, opacity: clamp01(s * 3), whiteSpace: "nowrap" }}>{c}</span>;
        })}
      </div>
      <div style={{ marginTop: 36, scale: `${Math.max(0, soonIn)}`, rotate: `${(1 - Math.min(1, soonIn)) * -10}deg` }}>
        <GameButton label="COMING SOON" color={C.gold} press={t >= soon && t < soon + 0.25 ? 1 - clamp01((t - soon - 0.1) / 0.15) : 0} size={70} />
      </div>
      <div style={{ position: "absolute", left: "50%", top: 780, translate: "-50% 0", width: 700, height: 700, borderRadius: "50%", pointerEvents: "none", opacity: 0, scale: `${press}` }} />
    </div>
  );
};

export { HEAVY, SOFT, POP, backOut, expoOut };
