# Bunk Master (Godot 4.4.1, GDScript)

## Branch, CI and releases
- Work happens on the `bunk-master` branch of github.com/KillCobra/BunkMaster (remote `origin`). `main` gets
  Bunk Master through PRs from `bunk-master`; never merge `main`'s files into `bunk-master`. (main's old Unity
  prototype history was joined once, with `-s ours`, so those PRs work; the Unity project is on `unity-archive`.)
- Every push to `bunk-master` runs `.github/workflows/checks.yml`: project import, all scripts compile, and a
  bot-played 5-minute round on map 0 reaching the final bell with no `SCRIPT ERROR`.
- Release = push a tag `vMAJOR.MINOR.PATCH` on a `bunk-master` commit (`git tag v0.5.0 && git push origin v0.5.0`).
  `.github/workflows/release.yml` runs the checks, exports Windows (`BunkMaster.zip`: exe + webrtc dll) and Mac
  (`BunkMaster-mac.zip`), and publishes a GitHub release. Tags not on `bunk-master` are refused.
- Before pushing, run the same checks locally (see below). Bump the tag from the latest `git tag --sort=-v:refname`.

## Local tools
- Godot editor (console): any `Godot_v4.4.1-stable_win64_console.exe` under
  `%TEMP%\claude\C--Users-gaura-desktop-cgame\*\scratchpad\godot441\`; export templates are in `export/templates/`.
- Compile check: `godot --headless --path . --quit-after 60` and grep for `SCRIPT ERROR|Parse Error`.
- Bot/dev flags are listed in README.md ("Develop"). Floating-prop audit: `godot --headless --path . -s scripts/prop_audit.gd`.
- `export/` is git-ignored (local builds only).
- Multiplayer bugs only show with two instances: `--session-host=NAME` in one, `--session-join=NAME --autoready` in the
  other (headless is fine). The Director's small `world` dict is sent unreliably and must stay under the 1350-byte
  MTU (grep host logs for "bigger than MTU"); put bigger or rarer state in `things`.
- Staff hearing without a mic: `--voice-test=AMP`. Each round prints `[moments]` (longest stretch where nothing happened).
