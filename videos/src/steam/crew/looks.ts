// The eight friends in the lobby lineup. Four from launch/voxel.ts CAST, four new ones built with
// scripts/palette.gd's own options (SKIN, HAIR, UNIFORMS, BAGS, hair styles 0-7, hats, bag styles),
// so between them they wear every uniform the character creator offers.
// buildCharacter (launch/voxel.ts) has no mohawk (style 7), beanie / headband (hat 2 / 3) or sling bag
// (bag_style 1): those are patched in here box-for-box from scenes/player/student_model.gd.
import { buildCharacter, CAST, darkened, type Box, type Look, type Parts, type V3 } from "../../launch/voxel";

export type CrewLook = Look & { mohawk?: boolean; hat2?: 2 | 3; sling?: boolean };

const add = (list: Box[], c: V3, s: V3, col: string) => list.push({ c, s, col });

export function crewParts(look: CrewLook): Parts {
  const base: Look = { ...look, hair_style: look.mohawk ? 4 : look.hair_style, bag: look.sling ? null : look.bag, hat: look.hat2 ? 0 : look.hat };
  const p = buildCharacter(base);
  const head = [...p.head];
  const torso = [...p.torso];
  if (look.mohawk) {
    // student_model.gd _add_hair style 7: shaved sides, tall strip. Drop the base cap boxes first.
    const baseCap = (bx: Box) => bx.col === look.hair && ((bx.c[1] === 0.42 && bx.s[1] === 0.08) || bx.c[1] === 0.29 || bx.c[1] === 0.32);
    for (let i = head.length - 1; i >= 0; i--) if (baseCap(head[i])) head.splice(i, 1);
    for (let k = 0; k < 4; k++) add(head, [0, 0.46 + (k % 2) * 0.03, -0.12 + k * 0.09], [0.07, 0.12, 0.09], look.hair);
    add(head, [0, 0.42, 0.01], [0.37, 0.02, 0.35], darkened(look.hair, 0.1));
  }
  const hc = look.hat_color ?? "#e0524f";
  if (look.hat2 === 2) {
    add(head, [0, 0.45, 0], [0.4, 0.14, 0.38], hc);
    add(head, [0, 0.38, 0], [0.405, 0.05, 0.385], darkened(hc, 0.2));
    add(head, [0, 0.55, 0], [0.1, 0.06, 0.1], "#ffffff");
  } else if (look.hat2 === 3) add(head, [0, 0.37, 0], [0.385, 0.045, 0.365], hc);
  if (look.sling && look.bag) {
    const g = look.bag;
    add(torso, [0.26, 0.05, 0.02], [0.1, 0.24, 0.3], g);
    for (let k = 0; k < 5; k++) {
      add(torso, [0.16 - k * 0.075, 0.1 + k * 0.1, -0.145], [0.06, 0.07, 0.01], darkened(g, 0.3));
      add(torso, [-0.16 + k * 0.075, 0.1 + k * 0.1, 0.145], [0.06, 0.07, 0.01], darkened(g, 0.3));
    }
  }
  return { ...p, head, torso };
}

export type Friend = { name: string; look: CrewLook; cls: number };

// Left to right on screen. Classes: palette CLASS_COLORS / network CLASSROOMS (Class A, B, C, Lab).
export const FRIENDS: Friend[] = [
  { name: "Mateo", look: CAST.friendC, cls: 2 },
  // Lab coat (palette UNIFORMS labcoat: shirt 9fc6ea, trousers 3a3d47, coat fbfbf6), pink top bun, square glasses.
  { name: "Lin", look: { skin: "#f6d5b5", hair: "#d65ba0", hair_style: 5, glasses_style: 2, uniform: "labcoat", shirt: "#9fc6ea", trousers: "#3a3d47", accent: "#fbfbf6", tie: "#5b6bd6", bag: null }, cls: 3 },
  { name: "Amara", look: CAST.friendB, cls: 1 },
  { name: "Sam", look: CAST.hero, cls: 0 },
  { name: "Riya", look: CAST.friendA, cls: 0 },
  // Blazer (shirt f4f4f0, trousers 3a3d47, jacket 24315e), shades, beanie, sling bag.
  { name: "Omar", look: { skin: "#8a5a36", hair: "#1f1a17", hair_style: 0, glasses_style: 3, uniform: "blazer", trousers: "#3a3d47", accent: "#24315e", tie: "#8a2a3a", bag: "#f2a93b", sling: true, hat2: 2, hat_color: "#e0524f" }, cls: 1 },
  // Kurta (shirt f4f1e6, trousers f4f4f0, vest f2a93b), long hair, headband.
  { name: "Zoe", look: { skin: "#a86e45", hair: "#1f1a17", hair_style: 1, uniform: "kurta", shirt: "#f4f1e6", trousers: "#f4f4f0", accent: "#f2a93b", bag: "#3aa4a0", hat2: 3, hat_color: "#ffd24a", height: 0.94 }, cls: 2 },
  // Classic with a blue mohawk, tall, sling bag.
  { name: "Kenji", look: { skin: "#e0ac7e", hair: "#3a5bc4", mohawk: true, uniform: "classic", tie: "#e0524f", bag: "#5b6bd6", sling: true, height: 1.06 }, cls: 3 },
];

export const CLASS_COLORS = ["#e0524f", "#4f86e0", "#48b06a", "#9a62d6"];
