// Body of the eye shader (see eye.gdshader for docs), shared by the per-player stencil variants.
#include "res://assets/shaders/toon_lighting.gdshaderinc"

uniform sampler2D atlas : hint_default_black, filter_linear, repeat_disable;
uniform int columns = 4;
uniform int rows = 4;
uniform vec4 iris_color : source_color = vec4(0.12, 0.10, 0.16, 1.0);
uniform vec4 iris_low_color : source_color = vec4(0.30, 0.28, 0.48, 1.0); // gradient toward the bottom
uniform vec4 pupil_color : source_color = vec4(0.04, 0.03, 0.06, 1.0);
uniform vec4 line_color : source_color = vec4(0.165, 0.133, 0.2, 1.0);  // #2A2233
uniform vec4 lid_color : source_color = vec4(1.0);

// Resting-eye personality (frame 0).
uniform float lid_top : hint_range(0.0, 0.7) = 0.0;     // how far the upper lid comes down
uniform float lid_slant : hint_range(-0.6, 0.6) = 0.0;  // + = lid lower on the inner side (stern), - = droopy outer
uniform float lid_bottom : hint_range(0.0, 0.4) = 0.0;  // lower lid coming up
uniform float pupil_scale : hint_range(0.3, 1.6) = 1.0;
uniform float brow_thickness : hint_range(0.0, 0.12) = 0.0; // 0 = no brow line
uniform float brow_slant : hint_range(-0.6, 0.6) = 0.0;     // + = inner end lower (angry/stern)
uniform float brow_height : hint_range(0.0, 0.4) = 0.12;
uniform float brow_raise_left : hint_range(0.0, 0.2) = 0.0; // left eye's brow higher (cocky)
uniform bool lashes = false;

instance uniform int eye_frame = 0;
instance uniform float eye_flip = 0.0;

float aa(float d) {
	return clamp(0.5 - d / 0.012, 0.0, 1.0);
}

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float t = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0);
	return length(p - (a + ab * t));
}

// Procedural resting eye -> (R iris, G pupil, B white, A coverage), same packing as the atlas.
vec4 resting(vec2 uv) {
	float r = length(uv - 0.5);
	float a = aa(r - 0.5);
	float iris = aa(r - 0.455);
	vec2 pd = (uv - vec2(0.5, 0.56)) / vec2(0.21, 0.235) / pupil_scale;
	float pupil = aa((length(pd) - 1.0) * 0.21 * pupil_scale) * iris;
	float hi = max(aa((length((uv - vec2(0.36, 0.33)) / vec2(0.14, 0.12)) - 1.0) * 0.12),
	               aa((length((uv - vec2(0.65, 0.68)) / 0.06) - 1.0) * 0.06));
	float ink = 0.0;
	if (lid_top > 0.001) {
		float y = lid_top + lid_slant * (0.5 - uv.x);
		if (uv.y < y - 0.035) { a = 0.0; }
		ink = max(ink, aa(abs(uv.y - y) - 0.035));
		if (uv.y < y + 0.03) { hi = 0.0; }
	}
	if (lid_bottom > 0.001) {
		float y = 1.0 - lid_bottom;
		if (uv.y > y + 0.03) { a = 0.0; }
		ink = max(ink, aa(abs(uv.y - y) - 0.03));
	}
	if (brow_thickness > 0.0) {
		float raise = eye_flip < 0.5 ? brow_raise_left : 0.0;
		float h = brow_height - raise;
		vec2 p0 = vec2(0.1, h + brow_slant * 0.4);
		vec2 p1 = vec2(0.9, h - brow_slant * 0.4);
		ink = max(ink, aa(seg(uv, p0, p1) - brow_thickness * 0.5));
	}
	if (lashes) {
		for (int i = 0; i < 3; i++) {
			float t = 0.62 + 0.13 * float(i);
			vec2 base = vec2(t, 0.5 - sqrt(max(0.25 - (t - 0.5) * (t - 0.5), 0.0)) + 0.02);
			ink = max(ink, aa(seg(uv, base, base + vec2(0.1, -0.12)) - 0.025));
		}
	}
	a = max(a, ink);
	return vec4(iris, pupil, hi, a) * vec4(1.0 - ink, 1.0 - ink, 1.0 - ink, 1.0);
}

void fragment() {
	vec2 uv = UV;
	if (eye_flip > 0.5) {
		uv.x = 1.0 - uv.x;
	}
	vec4 m;
	if (eye_frame == 0) {
		m = resting(uv);
	} else {
		vec2 cell = vec2(float(eye_frame % columns), float(eye_frame / columns));
		m = texture(atlas, (cell + clamp(uv, vec2(0.004), vec2(0.996))) / vec2(float(columns), float(rows)));
	}

	vec3 iris = mix(iris_color.rgb, iris_low_color.rgb, smoothstep(0.35, 0.95, uv.y));
	vec3 eye = mix(line_color.rgb, iris, m.r);
	eye = mix(eye, pupil_color.rgb, m.g);
	eye = mix(eye, vec3(1.0), m.b);

	ALBEDO = lid_color.rgb * (1.0 - m.a);
	EMISSION = eye * m.a;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
