// Pixel-art style palette (sRGB): 30 colors picked from the game's palette (forest greens, wood, water, the four
// player colors, inks and whites). as_palette() snaps a color to the nearest entry after a small ordered-dither
// nudge (4x4 Bayer on the pixel grid).
#ifndef STYLE_PALETTE_INC
#define STYLE_PALETTE_INC

const int PAL_N = 30;
const vec3 PAL[30] = vec3[30](
	vec3(0.106, 0.090, 0.141), vec3(0.231, 0.184, 0.247), vec3(0.184, 0.365, 0.227), vec3(0.310, 0.498, 0.227),
	vec3(0.420, 0.620, 0.290), vec3(0.553, 0.749, 0.353), vec3(0.722, 0.843, 0.478), vec3(0.361, 0.239, 0.180),
	vec3(0.612, 0.478, 0.322), vec3(0.788, 0.655, 0.486), vec3(0.910, 0.824, 0.651), vec3(0.957, 0.937, 0.882),
	vec3(1.0, 1.0, 1.0), vec3(0.416, 0.471, 0.569), vec3(0.663, 0.694, 0.733), vec3(0.310, 0.639, 0.788),
	vec3(0.561, 0.827, 0.910), vec3(0.169, 0.290, 0.471), vec3(0.302, 0.651, 1.0), vec3(0.761, 0.227, 0.227),
	vec3(1.0, 0.353, 0.353), vec3(0.949, 0.608, 0.690), vec3(1.0, 0.824, 0.247), vec3(0.941, 0.541, 0.141),
	vec3(0.541, 0.353, 0.761), vec3(0.710, 0.482, 1.0), vec3(0.098, 0.192, 0.141), vec3(0.137, 0.271, 0.176),
	vec3(0.502, 0.498, 0.502), vec3(0.239, 0.157, 0.122)
);

float pal_bayer(vec2 cell) {
	ivec2 p = ivec2(mod(cell, 4.0));
	int i = p.x + p.y * 4;
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0 - 0.5;
}

vec3 as_palette(vec3 srgb, vec2 cell) {
	vec3 c = srgb + pal_bayer(cell) * 0.035;
	vec3 best = PAL[0];
	float bd = 1e9;
	for (int i = 0; i < PAL_N; i++) {
		vec3 d = (c - PAL[i]) * vec3(0.9, 1.2, 0.7); // rough perceptual weights
		float dd = dot(d, d);
		if (dd < bd) {
			bd = dd;
			best = PAL[i];
		}
	}
	return best;
}

#endif
