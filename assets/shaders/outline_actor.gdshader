// Outline for toon_actor (stencil value 5, character art style).
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, depth_draw_opaque;
stencil_mode write, compare_always, 5;

#define AS_CHARACTER
#include "res://assets/shaders/outline_body.gdshaderinc"
