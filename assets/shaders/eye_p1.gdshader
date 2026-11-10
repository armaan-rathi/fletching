// Eye patch for player slot 1 (stencil value 2). See eye.gdshader.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
stencil_mode write, compare_always, 2;

#define AS_CHARACTER
#include "res://assets/shaders/eye_body.gdshaderinc"
