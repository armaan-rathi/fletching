@tool
class_name BirdModel
extends Node3D
## Assembles and animates a bird from the shared rigged base (child GLB "BirdBase", turned to face -Z):
## - Look: BirdData parts, color variant, body shape keys, rim tint, resting-eye personality.
## - Keyframed clips (assets/birds/anims/bird_anims.tres) via an AnimationPlayer: play_state() for looping
##   states (idle, draw, dash, ko, victory), play_once() for one-shots (release, slap, squawk).
## - Procedural layer on top (BirdPoseModifier): hop flaps, head tracking (±45°), neck pitch/extension,
##   head scale, beak opening.
## - Face (BirdExpressions): eye frames per eye, beak mode, blinks, floating anime symbols.

const DEFAULT_DATA := preload("res://data/birds/eagle.tres")
const ANIMS := preload("res://assets/birds/anims/bird_anims.tres")
const EYE_ATLAS := preload("res://assets/birds/eyes/ph_eye_atlas.png")
const MAX_HEAD_YAW := deg_to_rad(45.0)
const BEAK_MAX_OPEN := deg_to_rad(32.0)
const SHAPE_KEYS := ["puff", "hunch", "slim", "round"]
const BLEND := 0.12

@export var data: BirdData = DEFAULT_DATA:
	set(v):
		data = v if v else DEFAULT_DATA
		_apply()
@export_range(0, 3) var variant := 0:
	set(v):
		variant = v
		_apply()
## Player color, used for the occlusion silhouette.
@export var player_color := Color("ff5a5a"):
	set(v):
		player_color = v
		_apply()
## Player slot 0..3: picks the per-player stencil variant of the bird shaders (x-ray between birds).
@export_range(0, 3) var stencil_slot := 0:
	set(v):
		stencil_slot = v
		_apply()

## True while knocked out and lying down (the dizzy stars follow the head instead of the standing offset).
var lying := false
## Radians: extra procedural wing lift (hop flaps, flutters), positive = up.
var flap := 0.0
## Radians, relative to the body: where the head should look (clamped to ±45°).
var head_yaw_target := 0.0
## Hand bone attachment (the bow follows it when idle).
var hand_r: BoneAttachment3D
var expressions := BirdExpressions.new()

var skeleton: Skeleton3D
const FACE_CENTER_UP := 0.12 # head bone origin -> head center, along the bone (m)
const FACE_RADIUS := 0.3
var anim: AnimationPlayer
var _bones := {}
var _head_yaw := 0.0
var _beak := 0.0
var _beak_sign := 1.0
var _beak_pop := 0.0      # extra short beak opening (squawk)
var _blink_timer := 2.0
var _blink_t := -1.0
var _eyes: Array[MeshInstance3D] = []
var _eye_mat: ShaderMaterial
var _state := "idle"
var _state_clip := ""   # the looping/held state clip currently playing (non-looping ones hold their last frame)
var _oneshot := ""
var _pose_mod: BirdPoseModifier
var _symbol: AnimeSymbol
var _clock := 0.0

func _ready() -> void:
	var skels := find_children("*", "Skeleton3D", true, false)
	skeleton = skels[0] if skels.size() > 0 else null
	if skeleton and not Engine.is_editor_hint():
		for b in ["wing_L", "wing_R", "neck", "head", "beak_lower"]:
			_bones[b] = skeleton.find_bone(b)
		_beak_sign = _find_beak_open_sign()
		anim = AnimationPlayer.new()
		anim.name = "Anim"
		add_child(anim)
		anim.add_animation_library("", ANIMS)
		anim.animation_finished.connect(_on_anim_finished)
		var mod := BirdPoseModifier.new()
		mod.name = "ProceduralPose"
		mod.model = self
		skeleton.add_child(mod)
		_pose_mod = mod
		hand_r = BoneAttachment3D.new()
		hand_r.name = "HandR"
		hand_r.bone_name = "hand_R"
		skeleton.add_child(hand_r)
		expressions.changed.connect(_on_expression_changed)
	_blink_timer = randf_range(1.5, 4.0)
	_apply()
	if anim:
		play_state("idle")

# --- Look ----------------------------------------------------------------------------

func _apply() -> void:
	if not is_inside_tree() or data == null:
		return
	var cols := data.variant(variant)
	var shown := data.all_parts()
	var lid: Color = cols.get(data.lid_slot, cols.get("body", Color.WHITE))
	_eye_mat = _eye_material(cols, lid)
	_eyes.clear()
	_face_meshes.clear()
	_face_on = ArtStyle.char_style == ArtStyle.ANIME
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		mi.visible = shown.has(mi.name)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # the ground disc casts the bird's shadow
		if not mi.visible:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var slot: String = src.resource_name if src else "body"
			var color: Color = cols.get(slot, cols.get("body", Color.MAGENTA))
			var mat: Material
			if slot == "eyes":
				mat = _eye_mat
			else:
				# Every surface carries the x-ray pass so the whole bird's silhouette shows when hidden.
				mat = ToonMaterials.character_with_xray(color, player_color, data.rim_tint, data.rim_strength, stencil_slot, slot != "belly", 0.0 if slot in ["beak", "legs"] else 1.0)
			mi.set_surface_override_material(i, mat)
		for key in SHAPE_KEYS:
			var bi := mi.find_blend_shape_by_name(key)
			if bi >= 0:
				mi.set_blend_shape_value(bi, float(data.body_shape.get(key, 0.0)))
		if mi.name.begins_with("eyes_"):
			_eyes.append(mi)
			mi.set_instance_shader_parameter("eye_flip", 1.0 if mi.name.ends_with("_R") else 0.0)
	_show_eyes(expressions.eyes())
	if anim and _state == "idle":
		play_state("idle")

func _eye_material(cols: Dictionary, lid: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ToonMaterials.eye_shader(stencil_slot)
	m.set_shader_parameter("atlas", EYE_ATLAS)
	m.set_shader_parameter("iris_color", cols.get("iris", Color("2a1f1a")))
	m.set_shader_parameter("iris_low_color", cols.get("iris_low", Color("6b4a2a")))
	m.set_shader_parameter("lid_color", lid)
	m.set_shader_parameter("band_threshold", -0.3)
	# Light the lids exactly like the bird surface around them (same near-white handling as
	# ToonMaterials._apply_character), so pale faces don't get darker "eye sockets".
	m.set_shader_parameter("rim_in_shade", 0.45)
	if lid.get_luminance() > 0.8:
		m.set_shader_parameter("neutral_light", 0.85)
		m.set_shader_parameter("shade_lighten", 0.4)
	for k in data.eye_style:
		m.set_shader_parameter(k, data.eye_style[k])
	return m

# --- Animation -----------------------------------------------------------------------

## Looping state clip: "idle" (uses the bird's idle clip), "draw", "dash", "ko", "victory".
func play_state(state: String) -> void:
	_state = state
	if state == "ko" and _oneshot != "":
		# A KO interrupts any one-shot (release, slap, a near-miss squawk) right away, so the limp pose plays in
		# sync with the fall instead of starting after the bird has landed (the "twitch after dying").
		_oneshot = ""
		_state_clip = ""
	if _oneshot != "":
		return
	var clip := data.idle_anim if state == "idle" else state
	# Compare against what we last started, not current_animation: a finished non-looping clip (ko) leaves
	# current_animation empty, and restarting it every frame looked like the bird doing crunches.
	if anim and _state_clip != clip:
		_state_clip = clip
		anim.play(clip, BLEND)

## One-shot clip ("release", "slap", "squawk"); returns to the current state afterwards.
func play_once(clip: String) -> void:
	if anim == null or _state == "ko":
		return
	_oneshot = clip
	anim.play(clip, 0.05)
	if clip == "squawk":
		_beak_pop = 0.4

func _on_anim_finished(clip: StringName) -> void:
	if String(clip) == _oneshot:
		_oneshot = ""
		_state_clip = ""
		play_state(_state)

# --- Face ----------------------------------------------------------------------------

## Opens the beak briefly with the squawk clip (squawks, shock, KO screams).
func squawk() -> void:
	if _state == "ko":
		_beak_pop = 0.4 # the KO scream is just the beak; the limp clip keeps playing
		return
	play_once("squawk")

func _show_eyes(frames: Array) -> void:
	for e in _eyes:
		var f: int = frames[1] if e.name.ends_with("_R") else frames[0]
		e.set_instance_shader_parameter("eye_frame", f if f != 0 else data.resting_eye_frame)

func _on_expression_changed(name: String) -> void:
	_show_eyes(expressions.eyes())
	var kind := expressions.symbol()
	if not is_instance_valid(_symbol):
		_symbol = null # it already shrank away on its own
	if _symbol and (_symbol.kind != kind or _symbol.is_leaving()):
		_symbol.dismiss()
		_symbol = null
	if kind != "" and _symbol == null:
		_symbol = AnimeSymbol.create(kind)
		add_child(_symbol)
		_place_symbol()
	if name == "shocked" or name == "ko":
		squawk()

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or skeleton == null:
		return
	_clock += delta
	expressions.update(delta)
	# Blinks only on the resting face.
	if expressions.current == "neutral":
		_blink_timer -= delta
		if _blink_timer <= 0.0 and _blink_t < 0.0:
			_blink_t = 0.0
		if _blink_t >= 0.0:
			_blink_t += delta
			var seq := [1, 2, 2, 1]
			var i := int(_blink_t / 0.035)
			if i >= seq.size():
				_blink_t = -1.0
				_blink_timer = randf_range(2.0, 5.0)
				_show_eyes(expressions.eyes())
			else:
				_show_eyes([seq[i], seq[i]])
	# Beak: expression mode + squawk pop.
	var target := 0.0
	match expressions.beak_mode():
		"open":
			target = 0.8
		"chatter":
			target = 0.25 + 0.25 * signf(sin(_clock * 40.0))
		"clenched":
			target = -0.05
	_beak_pop = maxf(_beak_pop - delta, 0.0)
	if _beak_pop > 0.0:
		target = maxf(target, 1.0)
	_beak = move_toward(_beak, target, delta * 12.0)
	_head_yaw = lerp_angle(_head_yaw, clampf(head_yaw_target, -MAX_HEAD_YAW, MAX_HEAD_YAW), 1.0 - exp(-14.0 * delta))
	_place_symbol()
	_update_face_center()

## Anime art style: the toon shader bends normals around the head into a sphere's (smoothed face shading),
## so it needs the head's center every frame. Cleared when the character style changes away.
var _face_on := false
var _face_meshes: Array[MeshInstance3D] = []

func _update_face_center() -> void:
	var on := ArtStyle.char_style == ArtStyle.ANIME and _bones.has("head")
	if not on and not _face_on:
		return
	var v := Vector4.ZERO
	if on:
		var pose := skeleton.global_transform * skeleton.get_bone_global_pose(_bones["head"])
		var c := pose.origin + pose.basis.y.normalized() * FACE_CENTER_UP * pose.basis.get_scale().y
		v = Vector4(c.x, c.y, c.z, FACE_RADIUS * global_basis.get_scale().y)
	if _face_meshes.is_empty():
		for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
			if not mi.name.begins_with("eyes_"):
				_face_meshes.append(mi)
	for mi in _face_meshes:
		if is_instance_valid(mi) and mi.visible:
			mi.set_instance_shader_parameter("as_face", v)
	_face_on = on

## Short beak opening (e.g. a full-charge shot).
func pop_beak(duration := 0.25) -> void:
	_beak_pop = maxf(_beak_pop, duration)

## Keeps the floating symbol up and to the screen-right of the head, whatever way the bird faces.
func _place_symbol() -> void:
	if _symbol and is_instance_valid(_symbol):
		if lying:
			# KO'd and on its back/side: stars circle above the head wherever it ended up.
			var h := skeleton.global_transform * skeleton.get_bone_global_pose(_bones["head"]).origin
			_symbol.global_position = Vector3(h.x + 0.3, maxf(h.y, 0.3) + 0.45, h.z)
		else:
			_symbol.global_position = global_position + Vector3(0.48, 1.25 + data.neck_extend, 0.0)

# --- Procedural layer (called by BirdPoseModifier after the AnimationPlayer) ----------

func apply_procedural_pose(sk: Skeleton3D) -> void:
	if data == null:
		return
	for side in ["L", "R"]:
		var s := 1.0 if side == "L" else -1.0
		_add("wing_" + side, Quaternion(Vector3.BACK, s * flap), sk)
	var pitch := Quaternion(Vector3.RIGHT, deg_to_rad(data.neck_pitch)) # +X tips the head forward
	_add("neck", Quaternion(Vector3.UP, _head_yaw * 0.4) * pitch, sk)
	_add("head", Quaternion(Vector3.UP, _head_yaw * 0.6), sk)
	var h: int = _bones["head"]
	sk.set_bone_pose_scale(h, Vector3.ONE * data.head_scale)
	var neck_global := sk.get_bone_global_rest(_bones["neck"]).basis
	sk.set_bone_pose_position(h, sk.get_bone_rest(h).origin + neck_global.inverse() * Vector3(0, data.neck_extend, 0))
	var b: int = _bones["beak_lower"]
	var rest_rot := sk.get_bone_rest(b).basis.get_rotation_quaternion()
	sk.set_bone_pose_rotation(b, rest_rot * Quaternion(Vector3.RIGHT, _beak_sign * _beak * BEAK_MAX_OPEN))

## Multiplies a skeleton-space rotation onto a bone's current (animated) pose.
func _add(bone: String, delta_skel: Quaternion, sk: Skeleton3D) -> void:
	var idx: int = _bones[bone]
	var rest_global := sk.get_bone_global_rest(idx).basis
	var local := Quaternion(rest_global.inverse() * Basis(delta_skel) * rest_global)
	sk.set_bone_pose_rotation(idx, sk.get_bone_pose_rotation(idx) * local)

## Picks the rotation sign about beak_lower's local X that swings the jaw tip downward.
func _find_beak_open_sign() -> float:
	var idx: int = _bones["beak_lower"]
	var rest := skeleton.get_bone_global_rest(idx)
	var parent_global := rest * skeleton.get_bone_rest(idx).affine_inverse()
	var rest_rot := skeleton.get_bone_rest(idx).basis.get_rotation_quaternion()
	var opened := parent_global * Transform3D(Basis(rest_rot * Quaternion(Vector3.RIGHT, 0.3)), skeleton.get_bone_rest(idx).origin)
	return 1.0 if opened.basis.y.y < rest.basis.y.y else -1.0
