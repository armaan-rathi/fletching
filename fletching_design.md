# Fletching — Design Doc

## Pitch

Players choose a bird-brained, bird-bodied character, bring them into an arena and hunt down their friends.
Everyone comes equipped with a bow, arrows, and the ability to curve their shots to surprise their prey.
Between terrifying power-ups and surprise encounters with map obstacles, the last bird standing gets the worm.

## Inspirations

The game is primarily inspired by *Boomerang Fu* and will feature a similar style of chaotic gameplay.
The characters will have a similar cel-shaded style with bouncy movement, but bird-themed.
The main weapon is a bow and arrow, and arrows can be shot with a curve.
The camera is also like Boomerang Fu's: a top-down, isometric-feeling view.

## Goal

The initial prototype is a solid vertical slice that goes from title screen → character select → game settings → a playable match, with one map for now.
All birds share a common base model and skeleton, with variants making the different birds. The prototype includes **8 birds** (see Characters).
The end of Stage 1 is a simple map where we can control a simple bird character, dash, and shoot arrows that stick into a small tree.

---

## Camera

- **Projection:** Orthographic (Godot Camera3D, projection = Orthogonal).
- **Angle:** pitched ~50° downward, no yaw. Arena edges run parallel to the screen, Boomerang Fu-style, not a 45° diamond isometric view.
- **Framing:** the whole arena is always visible. A small script sets the camera's ortho size to fit the arena bounds plus a margin for the current screen aspect ratio, leaving room at the top for the score UI. Starting value for a 20 × 14 m arena at 16:9: size ≈ 13 (visible height in meters).
- **Placement:** centered over the arena, ~30 m back along the view direction (distance doesn't change size in ortho; it just avoids clipping). Near/far clip: 1 / 100.
- **No rotation or player-following** in the prototype.
- **Juice:**
  - Shake: small random offsets on hits and KOs.
  - Punch-zoom: briefly shrink the ortho size by ~3% on a KO, then ease back. Ortho has no FOV, so zoom = size.
- **Occlusion:** birds behind the central tree or other large props show a player-colored silhouette (x-ray outline). Tree canopies can also fade or dither when a bird is underneath.
- **Mouse aiming:** cast from the cursor onto the ground plane (y = 0). Simple in ortho, since every ray points the same direction.
- **Later (optional):** dynamic framing that tightens the ortho size around the living birds, between a min and max.

---

## Gameplay

### Controls (gamepad first, keyboard supported)

| Action | Gamepad | Keyboard (P1) |
|---|---|---|
| Move | Left stick | WASD |
| Aim | Faces movement direction by default; right stick overrides. While drawing, left stick also aims | Mouse; WASD aims while drawing |
| Draw / Shoot | Hold RT to draw, release to fire | Hold LMB / Space |
| Curve | Push left stick sideways while the arrow flies (see The Bow) | A / D while the arrow flies |
| Dash | A / Cross | Shift |
| Melee (no arrows) | Same as Shoot | Same as Shoot |
| Pause | Start | Esc |

### Movement and Dash

- Snappy acceleration, slight momentum, quick turn.
- **Bounce:** movement is a series of small hops (see Bounce Spec). Bounce is visual only; the hitbox stays grounded.
- **Rooted while drawing:** a bird can't move while drawing the bow. The move input rotates the aim instead.
- **Dash:** quick burst in the move direction with a short cooldown and a very short invulnerability window in the middle of the dash.
- **Dash cancels the draw:** dashing while drawing cancels the shot. No arrow is fired and the arrow stays in the quiver. This is the escape option when you're rooted.

### The Bow

- **Draw:** hold Shoot. Charge level controls arrow speed and range. A visible charge indicator appears on the bird/bow.
- **Fire:** release. Small recoil hop backwards.
- **Curve shots:** for a short window after release, steering sideways bends the arrow's path (limited curve budget). This uses the move input, so steering also moves your bird sideways. That's intentional. Lets players hook arrows around trees.
- **Arrows stick:** arrows embed in trees, walls and props, and lie on the ground if they hit the floor.
- **Quiver:** each bird holds 3 arrows. Walk over a stuck or dropped arrow to pick it up (any bird can grab any arrow).
- **Out of arrows:** Shoot becomes a short-range **wing slap** melee (also a one-hit KO).
- **Auto-return:** arrows stuck for > 5 s poof back to their owner's quiver.

### Hits and KOs

- Arrow or wing slap on a bird = KO: hit-stop, feather explosion, bird tumbles off-screen or goes limp.
- **No self-hits:** a bird's own arrows never hit it.
- Birds are invulnerable during the dash's invulnerability window (see Movement and Dash).

#### KO Sequence

1. **Impact (0–0.1 s):** hit-stop (0.08 s), camera shake and punch-zoom, feather burst, KO expression (X/swirl eyes, beak open in a scream, dizzy stars).
2. **Flop (0.1–0.5 s):** the bird is knocked back in the hit direction, spins, and lands limp on its back or side with a squash. Procedural, not full physics ragdoll, so it stays snappy and predictable.
3. **Spirit rise (0.5–2.0 s):** a ghostly version of the bird rises from the body and floats up into the sky:
   - Same bird mesh with a ghost material: translucent, soft glow at the edges, tinted in the player's color so everyone sees who went down.
   - Peaceful closed eyes (^ ^), gentle slow wing flaps, slight side-to-side sway as it rises.
   - Fades out as it leaves the top of the screen.
   - Purely visual: no collision, never blocks arrows or hides other birds, and stays brief so it never obscures the ongoing fight.
4. **Body:** stays where it fell for the rest of the round with no collision (it can't block arrows or birds), then poofs into feathers when the next round starts.

### Win Conditions

- **Last bird standing** (prototype): last bird alive wins the round. First to N round wins takes the match.
- Rounds to win: **3** (default), with options for **5** and **7**.
- *(Later)* A toggle between **Last Bird Standing** and **KOs** (most knockouts wins).

### Power-ups

Spawn randomly during a round. A bird holds one at a time; picking up a new one replaces it.
Prototype set (more can be added later):
- **Trifecta** – fires 3 arrows in a fan.
- **Eggsplosive** – arrow explodes on impact.
- **Featherweight** – speed boost and longer dash.

### Characters

All birds share the same skeleton, base proportions, hitbox and stats. **Birds are purely cosmetic, now and always. There are no stat differences.**
The prototype includes all 8:
- **Bald Eagle** – white head, dark brown body, yellow hooked beak, stern brows. Regal but a bit cranky.
- **Flamingo** – pink, curved banana beak, long neck tuft, stands on one leg in idle. Flamboyant.
- **Owl** – round, brown/beige, huge eyes, ear tufts. Wise but a little drowsy.
- **Crow** – glossy black with a blue sheen, sharp beak. Mischievous and greedy.
- **Pigeon** – bluish dark gray top, lighter gray bottom, a little ruffled. Wide-eyed and a bit manic-looking.
- **Rooster** – warm brown feathers, puffed-up chest, red comb. Cocky.
- **Swan** – white with a dark face mask, smooth and graceful. Haughty and elegant.
- **Vulture** – bald pinkish-red head, dark brown body, fluffy white neck ruff, hunched posture, hooked beak. Gloomy and opportunistic.

Each bird has up to 4 color variants so two players can pick the same bird.

### Game Flow and Menus

1. **Title** – logo, "Press any button", birds bouncing in the background.
2. **Character select** – each player joins by pressing a button on their device, picks a bird and a color variant, readies up. Supports 1–4 local players plus CPU fill.
3. **Game settings** – rounds to win (3 / 5 / 7), power-ups on/off, number of CPU birds and difficulty, map (one for now). *(Later: win condition toggle.)*
4. **Match** – rounds plus a quick between-round scoreboard.
5. **Results** – winner celebration, stats (KOs, arrows fired), Rematch / Back to Title.

### CPU Birds

Needed so one person can test. Simple state-machine AI: wander, keep distance, line-of-sight check, draw and fire with an aim error that scales by difficulty, dash when an arrow is incoming, retrieve arrows when empty.

### Prototype Map: "Aviary"

- A compact woodland clearing, ~20 × 14 m, bordered by dense bushes, rocks, stumps and tree trunks.
- A central tree (arrows stick) as the main cover, plus a few low bushes, rocks and logs.
- 4 spawn points near the corners.
- **Breakable eggs in nests:** 2–4 nests placed around the arena, away from the corners and spawn points. For now they're just flavor and a test target: they break when hit, with a little splat and pop, but no gameplay effect.

### Starting Tunables

All gameplay numbers live in one config resource (`res://data/tuning.tres`) so they can be tweaked without code changes. These are starting values; tune them in play.

| Parameter | Start value |
|---|---|
| Move speed | 6 m/s |
| Acceleration / deceleration | 40 / 50 m/s² |
| Movement while drawing | None (rooted; input aims) |
| Aim turn rate while drawing | 720°/s |
| Dash distance / duration | 3.5 m / 0.15 s |
| Dash cooldown | 0.8 s |
| Dash invulnerability | 0.06 s, centered mid-dash |
| Full draw time | 0.6 s |
| Arrow speed (min → full charge) | 14 → 28 m/s |
| Quiver size | 3 |
| Curve window / max turn rate | 0.6 s / 180°/s |
| Arrow auto-return | 5 s |
| Hit-stop on KO | 0.08 s |
| Rounds to win | 3 (options 5, 7) |
| Bird hitbox (capsule) | radius 0.4 m, height 1.0 m |

---

## Art Direction

### Look in One Line

Chunky, round, toy-like birds battling in a cozy woodland clearing, cel-shaded with clean ink outlines and a light anime touch in the faces.

### Style Rules

- **Shapes:** round and soft for birds, simple and chunky for environment pieces. Bold silhouettes readable at small size from above.
- **Shading:** 2-band cel shading (lit / shade), with an optional soft rim light. No realistic PBR, no detailed textures.
- **Outlines:** dark, slightly tinted (not pure black) outlines on characters and key props. Method: inverted hull or a next-pass outline shader (pick one in Stage 1, step 2 and use it everywhere).
- **Color:** flat colors from a shared woodland palette. Saturated but natural, not neon. Shadows tinted cool (blue/purple), light warm.
- **Faces (anime touch):** big glossy eyes with highlights, a movable beak, and floating anime symbols (see Expressions).
- **Lighting:** one warm directional "sunlight through the canopy" key light (cel shading relies on a single key light) plus soft ambient. *(Optional later: subtle dappled leaf shadows.)*
- **Background:** beyond the arena edge, a dense tree line and darker forest floor fading out, so the view never shows empty space.
- **Player readability:** colored ring under each bird plus an outline tint or name tag in the player's color.

### Palette (draft)

The final palette is sampled from the KayKit Forest Nature Pack's colors in Stage 1, step 2, so third-party props need minimal recoloring.
- Clearing grass `#8DBF5A`, moss/dark grass `#4F7F3A`, forest floor/dirt `#9C7A52`, bark `#6B4A33`, deep foliage `#2F5D3A`
- Warm sunlight `#FFE6B0`, shadow tint `#4A4E7A`, outline `#2A2233`
- Player colors: P1 `#FF5A5A`, P2 `#4DA6FF`, P3 `#FFD23F`, P4 `#B57BFF` (purple instead of green, to stand out against the foliage)

### Bird Base Model (shared)

- **Proportions (chibi):** ~1.0 m tall, origin at the feet. Big head ≈ 50% of total height and wider than the body; small pear-shaped torso ≈ 35%; short legs ≈ 15%.
- **Head:** clearly separate from the body, on a short neck. The head shape carries species identity (round, angular, flat-faced disc, slim). Swappable head mesh.
- **Beak:** big, chunky and a major design element, readable from above. Split into upper and lower halves. It points where the bird aims.
- **Eyes:** patch meshes on the head (see Expressions).
- **Wings:** stubby wing-hands with feathered tips; the right wing holds the bow.
- **Legs and feet:** short skinny legs, oversized chunky three-toed feet (they sell the bounce).
- **Feather plates:** layered, scalloped feather shapes for collars, ruffs and crests instead of fine detail.
- **Head tracking:** the head turns toward the aim direction (procedural, up to ±45°) so facing reads clearly from above.
- **Shared skeleton (fixed bone names):** `root`, `body`, `neck`, `head`, `beak_lower`, `wing_L`, `wing_R`, `hand_L`, `hand_R`, `leg_L`, `leg_R`, `foot_L`, `foot_R`, `tail`.
- **Swappable parts:** head, beak (upper + lower), crest/head feathers, collar/ruff, tail, eye style, extras (e.g. swan neck, flamingo tuft).
- **Body shape keys:** `puff` (rooster chest), `hunch` (vulture), `slim` (swan, flamingo, crow), `round` (owl, pigeon). Same skeleton and hitbox.
- **Material slots (fixed names):** `body`, `belly`, `beak`, `legs`, `eyes`, `accent`.
- **Budget:** ~1,200–2,000 triangles per assembled bird.
- **Silhouette envelope:** cosmetic parts may extend past the base silhouette visually, but the hitbox never changes.

### Weapons

- Bow and arrow are built in Blender in the same style as the birds (chunky, rounded, flat colored).
- Arrow is slightly oversized for readability, with a bright fletching in the owner's player color.

### Animation

- **Procedural (code):** movement bounce/hop, squash and stretch, lean into movement, turn snap, recoil, hit-stop shake, KO tumble. This carries most of the "feel".
- **Keyframed (small set):** idle, draw bow, release, dash pose, wing slap, KO, squawk, victory dance, plus a flamingo one-leg idle variant. Authored in Blender (or Godot AnimationPlayer) on the shared skeleton.
- Timing: snappy anticipation (2–3 frames), fast action, short overshoot settle.

### Bounce Spec (starting values)

- Hop height 0.08–0.12 m, hop rate scales with speed (~4–6 hops/s at full speed).
- Squash on land (scale Y 0.85, XZ 1.1), stretch on take-off (Y 1.1, XZ 0.95).
- Lean 10–15° into movement direction. Small idle breathing bob when stationary.

### Expressions

Faces are small on screen (roughly 20–30 px across at 1080p), so every expression must be bold and instantly readable. Expressions are built from four layers:

1. **Eye textures** – each eye patch uses a texture atlas holding every expression frame (brows are drawn into the frames). A shader parameter picks the frame per eye, so swaps are instant and the two eyes can differ (winks, one-eyed squints).
2. **Floating anime symbols** – bold, outlined 2D symbols that pop up beside the head: sweat drop, anger mark, sparkles, dizzy stars, "zzz", "!" and "?". They pop in with a scale overshoot, linger briefly, and render on top of the scene so they're never hidden behind props. Project-made, stored in `assets/vfx/symbols/`.
3. **Movable beak** – every beak is split into an upper half (follows `head`) and a lower half (skinned to `beak_lower`). It opens for squawks, KO screams and shock, and does a quick chatter when smug.
4. **Body language** – procedural squash, recoil, puffing up and drooping (see Animation and Bounce Spec) carry the rest.

#### Expression Set (prototype)

| Expression | Eyes | Symbol | Beak | Trigger |
|---|---|---|---|---|
| Neutral | Per-bird resting eyes, random blinks | – | Closed | Default |
| Focused | Squint | – | Closed | Drawing the bow |
| Determined | Narrowed, brows down | – | Clenched | Dashing |
| Shocked | Wide, tiny pupils | "!" | Open | Near-miss, power-up spawn |
| Annoyed | Brows down hard | Anger mark | Clenched | Out of arrows |
| Confused | Dot eyes | "?" | Closed | Bumping into a wall mid-dash |
| Smug | Half-lidded, one brow up | Sparkle | Chatter | Getting a KO |
| KO | Swirl / X eyes | Dizzy stars | Open (scream) | Getting knocked out |
| Happy | Closed arcs (^ ^) | Sparkles | Open | Winning a round |
| Sad | Teary, droopy | Sweat drop | Closed | Losing the match |
| Sleepy | Half-closed | "zzz" | Closed | Idle for a few seconds (the Owl dozes off sooner) |

#### Per-Bird Personality

Each bird has its own **resting eye shape**; the emotion frames are shared overlays (lids, brows, pupils) adapted to each eye shape. This avoids drawing 8 × 11 completely unique faces.
- **Bald Eagle** – heavy stern brows
- **Flamingo** – long lashes
- **Owl** – big, half-lidded
- **Crow** – sly, narrow
- **Pigeon** – wide with pinprick pupils
- **Rooster** – cocky, one brow slightly raised
- **Swan** – haughty, half-closed
- **Vulture** – droopy, tired

Eye color and pupil size are per-bird / per-variant parameters.

#### Rules

- Expressions have a priority order so faces don't flicker: KO > Shocked > Smug > Annoyed > Determined > Focused > Neutral.
- Each expression holds for a minimum time (~0.3 s) before another can replace it (except KO, which always wins).
- At most one floating symbol per bird at a time; a new one replaces the old.

### VFX

- Feather bursts (KO), dust puffs (hops, dash), arrow trails (player-colored), impact stars/sparks, charge sparkle at full draw, egg splats.
- Style: chunky, flat-colored, short-lived. No realistic particles.
- Kenney Particles (soft 2D sprites) are for dust and smoke. Feathers and impact stars are project-made chunky 3D particles using the toon shader.

### Third-Party Assets

- Environment props come from CC0 packs (see Assets).
- Imported packs are made to match: apply the project toon material and outline, remap colors to the palette, normalize scale.
- Never edit files inside `assets/third_party/`. Make project-side copies, materials or wrapper scenes instead.

### UI Style

- Mostly sleek and clean, with a hint of playful cartoonishness: crisp layouts, rounded corners, a bold readable font, subtle bounce on buttons and selections, player-colored accents.
- UI is made by Claude for now (no UI pack). Any font used must be free (CC0 or OFL) and listed in `CREDITS.md`.

---

## Technical Spec

### Tools

- **Engine:** Godot 4.x (latest stable), GDScript, Forward+ renderer.
- **3D:** Blender (latest stable), driven by Claude Code via MCP for Blender.
- **Engine automation:** Claude Code via a Godot MCP server, plus Godot's command line (headless) for checks.

### Units and Orientation

- 1 unit = 1 meter. Bird height ~1.0 m.
- Blender: Z-up, character faces -Y (front view), origin at the feet.
- Exported as GLB (glTF); imports into Godot Y-up. Each bird's wrapper scene corrects facing so gameplay code uses Godot's -Z forward.

### Project Structure

```
res://
  assets/
    birds/          # base body, parts, skeleton (GLB) + .blend sources in /source
    weapons/        # bow, arrow
    env/            # project-made environment pieces (terrain, nests, eggs)
    third_party/    # untouched CC0 packs, one folder per pack, with license files (see Assets)
    shaders/        # toon, outline, background
    materials/
    vfx/
    ui/
  data/
    tuning.tres     # all gameplay tunables
    birds/          # BirdData resources (eagle.tres, flamingo.tres, ...)
  scenes/
    birds/          # bird.tscn (shared), per-bird variants
    weapons/
    maps/           # test_map.tscn, aviary.tscn
    ui/             # title, character_select, settings, results
    game/           # match manager, round flow
  scripts/
  docs/
    decisions.md    # running log of design/tech decisions
    placeholders.md # list of temporary / AI-generated assets
CREDITS.md          # third-party assets, fonts and licenses
```

### Key Architecture

- **BirdData (Resource):** name, part selections, color variants, expression textures. The shared `bird.tscn` assembles a bird from a BirdData.
- **Bird scene:** CharacterBody3D → visual root (procedural bounce applied here) → skeleton + meshes; separate hitbox Area3D; bow attached via BoneAttachment3D to `hand_R`.
- **Arrow:** custom kinematic projectile (not full rigid-body physics) for predictable curving; raycast each frame; ignores its owner; on hitting a static body it becomes a stuck arrow pickup.
- **Input:** per-player device mapping (keyboard or gamepad N), set up in character select.
- **Game state:** a MatchManager autoload holding players, settings, scores and the round flow.
- **Collision layers:** 1 world, 2 birds, 3 bird hitboxes, 4 arrows, 5 pickups, 6 arrow-stickable surfaces, 7 breakables.
- **Third-party collision:** KayKit models come without collision. Third-party props get simple project-made collision shapes (e.g. a cylinder for a tree trunk) so arrows can stick and birds can't walk through.

### Naming Conventions

- Files: `snake_case`. Nodes: `PascalCase`. Blender objects: `bird_body`, `beak_hooked`, `crest_tufts`, etc.
- Bone and material slot names are fixed (see Bird Base Model) and must not change.

---

## Workflow (for Claude Code)

1. **Setup:** read this doc fully. Create `CLAUDE.md` summarizing the key rules (structure, naming, skeleton, units, stage plan, "don't touch third_party"). Verify both MCP servers respond before Stage 1.
2. **Work stage by stage, step by step.** Don't start the next step until the current one meets its done criteria.
3. **Verify before reporting:** run Godot headless to catch script errors; use screenshots (Blender `look`, Godot run captures) to check visuals.
4. **Checkpoints:** at the end of each step, summarize what changed and what to test, and wait for my playtest feedback before continuing.
5. **Tunables** go in `tuning.tres`, never hard-coded.
6. **Decisions** (and anything that deviates from this doc) are logged in `docs/decisions.md`.
7. **Ask, don't guess,** on anything listed under Open Questions.
8. **Placeholders:** any AI-generated or temporary asset is named with a `ph_` prefix and listed in `docs/placeholders.md`.

---

## Assets

Chosen packs go in `assets/third_party/<pack_name>/` with their license file, and are credited in `CREDITS.md`. Use the **glTF** versions only (no FBX/OBJ copies in the project).

| Pack | Path | Use |
|---|---|---|
| KayKit Forest Nature Pack (free tier) | `assets/third_party/kaykit_forest/` | Main environment: trees, bushes, rocks, grass |
| KayKit Halloween Bits (free tier) | `assets/third_party/kaykit_halloween/` | Mostly unused for now; kept for future maps |
| Kenney Particle Pack | `assets/third_party/kenney_particles/` | Dust and smoke sprites |

Project-made (not from packs): arena terrain/ground, nests and eggs, birds, bow and arrows, feather/impact VFX, UI.
All generated assets should keep an eye on polygon counts to make sure they're not too high.

---

## Roadmap

### Stage 1 — Foundations and Core Feel

**Goal:** a simple bird I can control on a basic map, with a dash, shooting arrows that stick into a tree.
1. **Project setup** – Godot project, folder structure, `CLAUDE.md`, input map (keyboard + 1 gamepad), `tuning.tres`, organize the third-party packs (see Assets), MCP checks.
2. **Look test** – toon shader, outline, single-light setup, woodland background, camera angle, palette sampled from KayKit Forest. Test scene with primitive shapes and a few KayKit props for approval.
3. **Base bird v0** – Blender: egg body, legs, wings, “shared skeleton (including beak_lower), split beak, eye patches with a neutral eye texture”. Export GLB, build `bird.tscn` wrapper.
4. **Test map** – flat ground, border, one KayKit tree with trunk collision (arrow-stickable), cel shaded.
5. **Movement** – controller with acceleration, turning and procedural bounce/lean.
6. **Dash** – burst, cooldown, mid-dash invulnerability, dust puff, squash/stretch.
7. **Bow and arrows** – draw/charge (rooted, input aims), fire, recoil, dash-cancel, arrows stick in the tree, walls and ground, pick-up, quiver of 3, 5 s auto-return.
8. **Feel pass** – camera shake, hit-stop hook, arrow trail, tune the numbers together.

**Done when:** I can bounce around, dash, shoot all 3 arrows into the tree, collect them, and it feels fun.

### Stage 2 — Bird Kit and the Flock

1. Modular parts (beaks, crests, tails, eyes, brows, extras) on the shared skeleton.
2. BirdData resource and assembly system, plus color variants.
3. Build all 8 birds (see Characters); turntable screenshots for approval.
4. Keyframed animations (idle, draw, release, dash, slap, KO, victory) and expression swaps.
5. Bow attachment and per-player arrow color.
6. Expressions: eye texture atlases, per-bird resting eyes, beak open/chatter, floating anime symbols, priority rules (see Expressions).

### Stage 3 — Combat and Multiplayer

1. Hits, KOs (no self-hits), feather burst, hit-stop.
2. 2–4 local players (device assignment), spawning, player rings.
3. Round flow, scoring, match win condition (first to 3 / 5 / 7).
4. Curve shots.
5. Wing slap melee.
6. CPU birds (easy / normal).

### Stage 4 — Menus and Flow

1. Title screen.
2. Character select (join, pick bird and variant, ready).
3. Game settings.
4. Between-round scoreboard and results screen; full loop back to title.

### Stage 5 — Power-ups and the Real Map

1. Aviary map built from KayKit Forest plus project-made terrain, nests and eggs.
2. Power-up spawning system and the 3 prototype power-ups (Trifecta, Eggsplosive, Featherweight).
3. VFX pass.

### Stage 6 — Polish and Wrap

1. Tuning sessions, bug fixing, performance check.
2. UI polish and juice.
3. Desktop export build.

### Stage 7 — Sound (later)

SFX and music.

---

## Open Questions

1. **Curve feel:** how strong should steering be, and should the curve window start immediately on release or after a short delay?
2. **Aiming while drawing:** snap instantly to the stick direction, or rotate at the aim turn rate? Any aim assist?
3. **Power-up spawns:** random open spots, fixed spawn points, or (later) from breaking eggs?
4. **Eggs:** stay pure flavor, or eventually drop power-ups or have another effect?
5. **KO win mode (later):** most KOs per round, per match, or a timed match?
6. **Wing slap:** range and arc size; can it be spammed or does it have a cooldown?
7. **Keyboard players:** support one keyboard player, or two sharing a keyboard?
8. **CPU difficulty:** just easy / normal, or add hard?
9. Taunt button (later): a dedicated squawk/taunt input using the beak and symbols?
