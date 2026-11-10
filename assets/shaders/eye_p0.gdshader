// Eye patch for player slot 0 (stencil value 1). See eye.gdshader.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
stencil_mode write, compare_always, 1;

#define AS_CHARACTER
#include "res://assets/shaders/eye_body.gdshaderinc"
