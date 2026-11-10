@tool
class_name ArenaCamera
extends Camera3D
## Fixed orthographic arena camera, Boomerang Fu-style: pitched down, no yaw, no follow.
## Fits the ortho size so the whole arena (plus margins and UI space) is always visible.

@export var arena_size := Vector2(20.0, 14.0):
	set(value):
		arena_size = value
		fit()
@export var arena_center := Vector3.ZERO:
	set(value):
		arena_center = value
		fit()
## Extra vertical room for tall props standing on the far edge (m).
@export var back_prop_height := 1.5:
	set(value):
		back_prop_height = value
		fit()
## Overrides tuning.camera_pitch when > 0 (useful for comparing angles).
@export_range(0.0, 89.0) var pitch_override := 0.0:
	set(value):
		pitch_override = value
		fit()
@export var distance := 30.0
## Number keys 1/2/3 switch between 50°/55°/60° at runtime (look test only).
@export var debug_pitch_keys := false

func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	keep_aspect = KEEP_HEIGHT
	near = 1.0
	far = 100.0
	if not Engine.is_editor_hint():
		get_viewport().size_changed.connect(fit)
	fit()

func get_pitch() -> float:
	return pitch_override if pitch_override > 0.0 else Tuning.get_default().camera_pitch

func fit() -> void:
	if not is_inside_tree():
		return
	var tuning := Tuning.get_default()
	var pitch := deg_to_rad(get_pitch())
	rotation = Vector3(-pitch, 0.0, 0.0)
	var forward := -basis.z
	position = arena_center - forward * distance

	var vp_size := get_viewport().get_visible_rect().size
	if Engine.is_editor_hint():
		vp_size = Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"),
				ProjectSettings.get_setting("display/window/size/viewport_height"))
	var aspect := vp_size.x / maxf(vp_size.y, 1.0)

	var m := tuning.camera_margin
	# Ground depth foreshortens by sin(pitch); vertical props show by cos(pitch).
	var needed_height := (arena_size.y + 2.0 * m) * sin(pitch) + back_prop_height * cos(pitch)
	var needed_width := arena_size.x + 2.0 * m
	var fit_height := maxf(needed_height, needed_width / aspect)
	_base_size = fit_height + tuning.camera_top_ui_margin
	size = _base_size
	# Shift the view up so the arena sits low and the top band is free for the score UI.
	_base_v_offset = tuning.camera_top_ui_margin * 0.5
	v_offset = _base_v_offset

# --- Juice ---------------------------------------------------------------------

var _base_size := 13.0
var _base_v_offset := 0.0
var _trauma := 0.0
var _punch := 0.0
var _noise_t := 0.0

## Adds screen shake (0..1). Offset scales with trauma² so small hits stay subtle.
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

## Briefly shrinks the ortho size (zoom in), then eases back.
## Match win: ease in on a point (zoom = fraction of the normal view size), until the scene reloads.
var _focus_on := false
var _focus_point := Vector3.ZERO
var _focus_zoom := 1.0
var _focus_k := 0.0

func focus_on(point: Vector3, zoom := 0.6) -> void:
	_focus_on = true
	_focus_k = 0.0
	_focus_point = point
	_focus_zoom = zoom

## Back to the whole arena (next round): eases out.
func clear_focus() -> void:
	_focus_on = false

func punch_zoom() -> void:
	_punch = 1.0

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var tuning := Tuning.get_default()
	_noise_t += delta
	_trauma = maxf(_trauma - tuning.shake_decay * delta, 0.0)
	_punch = maxf(_punch - delta * 3.0, 0.0)
	var amp := _trauma * _trauma * tuning.shake_max_offset
	h_offset = amp * sin(_noise_t * 71.0) * cos(_noise_t * 13.0)
	v_offset = _base_v_offset + amp * sin(_noise_t * 59.0 + 1.7) * cos(_noise_t * 17.0)
	var p := _punch * _punch * (3.0 - 2.0 * _punch) # smoothstep: fast in, eased out
	size = _base_size * (1.0 - tuning.punch_zoom_amount * p)
	_focus_k = move_toward(_focus_k, 1.0 if _focus_on else 0.0, delta / 0.7)
	if _focus_k > 0.0:
		var k := _focus_k * _focus_k * (3.0 - 2.0 * _focus_k)
		var rel := _focus_point + Vector3.UP * 0.5 - arena_center
		h_offset = lerpf(h_offset, rel.dot(global_basis.x), k)
		v_offset = lerpf(v_offset, rel.dot(global_basis.y), k)
		size = lerpf(size, _base_size * _focus_zoom, k)
	# Pixel-art style: shake moves in whole low-res pixels and the punch zoom is off, so scenery never shimmers.
	var snap := ArtStyle.pixel_snap(self)
	if snap > 0.0:
		size = _base_size
		snap = ArtStyle.pixel_snap(self)
		h_offset = snappedf(h_offset, snap)
		v_offset = snappedf(v_offset - _base_v_offset, snap) + _base_v_offset

func _unhandled_input(event: InputEvent) -> void:
	if not debug_pitch_keys:
		return
	for deg in [50, 55, 60]:
		if event.is_action_pressed("debug_pitch_%d" % deg):
			pitch_override = deg
			print("Camera pitch: %d°" % deg)
