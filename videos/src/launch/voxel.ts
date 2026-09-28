// Box-for-box port of scenes/player/student_model.gd (build / _build_outfit / _build_bag /
// _build_head / _add_hair) and scripts/palette.gd looks. Same metres, same colours, same pivots,
// so the characters in the film are the game's characters.

export type V3 = [number, number, number];
export type Box = { c: V3; s: V3; col: string };

// Godot Color.darkened / lightened: lerp toward black / white.
const hex2 = (h: string) => {
  const s = h.replace("#", "");
  return [0, 2, 4].map((i) => parseInt(s.slice(i, i + 2), 16) / 255);
};
const rgb2hex = (c: number[]) => "#" + c.map((v) => Math.round(Math.min(1, Math.max(0, v)) * 255).toString(16).padStart(2, "0")).join("");
export const darkened = (h: string, a: number) => rgb2hex(hex2(h).map((v) => v * (1 - a)));
export const lightened = (h: string, a: number) => rgb2hex(hex2(h).map((v) => v + (1 - v) * a));

export const P = {
  SHIRT: "#f4f4f0", TROUSERS: "#2b3a67", SHOES: "#26262e", BELT: "#3a2d26", METAL: "#9aa3ad",
  ID_CARD: "#ffffff", ID_STRAP: "#2f6fd6", WHITE: "#ffffff",
  GRASS: "#8cc45c", GRASS_DARK: "#74b04e", LEAVES: ["#5fae4a", "#4e9a3e", "#86c95a", "#3f8a45"], TRUNK: "#8a5a3a",
  WALL: "#f3e3c3", WALL_SHADE: "#e7d2aa", DADO_INSIDE: "#a9d3a4", DADO_OUTSIDE: "#c8704f", TRIM: "#d9774f",
  BRICK: "#b95c43", BRICK_CAP: "#e2c9a6", FLOOR_A: "#efe4cc", FLOOR_B: "#d9c6a4", ASPHALT: "#4a4d57", LINE: "#f4f1e6",
  WOOD: "#b0703e", WOOD_DARK: "#7a4a2a", METAL_DARK: "#4a4f5a", BOARD: "#2f5d4a", CHALK: "#f3f6ee", PAPER: "#fbf6e8",
  KHAKI: "#b8a06a", KHAKI_DARK: "#8f7a4a", GREY_HAIR: "#b9b6b0", CLASS: ["#e0524f", "#4f86e0", "#48b06a", "#9a62d6"],
};

export type Look = {
  skin: string; hair: string; hair_style?: number; eyes?: string; facial?: number; glasses_style?: number;
  uniform?: "classic" | "blazer" | "sweater" | "sports" | "kurta" | "skirt" | "labcoat";
  shirt?: string; trousers?: string; accent?: string; tie?: string | null; shoes?: string;
  bag?: string | null; bag_style?: number; hat?: number; hat_color?: string; cap?: string | null;
  id_card?: boolean; book?: boolean; height?: number;
};

export type Parts = {
  legL: Box[]; legR: Box[]; torso: Box[]; armL: Box[]; armR: Box[]; head: Box[];
};

export const HIP_HEIGHT = 0.78;
export const PIVOT = {
  hips: [0, HIP_HEIGHT, 0] as V3,
  legL: [-0.1, 0, 0] as V3, legR: [0.1, 0, 0] as V3,
  armL: [-0.3, 0.52, 0] as V3, armR: [0.3, 0.52, 0] as V3,
  head: [0, 0.56, 0] as V3,
};

const b = (list: Box[], c: V3, s: V3, col: string) => list.push({ c, s, col });

export function buildCharacter(look: Look): Parts {
  const skin = look.skin;
  const uniform = look.uniform ?? "classic";
  const shirt = look.shirt ?? P.SHIRT;
  const trousers = look.trousers ?? P.TROUSERS;
  const accent = look.accent ?? trousers;
  const shoes = look.shoes ?? P.SHOES;
  let tie = look.tie ?? null;
  if (uniform === "sports" || uniform === "kurta") tie = null;

  const legs = [[] as Box[], [] as Box[]];
  legs.forEach((v, i) => {
    const right = i === 1;
    if (uniform === "skirt") {
      b(v, [0, -0.2, 0], [0.15, 0.4, 0.17], skin);
      b(v, [0, -0.53, 0], [0.16, 0.3, 0.18], P.WHITE);
    } else {
      b(v, [0, -0.36, 0], [0.17, 0.72, 0.2], trousers);
      if (uniform === "sports") b(v, [0.087 * (right ? 1 : -1), -0.36, 0], [0.01, 0.7, 0.05], P.WHITE);
    }
    b(v, [0, -0.73, -0.035], [0.19, 0.1, 0.29], shoes);
    b(v, [0, -0.77, -0.035], [0.195, 0.025, 0.295], uniform === "sports" ? lightened(shoes, 0.4) : darkened(shoes, 0.3));
  });

  const t: Box[] = [];
  // _build_outfit
  b(t, [0, 0.29, 0], [0.46, 0.56, 0.26], shirt);
  if (uniform !== "kurta") {
    b(t, [0, 0.03, 0], [0.48, 0.07, 0.28], P.BELT);
    b(t, [0, 0.03, -0.142], [0.08, 0.05, 0.01], P.METAL);
  }
  b(t, [-0.07, 0.54, -0.125], [0.1, 0.06, 0.03], darkened(shirt, 0.1));
  b(t, [0.07, 0.54, -0.125], [0.1, 0.06, 0.03], darkened(shirt, 0.1));
  if (tie) {
    b(t, [0, 0.51, -0.14], [0.08, 0.07, 0.03], tie);
    b(t, [0, 0.31, -0.137], [0.07, 0.34, 0.02], tie);
    b(t, [0, 0.2, -0.139], [0.071, 0.04, 0.021], lightened(tie, 0.35));
  } else if (uniform === "classic" || uniform === "labcoat") {
    for (let k = 0; k < 3; k++) b(t, [0, 0.45 - k * 0.13, -0.135], [0.025, 0.025, 0.01], darkened(shirt, 0.3));
  }
  if (uniform === "blazer") {
    for (const side of [-1, 1]) {
      b(t, [side * 0.145, 0.27, -0.005], [0.18, 0.56, 0.28], accent);
      b(t, [side * 0.07, 0.44, -0.145], [0.05, 0.2, 0.012], darkened(accent, 0.2));
    }
    b(t, [0, 0.29, 0.07], [0.48, 0.56, 0.14], accent);
    b(t, [-0.15, 0.36, -0.147], [0.08, 0.05, 0.01], "#ffd24a");
    for (let k = 0; k < 2; k++) b(t, [0.075, 0.14 + k * 0.1, -0.147], [0.025, 0.025, 0.01], "#ffd24a");
  } else if (uniform === "sweater") {
    b(t, [0, 0.25, 0], [0.475, 0.44, 0.27], accent);
    for (const side of [-1, 1]) b(t, [side * 0.09, 0.44, -0.001], [0.12, 0.08, 0.27], accent);
    b(t, [0, 0.05, 0], [0.48, 0.05, 0.275], darkened(accent, 0.2));
  } else if (uniform === "sports") {
    b(t, [0, 0.29, 0], [0.47, 0.57, 0.27], accent);
    b(t, [0, 0.29, -0.137], [0.02, 0.5, 0.01], P.WHITE);
    for (const side of [-1, 1]) b(t, [side * 0.237, 0.29, 0], [0.01, 0.52, 0.06], P.WHITE);
    b(t, [0, 0.56, 0], [0.36, 0.06, 0.28], darkened(accent, 0.15));
  } else if (uniform === "skirt") {
    b(t, [0, -0.12, 0], [0.52, 0.26, 0.32], trousers);
    b(t, [0, -0.26, 0], [0.54, 0.04, 0.33], darkened(trousers, 0.2));
  }
  if (look.id_card ?? true) {
    const front = uniform === "blazer" || uniform === "labcoat" || uniform === "sweater";
    b(t, [0.1, 0.26, front ? -0.152 : -0.14], [0.1, 0.13, 0.012], P.ID_CARD);
    b(t, [0.1, 0.305, front ? -0.16 : -0.147], [0.1, 0.035, 0.005], P.ID_STRAP);
  }
  // _build_bag (backpack)
  if (look.bag) {
    const g = look.bag;
    b(t, [0, 0.3, 0.22], [0.4, 0.46, 0.18], g);
    b(t, [0, 0.22, 0.32], [0.3, 0.2, 0.05], darkened(g, 0.2));
    b(t, [-0.19, 0.36, -0.132], [0.045, 0.36, 0.01], darkened(g, 0.3));
    b(t, [0.19, 0.36, -0.132], [0.045, 0.36, 0.01], darkened(g, 0.3));
  }

  let sleeve = ["blazer", "sports", "labcoat"].includes(uniform) ? accent : shirt;
  if (uniform === "kurta") sleeve = shirt;
  const arms = [[] as Box[], [] as Box[]];
  arms.forEach((a, i) => {
    const right = i === 1;
    const long = ["blazer", "sports", "labcoat", "kurta"].includes(uniform);
    b(a, [0, -0.12, 0], [0.15, 0.26, 0.17], sleeve);
    if (long) {
      b(a, [0, -0.33, 0], [0.14, 0.18, 0.15], sleeve);
      if (uniform === "sports") b(a, [0.075 * (right ? 1 : -1), -0.2, 0], [0.01, 0.38, 0.05], P.WHITE);
    } else b(a, [0, -0.34, 0], [0.12, 0.2, 0.13], skin);
    b(a, [0, -0.47, 0], [0.12, 0.08, 0.13], darkened(skin, 0.08));
    if (!right && look.book) b(a, [0, -0.46, -0.1], [0.05, 0.3, 0.22], "#e0524f");
  });

  const h: Box[] = [];
  const eyes = look.eyes ?? "#1c1c24";
  const hair = look.hair;
  b(h, [0, 0.03, 0], [0.14, 0.07, 0.14], darkened(skin, 0.08));
  b(h, [0, 0.23, 0], [0.36, 0.34, 0.34], skin);
  for (const side of [-1, 1]) {
    b(h, [side * 0.08, 0.24, -0.172], [0.05, 0.07, 0.01], eyes);
    b(h, [side * 0.08 + 0.012, 0.255, -0.1735], [0.015, 0.02, 0.005], P.WHITE);
    b(h, [side * 0.13, 0.17, -0.171], [0.05, 0.03, 0.01], "#ff9a8a");
    b(h, [side * 0.08, 0.3, -0.172], [0.07, 0.02, 0.01], darkened(hair, 0.15));
  }
  b(h, [0, 0.13, -0.172], [0.09, 0.02, 0.01], darkened(skin, 0.35));
  const facial = look.facial ?? 0;
  if (facial >= 1 && facial <= 2) b(h, [0, 0.155, -0.175], [0.16, 0.035, 0.015], darkened(hair, 0.2));
  if (facial === 2) {
    b(h, [0, 0.09, -0.16], [0.3, 0.12, 0.05], darkened(hair, 0.15));
    for (const side of [-1, 1]) b(h, [side * 0.172, 0.16, -0.06], [0.03, 0.18, 0.16], darkened(hair, 0.15));
  }
  const glasses = look.glasses_style ?? 0;
  if (glasses > 0) {
    const frame = glasses !== 1 ? "#22232b" : "#5a3a22";
    const lens = glasses !== 3 ? "#bfe8ff" : "#1c1c24";
    const gw = glasses === 1 ? 0.11 : 0.13;
    for (const side of [-1, 1]) {
      b(h, [side * 0.08, 0.24, -0.18], [gw, glasses !== 2 ? 0.1 : 0.085, 0.012], frame);
      b(h, [side * 0.08, 0.24, -0.186], [gw - 0.035, glasses !== 2 ? 0.065 : 0.05, 0.004], lens);
    }
    b(h, [0, 0.25, -0.18], [0.05, 0.015, 0.012], frame);
  }
  addHair(h, hair, look.hair_style ?? 0);
  let hat = look.hat ?? 0;
  let hatColor = look.hat_color ?? "#e0524f";
  if (look.cap) {
    hat = 1;
    hatColor = look.cap;
  }
  if (hat === 1) {
    b(h, [0, 0.45, 0], [0.4, 0.1, 0.38], hatColor);
    b(h, [0, 0.41, -0.24], [0.36, 0.03, 0.14], darkened(hatColor, 0.2));
    b(h, [0, 0.45, -0.195], [0.08, 0.06, 0.01], "#ffd24a");
  }
  return { legL: legs[0], legR: legs[1], torso: t, armL: arms[0], armR: arms[1], head: h };
}

function addHair(h: Box[], c: string, style: number) {
  b(h, [0, 0.42, 0.01], [0.38, 0.08, 0.37], c);
  b(h, [0, 0.29, 0.155], [0.38, 0.22, 0.07], c);
  b(h, [-0.185, 0.32, 0.04], [0.03, 0.14, 0.28], c);
  b(h, [0.185, 0.32, 0.04], [0.03, 0.14, 0.28], c);
  if (style === 0) b(h, [-0.07, 0.37, -0.175], [0.24, 0.07, 0.04], c);
  else if (style === 1) {
    b(h, [0, 0.16, 0.16], [0.38, 0.34, 0.07], c);
    b(h, [-0.19, 0.2, 0.03], [0.04, 0.3, 0.3], c);
    b(h, [0.19, 0.2, 0.03], [0.04, 0.3, 0.3], c);
    b(h, [0, 0.38, -0.175], [0.36, 0.05, 0.04], c);
  } else if (style === 2) {
    for (let i = 0; i < 4; i++) b(h, [-0.13 + i * 0.087, 0.49, -0.05 + (i % 2) * 0.1], [0.07, 0.08, 0.07], c);
  } else if (style === 3) {
    b(h, [0, 0.36, 0.22], [0.12, 0.12, 0.08], c);
    b(h, [0, 0.2, 0.25], [0.08, 0.22, 0.06], c);
    b(h, [0, 0.38, -0.175], [0.36, 0.05, 0.04], c);
  } else if (style === 5) {
    b(h, [0, 0.52, 0.05], [0.16, 0.12, 0.16], c);
    b(h, [0, 0.38, -0.175], [0.36, 0.05, 0.04], c);
  } else if (style === 6) {
    for (let i = 0; i < 3; i++)
      for (let j = 0; j < 3; j++) b(h, [-0.13 + i * 0.13, 0.47 + ((i + j) % 2) * 0.03, -0.12 + j * 0.13], [0.14, 0.1, 0.14], c);
    b(h, [0, 0.36, -0.17], [0.38, 0.08, 0.05], c);
  }
}

// ---- The cast (looks built with palette.gd's own rules) ----
export const CAST: Record<string, Look> = {
  // The hero from art/icon.png: buzz cut, classic uniform, ID card, red backpack.
  hero: { skin: "#c68a5c", hair: "#1f1a17", hair_style: 4, bag: "#e0524f", tie: null },
  friendA: { skin: "#f2c9a0", hair: "#5a3a22", hair_style: 3, uniform: "skirt", bag: "#f2a93b", tie: "#4f86e0" },
  friendB: { skin: "#8a5a36", hair: "#1f1a17", hair_style: 2, uniform: "sports", accent: "#24315e", trousers: "#24315e", bag: "#3aa4a0" },
  friendC: { skin: "#e0ac7e", hair: "#8a4b2a", hair_style: 6, glasses_style: 1, uniform: "sweater", accent: "#8a2a3a", bag: "#5b6bd6", tie: "#48b06a" },
  // make_teacher_look: grey hair, glasses, moustache, teacher shirt, tie, book, no ID card.
  teacher: { skin: "#d09a6a", hair: "#b9b6b0", hair_style: 1, glasses_style: 1, facial: 0, shirt: "#9fc6ea", trousers: "#5a5f6e", tie: "#24315e", bag: null, id_card: false, book: true },
  // make_guard_look(7, true)
  guard: { skin: "#a86e45", hair: "#3b2618", hair_style: 4, facial: 1, shirt: "#b8a06a", trousers: "#8f7a4a", tie: null, bag: null, id_card: false, cap: "#24315e" },
  // Proctor: _staff_look(888) with shirt #4f7fd9.
  proctor: { skin: "#f2c9a0", hair: "#3b2618", hair_style: 4, glasses_style: 2, facial: 1, shirt: "#4f7fd9", trousers: "#3a3d47", tie: "#24315e", bag: null, id_card: false },
  npc1: { skin: "#f6d5b5", hair: "#3b2618", hair_style: 1, tie: "#e0524f", bag: "#5b6bd6" },
  npc2: { skin: "#a86e45", hair: "#1f1a17", hair_style: 0, tie: "#e0524f", bag: "#333845" },
  npc3: { skin: "#e0ac7e", hair: "#c9a25a", hair_style: 5, uniform: "skirt", tie: "#e0524f", bag: "#d65ba0" },
  npc4: { skin: "#6b4028", hair: "#1f1a17", hair_style: 6, tie: "#e0524f", bag: "#f2a93b" },
};

// Pose: joint rotations (radians, Godot XYZ euler) plus hip height.
export type Pose = {
  hipY: number; legL: number; legR: number; torsoX: number; armLX: number; armRX: number;
  armLZ: number; armRZ: number; headX: number; headY: number;
};
export const REST: Pose = { hipY: HIP_HEIGHT, legL: 0, legR: 0, torsoX: 0, armLX: 0, armRX: 0, armLZ: -0.06, armRZ: 0.06, headX: 0, headY: 0 };

/** student_model.gd animate(): walk/run at `phase`, amount 0..1, crouch 0..1, sit 0..1. */
export function walkPose(phase: number, amount: number, crouch = 0, sprint = false): Pose {
  const swing = Math.sin(phase) * amount * 0.8;
  const crouchLeg = crouch * 1.1;
  const torso = sprint || crouch > 0.01 ? -0.08 * amount * (1 - crouch) + -0.35 * crouch : 0;
  return {
    hipY: HIP_HEIGHT + (0.46 - HIP_HEIGHT) * crouch + Math.abs(Math.cos(phase)) * amount * 0.04,
    legL: swing + crouchLeg, legR: -swing + crouchLeg, torsoX: torso,
    armLX: -swing * 0.9 + crouch * 0.4, armRX: swing * 0.9 + crouch * 0.4,
    armLZ: -0.06, armRZ: 0.06, headX: -torso, headY: 0,
  };
}

export function sitPose(s: number): Pose {
  return {
    hipY: HIP_HEIGHT + (0.5 - HIP_HEIGHT) * s, legL: 1.45 * s, legR: 1.45 * s, torsoX: -0.4 * Math.sin(s * Math.PI),
    armLX: 0.5 * s, armRX: 0.5 * s, armLZ: -0.06, armRZ: 0.06, headX: 0, headY: 0,
  };
}

export const mixPose = (a: Pose, c: Pose, u: number): Pose => {
  const o = { ...a };
  for (const k of Object.keys(a) as (keyof Pose)[]) o[k] = a[k] + (c[k] - a[k]) * u;
  return o;
};
