// Subtle screen-space vignette (cool, dark) that pulls the eye to the clearing.
shader_type canvas_item;

uniform vec4 tint : source_color = vec4(0.10, 0.12, 0.20, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.35;
uniform float inner : hint_range(0.0, 1.5) = 0.55;
uniform float outer : hint_range(0.0, 2.0) = 1.25;

void fragment() {
	vec2 p = (UV - 0.5) * vec2(1.0, 0.9) * 2.0;
	float v = smoothstep(inner, outer, length(p));
	COLOR = vec4(tint.rgb, v * strength);
}
