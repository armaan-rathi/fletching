// Per-instance canopy fade: screen-door dithers away fragments above `canopy_min_height`
// (world space) when the instance's `canopy_fade` > 0, so birds and stuck arrows under a tree
// stay visible while the toon look stays fully opaque. Set it with
// GeometryInstance3D.set_instance_shader_parameter("canopy_fade", x).
// In vertex(): canopy_world_y = canopy_height(VERTEX, MODEL_MATRIX);

instance uniform float canopy_fade : hint_range(0.0, 1.0) = 0.0;
uniform float canopy_min_height = 1.1;

varying float canopy_world_y;

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i.y * 4 + i.x]) + 0.5) / 16.0;
}

float canopy_height(vec3 vertex, mat4 model_matrix) {
	return (model_matrix * vec4(vertex, 1.0)).y;
}

void canopy_discard(vec2 fragcoord) {
	if (canopy_fade > 0.001 && canopy_world_y > canopy_min_height && bayer4(fragcoord) < canopy_fade) {
		discard;
	}
}
