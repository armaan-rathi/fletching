class_name BirdSpirit
extends Node3D
## KO spirit: a translucent, glowing copy of the knocked-out bird (same parts and shape, tinted in the player's
## color) with peaceful closed eyes. It rises slowly up the screen with wing flaps and a gentle sway, then fades.
## The KO'd player can steer it with their move input while it rises (a little fun for the loser): sideways
## drifts it, up / down speed up or hold back the rise; it leans into the drift and flaps harder.
## Purely visual: no collision, no shadow, never x-rayed.

const BASE := preload("res://assets/birds/bird_base.glb")
const GHOST := preload("res://assets/shaders/ghost.gdshader")
const GHOST_EYE := preload("res://assets/shaders/ghost_eye.gdshader")
const EYE_ATLAS := preload("res://assets/birds/eyes/ph_eye_atlas.png")

var _t := 0.0
var _model: BirdModel
var _mats: Array[ShaderMaterial] = []
var _start := Vector3.ZERO
var _up := Vector3.UP
var _right := Vector3.RIGHT
var _tune: Tuning
var _input: Object # the KO'd bird's input (PlayerInput / CpuInput); CPUs give no input
var _steer := Vector2.ZERO # x: sideways drift (m), y: extra rise (m)
var _lean := 0.0
var _effort := 0.0
var _flap_phase := 0.0

static func spawn(bird: Bird) -> BirdSpirit:
	var s := BirdSpirit.new()
	s.name = "Spirit"
	var m := BirdModel.new()
	m.data = bird.bird_data
	m.variant = bird.variant
	var base := BASE.instantiate()
	base.name = "BirdBase" # animation tracks are relative to this name
	base.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) # GLB faces -Y in Blender (= +Z here)
	m.add_child(base)
	s.add_child(m)
	s._model = m
	Fx._parent().add_child(s)
	s._setup(bird)
	return s

func _setup(bird: Bird) -> void:
	_tune = Tuning.get_default()
	_input = bird.input
	_start = bird.global_position + Vector3.UP * 0.15
	global_position = _start
	rotation.y = PI # face the camera so the closed eyes read
	var cam := get_viewport().get_camera_3d()
	if cam:
		_up = cam.global_basis.y
		_right = cam.global_basis.x
	var body := ShaderMaterial.new()
	body.shader = GHOST
	var eye := ShaderMaterial.new()
	eye.shader = GHOST_EYE
	eye.set_shader_parameter("atlas", EYE_ATLAS)
	for mat in [body, eye]:
		mat.set_shader_parameter("tint", bird.player_color)
		mat.set_shader_parameter("alpha", _tune.ko_spirit_alpha)
		mat.set_shader_parameter("fade", 0.0)
		_mats.append(mat)
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			mi.set_surface_override_material(i, eye if src and src.resource_name == "eyes" else body)
	scale = Vector3.ONE * 0.85
	_update(0.0)

func _process(delta: float) -> void:
	_t += delta
	var m := Vector2.ZERO
	if _input and is_instance_valid(_input) and _input.has_method("get_move"):
		m = _input.get_move() # screen axes: x right, y down
	_steer.x = clampf(_steer.x + m.x * _tune.ko_spirit_steer_speed * delta, -_tune.ko_spirit_steer_max, _tune.ko_spirit_steer_max)
	_steer.y = maxf(_steer.y - m.y * _tune.ko_spirit_steer_rise * delta, -_tune.ko_spirit_height * 0.5)
	_lean = lerpf(_lean, m.x, 1.0 - exp(-6.0 * delta))
	_effort = lerpf(_effort, m.length(), 1.0 - exp(-6.0 * delta))
	_flap_phase += delta * TAU * lerpf(1.1, 2.6, _effort)
	_update(_t)
	if _t >= _tune.ko_spirit_time:
		queue_free()

func _update(t: float) -> void:
	var u := clampf(t / _tune.ko_spirit_time, 0.0, 1.0)
	# Starts slow out of the body, then floats away up the screen.
	var rise := _tune.ko_spirit_height * pow(u, 1.4) + _steer.y
	var sway := sin(t * 3.0) * 0.18
	global_position = _start + _up * maxf(rise, 0.0) + _right * (sway + _steer.x)
	rotation.z = -sin(t * 3.0) * 0.12 - _lean * 0.35 # leans into the drift
	scale = Vector3.ONE * lerpf(0.85, 1.0, minf(u * 3.0, 1.0))
	# Slow, gentle wing flaps; faster and bigger while the player is steering.
	_model.flap = 0.25 + sin(_flap_phase) * lerpf(0.45, 0.7, _effort)
	var f := minf(u / 0.12, 1.0) * (1.0 - smoothstep(0.55, 1.0, u))
	for m in _mats:
		m.set_shader_parameter("fade", f)
