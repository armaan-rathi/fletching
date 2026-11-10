# Fletching — playtest checklist

Everything below has passing automated checks (`tools/sim_*.gd`, `ko_check`, `editor_check`, `sim_birdbath`,
`sim_shrike`), so mechanics *work*. What only a person can judge is how they **feel, read and sound**. Items marked
**(new)** haven't been played by you yet.

## 1. Controls and devices
- [ ] Keyboard + mouse: move (WASD), aim (mouse), draw/shoot (LMB / Space), dash (Shift), melee (RMB / F),
      **shrike (Q / middle mouse) (new)**, pause (Esc).
- [ ] Gamepad: move (left stick), aim (right stick), shoot (RT), dash (A), melee (RB / X), **shrike (LT / Y) (new)**,
      pause (Start).
- [ ] Two players: one keyboard, one pad. Then two pads. Quick-play key J (keyboard and pad 0 as separate players).
- [ ] Nothing fights for the same button. Shrike on LT next to shoot on RT; melee on RB.
- [ ] Debug keys (no F-keys): H help, T reload tuning, R restart, B/N bird, V colors, E expression, G clip,
      C CPU count, K CPU level, J split.

## 2. Core combat feel
- [ ] Movement and hops; acceleration and stopping.
- [ ] Dash: distance, cooldown, invulnerable middle, bonking into cover.
- [ ] Draw: charge time (0.6 s), full-charge flash, arrow speed and range at low and full charge.
- [ ] Curve shots: steering strength (120°/s) and window (0.6 s).
- [ ] Homing: should be *very* slight (≤ 60°/s within 2.5 m).
- [ ] Arrow pickup; stuck arrows return after **7 s (new)**; quiver pips; empty-quiver click.
- [ ] Near-miss "!" reactions.

## 3. Melee and parry (new)
- [ ] Slap stuns for 1 s (no KO); slap-then-shoot combo; no stun-lock (0.6 s immunity).
- [ ] Parry timing is tight but doable: press about 40–130 ms before impact against slow arrows, 30–100 ms
      against fast ones.
- [ ] Batted arrow direction depends on where it hits the wing (head-on goes back, glancing skims off).
- [ ] Batting shoves you back about 0.75 m and locks melee for 1 s. Does that stop endless defending?
- [ ] The white swoosh makes the timing readable.

## 4. Shrike lob shot (new)
- [ ] Charge and release: the arrow goes straight up and comes back where you stood.
- [ ] Steering while it's up (move input): too fast or slow? Is 4–6 m of reach right?
- [ ] Landing ring readable? Is the 0.35 s locked drop fair to dodge?
- [ ] Over cover: lob behind a log, rock or tree onto a hidden enemy.
- [ ] As a trap: lob, walk away, and have an enemy walk into it.
- [ ] Lands on top of cover (stuck in it); stands upright in the ground; you can pick it up.
- [ ] Can't be batted away; never hits you; Trifecta drops three; Eggsplosive explodes on landing.
- [ ] CPUs lob shrikes over cover and dash out of your rings.

## 5. KO sequence (re-check: twitch fix, new)
- [ ] Impact: hit-stop, shake, punch zoom, feathers, X eyes, scream.
- [ ] Flop: knocked back, half spin, tips onto back or side, small squash, then **completely still** (no twitch,
      no crunches).
- [ ] The ghost rises with ^ ^ eyes in the player's color and fades. Doesn't block anything.
- [ ] Body stays all round, no collision; poofs into feathers when the next round starts.
- [ ] KO while drawing, slapping, dashing or stunned: still a clean flop.

## 6. Birds (new models)
- [ ] All 8 birds × 4 color variants: in character select, at game zoom, and up close (title, results).
- [ ] Silhouettes tell apart at game zoom: crow wedge head, pigeon tall head, rooster plume, owl disc, etc.
- [ ] Wings, tails and feet look right in motion: hops, draw, release, slap, dash, victory dance, flamingo idle.
- [ ] Long necks (flamingo, swan) look natural; no cracks or popping.
- [ ] Expressions (11) and anime symbols: grow in, the anger pulse, gone after about 1 s; zzz while sleepy.
- [ ] X-ray silhouettes behind trees, cover and other birds.

## 7. CPU opponents
- [ ] Easy, Normal and Hard each feel distinct and fair.
- [ ] Hard isn't oppressive. Sims: it now wins about 50% of rounds against 2 Normals and 1 Easy (was ~42%).
- [ ] CPU stuns, parries, dodges and shrikes look intentional, not glitchy.

## 8. Power-ups
- [ ] Pads spawn power-ups; pickup burst and sound; HUD badges.
- [ ] Trifecta, Eggsplosive and Featherweight all feel good (with shots and with shrikes).
- [ ] They last the whole match; max 3; a 4th replaces the oldest; leaders don't snowball too hard.

## 9. Maps
- [ ] Test Clearing and Aviary: cover layout, nests and eggs, spawn fairness.
- [ ] **Birdbath (new):** 40 × 26 m. Are birds big enough on screen? Water slows you (60%) and shortens dashes;
      the puddle spreads each round and resets; splashes; you can't walk under the bowl; arrows clack on the
      stone.
- [ ] Custom maps made in the editor play correctly (spawns, pads, nests, size).

## 10. Level editor (title screen: E)
- [ ] Place, move, rotate (wheel / Q E), scale ([ ]), delete, duplicate, undo/redo, grid snap.
- [ ] Arena resize up to 44 × 30; camera and border follow.
- [ ] Save / Open / New; unsaved-changes prompt; maps show up in Game settings.
- [ ] Play-test and "Back to editor" keeps your edits; Birdbath item works in your own maps.

## 11. Menus and match flow
- [ ] Title → character select (join, pick bird and color, ready) → settings → match → results → rematch,
      character select or title.
- [ ] Settings: rounds, CPU count and difficulty, power-ups, map list (built-ins and your maps), volume.
- [ ] Countdown, round banners, scoreboard, results stats; pause menu; HUD panels dim on KO and pop on changes;
      leaves drifting in the menus.

## 12. Sound (listen-through)
- [ ] Every event audible and fitting: draw creak, shot, impacts (wood, stone, soft), KO punch, parry clang and
      ring, stun, eggs, explosion, power-ups, round bells, UI clicks, editor sounds, **shrike drop whoosh (new)**,
      splashes.
- [ ] Mix: KOs and explosions loudest, UI soft, footsteps not annoying with 4 birds.
- [ ] Stand-ins acceptable? Shot swish (no twang), explosion thump, whizz, water "plip".
- [ ] Volume setting works and is remembered.

## 13. Performance and display
- [ ] Steady frame rate with 4 birds, especially on Birdbath (bigger map, water).
- [ ] High-refresh screens (120 Hz): character movement still updates at 60 Hz (no physics interpolation).
      Smooth enough? The KO tumble is now render-rate.
- [ ] Window resize and fullscreen; HUD and menus scale.

## 14. Art style exploration (debug keys in an arena)
- [ ] U cycles all 11 styles on both layers; Y changes only the birds' style, P only the world's (try anime birds
      on a watercolor world). The toast names both.
- [ ] Anime with O on: speed lines on dash, a smear on the wing slap, a black-and-white impact frame on a KO.
      O turns them off. Is the impact frame too much in a real match?
- [ ] Watercolor: O toggles pencil lines; birds and arrows stay sharper than the world.
- [ ] Pixel art: no shimmer when the camera shakes; birds and rings readable at 1/3 resolution.
- [ ] Felt and claymation feel playable at 12 fps (the input still runs at 60 Hz).
- [ ] Switching styles mid-match, then R (restart): the style and anime glow survive the reload.

## Not testable yet / open
- [ ] Music: no music pack yet (the Music bus is ready).
- [ ] Desktop export: skipped for now (your choice).
- [ ] Design doc open questions: 5 (KO win mode) and 9 (taunt button).

## 15. Playtest round 2 fixes
- [ ] Switch pad: in game, R / ZR / X shoot, L / ZL / Y shrike, B dash, A melee. In menus A = yes, B = back.
      If A/B are swapped, flip Game settings → Controller.
- [ ] Rumble when the bow reaches full charge (Switch pad).
- [ ] Charge time (0.9 s) feels right; homing a touch stronger; bigger arrows read better.
- [ ] Shrike: the landing ring while drawing, the arc over cover, stun on a near miss. Is the stun radius right?
- [ ] Trifecta splits about halfway: still worth picking up, no longer too strong?
- [ ] Power-ups catch the eye now.
- [ ] Character select: ◀ ▶ bird → A → ◀ ▶ color → A ready; B steps back.
- [ ] Overtime: timer at 2:00 into a round, egg rain at 2:30; shadows readable; rounds end.
- [ ] Any CPU still pacing back and forth? (Note the map and roughly where.)
- [ ] Sound: no squeak; footsteps quiet; nothing too loud or too quiet.
- [ ] Fullscreen from Game settings → Display, or Alt+Enter. If it still doesn't scale, are you running from
      the Godot editor (embedded Game tab)?
- [ ] Round and match wins: the winner celebrates (camera zooms in) before the scoreboard; it zooms back out next round.
- [ ] Switch B dashes without opening the pause menu; + pauses.
- [ ] Character select: random reactions while scrolling, the celebration when you lock in a bird.
- [ ] After being knocked out, steer your ghost with the stick while it floats up. Fun? Too long on screen?
