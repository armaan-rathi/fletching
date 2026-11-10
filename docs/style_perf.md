# Art style performance log

Setup: a live 4-CPU match on the Aviary (power-ups on) with a particle burst every 0.3 s (feathers, an explosion
and dust), 1600 × 900 window, VSync off, 4 s per row. Anime runs with its FX extras on (the CPUs dash, slap and
get knocked out, so speed lines, smears and impact frames fire). Machine: Apple M3 Pro (Metal). Tool:
`tools/style_perf.gd` (the Birds / World columns are the character and environment styles).

**Read this first:**
- This Mac's display path caps at about 80 fps even with VSync off, the same cap Stage 6's performance check hit.
- GPU timestamps aren't exposed on this Metal setup, so the GPU ms column reads 0.
- **At native resolution every style and hybrid holds the cap.**
- To push the GPU, the second run renders the 3D view at 2× (4× the pixels, about a 4K frame). That is where the
  styles separate:
  - The full-screen scene passes cost the most: anime (~70 fps), watercolor (~66) and colored line art (~76).
    These styles copy the screen with mipmaps and read depth/normals; anime also turns on glow.
  - The anime birds + watercolor world hybrid is the heaviest (~62 fps): both scene passes plus glow.
  - Everything else holds the cap. Pixel art always renders 3D at 1/3 resolution, so the 2× setting doesn't
    apply to it.
- 1% lows (40–68 fps) move run to run with the particle bursts and KOs (hit-stop), not with the style.
- CPU render time is about 0.65–0.75 ms per frame for every style.
- Felt and claymation run at 12 fps by design (stop-motion). With the cap lifted they measure like the others.
  While stepping, their CPU render time per rendered frame reads higher (~1.6–1.9 ms, also in the earlier felt
  run). Not investigated; it's still small at 12 frames a second.
- Re-run on the slowest target machine before committing to a style.

## 1× (native)

| Birds | World | Tilt-shift | Avg FPS | 1% low FPS | GPU ms/frame | CPU render ms/frame |
|---|---|---|---|---|---|---|
| Baseline toon | Baseline toon | off | 80 | 38 | 0.00 | 0.64 |
| Baseline toon | Baseline toon | on | 80 | 44 | 0.00 | 0.68 |
| Field guide | Field guide | off | 80 | 51 | 0.00 | 0.67 |
| Field guide | Field guide | on | 81 | 64 | 0.00 | 0.66 |
| Felt stop-motion | Felt stop-motion | off | 12 | 11 | 0.00 | 1.70 |
| Felt stop-motion | Felt stop-motion | on | 12 | 11 | 0.00 | 1.77 |
| Risograph | Risograph | off | 80 | 43 | 0.00 | 0.72 |
| Risograph | Risograph | on | 80 | 64 | 0.00 | 0.70 |
| Sketchbook | Sketchbook | off | 80 | 68 | 0.00 | 0.69 |
| Sketchbook | Sketchbook | on | 80 | 67 | 0.00 | 0.67 |
| Anime | Anime | off | 80 | 52 | 0.00 | 0.68 |
| Anime | Anime | on | 80 | 60 | 0.00 | 0.68 |
| Watercolor | Watercolor | off | 80 | 65 | 0.00 | 0.67 |
| Watercolor | Watercolor | on | 81 | 58 | 0.00 | 0.72 |
| Woodblock print | Woodblock print | off | 80 | 66 | 0.00 | 0.68 |
| Woodblock print | Woodblock print | on | 81 | 62 | 0.00 | 0.70 |
| 3D pixel art | 3D pixel art | off | 80 | 50 | 0.00 | 0.69 |
| 3D pixel art | 3D pixel art | on | 81 | 49 | 0.00 | 0.71 |
| Claymation | Claymation | off | 12 | 11 | 0.00 | 1.57 |
| Claymation | Claymation | on | 12 | 12 | 0.00 | 1.86 |
| Colored line art | Colored line art | off | 80 | 58 | 0.00 | 0.69 |
| Colored line art | Colored line art | on | 80 | 51 | 0.00 | 0.66 |
| Felt stop-motion | Felt stop-motion (12 fps cap lifted) | off | 80 | 58 | 0.00 | 0.70 |
| Claymation | Claymation (12 fps cap lifted) | off | 80 | 56 | 0.00 | 0.68 |
| Anime | Watercolor | off | 80 | 54 | 0.00 | 0.69 |
| Claymation | Woodblock print (12 fps cap lifted) | off | 81 | 66 | 0.00 | 0.68 |
| 3D pixel art | Baseline toon | off | 82 | 47 | 0.00 | 0.73 |
| Colored line art | Sketchbook | off | 80 | 59 | 0.00 | 0.69 |

## 2× 3D render scale (4× pixels)

| Birds | World | Tilt-shift | Avg FPS | 1% low FPS | GPU ms/frame | CPU render ms/frame |
|---|---|---|---|---|---|---|
| Baseline toon | Baseline toon | off | 80 | 54 | 0.00 | 0.64 |
| Baseline toon | Baseline toon | on | 80 | 42 | 0.00 | 0.67 |
| Field guide | Field guide | off | 80 | 54 | 0.00 | 0.64 |
| Field guide | Field guide | on | 80 | 62 | 0.00 | 0.65 |
| Felt stop-motion | Felt stop-motion | off | 12 | 11 | 0.00 | 1.59 |
| Felt stop-motion | Felt stop-motion | on | 12 | 12 | 0.00 | 1.89 |
| Risograph | Risograph | off | 80 | 53 | 0.00 | 0.67 |
| Risograph | Risograph | on | 80 | 57 | 0.00 | 0.66 |
| Sketchbook | Sketchbook | off | 81 | 62 | 0.00 | 0.67 |
| Sketchbook | Sketchbook | on | 80 | 64 | 0.00 | 0.68 |
| Anime | Anime | off | 69 | 54 | 0.00 | 0.68 |
| Anime | Anime | on | 71 | 61 | 0.00 | 0.72 |
| Watercolor | Watercolor | off | 66 | 54 | 0.00 | 0.70 |
| Watercolor | Watercolor | on | 66 | 51 | 0.00 | 0.71 |
| Woodblock print | Woodblock print | off | 91 | 65 | 0.00 | 0.63 |
| Woodblock print | Woodblock print | on | 80 | 58 | 0.00 | 0.64 |
| 3D pixel art | 3D pixel art | off | 81 | 54 | 0.00 | 0.67 |
| 3D pixel art | 3D pixel art | on | 80 | 50 | 0.00 | 0.72 |
| Claymation | Claymation | off | 12 | 11 | 0.00 | 1.68 |
| Claymation | Claymation | on | 12 | 11 | 0.00 | 1.62 |
| Colored line art | Colored line art | off | 76 | 61 | 0.00 | 0.69 |
| Colored line art | Colored line art | on | 75 | 57 | 0.00 | 0.74 |
| Felt stop-motion | Felt stop-motion (12 fps cap lifted) | off | 80 | 55 | 0.00 | 0.65 |
| Claymation | Claymation (12 fps cap lifted) | off | 81 | 58 | 0.00 | 0.67 |
| Anime | Watercolor | off | 62 | 52 | 0.00 | 0.70 |
| Claymation | Woodblock print (12 fps cap lifted) | off | 84 | 55 | 0.00 | 0.64 |
| 3D pixel art | Baseline toon | off | 80 | 58 | 0.00 | 0.71 |
| Colored line art | Sketchbook | off | 78 | 58 | 0.00 | 0.70 |
