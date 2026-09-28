// Launch film review stills: bundle once, render many frames (60 fps), then one contact sheet.
//   npx tsx scripts/launch-stills.ts <out dir> <frame>... [--debug]
import { execFileSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import { join, resolve } from "node:path";
import { bundle } from "@remotion/bundler";
import { renderStill, selectComposition } from "@remotion/renderer";

const args = process.argv.slice(2);
const debug = args.includes("--debug");
const [dir, ...frames] = args.filter((a) => a !== "--debug");
const root = resolve(__dirname, "..");
const out = resolve(dir);
mkdirSync(out, { recursive: true });
(async () => {
  const serveUrl = await bundle({ entryPoint: join(root, "src/index.ts"), publicDir: join(root, "public") });
  const inputProps = { fps: 60, debug };
  const composition = await selectComposition({ serveUrl, id: "Launch", inputProps, chromiumOptions: { gl: "angle" } });
  const files: string[] = [];
  for (const f of frames) {
    const output = join(out, `f${String(f).padStart(4, "0")}.png`);
    await renderStill({ serveUrl, composition, inputProps, frame: Number(f), output, overwrite: true, chromiumOptions: { gl: "angle" } });
    files.push(output);
  }
  if (files.length > 1) {
    const cols = files.length <= 4 ? 2 : 3;
    const inputs = files.flatMap((f) => ["-i", f]);
    const scaled = files.map((_, i) => `[${i}:v]scale=960:540[s${i}]`).join(";");
    const layout = files.map((_, i) => `${(i % cols) === 0 ? "0" : Array.from({ length: i % cols }, () => "w0").join("+")}_${Math.floor(i / cols) === 0 ? "0" : Array.from({ length: Math.floor(i / cols) }, () => "h0").join("+")}`).join("|");
    execFileSync("ffmpeg", ["-v", "error", "-y", ...inputs, "-filter_complex", `${scaled};${files.map((_, i) => `[s${i}]`).join("")}xstack=inputs=${files.length}:layout=${layout}:fill=black`, join(out, "sheet.jpg")]);
    console.log(join(out, "sheet.jpg"));
  } else console.log(files[0]);
})();
