// Arena ground: grassy clearing inside a rounded rectangle, fading through forest-floor dirt
// into dark undergrowth beyond the edge so the view never shows empty space. Toon lit.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

#include "res://assets/shaders/toon_lighting.gdshaderinc"
#include "res://assets/shaders/border_fade.gdshaderinc"

uniform float corner_radius = 2.0;
uniform vec4 grass_color : source_color = vec4(0.553, 0.749, 0.353, 1.0); // #8DBF5A
uniform vec4 moss_color : source_color = vec4(0.310, 0.498, 0.227, 1.0);  // #4F7F3A (used past the edge)
// Clearing patches are lighter/warmer than the grass so they never read as shadows.
uniform vec4 patch_light_color : source_color = vec4(0.659, 0.784, 0.392, 1.0); // #A8C864
uniform vec4 patch_warm_color : source_color = vec4(0.596, 0.737, 0.353, 1.0);  // #98BC5A
uniform vec4 dirt_color : source_color = vec4(0.612, 0.478, 0.322, 1.0);  // #9C7A52
uniform vec4 deep_color : source_color = vec4(0.184, 0.365, 0.227, 1.0);  // #2F5D3A
uniform float patch_scale = 0.38;
// Optional trampled dirt patch inside the clearing (x, z, radius); radius 0 = none. Aviary: under the big tree.
uniform vec3 dirt_spot = vec3(0.0);
// More trampled dirt patches (x, z, radius), used by editor-made maps.
uniform int dirt_count = 0;
uniform vec3 dirt_spots[16];
uniform vec4 trampled_color : source_color = vec4(0.71, 0.66, 0.43, 1.0); // #B5A86E
uniform float edge_width = 1.4;   // dirt band past the clearing edge
uniform float fade_distance = 7.0; // dirt -> deep undergrowth

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return value_noise(p) * 0.6 + value_noise(p * 2.13 + 7.1) * 0.3 + value_noise(p * 4.7 - 3.3) * 0.1;
}

float sd_round_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float n = fbm(p * patch_scale);
	// Wobble the clearing edge so it doesn't look like a perfect rectangle.
	float d = sd_round_box(p, arena_half_size, corner_radius) + (n - 0.5) * 1.2;

	// Flat, posterized moss patches inside the clearing.
	float n2 = value_noise(p * 0.9 + 13.0);
	vec3 inside = grass_color.rgb;
	inside = mix(inside, patch_warm_color.rgb, step(0.7, n) * 0.7);
	inside = mix(inside, patch_light_color.rgb, step(0.83, n2) * 0.6);

	float sd = 1e5;
	if (dirt_spot.z > 0.0) {
		sd = length(p - dirt_spot.xy) - dirt_spot.z;
	}
	for (int i = 0; i < min(dirt_count, 16); i++) {
		sd = min(sd, length(p - dirt_spots[i].xy) - dirt_spots[i].z);
	}
	if (sd < 1e4) {
		sd += (n - 0.5) * 0.9;
		inside = mix(inside, trampled_color.rgb, (1.0 - smoothstep(-0.05, 0.05, sd)) * 0.85);
	}
	float to_dirt = smoothstep(-0.05, 0.05, d);
	float to_deep = smoothstep(edge_width, edge_width + fade_distance, d);
	vec3 outside = mix(dirt_color.rgb, deep_color.rgb * 0.75, to_deep);
	outside = mix(outside, deep_color.rgb * 0.8, step(0.55, n) * smoothstep(0.0, edge_width, d) * 0.6);

	vec3 gcol = mix(inside, outside, to_dirt);
	if (art_style == 1) {
		// Watercolor ground: large soft washes with darker pooled edges.
		float w = as_fbm(p * 0.22 + 3.0);
		gcol *= 0.86 + 0.28 * w;
		gcol *= 1.0 - 0.12 * smoothstep(0.42, 0.5, w) * (1.0 - smoothstep(0.5, 0.58, w));
	}
	gcol = as_style_albedo(gcol, world_pos, FRAGCOORD.xy);
	if (art_style == 9) {
		NORMAL = as_bump(NORMAL, VERTEX, as_clay_height(world_pos, floor(TIME * 12.0)) * 1.6);
	}
	ALBEDO = border_fade(gcol, world_pos);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
