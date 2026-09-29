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

## Reel Studio (dashboard)

Web dashboard for making short ads without prompting: live preview, timeline editor, Opus storyboards, MP4 render.

```bash
cp dashboard/.env.example dashboard/.env   # add ANTHROPIC_API_KEY (only needed for "Ask Claude")
npm run dashboard                          # http://localhost:5174
```

- A reel is JSON in `reels/` (scenes measured in beats of the 128 BPM score); the model writes that JSON, never code.
- Scene kinds live in `src/reel/Reel.tsx`, their fields in `src/reel/spec.ts` (add a kind in both, plus `KINDS`).
- Renders land in `out/reels/` (git-ignored). Formats: 9:16, 1:1, 16:9 at 30 fps. `REEL_MODEL` overrides the model.
