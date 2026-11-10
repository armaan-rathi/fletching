// Bird toon surface for player slot 0: writes stencil value 1 so the x-ray of OTHER birds can still
// draw over it (a bird hidden behind another bird gets a silhouette), but never over this bird itself.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
stencil_mode write, compare_always, 1;

#define AS_CHARACTER
#include "res://assets/shaders/toon_body.gdshaderinc"
