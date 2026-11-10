# Placeholders

Temporary or AI-generated assets. Each should be replaced or approved before release.
Note: Stage 1 models are AI-generated but intended as the real base assets, so they keep the doc's names
instead of a `ph_` prefix (renaming would break the fixed naming scheme). They're listed here for approval.

| Asset | Path | Notes |
|---|---|---|
| `ph_TestBird1`–`4` | `scenes/maps/look_test.tscn` | Primitive egg birds for the look test only. |
| `ph_Log`, `ph_Stump` | `scenes/maps/look_test.tscn` | Cylinder primitives standing in for project-made log/stump props. |
| Base bird rig + parts library (8 birds) | `assets/birds/bird_base.glb` (`tools/blender/build_bird_base.py`) | AI-generated (v2 model quality pass, procedural Blender script). |
| Bird data / color variants | `data/birds/*.tres` (`tools/build_bird_data.gd`) | Draft palettes, 4 variants per bird. |
| Bow, arrow | `assets/weapons/{bow,arrow}.glb` (`tools/blender/build_weapons.py`) | AI-generated. |
| `ph_eye_atlas.png` | `assets/birds/eyes/` (`tools/make_eye_atlas.gd`) | Generated expression frames (blink, focused, determined, shocked, annoyed, confused, smug, KO, happy, sad, sleepy). |
| `ph_sweat/anger/sparkle/dizzy.png` | `assets/vfx/symbols/` (`tools/make_symbols.gd`) | Generated anime symbols; the anger mark especially is rough. |
| Bird animation clips | `assets/birds/anims/bird_anims.tres` (`tools/build_bird_anims.gd`) | AI-authored keyframes; editable in Godot. |
| `ph_shape_*` (6) | `assets/birds/exploration/` (`tools/blender/shape_exploration.py`) | Shape exploration only; not used in game. Delete after the base bird rebuild. |
| `ph_shape_{eagle,owl}_v2` | `assets/birds/exploration/` (`tools/blender/shape_v2.py`) | Shape iteration v2 at 50% head; reference for the base bird rebuild. |
| Aviary props (log, stump, nest, egg) | `assets/env/*.glb` (`tools/blender/build_env_props.py`) | AI-generated, chunky low-poly. |
| Power-up icons | `assets/ui/powerups/ph_*.png` (`tools/make_powerup_icons.gd`) | Generated placeholders. |
| Flowers (`FlowerPatch`) | `scripts/flower_patch.gd` | Procedural low-poly flower clusters for the level editor's decoration. |
