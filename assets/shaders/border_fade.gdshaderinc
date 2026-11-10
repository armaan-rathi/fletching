// Darkens and desaturates surfaces outside the arena so the clearing is the brightest area
// (a world-space "vignette"). Arena bounds and strength are shader globals set per map.

global uniform vec2 arena_half_size;
global uniform float border_darken;      // 0..1 brightness lost far outside the arena
global uniform float border_desaturate;  // 0..1 saturation lost far outside the arena
global uniform float border_fade_distance; // m past the edge where the full effect is reached

float border_sd_round_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vec3 border_fade(vec3 col, vec3 world_pos) {
	float d = border_sd_round_box(world_pos.xz, arena_half_size, 2.0);
	float f = smoothstep(0.5, max(border_fade_distance, 0.6), d);
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum), f * border_desaturate);
	return col * (1.0 - f * border_darken);
}
