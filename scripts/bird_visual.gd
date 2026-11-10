class_name BirdVisual
extends Node3D
## Procedural animation on the bird's visual root: hop bounce, squash & stretch, lean, turn,
## recoil hop and idle breathing. Purely visual: the CharacterBody3D and hitbox stay grounded.
## Expects a child "Squash" (scaled around the feet) holding the model.

@onready var squash_node: Node3D = $Squash
@onready var model: BirdModel = $Squash/Model

var t: Tuning

var _hop_phase := 0.0 # 0..PI during a hop
var _hopping := false
var _squash := 0.0    # <0 squash, >0 stretch
var _squash_vel := 0.0
var _air_y := 0.0     # extra ballistic height from recoil etc.
var _air_vy := 0.0
var _lean := Vector3.ZERO
var _yaw := 0.0
var _time := 0.0
var _flap_kick := 0.0
## World yaw the head should look toward (set by the bird each frame). The head leads; the body follows.
var look_yaw := 0.0

signal landed(strength: float)

func _ready() -> void:
	t = Tuning.get_default()

## Called by the bird every physics frame.
func update_visual(delta: float, velocity: Vector3, facing: float, state_drawing: bool, dashing: bool) -> void:
	_time += delta
	var speed := Vector2(velocity.x, velocity.z).length()
	var speed_frac := clampf(speed / t.move_speed, 0.0, 1.5)

	# Hops: start when moving, always finish the current hop.
	var hop_y := 0.0
	if not dashing and (speed > 0.6 or _hopping):
		if not _hopping:
			_hopping = true
			_hop_phase = 0.0
			kick(1.0)
		var rate := lerpf(t.hop_rate_min, t.hop_rate_max, clampf(speed_frac, 0.0, 1.0))
		_hop_phase += delta * rate * PI
		if _hop_phase >= PI:
			_hopping = false
			kick(-1.0)
			landed.emit(speed_frac)
			if speed > 0.6:
				_hopping = true
				_hop_phase = fmod(_hop_phase, PI)
				kick(0.7)
		var height := lerpf(t.hop_height_min, t.hop_height_max, clampf(speed_frac, 0.0, 1.0))
		hop_y = sin(_hop_phase) * height if _hopping else 0.0

	# Ballistic extra hop (recoil).
	if _air_y > 0.0 or _air_vy > 0.0:
		_air_vy -= 18.0 * delta
		_air_y += _air_vy * delta
		if _air_y <= 0.0:
			_air_y = 0.0
			_air_vy = 0.0
			kick(-0.8)

	# Squash spring.
	var k := 320.0
	var c := 18.0
	_squash_vel += (-k * _squash - c * _squash_vel) * delta
	_squash += _squash_vel * delta
	var s := clampf(_squash, -1.0, 1.0)
	var target := t.stretch_scale if s > 0.0 else t.squash_scale
	var a := absf(s)
	var breathe := 0.0 if speed > 0.3 else sin(_time * 2.6) * 0.02
	squash_node.scale = Vector3(lerpf(1.0, target.x, a) - breathe * 0.5, lerpf(1.0, target.y, a) + breathe, lerpf(1.0, target.x, a) - breathe * 0.5)

	# Lean into movement.
	var move_dir := Vector3(velocity.x, 0, velocity.z)
	var lean_target := Vector3.ZERO
	if move_dir.length() > 0.1:
		var axis := Vector3.UP.cross(move_dir.normalized())
		lean_target = axis * deg_to_rad(t.lean_degrees) * clampf(speed_frac, 0.0, 1.2)
	_lean = _lean.lerp(lean_target, 1.0 - exp(-14.0 * delta))

	# Body yaw follows the logical facing a little behind the head, so the head visibly leads turns.
	_yaw = lerp_angle(_yaw, facing, 1.0 - exp(-16.0 * delta))
	model.head_yaw_target = wrapf(look_yaw - _yaw, -PI, PI)

	var lean_basis := Basis.IDENTITY
	if _lean.length() > 0.0001:
		lean_basis = Basis(_lean.normalized(), _lean.length())
	basis = lean_basis * Basis(Vector3.UP, _yaw)
	position.y = hop_y + _air_y

	# Wings: little flaps on hops and a flutter after kicks, on top of the keyframed clip.
	_flap_kick = move_toward(_flap_kick, 0.0, delta * 4.0)
	var hop_flap := sin(_hop_phase) * 0.35 if _hopping and not state_drawing else 0.0
	model.flap = hop_flap + sin(_time * 40.0) * _flap_kick * 0.6

## Positive = stretch, negative = squash (about -1..1).
func kick(amount: float) -> void:
	_squash_vel += amount * 9.0

func hop(up_speed: float) -> void:
	_air_vy = maxf(_air_vy, up_speed)
	_air_y = maxf(_air_y, 0.001)
	kick(0.8)

func flutter() -> void:
	_flap_kick = 1.0
