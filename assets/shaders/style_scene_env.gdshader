// Art style scene pass, environment layer (stencil 0 only). See style_scene_body.gdshaderinc.
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, blend_mix;
stencil_mode read, compare_equal, 0;

#include "res://assets/shaders/style_scene_body.gdshaderinc"
