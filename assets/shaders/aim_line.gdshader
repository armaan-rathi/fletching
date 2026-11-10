// Dashed aim line on the ground in front of a drawing bird. The quad's UV.y runs from the bird
// (UV.y = 1) to the predicted landing point (UV.y = 0). `length_m` keeps dashes a constant size.
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled, blend_mix;

uniform vec4 color : source_color = vec4(1.0, 0.35, 0.35, 1.0);
uniform float length_m = 8.0;
uniform float dash_m = 0.45;
uniform float charge : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float along = (1.0 - UV.y) * length_m; // meters from the bird
	float across = abs(UV.x - 0.5) * 2.0;
	float dash = step(0.45, fract(along / dash_m - TIME * 2.0));
	// Arrowhead-ish taper at the far end, soft start near the bird.
	float tip = smoothstep(0.0, 0.6, length_m - along);
	float width = mix(0.35, 1.0, tip);
	float body = 1.0 - smoothstep(width - 0.15, width, across);
	float fade_in = smoothstep(0.5, 1.2, along);
	float end_cap = 1.0 - smoothstep(length_m - 0.25, length_m, along);
	ALBEDO = mix(color.rgb, vec3(1.0), charge >= 0.999 ? 0.35 : 0.0);
	ALPHA = body * dash * fade_in * end_cap * mix(0.45, 0.9, charge);
}
