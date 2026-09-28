// Chaos act 2D pieces: titles on flat fields, the style combo stack, the surprise test papers,
// the merit badge, Pappu Uncle's canteen and the quest chain. All pure functions of t.
import React from "react";
import { step } from "../../kit/spring";
import { b, BEAT } from "../cues";
import { Burst, Rays, Shockwave, slam } from "../../film/fxui";
import { clamp01, easeIn, easeInOut, easeOut, expoIn, lerp, rand, SNAP, sp, squash, WOBBLE } from "../../launch/juice";
import { badgeSvg, ITEM_SVG } from "../../launch/icons";
import { C } from "../../launch/tokens";
import { font, GameButton, Icon, outline } from "../../launch/ui";

export const FIELD = { red: "#e0524f", yellow: "#ffd24a", purple: "#b07cff", green: "#7fe0a0", orange: "#ff9a3c", ink: "#2a1a0e", sky: "#8dd0ef" };
export const GAME_COLS = [C.gold, "#e0524f", "#4f86e0", "#48b06a", "#b07cff", "#ff9a3c", "#ffffff"];

/** A flat colour field with trailer 1's drifting diagonal ink stripes. */
export const Field: React.FC<{ t: number; color: string; stripes?: number; style?: React.CSSProperties; children?: React.ReactNode }> = ({ t, color, stripes = 0.12, style, children }) => (
  <div style={{ position: "absolute", inset: 0, background: color, overflow: "hidden", ...style }}>
    <svg width={1920} height={1080} style={{ position: "absolute", inset: 0, opacity: stripes }}>
      {Array.from({ length: 26 }, (_, i) => (
        <rect key={i} x={-700 + i * 160 + ((t * 260) % 160)} y={-300} width={62} height={1700} fill={C.ink} transform="rotate(20 960 540)" />
      ))}
    </svg>
    {children}
  </div>
);

/** One slammed title word (trailer 1): from 2.4x with overshoot, a tilt that settles, squash on landing. */
export const Slam: React.FC<{ t: number; at: number; text: string; size: number; color?: string; tilt?: number; stroke?: number; from?: number }> = ({ t, at, text, size, color = C.gold, tilt = -6, stroke, from = 2.5 }) => {
  if (t < at) return <div style={{ height: size * 0.9 }} />;
  const s = slam(t, at, from, 0.24);
  const [sx, sy] = squash(t, at + 0.08, 0.14, 26, 10);
  return (
    <div style={{
      ...font(size, color), ...outline(stroke ?? size * 0.055), height: size * 0.9, display: "flex", alignItems: "center", whiteSpace: "nowrap",
      scale: `${s * sx} ${s * sy}`, rotate: `${tilt * (s - 1) * 1.4 + tilt * 0.25}deg`, textShadow: `0 ${size * 0.075}px 0 rgba(0,0,0,.35)`, letterSpacing: size * 0.015,
    }}>{text}</div>
  );
};

// ================================================================== style combos (hud.gd _pop_style)
// A receipt, centre-right: one "TITLE +points" row per beat (they stay put, reading order top to bottom),
// a rule, and the running total underneath that bumps with every row and bursts on the last.
const COMBOS = [
  { title: "CLOSE CALL", pts: 50, at: b(10, 3), color: "#ffffff" },
  { title: "SILENT", pts: 30, at: b(11, 0), color: "#ffd24a" },
  { title: "SHOOK THEM OFF", pts: 60, at: b(11, 2), color: "#ff9a3c" },
];
const ROW_Y = [300, 424, 548];
const ROW_SIZE = 104;
const TOTAL_Y = 690;
export const COMBO_OUT = b(11, 3.6);

export const Combos: React.FC<{ t: number }> = ({ t }) => {
  if (t < COMBOS[0].at - 0.01 || t > b(12)) return null;
  const out = expoIn(clamp01((t - COMBO_OUT) / (BEAT * 0.4)));
  const last = COMBOS[COMBOS.length - 1].at;
  let total = 0, bump = 0;
  COMBOS.forEach((c) => {
    if (t >= c.at) {
      total += c.pts * easeOut(clamp01((t - c.at) / 0.14));
      bump += 0.16 * Math.exp(-(t - c.at) * 9) * Math.cos((t - c.at) * 28);
    }
  });
  const ruleIn = easeOut(clamp01((t - COMBOS[0].at) / 0.2));
  return (
    <>
      <div style={{ position: "absolute", left: 0, top: 0, width: 1920, height: 1080, translate: `${out * 1300}px 0`, filter: out > 0.02 ? `blur(${out * 10}px)` : undefined }}>
        {COMBOS.map((c, i) => {
          if (t < c.at) return null;
          const s = slam(t, c.at, 1.5, 0.22);
          const inX = (1 - easeOut(clamp01((t - c.at) / 0.12))) * 260;
          return (
            <div key={i} style={{ position: "absolute", right: 90, top: ROW_Y[i], translate: `${inX}px 0`, scale: `${s}`, transformOrigin: "100% 60%", rotate: `${(s - 1) * -12 - 2}deg`, whiteSpace: "nowrap" }}>
              <span style={{ ...font(ROW_SIZE, c.color), ...outline(7, "#000"), textShadow: "0 8px 0 rgba(0,0,0,.35)" }}>{c.title}&nbsp;&nbsp;+{c.pts}</span>
            </div>
          );
        })}
        <div style={{ position: "absolute", right: 90, top: TOTAL_Y - 22, width: 700 * ruleIn, height: 12, borderRadius: 6, background: C.gold, boxShadow: "0 5px 0 rgba(0,0,0,.35)", outline: `4px solid ${C.ink}` }} />
        <div style={{ position: "absolute", right: 90, top: TOTAL_Y, scale: `${1 + bump}`, transformOrigin: "100% 50%", rotate: "-3deg", opacity: clamp01(ruleIn * 3), whiteSpace: "nowrap" }}>
          <span style={{ ...font(200, C.gold), ...outline(12, C.ink), textShadow: "0 14px 0 rgba(0,0,0,.35)" }}>+{Math.round(total)}</span>
        </div>
      </div>
      <Burst t={t} at={last} x={1600} y={TOTAL_Y + 100} colors={GAME_COLS} seed={31} power={1600} size={24} n={26} />
      <Shockwave t={t} at={last} x={1600} y={TOTAL_Y + 100} color="#ffd24a" r={800} width={40} dur={0.45} />
    </>
  );
};

// ================================================================== interact prompt + item pop
export const Prompt: React.FC<{ t: number; at: number; until: number; x: number; y: number }> = ({ t, at, until, x, y }) => {
  if (t < at - 0.02 || t > until + 0.3) return null;
  const s = sp(t, at, { stiffness: 620, damping: 20 });
  const leave = easeIn(clamp01((t - until) / 0.16));
  const words: [string, number][] = [["Take", 0.05], ["the", 0.09], ["fire", 0.13], ["extinguisher", 0.17]];
  return (
    <div style={{ position: "absolute", left: x, top: y, translate: "-50% -50%", display: "flex", alignItems: "center", gap: 20, scale: `${Math.max(0, s) * (1 - leave * 0.4)}`, opacity: 1 - leave, whiteSpace: "nowrap" }}>
      <span style={{ ...font(80, C.ink), background: C.gold, borderRadius: 16, padding: "8px 22px 4px", boxShadow: `0 8px 0 #a86e08`, scale: `${t > at + 0.3 && t < until ? 1 - 0.1 * Math.exp(-(t - until + 0.08) * 20) : 1}` }}>E</span>
      {words.map(([w, d], i) => {
        const ws = sp(t, at + d, SNAP);
        return <span key={i} style={{ ...font(88, C.white), ...outline(7, "#000"), display: "inline-block", opacity: clamp01(ws * 3), translate: `0 ${(1 - ws) * 40}px` }}>{w}</span>;
      })}
    </div>
  );
};

// ================================================================== surprise test (exam_game.gd)
// One paper at a time, big and centred: it slams in on a beat, its mini-game resolves, the result holds,
// then it swipes off before the next one lands.
const PAPER_W = 1600, PAPER_H = 900;
const PAPERS = [
  { at: b(12, 1), out: b(12, 3.5), side: -1 },
  { at: b(13, 0), out: b(13, 1.5), side: 1 },
  { at: b(13, 2), out: b(14) + 1, side: -1 },
];
export const REACTOR_STOP = b(12, 2);
export const SUMS_PRESS = b(13, 0.5);
export const SORT_CLICKS = Array.from({ length: 6 }, (_, k) => b(13, 2.25 + k * 0.125)); // 32nds
export const SORTED = b(13, 3);

const PaperHead: React.FC<{ subject: string; variant: string; secs: number }> = ({ subject, variant, secs }) => (
  <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
    <span style={font(72, C.paperTitle)}>{subject}&nbsp;&nbsp;·&nbsp;&nbsp;{variant}</span>
    <span style={{ ...font(64, C.paperInk), background: "rgba(138,90,58,.14)", borderRadius: 14, padding: "6px 18px 2px" }}>{secs}s</span>
  </div>
);

const Reactor: React.FC<{ t: number; at: number }> = ({ t, at }) => {
  const stop = REACTOR_STOP;
  const settle = step(t - stop, { stiffness: 320, damping: 10 });
  const ph = (x: number) => 0.5 + 0.42 * Math.sin((x - at) * 9 + 1.2);
  const needle = t < stop ? ph(t) : lerp(ph(stop), 0.56, settle);
  const gs = sp(t, stop + 0.04, WOBBLE);
  return (
    <>
      <PaperHead subject="THERMODYNAMICS" variant="REACTOR CONTROL" secs={Math.max(0, 12 - Math.floor((t - at) * 3))} />
      <div style={{ ...font(56, C.paperInk), marginTop: 30 }}>Keep the needle in the green zone.</div>
      <div style={{ position: "relative", marginTop: 130, height: 110, background: "#3a3d47", borderRadius: 55 }}>
        <div style={{ position: "absolute", left: "44%", width: "24%", top: 0, bottom: 0, background: "#48b06a" }} />
        <div style={{ position: "absolute", left: "53%", width: "6%", top: 0, bottom: 0, background: "#7fe0a0" }} />
        <div style={{ position: "absolute", left: `${needle * 100}%`, top: -70, width: 30, height: 250, background: "#e0524f", borderRadius: 15, translate: "-50% 0", boxShadow: "0 8px 0 rgba(0,0,0,.25)", rotate: `${t < stop ? Math.cos((t - at) * 9 + 1.2) * 8 : 0}deg` }} />
      </div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginTop: 90 }}>
        <span style={font(72, "#4f86e0")}>COLD</span>
        <span style={{ ...font(170, "#48b06a"), ...outline(9, C.ink), opacity: t > stop ? 1 : 0, scale: `${Math.max(0, gs)}`, rotate: `${(1 - Math.min(1, gs)) * -20 - 3}deg`, display: "inline-block", textShadow: "0 12px 0 rgba(0,0,0,.25)" }}>STABLE!</span>
        <span style={font(72, "#e0524f")}>HOT</span>
      </div>
    </>
  );
};

const Sums: React.FC<{ t: number; at: number }> = ({ t, at }) => {
  const press = SUMS_PRESS;
  const right = t > press;
  const ps = sp(t, press, WOBBLE);
  return (
    <>
      <PaperHead subject="ENGINEERING MATHS" variant="QUICK SUMS" secs={Math.max(0, 9 - Math.floor((t - at) * 3))} />
      <div style={{ ...font(320, C.ink), textAlign: "center", marginTop: 20, display: "flex", justifyContent: "center", gap: 50 }}>
        <span>7 × 8 =</span>
        <span style={{ display: "inline-block", minWidth: 280, color: right ? "#48b06a" : C.ink, scale: `${right ? Math.max(0, ps) : 1}` }}>{right ? "56" : "?"}</span>
      </div>
      <div style={{ display: "flex", gap: 80, justifyContent: "center", marginTop: 30 }}>
        {["54", "56", "63"].map((n, i) => {
          const hot = n === "56" && right;
          const push = hot ? Math.exp(-(t - press) * 14) : 0;
          const s = sp(t, at + 0.06 + i * 0.05, WOBBLE);
          return <div key={n} style={{ scale: `${Math.max(0, s)}` }}><GameButton label={n} color={hot ? C.good : C.gold} press={push} size={110} /></div>;
        })}
      </div>
    </>
  );
};

const SORT = [42, 7, 88, 19, 63, 3];
const Sort: React.FC<{ t: number; at: number }> = ({ t, at }) => {
  const order = [...SORT].sort((x, y) => x - y);
  const ds = sp(t, SORTED, WOBBLE);
  return (
    <>
      <PaperHead subject="DATA STRUCTURES" variant="SORT IT OUT" secs={Math.max(0, 10 - Math.floor((t - at) * 3))} />
      <div style={{ ...font(56, C.paperInk), marginTop: 26, height: 60 }}>Click the numbers from SMALLEST to LARGEST.</div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 360px)", gap: "50px 70px", justifyContent: "center", marginTop: 50 }}>
        {SORT.map((n, i) => {
          const c = SORT_CLICKS[order.indexOf(n)];
          const hit = t >= c;
          const k = hit ? Math.exp(-(t - c) * 16) : 0;
          const s = sp(t, at + 0.05 + i * 0.035, WOBBLE);
          return (
            <div key={n} style={{ position: "relative", display: "grid", justifyItems: "center", scale: `${Math.max(0, s)}` }}>
              <GameButton label={String(n)} color={hit ? "#c9c2b0" : C.gold} press={hit ? 1 - 0.5 * (1 - k) : 0} size={120} style={{ opacity: hit ? 0.7 : 1 }} />
              {hit ? (
                <div style={{ position: "absolute", right: 30, top: -20, ...font(56, C.white), background: "#48b06a", borderRadius: 40, width: 76, height: 76, display: "grid", placeItems: "center", scale: `${sp(t, c, WOBBLE)}` }}>{order.indexOf(n) + 1}</div>
              ) : null}
            </div>
          );
        })}
      </div>
      {t >= SORTED ? (
        <div style={{ position: "absolute", left: "50%", top: 300, translate: "-50% 0", scale: `${Math.max(0, ds)}`, rotate: `${(1 - Math.min(1, ds)) * 30 - 8}deg`, ...font(260, "#48b06a"), ...outline(14, C.ink), textShadow: "0 16px 0 rgba(0,0,0,.3)", whiteSpace: "nowrap" }}>Sorted!</div>
      ) : null}
    </>
  );
};

export const Tests: React.FC<{ t: number }> = ({ t }) => {
  if (t < b(12) || t >= b(14)) return null;
  const titleOut = expoIn(clamp01((t - (b(12, 1) - 0.12)) / 0.14));
  return (
    <Field t={t} color={FIELD.yellow}>
      <Burst t={t} at={b(12)} x={960} y={420} colors={GAME_COLS} seed={5} power={1400} size={22} n={18} />
      <Burst t={t} at={b(12, 0.5)} x={960} y={660} colors={GAME_COLS} seed={8} power={1200} size={20} n={14} />
      {titleOut < 1 ? (
        <div style={{ position: "absolute", inset: 0, display: "grid", placeContent: "center", justifyItems: "center", translate: `0 ${-titleOut * 1100}px` }}>
          <Slam t={t} at={b(12)} text="SURPRISE" size={230} color={C.white} tilt={-5} />
          <Slam t={t} at={b(12, 0.5)} text="TEST!" size={260} color={C.gold} tilt={6} from={1.7} />
        </div>
      ) : null}
      {PAPERS.map((p, i) => {
        if (t < p.at - 0.12 || t > p.out + 0.3) return null;
        const s = step(t - (p.at - 0.12), { stiffness: 560, damping: 24 });
        const leave = expoIn(clamp01((t - p.out) / 0.22));
        const [sx, sy] = squash(t, p.at + 0.02, 0.06, 26, 12);
        const rest = [-2, 1.6, -1.2][i];
        return (
          <div key={i} style={{
            position: "absolute", left: 960, top: 560, width: PAPER_W, height: PAPER_H, marginLeft: -PAPER_W / 2, marginTop: -PAPER_H / 2,
            translate: `${(1 - s) * p.side * 1700 - leave * p.side * 2100}px ${(1 - s) * 260 + leave * 120}px`,
            rotate: `${lerp(p.side * 28, rest, s) - leave * p.side * 20}deg`, scale: `${sx} ${sy}`,
          }}>
            <div style={{ position: "absolute", inset: 0, background: C.paper, border: `16px solid ${C.paperEdge}`, borderRadius: 34, padding: "44px 60px", boxSizing: "border-box", boxShadow: "0 30px 0 rgba(42,26,14,.28)" }}>
              {i === 0 ? <Reactor t={t} at={p.at} /> : i === 1 ? <Sums t={t} at={p.at} /> : <Sort t={t} at={p.at} />}
            </div>
          </div>
        );
      })}
    </Field>
  );
};

// ================================================================== Pappu Uncle's canteen (hud.gd shop, director.gd SHOP)
// Bar 14: the title lands on the downbeat, then one item per beat (trailer 1's canteen build).
// Bar 15: buys on beats (BOUGHT!, pocket money rolls), the samosa ticks the quest, the chain completes
// with the merit badge (director.gd fires the "badge" effect on QUEST CHAIN DONE) and holds.
const SHOP = [
  { icon: "samosa", name: "Samosa", price: 10, drop: b(14, 1), buy: b(15, 0) },
  { icon: "hall_pass", name: "Hall Pass", price: 40, drop: b(14, 2), buy: b(15, 2) },
  { icon: "medical_note", name: "Medical Note", price: 70, drop: b(14, 3), buy: b(15, 3) },
] as const;
const START = 120;
const CREAM = "#fbf1dc", CANTEEN_RED = "#c4492f";
export const QUEST_IN = b(15, 0), QUEST_TICK = b(15, 0.5), CHAIN_DONE = b(15, 1);
export const CANTEEN_OUT = b(15, 3.5);

export const Canteen: React.FC<{ t: number }> = ({ t }) => {
  const at = b(14);
  if (t < at - 0.1 || t >= b(16)) return null;
  const enter = step(t - (at - 0.1), { stiffness: 520, damping: 26 });
  const title = slam(t, at, 2.0, 0.26);
  let cash = START;
  SHOP.forEach((it) => (cash -= it.price * easeInOut(clamp01((t - it.buy) / (BEAT * 0.3)))));
  const lastBuy = SHOP.reduce((acc, it) => (t >= it.buy ? it.buy : acc), -1);
  const cashKick = lastBuy > 0 ? Math.exp(-(t - lastBuy) * 8) : 0;
  const broke = t >= SHOP[2].buy + BEAT * 0.3;
  return (
    <div style={{ position: "absolute", inset: 0, background: CREAM, translate: `0 ${(1 - enter) * -1150}px`, overflow: "hidden" }}>
      <svg width={1920} height={1080} style={{ position: "absolute", inset: 0, opacity: 0.08 }}>
        {Array.from({ length: 30 }, (_, i) => <circle key={i} cx={(i * 263) % 1920} cy={((i * 181 + t * 90) % 1180) - 50} r={28} fill={CANTEEN_RED} />)}
      </svg>
      <div style={{ position: "absolute", inset: 30, border: `16px solid ${CANTEEN_RED}`, borderRadius: 48 }} />
      <div style={{ position: "absolute", left: 0, right: 0, top: 58, display: "flex", justifyContent: "center", scale: `${title}`, opacity: t >= at ? 1 : 0 }}>
        <div style={{ ...font(160, CANTEEN_RED), ...outline(8, C.ink), textShadow: "0 10px 0 rgba(42,26,14,.25)", whiteSpace: "nowrap" }}>PAPPU UNCLE'S CANTEEN</div>
      </div>
      <div style={{ position: "absolute", left: 0, right: 0, top: 226, display: "flex", justifyContent: "center", alignItems: "baseline", gap: 20, ...font(80, C.ink), whiteSpace: "nowrap", opacity: clamp01((t - at - 0.08) / 0.1) }}>
        Pocket money:
        <span style={{ display: "inline-block", minWidth: 220, color: broke ? "#e0524f" : C.ink, scale: `${1 + 0.4 * cashKick}`, rotate: `${cashKick * 8 * Math.sin((t - lastBuy) * 40)}deg`, transformOrigin: "20% 70%" }}>Rs {Math.round(cash)}</span>
      </div>
      {SHOP.map((it, i) => {
        const x = 370 + i * 590;
        if (t < it.drop) return null;
        // Drops into its slot from just above (short fall, no crossing the text above), squash on landing.
        const fall = clamp01((t - it.drop) / 0.1);
        const land = it.drop + 0.1;
        const [sx, sy] = t < land ? [0.85, 1.2] : squash(t, land, 0.3, 20, 8);
        const y = t < land ? -60 * (1 - fall * fall) : 0;
        const bought = t >= it.buy;
        const push = bought ? Math.exp(-(t - it.buy) * 12) : 0;
        const hop = bought ? Math.max(0, Math.sin(Math.min(Math.PI, (t - it.buy) * 10))) * 50 : 0;
        const label = sp(t, it.drop + 0.08, SNAP);
        const stamp = bought ? slam(t, it.buy, 1.8, 0.2) : 1;
        return (
          <React.Fragment key={it.name}>
            <div style={{ position: "absolute", left: x, top: 318, width: 520, marginLeft: -260, display: "grid", justifyItems: "center" }}>
              <div style={{ translate: `0 ${y - hop}px`, scale: `${sx} ${sy}`, transformOrigin: "50% 100%", opacity: clamp01(fall * 4) }}>
                <Icon svg={ITEM_SVG[it.icon]} size={290} />
              </div>
              <div style={{ ...font(68, C.ink), marginTop: -12, whiteSpace: "nowrap", opacity: clamp01(label * 3), translate: `0 ${(1 - Math.min(1, label)) * 30}px` }}>{it.name}</div>
              <div style={{ marginTop: 14, scale: `${clamp01(label) * stamp}`, rotate: bought ? `${-4 + (stamp - 1) * -20}deg` : "0deg" }}>
                <GameButton label={bought ? "BOUGHT!" : `Rs ${it.price}`} color={bought ? C.good : C.gold} press={push} size={58} />
              </div>
            </div>
            <Burst t={t} at={it.drop + 0.1} x={x} y={600} colors={[C.gold, "#ffd24a", "#ffffff", CANTEEN_RED]} seed={50 + i} power={700} size={14} n={10} />
            <Burst t={t} at={it.buy} x={x} y={760} colors={[C.gold, "#ffd24a", "#ffffff", C.good]} seed={60 + i} power={900} size={16} n={14} />
          </React.Fragment>
        );
      })}
      <QuestChain t={t} />
    </div>
  );
};

// director.gd QUESTS: the chain's last quest ticks the moment the samosa is bought; the chain completes
// ("QUEST CHAIN DONE! +200", Rules.CHAIN_BONUS) with the merit badge, and holds.
const QUEST = "Eat a samosa from the canteen";
const QuestChain: React.FC<{ t: number }> = ({ t }) => {
  if (t < QUEST_IN - 0.05) return null;
  const s = sp(t, QUEST_IN, { stiffness: 420, damping: 24 });
  const done = t >= QUEST_TICK;
  const k = done ? sp(t, QUEST_TICK, WOBBLE) : 0;
  const chain = t >= CHAIN_DONE;
  const cs = slam(t, CHAIN_DONE, 1.6, 0.22);
  const bs = sp(t, CHAIN_DONE, WOBBLE);
  return (
    <div style={{ position: "absolute", left: "50%", bottom: 58, translate: `-50% ${(1 - s) * 400}px` }}>
      <div style={{ position: "relative", background: "rgba(20,20,36,0.94)", borderRadius: 30, padding: "18px 44px 20px 230px", width: 1400, boxSizing: "border-box", whiteSpace: "nowrap" }}>
        <div style={{ position: "absolute", left: 20, top: "50%", translate: `0 -50%`, scale: `${Math.max(0, bs)}`, rotate: `${(1 - Math.min(1, bs)) * -120}deg`, opacity: chain ? 1 : 0 }}>
          <Icon svg={badgeSvg(2)} size={190} />
        </div>
        <div style={{ ...font(chain ? 78 : 56, chain ? C.gold : "rgba(255,255,255,.75)"), ...(chain ? outline(4, C.ink) : {}), scale: `${chain ? cs : 1}`, transformOrigin: "0 60%", height: 78, display: "flex", alignItems: "center" }}>
          {chain ? "QUEST CHAIN DONE!  +200" : "QUEST CHAIN  2/3"}
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 18, marginTop: 10 }}>
          <span style={{ display: "inline-grid", placeItems: "center", width: 60, height: 60, borderRadius: 12, background: done ? C.good : "rgba(255,255,255,.14)", border: done ? undefined : `4px solid ${C.warn}`, boxSizing: "border-box", ...font(50, C.ink) }}>
            <span style={{ display: "inline-block", scale: `${Math.max(0, k)}` }}>{done ? "✓" : ""}</span>
          </span>
          <span style={{ ...font(56, done ? C.good : C.warn) }}>{QUEST}</span>
        </div>
      </div>
    </div>
  );
};

export { rand };
