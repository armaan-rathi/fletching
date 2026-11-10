// Art style scene pass, character layer (birds 1..4 and flying arrows 5: stencil != 0). Reads the character
// style uniform. See style_scene_body.gdshaderinc.
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, blend_mix;
stencil_mode read, compare_not_equal, 0;

#define AS_CHARACTER
#include "res://assets/shaders/style_scene_body.gdshaderinc"
