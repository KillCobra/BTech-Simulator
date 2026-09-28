# Bunk Master: brand kit for films

Source of truth is the game. Every value below cites where it came from.

## Brief (product owner, 2026-09-28 interview)
- First public trailer / teaser. 16:9, 1920x1080, 30 s, with sound.
- Music: original track composed in code (`audio/launch_music.py`), no third-party audio.
- Must sell: sneaking out with friends (co-op, up to 8), proximity voice (staff hear you), chaos tools
  (trolley, paper ball, excuses, blame a friend), big maps and escape routes, surprise tests (quizzes),
  side quests (fire extinguisher), CCTV. "Make people want to play."
- Ending: logo + "Coming soon". No download link or price.
- Build fresh: earlier trailer versions (`src/film/`) are not a reference.

## Colors (scripts/palette.gd, scenes/main.gd, scenes/ui/hud.gd)
| Token | Hex | Source |
|---|---|---|
| GOLD (logo fill, CTA) | #ffc93c | main.gd GOLD |
| INK (logo outline, button text) | #2a1a0e | main.gd INK |
| Sky (splash bg) | #8dd0ef | art/splash.png |
| HUD card | rgba(20,20,36,.72) | hud.gd `_card` Color(0.08,0.08,0.14,0.72) |
| Info blue | #9fd8ff | hud.gd period label |
| Good green | #7fe0a0 | hud.gd done / escaped |
| Warn yellow | #ffd24a | quest current, suspicion start |
| Alarm red | #ff3b3b / #ff4a4a | suspicion end, RUN banner |
| Escape banner | #48b06a | hud.gd |
| Detention | #f2a93b | hud.gd |
| Fire alarm | #e0524f | hud.gd |
| Class colors | #e0524f #4f86e0 #48b06a #9a62d6 | palette CLASS_COLORS |
| Buttons | CREATE #ff9a3c, JOIN #b07cff, SETTINGS #b9e6a0, QUIT #e7d2aa | main.gd:390 |
| Paper (tests) | #f4ecd8, border #8a5a3a, title #8a2a3a | exam_game.gd |
| World | grass #8cc45c, wall #f3e3c3, dado #a9d3a4, board #2f5d4a, wood #b0703e | palette.gd |

## Type
- One face: Jersey 10 (SIL OFL, fonts/). Logo: GOLD fill, INK outline 22 at 76 px (≈ 29% of size),
  shadow rgba(0,0,0,.45) offset y 8 (main.gd:1332). Tagline INK outline 8.

## Components (redraw as React twins, all frame-driven)
| Component | Source | How |
|---|---|---|
| Voxel characters | scenes/player/student_model.gd | Ported box-for-box to `launch/voxel.ts`, rendered in three.js |
| Voxel shader bevel | shaders/voxel.gdshader | Same edge lightening (width .06, light .4) in a Lambert material |
| Item icons | scripts/icons.gd ITEM_SVG | SVG strings copied verbatim |
| HUD cards, banners, suspicion bar, excuse picker, test paper, final bell | scenes/ui/hud.gd, exam_game.gd | Redrawn, same radii/colors/strings |
| Menu buttons | main.gd `_button` | radius 12, border-bottom 6 darkened .35, press = 2 |
| Screenshots | videos/public/plates | Only as broken-up tiles/cards, never raw full-frame |

## Voice and claims
- Approved lines: "Sneak out of class. Don't get caught." (main.gd:1347), README pitch
  "Make a plan, someone ruins it, improvise, panic, barely get out."
- Up to 8 players (network_manager MAX_PLAYERS). Windows and Mac. Staff hear how loud you are, never what you say.
- Lobby offers First Day and Grand Campus only: do not show the three parked maps as playable.
- No "free", no release date.

## Craft defaults (product owner may overrule)
- Playful game brand: overshoot springs, squash and stretch, screen shake on hits are on-brand here
  (chunky toy voxels, bouncy press buttons).
