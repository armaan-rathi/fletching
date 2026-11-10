// Toon water (Birdbath map): flat cel-lit blues, slow posterized ripples, a crisp foam edge.
// mode 0 = puddle: a wobbly circle of `radius` around `center` (local xz), edges cut with alpha scissor.
// mode 1 = stream: a ribbon (UV.x across, UV.y down the fall) with foamy stripes flowing down.
// mode 2 = basin: a disc of `radius` (the bowl's surface): ripple rings and a foam ring at the rim.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;

#include "res://assets/shaders/toon_lighting.gdshaderinc"

uniform int mode = 0;
uniform vec2 center = vec2(0.0);
uniform float radius = 1.0;
uniform vec4 shallow : source_color = vec4(0.561, 0.827, 0.910, 1.0); // #8FD3E8
uniform vec4 deep : source_color = vec4(0.310, 0.639, 0.788, 1.0);    // #4FA3C9
uniform vec4 foam : source_color = vec4(0.918, 0.973, 1.0, 1.0);      // #EAF8FF
uniform float flow_speed = 1.4;

varying vec3 lp;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float t = TIME;
	vec3 col;
	float a = 1.0;
	if (mode == 1) {
		float s = noise(vec2(UV.x * 4.0, UV.y * 7.0 - t * flow_speed * 3.0));
		col = mix(shallow.rgb, deep.rgb, step(0.5, s) * 0.45);
		col = mix(col, foam.rgb, step(0.74, s) * 0.9);
		col = mix(col, foam.rgb, step(0.88, UV.y));
		float e = abs(UV.x - 0.5) * 2.0 + (noise(vec2(UV.y * 9.0 - t * 5.0, 3.0)) - 0.5) * 0.6;
		a = 1.0 - step(0.82, e);
	} else {
		vec2 p = lp.xz - (mode == 0 ? center : vec2(0.0));
		float d = length(p);
		float ang = atan(p.y, p.x);
		float edge = radius;
		if (mode == 0) {
			// Lumpy, slowly breathing outline: noise sampled around a circle, so it wraps seamlessly.
			float n = noise(vec2(cos(ang), sin(ang)) * 1.8 + vec2(t * 0.12, 4.0));
			edge = radius * (0.84 + 0.26 * n);
		}
		float sd = d - edge;
		a = 1.0 - step(0.0, sd);
		float r = noise(lp.xz * 1.4 + vec2(t * 0.22, -t * 0.17));
		col = mix(shallow.rgb, deep.rgb, clamp(smoothstep(0.0, edge, edge - d) * 0.55 + step(0.62, r) * 0.25, 0.0, 1.0));
		float ring = fract(d * 1.5 - t * 0.35);
		col = mix(col, foam.rgb, step(0.93, ring) * 0.35 * clamp(1.0 - d / max(edge, 0.01), 0.0, 1.0));
		col = mix(col, foam.rgb, step(-0.11 - 0.04 * float(mode == 2), sd));
	}
	ALBEDO = col;
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
