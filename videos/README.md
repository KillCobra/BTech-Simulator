# Bunk Master trailer (Remotion)

30 s launch/showreel film. Everything is built from the game's own material:
- `public/plates/`: frames filmed in the game (`--nohud --cam=... --shot=...`, see ../README.md "Develop").
- `src/film/voxels.json`: the icon/splash diorama from `art/make_art.py`, rebuilt block by block.
- `src/film/icons.json`: item and badge SVGs from `scripts/icons.gd`.
- `src/film/ui.tsx`: frame-driven twins of the HUD (cards, phone, minimap, buttons), same colours and copy.
- `audio/make_music.py`: the original score, synthesized from scratch (128 BPM, 16 bars = 30.0 s);
  `src/film/cues.ts` uses the same bar grid, so every cut lands on a hit.

```bash
npm install
npm run music                                   # public/audio/trailer.wav (needs uv)
npx remotion studio src/index.ts                # preview
npx tsx scripts/stills.ts out/review 450 900    # stills at 60 fps frames
./scripts/render.sh v1                          # out/trailer/v1/BunkMaster-trailer.mp4 (240 fps -> motion blur)
```
