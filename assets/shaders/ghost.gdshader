// KO spirit body: translucent, unshaded, tinted in the player's color, with a soft glow at the edges.
// Purely visual: no shadows; writes depth only so the ghost's own parts don't stack (it draws after
// opaque geometry, so it never hides birds or triggers their x-ray).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_back, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha = 0.55;  // body opacity
uniform float fade = 1.0;    // 0..1 overall (fade in/out)

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	vec3 body = mix(vec3(1.0), tint.rgb, 0.7);
	vec3 edge = mix(tint.rgb, vec3(1.0), 0.35);
	ALBEDO = mix(body, edge, rim) * (1.0 + rim * 0.5);
	ALPHA = clamp(alpha * 0.75 + rim * 0.6, 0.0, 1.0) * fade;
}
