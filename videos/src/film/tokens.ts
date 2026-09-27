// Bunk Master's own colours (scripts/palette.gd, scenes/ui/hud.gd, scenes/main.gd). Hex only: many animate.
export const C = {
  gold: "#ffc93c", // title fill, START CLASS
  ink: "#2a1a0e", // title outline, button text
  sky: "#8fd3f0", // art/splash.png sky
  panel: "#14141f", // HUD card rgba(.08,.08,.14) on black
  panelA: "rgba(20,20,36,0.78)",
  phoneBezel: "#15161c",
  phoneBorder: "#3a3d4a",
  phoneScreen: "#1f2a3a",
  yellow: "#ffd24a", // cash, current quest
  green: "#7fe0a0", // done, I'M READY
  blue: "#9fd8ff", // period line
  cyan: "#7fd0ea", // Timetable, SETTINGS (pause)
  orange: "#ff9a3c", // CREATE SESSION, Trade
  orangeSoft: "#ff9a4a",
  purple: "#b07cff", // JOIN SESSION, Navigate
  pink: "#ff8aa8", // Tracker
  teal: "#5fd3c5", // Help Out
  red: "#ff4a4a", // RUN!
  redHot: "#ff3b3b",
  cream: "#fbf1dc", // canteen panel
  canteenRed: "#c4492f",
  paper: "#f4ecd8",
  white: "#ffffff",
  grass: "#7cbf5a",
  mapOutside: "#4a7f41",
  building: "#c9b48f",
  path: "#e8dcc0",
  road: "#5a5d68",
  mapInk: "#2a2230",
  classA: "#e0524f",
  classB: "#4f86e0",
  classC: "#48b06a",
  lab: "#9a62d6",
} as const;

export const FONT = "Jersey10";
export const W = 1920;
export const H = 1080;
