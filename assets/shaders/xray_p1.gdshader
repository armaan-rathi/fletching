// Occlusion silhouette for player slot 1: draws wherever this bird is hidden, except over its own pixels
// (stencil value 2). Over other birds and scenery it shows, so birds behind birds get a silhouette.
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_back, shadows_disabled, blend_mix;
stencil_mode read, write, compare_not_equal, 2; // write too: one tint per pixel per bird

#include "res://assets/shaders/xray_body.gdshaderinc"
