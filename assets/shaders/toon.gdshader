// Standard toon surface: flat color or palette texture (e.g. KayKit's gradient atlas), 2-band cel lighting.
// Pair with outline.gdshader as next_pass for inked silhouettes.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

#include "res://assets/shaders/toon_body.gdshaderinc"
