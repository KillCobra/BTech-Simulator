# Bunk Master: Steam store trailer (brief for every act)

45 s · 1920x1080 · 60 fps (final render at 240 fps, blended to 60 for motion blur) · 128 BPM, 24 bars.
Composition `Steam` in `src/steam/`. It plays first on the Steam page, **autoplaying muted**: every beat must
read with no sound. World class, not a demo.

## What the product owner said
- Trailer 1 (`media/BunkMaster-trailer.mp4`, code in `src/film/`) is the favourite: **how it started and how it
  showed things**. Keep its flow and its language, make everything better:
  dark ringing-clock cold open → HUD card → classroom POV, suspicion fills, RUN! → big kinetic type on bold flat
  colour fields (yellow stripes, red) → feature beats, each with a big 1-3 word title and the game's own UI
  moving (minimap dodge, combos, phone, maps, 8 friends, canteen, ranks) → voxel island logo.
- v2 (`src/launch/`, "Launch") added real 3D voxel characters rebuilt from the game and a synced score. Use that
  3D (it is our unfair advantage), but trailer 1's pacing, type and colour fields lead.
- No raw screenshots: break UI and captures into pieces and animate the pieces. Juicy motion: squash and stretch,
  overshoot, anticipation, impact frames, screen shake, smear/motion blur, stagger on 8ths/16ths.

## Look at these first
- `media/BunkMaster-trailer.mp4` (trailer 1). Contact sheet: `ffmpeg -i ../media/BunkMaster-trailer.mp4 -vf "select='not(mod(n\,15))',scale=320:180,tile=8x15" -frames:v 1 -fps_mode vfr sheet.jpg`
- `src/film/` (trailer 1 code: `ui.tsx` Card/Button/Chip/NameTag/ItemIcon/Badge/APPS/Glyph/Wedge/StaffDot/PlayerArrow/ExitMarker/Star,
  `fxui.tsx` PixelWipe/Burst/Shockwave/Rays/Flash/Iris/slam, `fx.ts` springs and easings, `voxel.tsx`, acts/*).
  You may import from `src/film/*` and `src/launch/*` (read only) or copy pieces into your own files.
- `src/launch/` (v2): `voxel.ts` (CAST looks, poses: walkPose/sitPose/REST/mixPose), `three.tsx` (Voxels,
  Character, G), `sets.ts` (classroom, corridor, cctv, trolley, outside, island, clouds, SAMOSA, PAPER_BALL,
  CHAI_GLASS), `ui.tsx` (font, outline, Card, GameButton, Icon, Alert, Speech, Banner, Plate, PopWords),
  `overlays.tsx` (HUD twins: suspicion, excuse picker, test papers, final bell, logo lockup), `icons.ts`, `juice.ts`.
- `videos/BRAND.md`: colours, type, claims. `launch-prompt.md`: v2 beat sheet.
- Game captures: `public/plates/*.jpg` (c_air0 = First Day aerial, c_air1 = Grand Campus aerial, c_low1 = Grand
  Campus low, class0/fp0 = classroom POV, menu = main menu). Font `Jersey10` (already loaded).

## Shared pieces (do not edit; ask the lead if you need a change)
`src/steam/cues.ts` (BPM, BEAT, BAR, b(bar, beat), ACTS), `src/steam/Stage3D.tsx` (a ThreeCanvas stage with camera,
lights, sky, fog; `toScreen(cam, p)` pins 2D to 3D), `src/steam/Steam.tsx`, `src/steam/timeline.json`, `src/Root.tsx`,
everything in `src/launch/`, `src/film/`, `src/kit/`.

## Your files
Only `src/steam/acts/<YourAct>.tsx`, any new files under `src/steam/<youract>/`, and `src/steam/sfx/<youract>.json`
(sound cues: `[["stamp", 4, 0, 0.7], ...]` = [name, bar, beat, gain]; names: bell, blip, pop, ping, star, whoosh,
stamp, shuffle, psst, spotted, whir, siren, click, crash, paper, spray, slap, impact, win, riser, tick, cash, laugh).
The music agent turns those into sound on the grid.

## Rules
- Every frame is a pure function of `t` (seconds). No CSS transitions/keyframes, timers, Math.random, Date.
  Deterministic randomness: a hash of an index. Springs: `step()`/`track()` from `src/kit/spring.ts` or the helpers
  in `src/launch/juice.ts` / `src/film/fx.ts`.
- Time only through `b(bar, beat)`. Render `null` outside your ACTS window. Your first frame must land with an
  impact on the downbeat; your last half-beat hands off (whip, wipe, smash cut on the next downbeat is fine).
- Something happens on every beat. Big titles land on downbeats; lists on 8ths.
- Type: Jersey10. Titles 150-260 px, GOLD `#ffc93c` (or white) with INK `#2a1a0e` outline (`outline()` from
  launch/ui.tsx) and a hard drop shadow. Body UI text >= 30 px. Max 6 words on screen per title.
- Colour fields: flat game colours (yellow `#ffd24a`/gold stripes, red `#e0524f`, purple `#b07cff`, green `#7fe0a0`,
  orange `#ff9a3c`, sky `#8dd0ef`, ink `#2a1a0e`). No invented gradients or glows beyond what's already in the kits.
- Claims: only real game features and strings (grep the Godot code under `../scenes`, `../scripts`, `../autoload`).
  Up to 8 players. Lobby maps: First Day, Grand Campus (don't present the 3 parked maps as playable).
  No price, no release date.
- Readable at 1080p, text never covered, never crossing other text.

## Check your work
`COMP=Steam npx tsx scripts/steam-stills.ts out/steam/review/<youract>-N <frames...>` (frames at 60 fps:
frame = seconds x 60; your window's frames from `ACTS`). It writes PNGs plus `sheet.jpg`. Look at every sheet.
Typecheck: `npx tsc --noEmit -p .` (ignore errors under src/film). Iterate until it looks world class.
Half-res preview of just your window (optional):
`npx remotion render src/index.ts Steam out/steam/review/<youract>.mp4 --frames=<from>-<to> --scale=0.5 --gl=angle --concurrency=4`

## Round 2: readability pass (product owner, after v3)
"Overall good, but in the middle there are frames that are not readable. Add more built-in animation, like the canteen
in trailer 1 (media/BunkMaster-trailer.mp4 ~24-27 s): each item put in one by one on the beat. Fun to watch AND readable."

- The film is now 30 bars / 56.25 s. Each act works in LOCAL bars (`ACTS` in cues.ts, unchanged meaning of b()),
  and Steam.tsx shifts it onto the film by `OFFSET[act]` bars. Your sfx json stays in LOCAL bars.
  Global frame for stills = (local seconds + OFFSET x 1.875) x 60.
- Build, don't flash: one element per beat (8ths only for tiny pops), each element big and landing with a juicy
  squash, and the finished group HOLDS still for at least 1 s (2 beats+) before anything leaves. One idea on screen at a time.
- Size: body text >= 44 px, labels >= 40 px, titles 150+ px. If it can't be that big, it's too much: cut it.
  Small in-game HUD is fine only as texture when nothing on it needs reading.
- Big centre-stage cards beat small HUD corners: when the UI is the point (excuse picker, test paper, canteen,
  score stack), bring it to the middle, large, then let it leave.
- Fewer words: drop secondary lines (tips, sub-captions, minor labels) rather than shrinking them.
- Check with 4 fps contact sheets of your window: every text you see must be readable in 2+ consecutive tiles.
