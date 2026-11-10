// Art style scene pass (scripts/art_style.gd): a full-screen quad drawn first in the transparent pass, reading
// the opaque scene (color, depth, normals). The env variant only touches stencil 0 (scenery), the char variant
// only stencil != 0 (birds = 1..4, flying arrows = 5), so the two layers can be styled differently. Particles and
// x-ray silhouettes draw after it. Styles here:
//   5 anime / 10 colored line: inner lines from normal + depth breaks (dark / tinted by the local color)
//   6 watercolor: wobbly sampling, color bleeding and pigment pooled at wash edges (strong on scenery, light on
//     birds and arrows so they stay crisp)
//   8 pixel art (char layer, when the environment isn't pixel art): pixelated + palette birds
#include "res://assets/shaders/art_style.gdshaderinc"
#include "res://assets/shaders/style_palette.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest;
uniform int style = 0;
uniform bool character_layer = false;
uniform float pixel_size = 3.0;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.5, 1.0);
}

vec3 sc_normal(vec2 uv) {
	return texture(normal_tex, uv).xyz * 2.0 - 1.0;
}

float sc_lum(vec3 c) {
	return dot(c, vec3(0.3, 0.59, 0.11));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = 1.0 / vec2(textureSize(screen_tex, 0));
	vec2 fp = FRAGCOORD.xy;
	vec3 c = textureLod(screen_tex, uv, 0.0).rgb;
	if (style == 5 || style == 10) {
		vec3 n0 = sc_normal(uv);
		float d0 = texture(depth_tex, uv).r;
		float en = 0.0;
		float ed = 0.0;
		for (int i = 0; i < 4; i++) {
			vec2 o = (i == 0 ? vec2(1.0, 0.0) : i == 1 ? vec2(-1.0, 0.0) : i == 2 ? vec2(0.0, 1.0) : vec2(0.0, -1.0)) * px;
			en = max(en, length(n0 - sc_normal(uv + o)));
			ed = max(ed, abs(d0 - texture(depth_tex, uv + o).r));
		}
		// Depth breaks (a wing in front of the body, a log on the ground) and only sharp normal creases, so small
		// things (feathers, grass) don't turn solid. Birds: finer depth threshold (they're small).
		vec2 dt = character_layer ? vec2(0.0007, 0.0014) : vec2(0.002, 0.004);
		float edge = max(smoothstep(1.0, 1.3, en), smoothstep(dt.x, dt.y, ed));
		vec3 line = style == 10 ? as_line_from(c) : c * vec3(0.3, 0.27, 0.34);
		c = mix(c, line, edge * 0.8);
	} else if (style == 6) {
		float wob = character_layer ? 1.0 : 3.5;
		vec2 w = (vec2(as_noise(fp * 0.03), as_noise(fp * 0.03 + 17.0)) - 0.5) * 2.0 * wob * px;
		vec3 sharp = textureLod(screen_tex, uv + w, 0.0).rgb;
		vec3 soft = textureLod(screen_tex, uv + w * 1.8, character_layer ? 0.8 : 2.2).rgb;
		vec3 wide = textureLod(screen_tex, uv + w, character_layer ? 2.0 : 3.6).rgb;
		c = mix(sharp, soft, character_layer ? 0.2 : 0.6);
		// Pigment pools where a wash meets a lighter area: darken the darker side of every color edge.
		float pool = smoothstep(0.0, 0.05, sc_lum(wide) - sc_lum(sharp));
		c *= 1.0 - (character_layer ? 0.35 : 0.55) * pool;
	} else if (style == 8) {
		vec2 cell = floor(fp / pixel_size);
		vec3 s = textureLod(screen_tex, (cell + 0.5) * pixel_size * px, 0.0).rgb;
		c = as_lin(as_palette(as_srgb(s), cell));
	}
	ALBEDO = c;
	ALPHA = 1.0;
}
