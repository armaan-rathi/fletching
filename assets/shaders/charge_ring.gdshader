// Ground ring around a bird that fills clockwise with draw charge and flashes at full charge.
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled, blend_mix;

uniform vec4 color : source_color = vec4(1.0, 0.35, 0.35, 1.0);
uniform float charge : hint_range(0.0, 1.0) = 0.0;
uniform float inner = 0.74;
uniform float outer = 0.9;
uniform float full_flash = 0.0; // 1 -> 0 after reaching full charge

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float ring = smoothstep(inner - 0.02, inner, r) * (1.0 - smoothstep(outer, outer + 0.02, r));
	// Angle from "forward" (-V), clockwise, 0..1.
	float a = fract(atan(p.x, -p.y) / 6.28318 + 1.0);
	float filled = step(a, charge);
	vec3 c = mix(color.rgb * 0.5, color.rgb, filled);
	c = mix(c, vec3(1.0), full_flash);
	ALBEDO = c;
	ALPHA = ring * mix(0.25, 0.95, filled);
}
