// Body of the toon surface shader (includes, uniforms, vertex, fragment), shared by toon.gdshader
// and toon_character.gdshader. See toon.gdshader for usage.
#include "res://assets/shaders/toon_lighting.gdshaderinc"
#include "res://assets/shaders/canopy_fade.gdshaderinc"
#include "res://assets/shaders/border_fade.gdshaderinc"

varying vec3 toon_world_pos;

uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_texture = false;
uniform sampler2D albedo_texture : source_color, filter_linear, repeat_disable, hint_default_white;
// Palette remap for KayKit-style gradient atlases: the texture is split into 4 horizontal
// bands (foliage, bark, rock, spare). Each band's color is multiplied by its tint.
uniform vec4 band_tint_0 : source_color = vec4(1.0);
uniform vec4 band_tint_1 : source_color = vec4(1.0);
uniform vec4 band_tint_2 : source_color = vec4(1.0);
uniform vec4 band_tint_3 : source_color = vec4(1.0);

#ifdef AS_CHARACTER
// Anime style, smoothed face normals: BirdModel feeds the head's center (xyz, world) and radius (w) while the
// character style is anime; normals near it are bent toward a sphere's, so the face shades as one clean shape.
// `face_smooth` 0 opts a material out (beaks, legs).
instance uniform vec4 as_face = vec4(0.0);
uniform float face_smooth : hint_range(0.0, 1.0) = 1.0;
#endif

void vertex() {
	canopy_world_y = canopy_height(VERTEX, MODEL_MATRIX);
	toon_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
#ifdef AS_CHARACTER
	if (art_style == 5 && as_face.w > 0.0 && face_smooth > 0.0) {
		vec3 to_v = toon_world_pos - as_face.xyz;
		float f = (1.0 - smoothstep(as_face.w * 0.75, as_face.w * 1.25, length(to_v))) * face_smooth;
		if (f > 0.0) {
			vec3 nw = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
			nw = normalize(mix(nw, normalize(to_v), f * 0.85));
			NORMAL = normalize((inverse(MODEL_MATRIX) * vec4(nw, 0.0)).xyz);
		}
	}
#endif
}

void fragment() {
	canopy_discard(FRAGCOORD.xy);
	vec3 col = albedo.rgb;
	if (use_texture) {
		col *= texture(albedo_texture, UV).rgb;
		int band = clamp(int(UV.y * 4.0), 0, 3);
		vec4 tints[4] = vec4[4](band_tint_0, band_tint_1, band_tint_2, band_tint_3);
		col *= tints[band].rgb;
	}
	col = as_style_albedo(col, toon_world_pos, FRAGCOORD.xy);
	if (art_style == 9) {
		NORMAL = as_bump(NORMAL, VERTEX, as_clay_height(toon_world_pos, floor(TIME * 12.0)));
	}
	ALBEDO = border_fade(col, toon_world_pos);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
