// Review stills: bundle once, render many frames.  npx tsx scripts/stills.ts <out dir> <frame>...
import { mkdirSync } from "node:fs";
import { join, resolve } from "node:path";
import { bundle } from "@remotion/bundler";
import { renderStill, selectComposition } from "@remotion/renderer";

const [dir, ...frames] = process.argv.slice(2);
const root = resolve(__dirname, "..");
const out = resolve(dir);
mkdirSync(out, { recursive: true });
(async () => {
  const serveUrl = await bundle({ entryPoint: join(root, "src/index.ts"), publicDir: join(root, "public") });
  const inputProps = { fps: 60 };
  const composition = await selectComposition({ serveUrl, id: "Trailer", inputProps });
  for (const f of frames) {
    const output = join(out, `f${String(f).padStart(4, "0")}.png`);
    await renderStill({ serveUrl, composition, inputProps, frame: Number(f), output, overwrite: true });
    console.log(output);
  }
})();
