import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import path from "node:path";

// The UI lives in dashboard/, but shares src/ (reel scenes, game UI twins) and public/ (fonts, plates, music).
export default defineConfig({
  root: __dirname,
  publicDir: path.resolve(__dirname, "../public"),
  plugins: [react()],
  server: { fs: { allow: [path.resolve(__dirname, "..")] } },
});
