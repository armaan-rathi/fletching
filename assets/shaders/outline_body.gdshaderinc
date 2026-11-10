// Body of the inverted-hull outline shader, shared by outline.gdshader and outline_character.gdshader.
#include "res://assets/shaders/canopy_fade.gdshaderinc"
#include "res://assets/shaders/art_style.gdshaderinc"

varying vec3 ol_world;
varying vec3 ol_normal;

global uniform vec4 toon_outline_color;

uniform float outline_width : hint_range(0.0, 0.2) = 0.03;
// Optional tint (e.g. a player's color) blended over the global outline color.
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 0.0);
// Birds: per-vertex width factor in UV2.x (bird_base.glb's second UV map), so feather and toe tips taper to
// crisp points. Off for everything else (meshes without that UV map would lose their outline).
uniform bool vertex_width = false;
// The color of the surface this outlines (styles that tint lines by the color underneath). ToonMaterials sets
// base_color (alpha 1); textured props sample the same texture (band 1 tinted like the surface). Neither set:
// the plain ink color.
uniform vec4 base_color : source_color = vec4(0.0);
uniform bool base_use_texture = false;
uniform sampler2D base_texture : source_color, filter_linear, repeat_disable, hint_default_white;
uniform vec4 base_band_tint_1 : source_color = vec4(1.0);

void vertex() {
	float scale = length(MODEL_MATRIX[0].xyz);
	float w = (vertex_width && UV2.x > 0.0) ? clamp(UV2.x, 0.0, 1.0) : 1.0; // 0 = no width data: full width
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 nw = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (art_style == 1) {
		w *= 0.8; // finer ink
	} else if (art_style == 2) {
		w *= 0.75;
	} else if (art_style == 3) {
		w *= 0.7;
	} else if (art_style == 4) {
		// Boiling pencil line: width wobbles along the line and re-draws ~8 times a second.
		float step_t = floor(TIME * 8.0);
		w *= 0.55 + 0.9 * as_noise(wp.xz * 9.0 + wp.y * 7.0 + step_t * 17.3);
	} else if (art_style == 5) {
		// Weighted brush line: thin on top (lit side), heavy along the underside.
		w *= mix(0.55, 1.5, smoothstep(0.35, -0.55, nw.y));
	} else if (art_style == 6) {
		// Optional pencil lines (O); otherwise the shapes are carried by the washes and edge darkening.
		float step_t = floor(TIME * 8.0);
		w *= ((art_style_opts & 1) != 0) ? 0.35 + 0.45 * as_noise(wp.xz * 8.0 + wp.y * 6.0 + step_t * 11.7) : 0.0;
	} else if (art_style == 7) {
		w *= 1.7 * (0.8 + 0.4 * as_noise(wp.xz * 4.0 + wp.y * 3.0)); // bold, carved
	} else if (art_style == 8) {
		w *= 2.2; // survives the low-res render as a crisp 1-pixel line
	} else if (art_style == 9) {
		w *= 0.5; // just a crease where clay pieces meet
	} else if (art_style == 10) {
		w *= 1.15;
	}
	VERTEX += normalize(NORMAL) * outline_width * w / max(scale, 0.001);
	ol_world = wp;
	ol_normal = nw;
	canopy_world_y = canopy_height(VERTEX, MODEL_MATRIX);
}

vec3 ol_base(vec2 uv, vec3 fallback) {
	if (base_use_texture) {
		vec3 c = texture(base_texture, uv).rgb;
		return int(uv.y * 4.0) == 1 ? c * base_band_tint_1.rgb : c;
	}
	return base_color.a > 0.5 ? base_color.rgb : fallback;
}

void fragment() {
	canopy_discard(FRAGCOORD.xy);
	// Global colors are not sRGB-decoded automatically, so decode here.
	vec3 ink = pow(toon_outline_color.rgb, vec3(2.2));
	if (art_style == 1) {
		ink = as_lin(vec3(0.22, 0.15, 0.1)); // sepia ink
	} else if (art_style == 2) {
		// Stitched felt edge: dashed thread over a darker felt rim.
		float dash = step(0.5, fract((ol_world.x + ol_world.z) * 9.0 + ol_world.y * 9.0));
		ink = mix(as_lin(vec3(0.2, 0.15, 0.13)), as_lin(vec3(0.93, 0.88, 0.76)), dash);
	} else if (art_style == 3) {
		ink = as_lin(vec3(0.24, 0.42, 0.78)); // riso blue ink
	} else if (art_style == 4) {
		ink = as_lin(vec3(0.27, 0.27, 0.3)); // graphite
	} else if (art_style == 5) {
		ink = mix(ink, as_line_from(ol_base(UV, ink)), 0.35); // dark lines with a hint of the local color
	} else if (art_style == 6) {
		ink = as_lin(vec3(0.34, 0.33, 0.36)); // soft pencil
	} else if (art_style == 7) {
		ink = as_lin(vec3(0.1, 0.09, 0.13)); // sumi ink
	} else if (art_style == 8) {
		vec3 b = ol_base(UV, vec3(-1.0));
		ink = b.r < 0.0 ? as_lin(vec3(0.08, 0.07, 0.1)) : mix(as_line_from(b), vec3(0.0), 0.45); // sel-out
	} else if (art_style == 9) {
		ink = as_line_from(ol_base(UV, as_lin(vec3(0.5, 0.4, 0.35)))) * 1.3;
	} else if (art_style == 10) {
		ink = as_line_from(ol_base(UV, ink));
	}
	ALBEDO = mix(ink, tint.rgb, tint.a);
}
