# Fletching — working rules

Boomerang Fu-style local-multiplayer brawler: chibi cel-shaded birds fighting with bows and curving arrows.
The full spec is `fletching_design.md`. This file is the short version; the design doc wins if they disagree.

## Tools
- Godot 4.6 (`/Applications/Godot.app/Contents/MacOS/Godot`), GDScript, Forward+, Jolt physics.
- Blender 5.2 (`/Applications/Blender.app/Contents/MacOS/Blender`), run headless with `-b --python`.
- No MCP servers are connected; both apps are driven from the command line (see `docs/decisions.md`).
- Checks: `Godot --headless --path . --import` (re-import), `Godot --headless --editor --path . --quit` (script errors),
  `Godot --path . -s tools/screenshot.gd -- <scene> <out.png> [pitch]` (rendered capture),
  `Godot --path . --resolution 1600x900 -s tools/sim_playtest.gd -- <dir>` (scripted gameplay checks + screenshots),
  `Godot --path . --resolution 1600x700 -s tools/bird_turntable.gd -- <out.png>` (bird close-up).
- Windowed sims make sound since Stage 7: add `--audio-driver Dummy` so test runs stay silent. Sound check:
  `tools/sfx_check.gd -- match` (which events fire) / `-- levels` (offline render for the mix, see the script).
- Wrap Godot runs in `perl -e 'alarm 60; exec @ARGV' ...` so a stuck script can't hang the shell (no `timeout` on macOS).
- Generators: `tools/blender/build_bird_base.py`, `tools/blender/build_weapons.py` (run with Blender `-b --python <f> -- <project>`),
  `tools/build_stage1.gd` (arrow, bow, bird, tree wrapper, test map), `tools/build_look_test.gd` (materials, look test),
  `tools/setup_project.gd` (input map, layers, render settings, shader globals).
- Tool scripts that load game scripts should `await process_frame` first. Don't add autoloads casually (see decisions).
- Folders with `.gdignore`: `docs/`, `tools/blender/`, `assets/*/source/`.

## Hard rules
- **Never edit files inside `assets/third_party/`.** Use project-side materials, wrapper scenes or copies.
- **All gameplay numbers live in `data/tuning.tres`** (`scripts/tuning.gd`). Never hard-code tunables.
- **Log decisions and deviations** from the design doc in `docs/decisions.md`.
- **Placeholders:** temporary / AI-made assets get a `ph_` prefix and a line in `docs/placeholders.md`.
- **Ask, don't guess** on the design doc's Open Questions.
- Birds are purely cosmetic. Never give birds different stats.
- Keep poly counts low (< 3,750 tris per assembled bird: the 3k limit + 25%, user; the bird generator enforces it).

## Units and orientation
- 1 unit = 1 m. Bird ~1.0 m tall, origin at the feet.
- Blender: Z-up, character faces -Y. Export GLB. Godot: Y-up, gameplay forward is -Z (wrapper scenes fix facing).
- Ground plane is y = 0. Arena (Stage 1) is 20 × 14 m, centered at the origin.

## Naming
- Files `snake_case`, nodes `PascalCase`, Blender objects `bird_body`, `beak_hooked`, ...
- Skeleton bones (fixed, 14): `root body neck head beak_lower wing_L wing_R hand_L hand_R leg_L leg_R foot_L foot_R tail`.
  `assets/birds/bird_base.glb` = rig + all parts; `data/birds/*.tres` (BirdData) picks parts/shape/colors per bird.
- Debug keys: never function keys. H help, T reload tuning, R restart, B/N bird, V variant, E expression, G clip,
  C CPU count, K CPU difficulty, J split keyboard/pad, U art style (both layers), Y birds' style, P world's style,
  O style option, I tilt-shift.
- Animation: clips in `assets/birds/anims/bird_anims.tres` (AnimationPlayer); procedural layer in
  `BirdPoseModifier` (SkeletonModifier3D). Faces: `BirdExpressions` (priority/hold), `eye.gdshader` (frame 0 =
  per-bird procedural resting eye from `BirdData.eye_style`), `AnimeSymbol`.
- Material slots (fixed): `body belly beak legs eyes accent`.
- Bird meshes (v2 generator): every vertex carries an outline-width factor in UV2.x (the bird outline material
  reads it, `vertex_width`), so feather/beak tips taper and parts buried in others don't poke ink through.
  Review sheets (before/after style): `tools/bird_review.gd -- <dir>`. Bird models v2 approved by the user
  (2026-11-10), including the crow's wedge head and the pigeon's tall oval head.

## Collision layers
1 world · 2 birds · 3 bird_hitboxes · 4 arrows · 5 pickups · 6 arrow_stickable · 7 breakables · 8 bird_blockers (birds only; e.g. under the birdbath bowl)

## Look
- Toon lighting: `assets/shaders/toon_lighting.gdshaderinc` (2-band, cool shade tint from the global
  `toon_shade_color`, optional rim). Every lit surface uses `toon.gdshader` or a shader that includes it.
  Global shader colors must be sRGB-decoded in the shader (`pow(c, 2.2)`); Godot doesn't do it for globals.
- Materials in code: `ToonMaterials.toon(color)`, `ToonMaterials.toon_with_xray(...)`. Game feel: static `Fx` class.
- Outlines: inverted hull, `assets/shaders/outline.gdshader`, used as the `next_pass` of toon materials.
- Third-party props: `scripts/toon_prop.gd` instantiates a pack model and swaps its materials for the toon ones.
- Camera: orthographic, fixed pitch, auto-fit to the arena (`scripts/arena_camera.gd`).
- Palette lives in `docs/decisions.md` (sampled from KayKit Forest's `forest_texture.png`).

## Workflow
- Work stage by stage, step by step. Verify (headless run + screenshots) before reporting.
- Look test approved; camera 50°. Tonemap stays Linear unless the user says otherwise.
- Stage 6 done (perf, homing, procedural KO flop + `BirdSpirit` per the doc's KO Sequence, per-player x-ray stencil, UI juice, CPU balance). Desktop export
  skipped for now (user choice). Waiting on the user's playtest.
- Stage 7 (sound) built: `Sfx.play("event")` (static, like Fx) with one bank row per event in `scripts/sfx.gd`
  (files, dB, pitch range, bus, voice/gap limits). Buses Music / SFX / UI -> Master (hard limiter), in
  `default_bus_layout.tres` (made by setup_project.gd). Volume in Game settings, saved to user://settings.cfg.
  No music yet (no music pack). Waiting on the user's listen-through.
- Level editor: title screen E (`scripts/ui/level_editor.gd`). Layouts are JSON in `data/maps/`, built at runtime by
  `MapBuilder` + `MapCatalog` (add placeable items there), played through `scenes/maps/custom_map.tscn`.
  Check: `tools/editor_check.gd`.
- Melee (user rework): own button (RMB / F, pad A), stuns 1 s instead of KO; a tight-window swing bats arrows
  back (they change owner, return to the shooter's quiver). Tunables in tuning's Melee group. Test: `tools/sim_melee.gd`.
- Shrike (lob shot, user rework): own button (Q / MMB; pad L / ZL / Y): aimed arc, charge = distance (4–11 m),
  landing ring preview, move nudges it in flight, direct hit KOs, landing shockwave stuns nearby; can't be parried.
  Tunables in tuning's Shrike group. Test: `tools/sim_shrike.gd`.
- Pads (Switch layout, positional SDL3 buttons): R/ZR/X shoot, L/ZL/Y shrike, B dash, A melee; menus confirm/back by
  the pad's labels (`MenuInput.is_nintendo`, Game settings "Controller"). Game settings also has Display (fullscreen).
- Overtime: 2 min into a round a 30 s timer, then egg rain (`SkyEgg`). Test: `tools/sim_overtime.gd`. CPU stalls:
  `tools/sim_stall.gd` (patience watchdog in `CpuInput`). Match win: winner celebrates per `BirdData.victory_style`
  (`tools/celebration_shots.gd`).
- KO: the tumble renders in `Bird._process` (render rate); a KO cancels one-shot clips. `tools/ko_check.gd` fails on
  any bone movement after landing.
- Art style exploration (11 styles): `ArtStyle` + globals `art_style_char` / `art_style_env` (shaders that
  `#define AS_CHARACTER` read the char one), branched in the shared toon/outline/ground shaders, two stencil-gated
  scene passes (`style_scene_*`) and `style_post.gdshader` (0 = baseline, untouched). Flying arrows use
  `ToonMaterials.actor()` (stencil 5). Captures: `tools/style_shots.gd`; perf: `tools/style_perf.gd`.
- Power-ups: last the whole match, max 3 held, 4th replaces the oldest (user decision; overrides the doc).
- UI: `scripts/ui/` (UiKit look + transitions, MenuInput per-device menu actions). Flow test: `tools/sim_flow.gd`.
- Open questions 1, 2, 3, 4, 6, 7, 8 are answered (see decisions). Still open: 5 (KO win mode), 9 (taunt button).
- Match: `MatchManager` autoload + `RoundController` in the arena. Tests: `tools/sim_stage3.gd` (mechanics + CPU match).
- Sims press inputs with `PlayerInput.test_press/test_release` (immune to focus loss). Stage 6 tools: `perf_check.gd`,
  `ko_check.gd`, `balance_sim.gd -- <matches> on|off [hard overrides]`.
- Bird surfaces must use `ToonMaterials.character*` with the bird's `stencil_slot` (0-3, stencil value slot+1);
  that includes the bow and quiver pips.
- Keep playtests short unless asked (`sim_playtest.gd -- <dir> quick`).
- No git for now.

## Stage plan (summary)
1. Foundations: setup → look test → base bird v0 → test map → movement → dash → bow & arrows → feel pass.
2. Bird kit and the 8 birds. 3. Combat and local multiplayer, curve shots, CPU. 4. Menus. 5. Power-ups + Aviary map. 6. Polish. 7. Sound.
