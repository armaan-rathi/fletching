// Body of the x-ray silhouette shader, shared by the per-player stencil variants.
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec4 color : source_color = vec4(1.0, 0.35, 0.35, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.65;
// Ignore occluders closer than this (in depth-buffer units; ortho camera with near 1 / far 100,
// so ~0.01 per meter, ~10 cm here). Self-occlusion is handled by the stencil; this just absorbs
// depth noise at the bird's own silhouette edge and things like its bow.
uniform float self_tolerance = 0.001;

void fragment() {
	float scene_depth = texture(depth_tex, SCREEN_UV).r;
	if (FRAGCOORD.z >= scene_depth - self_tolerance) {
		discard;
	}
	// Rim-darkened silhouette so it still reads as a round body.
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = mix(color.rgb, color.rgb * 0.6, smoothstep(0.5, 0.9, rim));
	ALPHA = opacity;
}
