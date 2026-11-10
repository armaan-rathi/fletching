class_name ToonMaterials
extends RefCounted
## Builds (and caches) toon materials with the shared outline pass.
## Bird ("character") materials come in 4 per-player stencil variants (slot 0..3, stencil value slot+1):
## each bird's x-ray silhouette skips only its own pixels, so a bird hidden behind another bird still shows.

const TOON := preload("res://assets/shaders/toon.gdshader")
const OUTLINE := preload("res://assets/materials/outline.tres")
const XRAY := preload("res://assets/shaders/xray.gdshader")
const EYE := preload("res://assets/shaders/eye.gdshader")
const ACTOR := preload("res://assets/shaders/toon_actor.gdshader")
const OUTLINE_ACTOR := preload("res://assets/shaders/outline_actor.gdshader")
const SLOTS := 4

static var _cache := {}
static var _toon_char: Array[Shader] = []
static var _outline_char_shader: Array[Shader] = []
static var _xray: Array[Shader] = []
static var _eye: Array[Shader] = []
static var _outline_char: Array[ShaderMaterial] = []

static func _load_variants() -> void:
	if not _toon_char.is_empty():
		return
	for k in SLOTS:
		_toon_char.append(load("res://assets/shaders/toon_character_p%d.gdshader" % k))
		_outline_char_shader.append(load("res://assets/shaders/outline_character_p%d.gdshader" % k))
		_xray.append(load("res://assets/shaders/xray_p%d.gdshader" % k))
		_eye.append(load("res://assets/shaders/eye_p%d.gdshader" % k))
		var o: ShaderMaterial = OUTLINE.duplicate()
		o.shader = _outline_char_shader[k]
		_outline_char.append(o)

static func _slot(slot: int) -> int:
	return clampi(slot, 0, SLOTS - 1)

## Shared bird outline for a player slot (same width as OUTLINE, writes that slot's stencil value).
static func outline_character(slot := 0) -> ShaderMaterial:
	_load_variants()
	return _outline_char[_slot(slot)]

## Eye shader for a player slot (BirdModel builds per-bird eye materials with it).
static func eye_shader(slot := 0) -> Shader:
	_load_variants()
	return _eye[_slot(slot)]

## Toon material with the shared outline. Cached per (color, rim, outline) so identical props share it.
static func toon(color: Color, rim := 0.2, outline := true, rim_in_shade := 0.0) -> ShaderMaterial:
	var key := "%s|%.2f|%s|%.2f" % [color.to_html(), rim, outline, rim_in_shade]
	if _cache.has(key):
		return _cache[key]
	var m := _make(color, rim)
	m.set_shader_parameter("rim_in_shade", rim_in_shade)
	if outline:
		m.next_pass = _outline_for(color)
	_cache[key] = m
	return m

## Toon material in the CHARACTER art style for things that belong to no player slot (flying arrows): stencil
## value 5 (see toon_actor.gdshader). Same look as toon() in every style where characters and environment match.
static func actor(color: Color, rim := 0.2) -> ShaderMaterial:
	var key := "actor|%s|%.2f" % [color.to_html(), rim]
	if _cache.has(key):
		return _cache[key]
	var m := _make(color, rim)
	m.shader = ACTOR
	m.set_shader_parameter("face_smooth", 0.0)
	var o := _outline_for(color)
	o.shader = OUTLINE_ACTOR
	m.next_pass = o
	_cache[key] = m
	return m

## An outline pass that knows the color it outlines (art styles tint lines by the color underneath).
static func _outline_for(color: Color, shader: Shader = null) -> ShaderMaterial:
	var o: ShaderMaterial = OUTLINE.duplicate()
	if shader:
		o.shader = shader
	o.set_shader_parameter("base_color", Color(color, 1.0))
	return o

## Anime style: the authored shadow color for a material color (also derived in-shader for textured props,
## same rule: art_style.gdshaderinc as_anime_shade). Warm hues lean red, the rest blue-violet; whites lavender.
static func anime_shade(color: Color) -> Color:
	if color.s < 0.14:
		return Color(0.76, 0.74, 0.9) * color.v
	var h := color.h
	if h < 0.16 or h > 0.9:
		h = fposmod(h - 0.035, 1.0)
	else:
		h += (0.7 - h) * 0.14
	return Color.from_hsv(h, clampf(color.s * 1.1 + 0.12, 0.0, 1.0), color.v * 0.66)

## Character preset: faces mostly lit (lower band threshold), rim that shows in shade, and near-white
## colors kept truly white (neutral light, lighter shade). Use for every bird surface.
static func character(color: Color, outline := true, rim_tint := Color.WHITE, rim := 0.4, slot := 0) -> ShaderMaterial:
	_load_variants()
	var key := "char|%s|%s|%s|%.2f|%d" % [color.to_html(), outline, rim_tint.to_html(), rim, _slot(slot)]
	if _cache.has(key):
		return _cache[key]
	var m := _make(color, rim)
	m.shader = _toon_char[_slot(slot)]
	_apply_character(m, color)
	m.set_shader_parameter("rim_tint", rim_tint)
	m.set_shader_parameter("face_smooth", 0.0) # bows, quivers, held arrows
	if outline:
		m.next_pass = _outline_for(color, _outline_char_shader[_slot(slot)])
	_cache[key] = m
	return m

static func _apply_character(m: ShaderMaterial, color: Color) -> void:
	m.set_shader_parameter("rim_in_shade", 0.45)
	m.set_shader_parameter("band_threshold", -0.3)
	if color.get_luminance() > 0.8:
		m.set_shader_parameter("neutral_light", 0.85)
		m.set_shader_parameter("shade_lighten", 0.4)

## Character preset plus the occlusion x-ray chain (toon -> outline -> x-ray), for one player slot.
## Cached; every bird surface uses it so the whole silhouette shows when hidden (x-ray writes the slot's
## stencil value, so overlapping parts of one bird tint a pixel only once).
## `smooth_face`: 1 lets the anime style bend this surface's normals around the head (0 for beaks and legs).
static func character_with_xray(color: Color, xray_color: Color, rim_tint := Color.WHITE, rim := 0.4, slot := 0, outline_on := true, smooth_face := 1.0) -> ShaderMaterial:
	_load_variants()
	var k := _slot(slot)
	var key := "charx|%s|%s|%s|%.2f|%d|%s|%.1f" % [color.to_html(), xray_color.to_html(), rim_tint.to_html(), rim, k, outline_on, smooth_face]
	if _cache.has(key):
		return _cache[key]
	var m := _make(color, rim)
	m.shader = _toon_char[k]
	_apply_character(m, color)
	m.set_shader_parameter("rim_tint", rim_tint)
	m.set_shader_parameter("face_smooth", smooth_face)
	var outline := _outline_for(color, _outline_char_shader[k])
	outline.set_shader_parameter("vertex_width", true) # bird parts carry per-vertex outline widths (UV2.x)
	var xray := ShaderMaterial.new()
	xray.shader = _xray[k]
	xray.set_shader_parameter("color", xray_color)
	xray.render_priority = 1
	if outline_on:
		outline.next_pass = xray
		m.next_pass = outline
	else:
		m.next_pass = xray
	_cache[key] = m
	return m

## Default eye material (neutral dark eyes, white lid). BirdModel builds per-bird eye materials.
static func eye() -> ShaderMaterial:
	if not _cache.has("eye"):
		var m := ShaderMaterial.new()
		m.shader = EYE
		m.set_shader_parameter("atlas", load("res://assets/birds/eyes/ph_eye_atlas.png"))
		_cache["eye"] = m
	return _cache["eye"]

static func _make(color: Color, rim: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("rim_strength", rim)
	m.set_shader_parameter("anime_shade", Color(anime_shade(color), 1.0))
	return m
