// Bird outline for player slot 2 (stencil value 3).
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, depth_draw_opaque;
stencil_mode write, compare_always, 3;

#define AS_CHARACTER
#include "res://assets/shaders/outline_body.gdshaderinc"
