// Art style exploration: full-screen post pass (drawn under the HUD, over the 3D view and particles). Frame-level
// effects follow the ENVIRONMENT style (see scripts/art_style.gd); per-layer effects live in the scene passes.
//   1 field guide: warm paper tone + paper grain     2 felt: soft grain + gentle vignette
//   3 risograph: ink misregistration + heavy grain   4 sketchbook: paper grain
//   6 watercolor: cold-press paper texture           7 woodblock: washi fibers + bokashi (soft gradient) bands
//   8 pixel art: pixelation (render is already low-res) + palette + ordered dither (whole frame)
//   9 claymation: warm grade, grain, vignette        10 colored line: light paper tone
//   tilt_shift (any style): top and bottom of the frame blur out (miniature look), slight saturation boost.
//   impact (anime FX, any style): a 2-phase black-and-white impact frame with radial lines on a KO.
shader_type canvas_item;

#include "res://assets/shaders/style_palette.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform int style = 0;
uniform bool tilt_shift = false;
uniform float focus_center = 0.55; // screen v of the sharp band
uniform float focus_width = 0.16;
uniform float pixel_size = 3.0;
uniform float impact = 0.0;        // 1 -> 0 over the impact frame
uniform vec2 impact_center = vec2(0.5);

float ps_hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float ps_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(ps_hash(i), ps_hash(i + vec2(1.0, 0.0)), u.x), mix(ps_hash(i + vec2(0.0, 1.0)), ps_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

vec3 sample_scene(vec2 uv, float blur) {
	if (blur <= 0.01) {
		return textureLod(screen_tex, uv, 0.0).rgb;
	}
	// Mip blur with a small rotated tap pattern so it doesn't look blocky.
	vec2 px = exp2(blur) * 0.6 / vec2(textureSize(screen_tex, 0));
	vec3 c = textureLod(screen_tex, uv, blur).rgb * 0.4;
	c += textureLod(screen_tex, uv + vec2(px.x, px.y * 0.5), blur).rgb * 0.15;
	c += textureLod(screen_tex, uv - vec2(px.x, px.y * 0.5), blur).rgb * 0.15;
	c += textureLod(screen_tex, uv + vec2(-px.x * 0.5, px.y), blur).rgb * 0.15;
	c += textureLod(screen_tex, uv - vec2(-px.x * 0.5, px.y), blur).rgb * 0.15;
	return c;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 fp = FRAGCOORD.xy;
	vec2 cell = floor(fp / pixel_size);
	if (style == 8) {
		uv = (cell + 0.5) * pixel_size / vec2(textureSize(screen_tex, 0));
	}
	float blur = 0.0;
	if (tilt_shift) {
		blur = smoothstep(focus_width, focus_width + 0.32, abs(uv.y - focus_center)) * 3.2;
	}
	vec3 c;
	if (style == 3) {
		// Misregistration: each ink plate slightly off (channels sampled with small offsets).
		vec2 o = vec2(0.0012, 0.0007);
		c = vec3(sample_scene(uv + o, blur).r, sample_scene(uv, blur).g, sample_scene(uv - o * vec2(0.6, 1.4), blur).b);
	} else {
		c = sample_scene(uv, blur);
	}
	float grain = ps_hash(fp + floor(TIME * 12.0) * 7.13) - 0.5;
	float paper = ps_noise(fp * 0.08) * 0.6 + ps_noise(fp * 0.35) * 0.4;
	if (style == 1) {
		c = mix(c, c * vec3(1.03, 1.0, 0.92), 0.6);         // warm paper tone
		c *= 0.95 + 0.07 * paper + 0.03 * grain;
	} else if (style == 2) {
		c *= 0.97 + 0.04 * grain;
		vec2 q = (uv - 0.5) * vec2(1.0, 0.9) * 2.0;
		c *= 1.0 - 0.18 * smoothstep(0.6, 1.4, length(q));
	} else if (style == 3) {
		c *= 0.93 + 0.1 * paper + 0.08 * grain;
	} else if (style == 4) {
		c *= 0.96 + 0.06 * paper + 0.02 * grain;
	} else if (style == 6) {
		// Cold-press paper: a bumpy tooth that catches pigment in its pits, lit from the top left.
		float tooth = ps_noise(fp * 0.22) * 0.65 + ps_noise(fp * 0.6) * 0.35;
		float relief = tooth - ps_noise((fp + vec2(1.5, 1.5)) * 0.22) * 0.65 - ps_noise((fp + vec2(1.5, 1.5)) * 0.6) * 0.35;
		c *= 0.94 + 0.08 * tooth + 0.08 * relief;
		c = mix(c, vec3(0.99, 0.97, 0.92), 0.06);
	} else if (style == 7) {
		// Washi: long fibers and a warm paper ground; bokashi: soft hand-wiped gradients at the top (prussian blue)
		// and the bottom (warm umber) of the print.
		float fib = smoothstep(0.78, 0.95, ps_noise(vec2(fp.x * 0.012 + fp.y * 0.05, fp.y * 0.6 - fp.x * 0.08)));
		c = mix(c, vec3(0.97, 0.94, 0.86), 0.18 * fib);
		c *= 0.96 + 0.06 * paper;
		float top = 1.0 - smoothstep(0.0, 0.36, uv.y);
		float bot = smoothstep(0.82, 1.0, uv.y);
		c = mix(c, c * vec3(0.32, 0.46, 0.7), top * 0.55);
		c = mix(c, c * vec3(0.62, 0.5, 0.4), bot * 0.4);
	} else if (style == 8) {
		c = as_palette(c, cell);
	} else if (style == 9) {
		c = mix(c, c * vec3(1.05, 1.0, 0.92), 0.5);
		c *= 0.97 + 0.05 * grain;
		vec2 q = (uv - 0.5) * vec2(1.0, 0.9) * 2.0;
		c *= 1.0 - 0.2 * smoothstep(0.6, 1.4, length(q));
	} else if (style == 10) {
		c *= 0.985 + 0.03 * paper;
	}
	if (tilt_shift) {
		float l = dot(c, vec3(0.3, 0.59, 0.11));
		c = mix(vec3(l), c, 1.15); // toy-like saturation
	}
	if (impact > 0.0) {
		// Impact frame: hard black-and-white threshold (inverted in the first half), radial burst lines.
		float l = dot(c, vec3(0.3, 0.59, 0.11));
		float v = step(0.48, l);
		vec2 d = (SCREEN_UV - impact_center) * vec2(textureSize(screen_tex, 0)) / float(textureSize(screen_tex, 0).y);
		float ang = atan(d.y, d.x);
		float rays = step(0.72, ps_noise(vec2(ang * 22.0, floor(TIME * 40.0) * 3.7))) * smoothstep(0.12, 0.3, length(d));
		if (impact > 0.5) {
			v = 1.0 - v;
		}
		v = mix(v, 1.0 - v, rays); // burst lines always contrast with what's under them
		c = vec3(v);
	}
	COLOR = vec4(c, 1.0);
}
