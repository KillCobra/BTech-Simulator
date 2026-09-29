// Showreel tokens - extends brand colors with motion-specific values
export const W = 1920;
export const H = 1080;
export const FONT = "Jersey10";

export const C = {
  // Brand colors (from BRAND.md)
  gold: "#ffc93c",
  ink: "#2a1a0e",
  sky: "#8dd0ef",
  panel: "#14141f",
  panelA: "rgba(20,20,36,0.78)",
  yellow: "#ffd24a",
  green: "#7fe0a0",
  blue: "#9fd8ff",
  cyan: "#7fd0ea",
  orange: "#ff9a3c",
  purple: "#b07cff",
  pink: "#ff8aa8",
  teal: "#5fd3c5",
  red: "#ff4a4a",
  redHot: "#ff3b3b",
  cream: "#fbf1dc",
  canteenRed: "#c4492f",
  paper: "#f4ecd8",
  paperEdge: "#8a5a3a",
  paperTitle: "#8a2a3a",
  white: "#ffffff",
  grass: "#7cbf5a",
  mapInk: "#2a2230",
  classA: "#e0524f",
  classB: "#4f86e0",
  classC: "#48b06a",
  lab: "#9a62d6",
  
  // Showreel-specific
  bgDark: "#0d0d12",
  bgDarker: "#060608",
  accent1: "#00ffc8",  // cyan accent for tech feel
  accent2: "#ff2d75",  // magenta accent
  accent3: "#ffd700",  // gold accent
  glass: "rgba(255,255,255,0.08)",
  glassBorder: "rgba(255,255,255,0.15)",
  neonCyan: "#00ffff",
  neonMagenta: "#ff00ff",
  neonYellow: "#ffff00",
} as const;

// Easing presets
export const EASE = {
  expo: (t: number) => t === 1 ? 1 : 1 - Math.pow(2, -10 * t),
  expoIn: (t: number) => t === 0 ? 0 : Math.pow(2, 10 * (t - 1)),
  circ: (t: number) => 1 - Math.sqrt(1 - t * t),
  back: (t: number) => t * t * (2.7 * t - 1.7),
  elastic: (t: number) => t === 0 || t === 1 ? t : -Math.pow(2, 10 * (t - 1)) * Math.sin((t - 1.1) * 5 * Math.PI),
} as const;