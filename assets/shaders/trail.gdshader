// Arrow trail ribbon. Vertex color carries the player color and alpha fade.
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled, blend_mix;

void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a;
}
