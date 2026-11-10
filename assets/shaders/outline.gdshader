// Inverted-hull outline. Use as the next_pass of a toon material.
// Width is in meters and compensates for object scale; the camera is orthographic, so it is
// constant on screen. Meshes with hard (split) normals may show small gaps at sharp corners.
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, depth_draw_opaque;

#include "res://assets/shaders/outline_body.gdshaderinc"
