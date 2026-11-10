// Toon surface for things that follow the character art style but belong to no player slot (flying arrows):
// stencil value 5, so the style scene passes treat them like birds (e.g. watercolor keeps them sharp) while
// every bird's x-ray (compare_not_equal to its own slot) still draws over them as over scenery.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
stencil_mode write, compare_always, 5;

#define AS_CHARACTER
#include "res://assets/shaders/toon_body.gdshaderinc"
