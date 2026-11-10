// Shared 2-band cel lighting. Include in any spatial shader that should match the toon look.
// - Form shade (surfaces turned away from the sun): global `toon_shade_color` x light energy.
// - Cast shadows (something blocks the sun): global `toon_cast_shadow_color`, cooler/bluer, crisp edge.
// - Lit band: the sun's own warm color.
// - Optional rim light on silhouette edges (`rim_strength`, `rim_in_shade` keeps some rim on the dark side).
// Global colors are not sRGB-decoded by Godot, so they're decoded here with pow(c, 2.2).
// Ambient is expected to be ~0 in the environment.

#include "res://assets/shaders/art_style.gdshaderinc"

global uniform vec4 toon_shade_color;
global uniform vec4 toon_cast_shadow_color;
global uniform vec4 toon_cast_shadow_lift; // rgb = cool tint (design doc shadow tint), a = amount

uniform float band_threshold : hint_range(-1.0, 1.0) = 0.05;
uniform float band_softness : hint_range(0.0, 0.5) = 0.04;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.0;
uniform float rim_in_shade : hint_range(0.0, 1.0) = 0.0;
// Rim color multiplier (e.g. blue for the crow's glossy sheen).
uniform vec4 rim_tint : source_color = vec4(1.0);
// For white/near-white materials: 1 = the lit band uses neutral (untinted) light so whites stay white.
uniform float neutral_light : hint_range(0.0, 1.0) = 0.0;
// Lightens the shaded/cast-shadow bands toward full light (0 = normal shade, 1 = no shade).
uniform float shade_lighten : hint_range(0.0, 1.0) = 0.0;
// Anime style: authored shadow color for this material (alpha 0 = derive it from the albedo, see art_style).
uniform vec4 anime_shade : source_color = vec4(0.0);

void light() {
	vec3 light_col = LIGHT_COLOR / PI;
	float energy = max(light_col.r, max(light_col.g, light_col.b));
	light_col = mix(light_col, vec3(energy), neutral_light);

	float ndl = dot(NORMAL, LIGHT);
	float softness = art_style == 8 ? 0.002 : band_softness; // pixel art: hard band edges
	float band = smoothstep(band_threshold - softness, band_threshold + softness, ndl);
	float shadow = smoothstep(0.45, 0.55, ATTENUATION);

	if (art_style == 1) {
		// Field guide: soft warm-paper light, a pale wash in shade, ink crosshatching (single in form shade,
		// crossed in cast shadow).
		vec3 paper_light = mix(light_col, vec3(energy), 0.55);
		float form = 1.0 - band;
		float cast = band * (1.0 - shadow);
		float shade = max(form, cast);
		float ink = as_hatch(FRAGCOORD.xy, 0.7854, 6.0, 0.32) * shade + as_hatch(FRAGCOORD.xy, -0.7854, 6.0, 0.32) * cast;
		DIFFUSE_LIGHT += paper_light * mix(1.0, 0.8, shade) * (1.0 - 0.6 * clamp(ink, 0.0, 1.0));
	} else if (art_style == 2) {
		// Felt: soft wrap light (no hard terminator), softened shadows, and a fuzzy sheen at the edges.
		float wrap = smoothstep(-0.35, 0.75, ndl);
		float soft_shadow = mix(0.55, 1.0, smoothstep(0.2, 0.8, ATTENUATION));
		vec3 felt_shade = pow(toon_shade_color.rgb, vec3(2.2)) * energy * 1.15;
		DIFFUSE_LIGHT += mix(felt_shade, light_col, wrap * soft_shadow);
		float fuzz = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.8);
		DIFFUSE_LIGHT += mix(light_col, vec3(energy), 0.5) * fuzz * 0.55;
	} else if (art_style == 3) {
		// Risograph: neutral light (the ink separation carries the color); shade is a halftone of the blue ink.
		float shade = 1.0 - band * shadow;
		float dots = as_screen(FRAGCOORD.xy, 5.0, 1.309, shade * 0.6);
		DIFFUSE_LIGHT += vec3(energy) * mix(vec3(1.0), as_lin(vec3(0.24, 0.42, 0.78)) / as_lin(vec3(0.96, 0.93, 0.85)), dots * 0.85);
	} else if (art_style == 4) {
		// Sketchbook: paper-white light, light graphite hatching in shade, a bit denser in cast shadow.
		float form = 1.0 - band;
		float cast = band * (1.0 - shadow);
		float jitter = as_noise(FRAGCOORD.xy * 0.05 + floor(TIME * 8.0) * 3.1) * 2.0;
		float lines = as_hatch(FRAGCOORD.xy + jitter, 1.1, 5.0, 0.22) * max(form, cast) + as_hatch(FRAGCOORD.xy - jitter, -0.5, 5.0, 0.22) * cast;
		DIFFUSE_LIGHT += vec3(energy) * mix(1.0, 0.9, max(form, cast)) * (1.0 - 0.45 * clamp(lines, 0.0, 1.0));
	} else if (art_style == 5) {
		// Anime: hard cel band, one authored shadow color per material (cast shadows use it too), a sharp
		// specular highlight and a bright rim on the lit side that goes over 1.0 so the glow blooms it.
		float b = smoothstep(band_threshold - 0.012, band_threshold + 0.012, ndl);
		float lit = b * step(0.5, ATTENUATION);
		vec3 sh = anime_shade.a > 0.5 ? anime_shade.rgb : as_anime_shade(ALBEDO);
		vec3 lc = mix(light_col, vec3(energy), 0.6);
		DIFFUSE_LIGHT += mix(sh / max(ALBEDO, vec3(0.02)) * energy, lc, lit);
		float spec = smoothstep(0.955, 0.965, dot(NORMAL, normalize(LIGHT + VIEW))) * lit;
		SPECULAR_LIGHT += vec3(energy) * spec * 0.5 * step(0.15, rim_strength);
		float rim = smoothstep(0.54, 0.58, 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0)) * smoothstep(0.0, 0.35, ndl);
		SPECULAR_LIGHT += lc * rim_tint.rgb * rim * rim_strength * 3.4;
	} else if (art_style == 6) {
		// Watercolor: soft terminator, a cool blue-violet glaze for shade, and the bare paper left white in the
		// brightest highlights (shaped by a little noise so it reads as a reserved area, not a specular).
		float b = smoothstep(band_threshold - 0.3, band_threshold + 0.3, ndl);
		float lit = b * mix(0.55, 1.0, smoothstep(0.3, 0.7, ATTENUATION));
		vec3 glaze = as_lin(vec3(0.6, 0.64, 0.86)) * energy;
		float hl = smoothstep(0.8, 0.93, ndl + (as_noise(FRAGCOORD.xy * 0.08) - 0.5) * 0.16) * step(0.5, ATTENUATION);
		// Not the ground (its whole plane faces the sun); scenery keeps only a pale reserve.
		hl *= step(0.05, rim_strength) * (rim_strength > 0.25 ? 0.85 : 0.4);
		DIFFUSE_LIGHT += mix(glaze, vec3(energy), lit) * (1.0 - hl);
		SPECULAR_LIGHT += as_lin(vec3(0.98, 0.96, 0.9)) * energy * hl;
	} else if (art_style == 7) {
		// Woodblock: two flat impressions, the shade block printed as an indigo overprint.
		float lit = step(band_threshold, ndl) * step(0.5, ATTENUATION);
		DIFFUSE_LIGHT += mix(as_lin(vec3(0.66, 0.68, 0.84)) * energy, vec3(energy) * 1.02, lit);
	} else if (art_style == 9) {
		// Claymation: wide soft terminator, warm (subsurface-ish) shade, soft shadows, a broad waxy sheen.
		float wrap = smoothstep(-0.3, 0.6, ndl);
		float sh = mix(0.5, 1.0, smoothstep(0.25, 0.75, ATTENUATION));
		vec3 warm = as_lin(vec3(0.6, 0.42, 0.44)) * energy;
		DIFFUSE_LIGHT += mix(warm, light_col, wrap * sh);
		SPECULAR_LIGHT += light_col * pow(max(dot(NORMAL, normalize(LIGHT + VIEW)), 0.0), 12.0) * 0.22 * sh;
	} else {
	// Baseline toon (also pixel art with hard bands, and colored line art with lighter shade).
	float lighten = art_style == 10 ? max(shade_lighten, 0.35) : shade_lighten;
	vec3 form_shade = pow(toon_shade_color.rgb, vec3(2.2)) * energy;
	vec3 cast_shade = pow(toon_cast_shadow_color.rgb, vec3(2.2)) * energy;
	form_shade = mix(form_shade, light_col, lighten);
	cast_shade = mix(cast_shade, light_col, lighten);
	vec3 lit_col = mix(form_shade, light_col, band);
	// Cast shadow only replaces the lit band; form-shaded sides stay form-shaded.
	vec3 shadowed = mix(form_shade, cast_shade, band);
	DIFFUSE_LIGHT += mix(shadowed, lit_col, shadow);
	// Multiplying green by blue can't make it blue, so cast shadows also get a small additive cool lift
	// (not multiplied by albedo), pulling every surface's shadow toward the same cool tint.
	vec3 cool_lift = pow(toon_cast_shadow_lift.rgb, vec3(2.2)) * toon_cast_shadow_lift.a;
	SPECULAR_LIGHT += cool_lift * energy * band * (1.0 - shadow);

	if (rim_strength > 0.0 && art_style != 8) {
		float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		rim = smoothstep(0.6, 0.66, rim) * mix(rim_in_shade, 1.0, band * shadow);
		DIFFUSE_LIGHT += light_col * rim_tint.rgb * rim * rim_strength;
	}
	} // baseline toon
}
