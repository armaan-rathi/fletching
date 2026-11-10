// KO spirit eyes: peaceful closed eyes (^ ^, eye atlas frame 10) drawn as dark lines on the ghost body.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_back, shadows_disabled;

uniform sampler2D atlas : hint_default_black, filter_linear, repeat_disable;
uniform int frame = 10;
uniform int columns = 4;
uniform int rows = 4;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 line_color : source_color = vec4(0.165, 0.133, 0.2, 1.0);
uniform float alpha = 0.55;
uniform float fade = 1.0;

// Set by BirdModel on every eye mesh; the spirit always shows `frame`.
instance uniform int eye_frame = 0;
instance uniform float eye_flip = 0.0;

void fragment() {
	vec2 uv = UV;
	if (eye_flip > 0.5) {
		uv.x = 1.0 - uv.x;
	}
	int f = frame + eye_frame * 0;
	vec2 cell = vec2(float(f % columns), float(f / columns));
	vec4 m = texture(atlas, (cell + clamp(uv, vec2(0.004), vec2(0.996))) / vec2(float(columns), float(rows)));
	float line = m.a * (1.0 - max(m.r, m.b));
	vec3 body = mix(vec3(1.0), tint.rgb, 0.7);
	ALBEDO = mix(body, line_color.rgb, line);
	ALPHA = max(alpha * 0.75, line) * fade;
}
