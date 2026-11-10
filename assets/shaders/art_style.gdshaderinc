// Art style exploration (debug keys: U cycles both layers, Y characters only, P environment only, O style option,
// I tilt-shift; see scripts/art_style.gd). Characters and environment have their own global switch so hybrids
// can be tested: shaders that `#define AS_CHARACTER` before including this (birds, their bows/quivers, eyes,
// flying arrows) read `art_style_char`, everything else reads `art_style_env`. No material or asset rebuilds.
//   0 baseline toon (the approved look, untouched)
//   1 field guide   (watercolor washes, ink crosshatch in shade, sepia ink outlines; paper grain in post)
//   2 felt          (fuzzy fibers, soft wrap light, stitched outlines; 12 fps stop-motion in ArtStyle)
//   3 risograph     (3 inks + paper overprints, halftone shade, blue ink outlines; misregistration in post)
//   4 sketchbook    (paper + pastel tint, graphite hatching, boiling pencil outlines)
//   5 anime         (authored shadow colors, smoothed face normals, weighted outlines + inner lines, sharp
//                    highlights, blooming rim; FX extras in Fx/ArtStyle)
//   6 watercolor    (pigment washes, granulation, cool glazed shade, white paper highlights; bleeding, edge
//                    darkening and wobble in the scene pass, birds/arrows less than the environment; option:
//                    pencil lines)
//   7 woodblock     (flat ink colors, bold carved outlines, wood grain and uneven ink; bokashi gradients in post)
//   8 pixel art     (hard bands, thick crisp outlines; low-res render, palette + dither in post, snapped camera)
//   9 claymation    (clay with fingerprints and lumps, waxy soft light; 12 fps stop-motion shared with felt)
//   10 colored line (light fills, outlines tinted from the color underneath)
// Player colors (rings, x-ray, trails, markers, HUD) use their own materials and are never restyled.
#ifndef ART_STYLE_INC
#define ART_STYLE_INC

global uniform int art_style_char;
global uniform int art_style_env;
global uniform int art_style_opts; // bit 0: watercolor pencil lines

#ifdef AS_CHARACTER
#define art_style art_style_char
#else
#define art_style art_style_env
#endif

float as_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float as_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(as_hash(i), as_hash(i + vec2(1.0, 0.0)), u.x), mix(as_hash(i + vec2(0.0, 1.0)), as_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float as_fbm(vec2 p) {
	return as_noise(p) * 0.55 + as_noise(p * 2.07 + 5.3) * 0.3 + as_noise(p * 4.3 - 2.1) * 0.15;
}

vec3 as_lin(vec3 srgb) {
	return pow(srgb, vec3(2.2));
}

vec3 as_srgb(vec3 lin) {
	return pow(clamp(lin, vec3(0.0), vec3(1.0)), vec3(1.0 / 2.2));
}

vec3 as_rgb2hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

vec3 as_hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

// Anime shadow color for an albedo (linear in/out), the same rule ToonMaterials.anime_shade() uses to author
// per-material shades: warm hues shift toward red, the rest toward blue-violet, more saturated and darker;
// whites/greys get a cool lavender. Materials with an authored `anime_shade` use that instead.
vec3 as_anime_shade(vec3 lin) {
	vec3 hsv = as_rgb2hsv(as_srgb(lin));
	if (hsv.y < 0.14) {
		return as_lin(hsv.z * vec3(0.76, 0.74, 0.9));
	}
	if (hsv.x < 0.16 || hsv.x > 0.9) {
		hsv.x = fract(hsv.x - 0.035 + 1.0);
	} else {
		hsv.x += (0.7 - hsv.x) * 0.14;
	}
	hsv.y = clamp(hsv.y * 1.1 + 0.12, 0.0, 1.0);
	hsv.z *= 0.66;
	return as_lin(as_hsv2rgb(hsv));
}

// Line color from the color underneath (linear): same hue, more saturated, much darker.
vec3 as_line_from(vec3 lin) {
	vec3 hsv = as_rgb2hsv(as_srgb(lin));
	hsv.y = clamp(hsv.y * 1.25 + 0.12, 0.0, 1.0);
	hsv.z *= 0.42;
	return as_lin(as_hsv2rgb(hsv));
}

// 1 on hatch lines (screen space, `spacing` px apart, `width` 0..1 of the spacing), anti-aliased.
float as_hatch(vec2 frag, float angle, float spacing, float width) {
	float v = dot(frag, vec2(cos(angle), sin(angle))) / spacing;
	float d = abs(fract(v) - 0.5);
	return 1.0 - smoothstep(0.5 - width * 0.5 - 0.06, 0.5 - width * 0.5 + 0.06, d);
}

// Halftone dot coverage for `amount` 0..1 on a 45° grid of `cell` px.
float as_halftone(vec2 frag, float cell, float amount) {
	vec2 r = vec2(frag.x + frag.y, frag.x - frag.y) * 0.70710678 / cell;
	vec2 c = fract(r) - 0.5;
	float rad = sqrt(clamp(amount, 0.0, 1.0)) * 0.62;
	return 1.0 - smoothstep(rad - 0.06, rad + 0.06, length(c));
}

// Halftone dot coverage on a grid rotated by `angle` (radians), `cell` px.
float as_screen(vec2 frag, float cell, float angle, float amount) {
	float ca = cos(angle);
	float sa = sin(angle);
	vec2 r = vec2(ca * frag.x - sa * frag.y, sa * frag.x + ca * frag.y) / cell;
	vec2 c = fract(r) - 0.5;
	float rad = sqrt(clamp(amount, 0.0, 1.0)) * 0.64;
	return 1.0 - smoothstep(rad - 0.07, rad + 0.07, length(c));
}

// Risograph, 4 inks on cream paper: fills are separated into fluorescent pink, teal and yellow (least squares on
// ink absorption), each posterized to none / one tint / solid and printed as its own halftone screen at its own
// angle; the 4th ink, blue, is the line + shade plate (outlines, shade dots). Overprints come from overlap.
vec3 as_riso(vec3 c, vec2 frag) {
	vec3 paper = vec3(0.96, 0.93, 0.85);
	vec3 pink = vec3(1.0, 0.45, 0.62);
	vec3 teal = vec3(0.0, 0.6, 0.62);
	vec3 yellow = vec3(1.0, 0.86, 0.3);
	vec3 target = pow(clamp(c, vec3(0.0), vec3(1.0)), vec3(1.0 / 2.2));
	mat3 m = mat3(vec3(1.0) - pink / paper, vec3(1.0) - teal / paper, vec3(1.0) - yellow / paper);
	vec3 k = clamp(inverse(m) * (vec3(1.0) - target / paper), vec3(0.0), vec3(1.0));
	// Posterize each ink to none / one halftone tint / solid: mostly flat ink, dots only where a tint is needed.
	k = mix(vec3(0.38), vec3(1.0), step(vec3(0.62), k)) * step(vec3(0.2), k);
	vec3 col = paper;
	col *= mix(vec3(1.0), pink / paper, as_screen(frag, 4.5, 0.2618, k.x));
	col *= mix(vec3(1.0), teal / paper, as_screen(frag, 4.5, 1.309, k.y));
	col *= mix(vec3(1.0), yellow / paper, as_screen(frag, 4.5, 0.0, k.z));
	return as_lin(col);
}

// Claymation surface height (meters): a few thumbprints (whorled ridges) per 35 cm cell plus soft sculpted
// lumps. `step_t` re-sculpts very slightly every stop-motion frame.
float as_clay_height(vec3 p, float step_t) {
	vec3 cs = p / 0.35;
	vec3 cell = floor(cs);
	vec3 r = vec3(as_hash(cell.xy + cell.z * 7.13), as_hash(cell.yz + 3.31), as_hash(cell.zx - 1.77));
	vec3 ctr = cell + 0.3 + 0.4 * r;
	vec3 d = (cs - ctr) * 0.35;
	float e = length(d * vec3(1.0, 1.35, 0.85));
	float ridge = 0.5 + 0.5 * sin(e * 6.2832 / 0.055 + r.x * 6.0);
	float print = smoothstep(0.11, 0.06, e) * step(0.3, r.y);
	float jitter = as_noise(p.xz * 3.0 + step_t * 0.37) * 0.004;
	float lumps = as_fbm(p.xz * 2.6 + p.y * 2.1) * 0.04;
	return lumps + ridge * print * 0.014 + jitter;
}

// Bump-mapped normal from a height field (derivative bump mapping; view-space v and n).
vec3 as_bump(vec3 n, vec3 v, float h) {
	vec3 dpdx = dFdx(v);
	vec3 dpdy = dFdy(v);
	float dhx = dFdx(h);
	float dhy = dFdy(h);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	return normalize(abs(det) * n - grad);
}

// Surface color per style (linear albedo in, linear out). wpos = world position.
vec3 as_style_albedo(vec3 c, vec3 wpos, vec2 frag) {
	if (art_style == 1) {
		vec3 paper = as_lin(vec3(0.97, 0.94, 0.86));
		float g = as_fbm(wpos.xz * 1.7 + wpos.y * 1.3);
		float lum = dot(c, vec3(0.3, 0.59, 0.11));
		c = mix(c, vec3(lum), 0.15);           // a little less saturated, like pigment
		c = mix(paper, c, 0.82 + 0.18 * g);     // uneven wash, paper showing through
		c *= 0.9 + 0.18 * as_fbm(wpos.xz * 9.0); // granulation
	} else if (art_style == 2) {
		// Felt: matte, slightly dusty color with visible mottling and fibers (sized to read at game zoom).
		vec2 q = wpos.xz + vec2(wpos.y * 0.7, -wpos.y * 0.5);
		float mottle = as_fbm(q * 5.0);
		float fib = as_noise(q * 14.0 + as_noise(q * 4.0) * 3.0);
		float lum = dot(c, vec3(0.3, 0.59, 0.11));
		c = mix(c, vec3(lum), 0.2);
		c = c * (0.8 + 0.24 * mottle + 0.16 * fib) + vec3(0.012);
	} else if (art_style == 3) {
		c = as_riso(c, frag);
	} else if (art_style == 4) {
		vec3 paper = as_lin(vec3(0.97, 0.96, 0.92));
		c = mix(paper, c, 0.38);
	} else if (art_style == 5) {
		// Anime: clean, slightly richer flat color.
#ifdef AS_CHARACTER
		float lum = dot(c, vec3(0.3, 0.59, 0.11));
		c = max(mix(vec3(lum), c, 1.12), vec3(0.0));
#endif
	} else if (art_style == 6) {
		// Watercolor: transparent pigment washes, uneven (pooled) density, granulation in the pigment.
		vec3 paper = as_lin(vec3(0.98, 0.96, 0.9));
		vec2 q = wpos.xz + wpos.y * 0.8;
		float wash = as_fbm(q * 0.9 + 11.0);
		float gran = as_noise(frag * 0.45) * 0.6 + as_noise(q * 22.0) * 0.4;
		vec3 pig = mix(paper, c, 0.74 + 0.24 * wash);
		pig *= 0.9 + 0.16 * gran;
		c = pig;
	} else if (art_style == 7) {
		// Woodblock: flat ink, the block's grain printing through, slightly uneven pressure.
		vec3 paper = as_lin(vec3(0.95, 0.91, 0.82));
		vec2 q = wpos.xz + vec2(wpos.y * 0.6, wpos.y * 0.3);
		float wob = as_fbm(q * vec2(0.6, 2.4)) * 2.6;
		float rings = fract((q.x * 0.8 + q.y * 0.25 + wob) * 6.0);
		float grain = smoothstep(0.0, 0.12, rings) * smoothstep(0.5, 0.3, rings);
		float press = smoothstep(0.55, 0.85, as_fbm(q * 1.2 + 7.0));
		c = mix(c, paper, 0.13 * grain + 0.16 * press);
	} else if (art_style == 9) {
		// Clay: saturated, slightly waxy plasticine color.
		float lum = dot(c, vec3(0.3, 0.59, 0.11));
		c = max(mix(vec3(lum), c, 1.15), vec3(0.0)) * 0.95;
	} else if (art_style == 10) {
		c = mix(c, vec3(1.0), 0.05); // slightly lighter fills so the colored lines carry the form
	}
	return c;
}

#endif
