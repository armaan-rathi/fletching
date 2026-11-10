// Level editor: faint 1 m grid over the arena floor (shown while snapping is on).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec2 half_size = vec2(10.0, 7.0);
uniform float cell = 1.0;
uniform float strength = 0.22;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz / cell;
	vec2 g = abs(fract(p - 0.5) - 0.5) / fwidth(p);
	float line = 1.0 - clamp(min(g.x, g.y), 0.0, 1.0);
	// Center lines a little stronger.
	vec2 c = abs(wp.xz) / fwidth(wp.xz);
	float axis = 1.0 - clamp(min(c.x, c.y) * 0.6, 0.0, 1.0);
	vec2 m = abs(wp.xz) - half_size;
	float inside = 1.0 - step(0.0, max(m.x, m.y));
	ALBEDO = vec3(1.0, 0.97, 0.88);
	ALPHA = max(line * strength, axis * strength * 1.8) * inside;
}
