class_name Bird
extends CharacterBody3D
## A bird in the arena (human or CPU): snappy movement, dash (cancels a draw), bow draw/fire with a quiver,
## curve steering of fresh arrows, melee on its own button (wing slap stuns; a well-timed swing bats arrows away), one-hit KOs. Visual feel lives in BirdVisual;
## all numbers come from Tuning. Input comes from `input` (PlayerInput for humans, CpuInput for CPUs).

signal arrows_changed(count: int)
signal knocked_out(victim: Bird, killer: Bird)
signal arrow_fired(bird: Bird)
signal power_ups_changed(bird: Bird)
signal parried(bird: Bird, arrow: Arrow)
signal stunned(victim: Bird, by: Bird)
signal shrike_fired(bird: Bird)

enum State { NORMAL, DRAWING, DASHING, SLAPPING, STUNNED, KO }
enum AimSource { MOVE, STICK, MOUSE }

const ARROW_SCENE_PATH := "res://scenes/weapons/arrow.tscn" # loaded lazily: arrow.gd refers back to Bird
static var _arrow_scene: PackedScene
const MOUSE_FACE_TIME := 1.5 ## s after moving the mouse that an idle bird keeps facing the cursor
const L_BIRDS := 2
const L_HITBOX := 4

@export var player_index := 0
@export var player_color := Color("ff5a5a")
## Which bird this is (cosmetic only) and which of its color variants.
@export var bird_data: BirdData
@export_range(0, 3) var variant := 0
@export var display_name := "P1"

@onready var visual: BirdVisual = $VisualRoot
@onready var bow: Bow = $VisualRoot/Bow
@onready var model: BirdModel = $VisualRoot/Squash/Model
@onready var ring: MeshInstance3D = $PlayerRing
@onready var charge_ring: MeshInstance3D = $ChargeRing
@onready var aim_pivot: Node3D = $AimPivot
@onready var aim_line: MeshInstance3D = $AimPivot/AimLine
@onready var quiver_pips: Node3D = $VisualRoot/Squash/Quiver
@onready var blob: MeshInstance3D = $BlobShadow
@onready var hitbox: Area3D = $Hitbox

var input = PlayerInput.new() ## PlayerInput or CpuInput (same interface)
var t: Tuning
var state := State.NORMAL
var facing := PI ## yaw, radians; forward = -Z rotated by facing (PI = facing the camera)
var arrows := 3
## While true (round countdown, round over) the bird ignores input.
var frozen := false
## Looping clip shown instead of idle (e.g. "victory"); cleared by input or the next round.
var pose_override := ""
## Held power-ups, oldest first (max PowerUps.MAX_HELD). They last the whole match (kept between rounds).
var power_ups: Array[String] = []
var _badges: Node3D

var _draw_time := 0.0
var _full_flash := 0.0
var _was_full := false
var _dash_time := 0.0
var _dash_dir := Vector3.FORWARD
var _dash_cooldown := 0.0
var _dash_start := Vector3.ZERO
var last_dash_distance := 0.0 ## for tuning/tests
var _slap_time := 0.0
var _slap_cooldown := 0.0
var _slap_done := false
var _stun_time := 0.0
## Standing in water (Birdbath puddle): slower, shorter dashes, splashy hops.
var wading := false
var _stun_immune := 0.0
var _ko_time := 0.0
var _ko_dir := Vector3.FORWARD
var _ko_yaw := 0.0        # facing at the hit
var _ko_spin := 0.0       # radians of yaw spin over the flop
var _ko_tip := Basis()    # back/side tip, in the bird's yaw frame
var _ko_spirit := false
var _ko_vis_t := 0.0
var _shrike_draw := false # the current draw is a shrike (lob straight up), released with the shrike button     # render-time clock for the flop visuals (smooth on high-refresh screens)
var _aim_source := AimSource.MOVE
var _mouse_time := -100.0
var _prev_move := Vector2.ZERO
var _clock := 0.0
var _last_input := 0.0

func _ready() -> void:
	t = Tuning.get_default()
	arrows = t.quiver_size
	motion_mode = MOTION_MODE_FLOATING
	collision_mask |= 128 # bird_blockers (e.g. under the birdbath bowl; arrows ignore that layer)
	model.stencil_slot = clampi(player_index, 0, 3)
	model.player_color = player_color
	set_bird(bird_data if bird_data else model.data, variant)
	bow.set_stencil_slot(model.stencil_slot)
	bow.set_arrow_color(player_color)
	ring.material_override = ring.material_override.duplicate()
	(ring.material_override as StandardMaterial3D).albedo_color = player_color
	for mi in [charge_ring, aim_line]:
		mi.material_override = mi.material_override.duplicate()
		mi.material_override.set_shader_parameter("color", player_color)
	bow.hand = model.hand_r
	_build_quiver()
	visual.landed.connect(_on_landed)
	_update_quiver()
	add_to_group("birds")
	_badges = Node3D.new()
	_badges.name = "PowerBadges"
	add_child(_badges)

## Swap the bird's look (cosmetic only: stats, hitbox and controls never change).
func set_bird(data: BirdData, variant_index := 0) -> void:
	bird_data = data
	variant = variant_index
	model.data = data
	model.variant = variant_index

func is_alive() -> bool:
	return state != State.KO

func is_cpu() -> bool:
	return input is CpuInput

## Back to full health and arrows at a spawn point (between rounds).
func reset_for_round(pos: Vector3, face_yaw: float) -> void:
	if state == State.KO:
		# The body left from last round poofs into feathers.
		var cols := bird_data.variant(variant)
		Fx.poof(global_position + Vector3.UP * 0.3)
		Fx.feathers(global_position + Vector3.UP * 0.3, [cols.get("body", Color.WHITE), cols.get("accent", Color.WHITE), cols.get("belly", Color.WHITE)])
	global_position = pos
	facing = face_yaw
	velocity = Vector3.ZERO
	state = State.NORMAL
	_draw_time = 0.0
	_dash_cooldown = 0.0
	_slap_cooldown = 0.0
	_stun_time = 0.0
	_stun_immune = 0.0
	_shrike_draw = false
	_ko_spin = 0.0
	model.lying = false
	visual.transform = Transform3D()
	visual.squash_node.scale = Vector3.ONE
	collision_layer = L_BIRDS
	hitbox.collision_layer = L_HITBOX
	ring.visible = true
	_badges.visible = true
	blob.visible = true
	blob.position = Vector3(0, 0.1, 0)
	pose_override = ""
	_set_arrows(t.quiver_size)
	model.expressions.clear()
	model.play_state("idle")

# --- Power-ups ---------------------------------------------------------------------

func has_power(type: String) -> bool:
	return power_ups.has(type)

func add_power_up(type: String) -> void:
	power_ups = PowerUps.add(power_ups, type)
	_build_badges()
	model.expressions.request("happy", 0.8)
	visual.kick(0.9)
	Sfx.play("powerup_pickup")
	power_ups_changed.emit(self)

## Little power-up icons floating above the head (oldest left).
func _build_badges() -> void:
	for c in _badges.get_children():
		c.queue_free()
	for i in power_ups.size():
		var sp := Sprite3D.new()
		sp.texture = PowerUps.TYPES[power_ups[i]]["icon"]
		sp.pixel_size = 0.3 / 128.0
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.no_depth_test = true
		sp.shaded = false
		sp.render_priority = 8
		sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		sp.position = Vector3((i - (power_ups.size() - 1) * 0.5) * 0.32, 1.5 + bird_data.neck_extend, 0)
		_badges.add_child(sp)

func _speed() -> float:
	return t.move_speed * (t.featherweight_speed if has_power("featherweight") else 1.0) * (t.water_speed if wading else 1.0)

func _dash_length() -> float:
	return t.dash_distance * (t.featherweight_dash if has_power("featherweight") else 1.0) * (t.water_dash if wading else 1.0)

# --- Input helpers ---------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not (input is PlayerInput and input.uses_mouse()):
		return
	if PlayerInput.test_mode and input.include_actions:
		return # scripted test player: the real mouse over the window must not steer its aim
	if event is InputEventMouseMotion and event.relative.length() > 1.5:
		_mouse_time = _clock
		_last_input = _clock
		_aim_source = AimSource.MOUSE
	elif event is InputEventMouseButton and event.pressed:
		_mouse_time = _clock
		_aim_source = AimSource.MOUSE

func forward() -> Vector3:
	return Vector3(-sin(facing), 0.0, -cos(facing))

static func yaw_of(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)

## World-space move input (also steers this bird's fresh arrows: curve shots).
func get_move_input() -> Vector3:
	if frozen or state == State.KO:
		return Vector3.ZERO
	return PlayerInput.to_world(input.get_move())

## Direction from the bird to the point under the cursor (on the plane arrows fly in).
func _cursor_dir(screen_pos: Variant = null) -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.ZERO
	var mp: Vector2 = screen_pos if screen_pos != null else get_viewport().get_mouse_position()
	var origin := cam.project_ray_origin(mp)
	var dir := cam.project_ray_normal(mp)
	if absf(dir.y) < 0.0001:
		return Vector3.ZERO
	var hit := origin + dir * ((t.arrow_height - origin.y) / dir.y)
	var d := hit - global_position
	d.y = 0.0
	return d.normalized() if d.length() > 0.3 else Vector3.ZERO

## Where the head looks: the aim while drawing, else the right stick or a recently moved cursor, else ahead.
func _look_yaw(stick: Vector2) -> float:
	if state == State.NORMAL:
		if stick.length() > 0.35:
			return yaw_of(PlayerInput.to_world(stick))
		if _clock - _mouse_time < MOUSE_FACE_TIME:
			var d := _cursor_dir()
			if d != Vector3.ZERO:
				return yaw_of(d)
	return facing

func _turn_toward(dir: Vector3, rate_deg: float, delta: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	var target := yaw_of(dir)
	var diff := wrapf(target - facing, -PI, PI)
	var step := deg_to_rad(rate_deg) * delta
	facing = wrapf(facing + clampf(diff, -step, step), -PI, PI)

# --- Main loop -------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_clock += delta
	_dash_cooldown = maxf(_dash_cooldown - delta, 0.0)
	_slap_cooldown = maxf(_slap_cooldown - delta, 0.0)
	_stun_immune = maxf(_stun_immune - delta, 0.0)
	wading = is_alive() and Fx.in_water(global_position)
	input.poll()
	var live := not frozen and state != State.KO and state != State.STUNNED
	var move2: Vector2 = input.get_move() if live else Vector2.ZERO
	var move := PlayerInput.to_world(move2)
	var stick: Vector2 = input.get_aim_stick() if live else Vector2.ZERO
	if stick.length() > 0.35:
		_aim_source = AimSource.STICK
	if state == State.DRAWING and move2.length() > 0.3 and (move2 - _prev_move).length() > 0.15:
		_aim_source = AimSource.MOVE
	_prev_move = move2

	if live and input.dash_pressed() and _dash_cooldown <= 0.0 and state != State.DASHING and state != State.SLAPPING:
		_start_dash(move)
	# Melee has its own button: works with or without arrows, and cancels a draw (to bat an arrow away).
	if live and input.melee_pressed() and (state == State.NORMAL or state == State.DRAWING):
		_start_slap()

	match state:
		State.NORMAL:
			_process_normal(delta, move, stick, live)
		State.DRAWING:
			_process_drawing(delta, move, stick)
		State.DASHING:
			_process_dash(delta)
		State.SLAPPING:
			_process_slap(delta)
		State.STUNNED:
			_process_stun(delta)
		State.KO:
			_process_ko(delta)

	velocity.y = 0.0
	move_and_slide()
	global_position.y = 0.0
	if state == State.DASHING and get_slide_collision_count() > 0:
		model.expressions.request("confused", 1.0) # bonked into something mid-dash
		Sfx.play("bonk")

	if live and input.active():
		_last_input = _clock
		pose_override = ""
	_update_face_and_anim()

	visual.look_yaw = _look_yaw(stick)
	if state != State.KO: # the procedural KO flop owns the body while KO'd
		visual.update_visual(delta, velocity, facing, state == State.DRAWING, state == State.DASHING)
	# Ground shadow stays on the ground; it shrinks a little while the bird is in the air.
	var air := clampf(visual.position.y / 0.3, 0.0, 1.0) if state != State.KO else 0.0
	blob.scale = Vector3.ONE * (1.0 - 0.25 * air)
	_update_indicators(delta)

# --- Match win celebration (RoundController, after the match-deciding KO) ---------------
# Per-bird personality (BirdData.victory_style), ~3 s, built from the expression set, squawks, hops, kicks
# (squash), head turns and facing. The bird is frozen (no input) meanwhile.

## The expression the winner holds once the celebration is over (results screen).
func victory_expression() -> String:
	return "smug" if bird_data and bird_data.victory_style in ["evil_laugh", "smirk"] else "happy"

func celebrate() -> void:
	var style := bird_data.victory_style if bird_data else "proud"
	pose_override = "victory"
	var ex := model.expressions
	match style:
		"proud": # regal: chest out, a single proud squawk, surveys the field
			ex.request("happy", 3.2)
			_at(0.15, func(): model.squawk(); visual.kick(1.2))
			_at(0.9, func(): model.head_yaw_target = -0.5)
			_at(1.5, func(): model.head_yaw_target = 0.5)
			_at(2.1, func(): model.head_yaw_target = 0.0; visual.kick(1.0))
		"crowing": # cocky: three crows, hopping
			ex.request("happy", 3.2)
			for k in 3:
				_at(0.1 + k * 0.75, func(): model.squawk(); visual.hop(3.2); visual.kick(1.0))
		"evil_laugh": # mischievous: shaking with laughter
			ex.request("smug", 3.2)
			_at(0.1, func(): visual.hop(2.2))
			for k in 18:
				_at(0.35 + k * 0.11, func(): visual.kick(0.45 if k % 2 == 0 else -0.3))
			_at(0.5, func(): model.head_yaw_target = 0.35)
			_at(1.4, func(): model.head_yaw_target = -0.35)
			_at(2.3, func(): model.head_yaw_target = 0.0; model.squawk())
		"who_me": # surprised: "!", looks around "?", then delighted
			ex.request("shocked", 0.7)
			_at(0.05, func(): visual.hop(1.6))
			_at(0.75, func(): ex.request("confused", 0.9); model.head_yaw_target = 0.6)
			_at(1.2, func(): model.head_yaw_target = -0.6)
			_at(1.7, func(): model.head_yaw_target = 0.0; ex.request("happy", 2.0); visual.hop(3.0); model.squawk())
			_at(2.4, func(): visual.hop(2.4))
		"smirk": # haughty: turns its head away with a little snicker
			ex.request("smug", 3.2)
			_at(0.3, func(): model.head_yaw_target = 0.55; visual.kick(0.8))
			_at(1.2, func(): visual.kick(0.4))
			_at(1.45, func(): visual.kick(0.4))
			_at(2.4, func(): model.head_yaw_target = 0.0)
		"giggle": # flamboyant: a twirl and giggly hops
			ex.request("happy", 1.2)
			_at(0.15, func():
				visual.hop(2.6)
				var tw := create_tween()
				tw.tween_property(self, "facing", facing + TAU, 0.7).set_trans(Tween.TRANS_SINE))
			_at(1.2, func(): ex.request("smug", 2.0); visual.hop(2.0))
			_at(1.6, func(): visual.hop(1.6))
			_at(2.0, func(): visual.hop(1.6); model.squawk())

func _at(delay: float, f: Callable) -> void:
	get_tree().create_timer(delay).timeout.connect(func(): if is_instance_valid(self): f.call())

## Keyframed state clip + expression requests for the current state.
func _update_face_and_anim() -> void:
	match state:
		State.DRAWING:
			model.play_state("draw")
			model.expressions.request("focused")
		State.DASHING:
			model.play_state("dash")
			model.expressions.request("determined")
		State.SLAPPING:
			model.expressions.request("determined")
		State.STUNNED:
			model.play_state("idle")
			model.expressions.request("stunned") # dazed eyes + circling stars
		State.KO:
			model.play_state("ko") # limp pose (held); the flop in _process_ko tips the whole bird over
			model.expressions.request("ko") # X eyes, screaming beak, dizzy stars
		_:
			model.play_state(pose_override if pose_override != "" else "idle")
			if pose_override == "" and not frozen and _clock - _last_input > bird_data.sleepy_delay:
				model.expressions.request("sleepy")

func _process_normal(delta: float, move: Vector3, stick: Vector2, live: bool) -> void:
	if live and input.shrike_pressed():
		if arrows > 0:
			_start_draw(true)
			return
		visual.flutter()
		model.expressions.request("annoyed", 0.6)
		Sfx.play("empty")
	if live and input.shoot_pressed():
		if arrows > 0:
			_start_draw()
			return
		# Empty quiver: shoot does nothing (melee is its own button now).
		visual.flutter()
		model.expressions.request("annoyed", 0.6)
		Sfx.play("empty")
	var target := move * _speed()
	var rate := t.acceleration if move.length() > 0.1 else t.deceleration
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(target, rate * delta)
	velocity = Vector3(hv.x, 0, hv.z)

	if stick.length() > 0.35:
		_turn_toward(PlayerInput.to_world(stick), t.turn_speed, delta)
	elif move.length() > 0.2:
		_turn_toward(move, t.turn_speed, delta)
	elif live and _clock - _mouse_time < MOUSE_FACE_TIME:
		_turn_toward(_cursor_dir(), t.turn_speed, delta)

func _process_drawing(delta: float, move: Vector3, stick: Vector2) -> void:
	_draw_time += delta
	# Rooted: bleed off any momentum.
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(Vector3.ZERO, t.deceleration * delta)
	velocity = Vector3(hv.x, 0, hv.z)

	var aim := Vector3.ZERO
	match _aim_source:
		AimSource.MOUSE:
			aim = _cursor_dir()
		AimSource.STICK:
			aim = PlayerInput.to_world(stick) if stick.length() > 0.35 else Vector3.ZERO
		AimSource.MOVE:
			aim = move if move.length() > 0.2 else Vector3.ZERO
	_turn_toward(aim, t.aim_turn_rate, delta)

	var charge := get_charge()
	if charge >= 1.0 and not _was_full:
		_was_full = true
		_full_flash = 1.0
		Fx.impact(global_position + forward() * 0.45 + Vector3.UP * 0.6, Color("fff6b0"), 6, 2.0)
		if input.has_method("rumble"):
			input.rumble(t.full_charge_rumble_weak, t.full_charge_rumble_strong, t.full_charge_rumble_time)
	if frozen:
		_cancel_draw()
	elif _shrike_draw and not input.shrike_held():
		_fire_shrike()
	elif not _shrike_draw and not input.shoot_held():
		_fire()

func _process_dash(delta: float) -> void:
	# End at the start of the frame after the last dash frame, so every dash frame actually moves.
	if _dash_time >= t.dash_duration - 0.0001:
		_end_dash()
		return
	_dash_time += delta
	velocity = _dash_dir * (_dash_length() / t.dash_duration)

# --- Bow -------------------------------------------------------------------------

func get_charge() -> float:
	return clampf(_draw_time / t.full_draw_time, 0.0, 1.0) if state == State.DRAWING else 0.0

func _start_draw(shrike := false) -> void:
	_shrike_draw = shrike
	if _aim_source == AimSource.MOUSE and not input.uses_mouse():
		_aim_source = AimSource.MOVE
	state = State.DRAWING
	_draw_time = 0.0
	_was_full = false
	if _aim_source == AimSource.MOUSE:
		var d := _cursor_dir()
		if d != Vector3.ZERO:
			facing = lerp_angle(facing, yaw_of(d), 0.5)
	visual.kick(-0.5)

func _fire() -> void:
	var charge := get_charge()
	state = State.NORMAL
	var dir := forward()
	var speed := lerpf(t.arrow_speed_min, t.arrow_speed_max, charge)
	var center := global_position + Vector3.UP * t.arrow_height
	if _arrow_scene == null:
		_arrow_scene = load(ARROW_SCENE_PATH)
	var explosive := has_power("eggsplosive")
	# Trifecta: one arrow that splits into three partway through its flight (the two extras are bonus arrows:
	# they poof on impact, only this one comes from and returns to the quiver).
	var arrow: Arrow = _arrow_scene.instantiate()
	get_parent().add_child(arrow)
	arrow.launch(self, center, center + dir * 0.8, dir * speed, player_color, charge, explosive, false)
	if has_power("trifecta"):
		arrow.split_at = t.trifecta_split_time
	_set_arrows(arrows - 1)
	arrow_fired.emit(self)
	velocity = -dir * t.recoil_speed
	visual.hop(t.recoil_hop)
	model.play_once("release")
	if charge >= 1.0:
		model.pop_beak(0.3)
	if arrows == 0:
		model.expressions.request("annoyed", 1.0) # out of arrows
	Fx.shake(t.shake_on_fire * (1.0 + charge))
	Sfx.play("fire", lerpf(1.0, 1.15, charge), lerpf(-3.0, 1.0, charge))

## Shrike: lob the arrow on a high arc toward where the bird aims; charge sets how far it lands
## (shrike_range_min..max). While it flies, the move input nudges the landing spot. Trifecta lobs three across.
func _fire_shrike() -> void:
	var charge := get_charge()
	state = State.NORMAL
	_shrike_draw = false
	if _arrow_scene == null:
		_arrow_scene = load(ARROW_SCENE_PATH)
	var side := forward().cross(Vector3.UP).normalized()
	var from := global_position + Vector3.UP * 1.05 + forward() * 0.2
	var land := Arrow.shrike_landing(global_position, forward(), charge, t)
	var explosive := has_power("eggsplosive")
	var spread := [0.0, -1.0, 1.0] if has_power("trifecta") else [0.0]
	for k in spread:
		var arrow: Arrow = _arrow_scene.instantiate()
		get_parent().add_child(arrow)
		arrow.launch_shrike(self, from + side * (0.12 * k), land + side * (t.shrike_trifecta_offset * k),
			player_color, charge, explosive, k != 0.0)
	_set_arrows(arrows - 1)
	arrow_fired.emit(self)
	shrike_fired.emit(self)
	visual.hop(t.recoil_hop * 0.6)
	model.play_once("release")
	if arrows == 0:
		model.expressions.request("annoyed", 1.0)
	Fx.shake(t.shake_on_fire * 0.8)
	Sfx.play("fire", 1.3, -1.0)

## While drawing a shrike: a ring in the player's color where it would land now (moves with aim and charge).
var _shrike_preview: MeshInstance3D

func _update_shrike_preview(on: bool, charge: float) -> void:
	if not on:
		if _shrike_preview:
			_shrike_preview.visible = false
		return
	if _shrike_preview == null:
		_shrike_preview = MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.82
		torus.outer_radius = 1.0
		torus.rings = 32
		torus.ring_segments = 4
		_shrike_preview.mesh = torus
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(player_color.lerp(Color.WHITE, 0.3), 0.55)
		_shrike_preview.material_override = m
		_shrike_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_shrike_preview.top_level = true
		add_child(_shrike_preview)
	var p := Arrow.shrike_landing(global_position, forward(), charge, t)
	_shrike_preview.visible = true
	_shrike_preview.global_position = Vector3(p.x, 0.05, p.z)
	var r := t.shrike_stun_radius
	_shrike_preview.scale = Vector3(r, 0.12, r)

func _cancel_draw() -> void:
	state = State.NORMAL
	_draw_time = 0.0
	_shrike_draw = false

# --- Melee: wing slap (stuns) and arrow bat (parry) ---------------------------------------
# Separate button. The swing stuns birds in front for stun_time (no KO). For the first parry_window seconds
# it also bats away arrows that meet the wing: the arrow flies off mirrored about the contact direction
# (so the hit angle decides where it goes), still live and now owned by the batter. A bat shoves the batter
# back and locks melee for parry_cooldown, so nobody can defend forever.

func can_melee() -> bool:
	return _slap_cooldown <= 0.0 and (state == State.NORMAL or state == State.DRAWING)

## True while the swing can still bat arrows away.
func is_parrying() -> bool:
	return state == State.SLAPPING and _slap_time <= t.parry_window

## Could this swing bat an arrow at `pos` moving with `vel`? (in the window, in front, coming in)
func can_parry(pos: Vector3, vel: Vector3) -> bool:
	if not is_parrying():
		return false
	var to := pos - global_position
	to.y = 0.0
	if to.length() > t.parry_reach + 0.2:
		return false
	var v := Vector3(vel.x, 0, vel.z)
	if to.length() > 0.05 and v.dot(-to) <= 0.0:
		return false # moving away from us
	var dir := to if to.length() > 0.05 else -v
	return rad_to_deg(forward().angle_to(dir.normalized())) <= t.parry_arc * 0.5

## Bats an arrow that met the wing at `at`. Returns its new velocity (flat): mirrored about the contact
## normal, so a head-on arrow goes straight back and a glancing one skims off to the side.
func parry_arrow(arrow: Arrow, at: Vector3) -> Vector3:
	var n := at - global_position
	n.y = 0.0
	n = n.normalized() if n.length() > 0.05 else forward()
	var v := Vector3(arrow.velocity.x, 0, arrow.velocity.z)
	var speed := maxf(v.length() * t.parry_speed_scale, t.arrow_speed_min)
	var out := v - 2.0 * v.dot(n) * n
	if out.dot(n) < 0.2 * out.length():
		out = (out.normalized() + n).normalized() # always away from the batter
	out = out.normalized() * speed
	# The price: shoved back, and no melee for a moment.
	velocity = -n * t.parry_knockback
	_slap_cooldown = t.parry_cooldown
	visual.hop(0.12)
	Fx.hit_stop(t.parry_hitstop)
	Fx.shake(0.35)
	Fx.impact(at, Color("fff6b0"), 12, 4.5)
	Fx.impact(at, arrow.color, 5, 3.0)
	model.expressions.request("smug", 1.0)
	Sfx.play("parry")
	Sfx.play("parry_ring")
	parried.emit(self, arrow)
	return out

func _start_slap() -> void:
	if _slap_cooldown > 0.0:
		visual.flutter()
		return
	if state == State.DRAWING:
		_cancel_draw()
	state = State.SLAPPING
	Fx.swoosh(global_position + Vector3.UP * 0.5, facing, t.parry_arc, t.parry_reach + 0.2, t.parry_window * 1.6)
	if bird_data:
		Fx.smear(global_position + Vector3.UP * 0.55, facing, t.parry_arc, t.parry_reach, bird_data.variant(variant).get("body", Color.WHITE))
	Sfx.play("swing")
	_slap_time = 0.0
	_slap_done = false
	_slap_cooldown = t.slap_cooldown
	model.play_once("slap")
	visual.kick(0.8)

func _process_slap(delta: float) -> void:
	_slap_time += delta
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(Vector3.ZERO, t.deceleration * delta)
	velocity = Vector3(hv.x, 0, hv.z)
	if not _slap_done and _slap_time >= t.slap_hit_time:
		_slap_done = true
		var hit_any := false
		for b: Bird in get_tree().get_nodes_in_group("birds"):
			if b == self or not b.is_alive():
				continue
			var to := b.global_position - global_position
			to.y = 0.0
			if to.length() > t.slap_range or to.length() < 0.001:
				continue
			if rad_to_deg(forward().angle_to(to.normalized())) > t.slap_arc * 0.5:
				continue
			if b.stun(self, to.normalized()):
				hit_any = true
		Fx.impact(global_position + forward() * 0.8 + Vector3.UP * 0.5, Color.WHITE if not hit_any else Color("fff2c0"), 5 if not hit_any else 10, 3.0)
		if hit_any:
			Fx.shake(0.25)
	if _slap_time >= t.slap_root_time:
		state = State.NORMAL

## Hit by a wing slap: dazed for stun_time (can't move, shoot, dash or melee; still KO-able).
## Returns false if it didn't take (KO'd, mid-dash invulnerable, already stunned or briefly immune after one).
func stun(by: Bird, dir: Vector3) -> bool:
	if not is_alive() or is_invulnerable() or state == State.STUNNED or _stun_immune > 0.0:
		return false
	if state == State.DRAWING:
		_cancel_draw()
	state = State.STUNNED
	_stun_time = t.stun_time
	velocity = Vector3(dir.x, 0, dir.z).normalized() * t.stun_push
	visual.flutter()
	visual.hop(0.1)
	model.expressions.request("stunned", t.stun_time)
	Sfx.play("stun")
	Fx.hit_stop(0.04)
	stunned.emit(self, by)
	return true

func is_stunned() -> bool:
	return state == State.STUNNED

func _process_stun(delta: float) -> void:
	_stun_time -= delta
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(Vector3.ZERO, t.deceleration * 0.6 * delta)
	velocity = Vector3(hv.x, 0, hv.z)
	if _stun_time <= 0.0:
		state = State.NORMAL
		_stun_immune = t.stun_immunity
		model.expressions.clear()

# --- Dash ------------------------------------------------------------------------

func _start_dash(move: Vector3) -> void:
	if state == State.DRAWING:
		_cancel_draw()
	_dash_dir = move.normalized() if move.length() > 0.2 else forward()
	facing = yaw_of(_dash_dir)
	state = State.DASHING
	_dash_time = 0.0
	_dash_start = global_position
	visual.kick(1.2)
	Sfx.play("dash")
	Fx.dust(global_position + Vector3.UP * 0.1, 5, Fx.DUST_COLOR, 0.55, 1.6)
	Fx.speed_lines(global_position, _dash_dir, t.dash_duration + 0.15)
	if has_power("featherweight"):
		Fx.impact(global_position + Vector3.UP * 0.5, PowerUps.TYPES["featherweight"]["color"], 4, 2.0)

func _end_dash() -> void:
	state = State.NORMAL
	last_dash_distance = global_position.distance_to(_dash_start)
	velocity = _dash_dir * _speed()
	_dash_cooldown = t.dash_cooldown
	visual.kick(-1.0)
	Fx.dust(global_position + Vector3.UP * 0.1, 4, Fx.DUST_COLOR, 0.45, 1.0)
	# Holding shoot through a dash starts drawing right away.
	if not frozen and input.shoot_held() and arrows > 0:
		_start_draw()

func is_invulnerable() -> bool:
	if state != State.DASHING:
		return false
	return absf(_dash_time - t.dash_duration * 0.5) <= t.dash_invulnerability * 0.5

# --- Hits and KOs ----------------------------------------------------------------

## An arrow reached this bird's hitbox. Returns true if it knocked the bird out.
func hit_by_arrow(arrow: Arrow) -> bool:
	if not is_alive() or is_invulnerable():
		return false
	var dir := arrow.velocity
	dir.y = 0.0
	knock_out(arrow.owner_bird as Bird, dir.normalized())
	return true

func knock_out(killer: Bird, dir: Vector3) -> void:
	if not is_alive():
		return
	state = State.KO
	_draw_time = 0.0
	collision_layer = 0
	hitbox.collision_layer = 0
	if dir.length() < 0.01:
		dir = -forward()
	# Flop (procedural, see _process_ko): knocked back along the hit, spins, lands limp on its back or side.
	dir = Vector3(dir.x, 0, dir.z).normalized()
	_ko_time = 0.0
	_ko_dir = dir
	_ko_yaw = facing
	_ko_spin = TAU * t.ko_flop_turns * (1.0 if randf() < 0.5 else -1.0)
	var lie := randi() % 3 # 0 back, 1/2 left/right side
	_ko_tip = Basis(Vector3.RIGHT, PI / 2) if lie == 0 else Basis(Vector3.BACK, PI / 2 * (1.0 if lie == 1 else -1.0))
	_ko_spirit = false
	_ko_vis_t = 0.0
	visual.squash_node.scale = Vector3.ONE
	ring.visible = false
	_badges.visible = false
	var cols := bird_data.variant(variant)
	Fx.feathers(global_position + Vector3.UP * 0.6, [cols.get("body", Color.WHITE), cols.get("accent", Color.WHITE), cols.get("belly", Color.WHITE)])
	Fx.hit_stop(t.hitstop_ko)
	ArtStyle.impact_frame(global_position + Vector3.UP * 0.5) # anime FX extras only
	Sfx.play("ko")
	Fx.shake(0.55)
	Fx.punch_zoom()
	if killer and is_instance_valid(killer) and killer != self and killer.is_alive():
		killer.model.expressions.request("smug", 1.5)
	knocked_out.emit(self, killer)

func _process_ko(delta: float) -> void:
	_ko_time += delta
	var p := clampf(_ko_time / t.ko_flop_time, 0.0, 1.0)
	# Knockback slides out along the hit and stops as it lands (walls still stop it; no one collides with it).
	# The tumble itself is drawn in _process at render rate (see _ko_visual).
	velocity = _ko_dir * t.ko_knockback * (1.0 - p) * 2.0 * (1.0 if p < 1.0 else 0.0)
	model.lying = p > 0.5
	if not _ko_spirit and _ko_time >= t.ko_spirit_delay:
		_ko_spirit = true
		BirdSpirit.spawn(self)

func _process(delta: float) -> void:
	if state == State.KO:
		_ko_vis_t += delta
		_ko_visual(_ko_vis_t)

## The KO tumble: hop, half-spin (smooth sine ease, no whip at the start) and tip onto the back or side, then a
## small landing squash. Updated every rendered frame; after it lands the body is completely still.
func _ko_visual(time: float) -> void:
	var p := clampf(time / t.ko_flop_time, 0.0, 1.0)
	var e := sin(p * PI * 0.5)
	var hop := 4.0 * t.ko_flop_hop * p * (1.0 - p)
	var rot := Basis(Vector3.UP, _ko_yaw + _ko_spin * e) * Basis().slerp(_ko_tip, smoothstep(0.15, 0.9, p))
	var c := t.ko_body_center
	var lift := lerpf(c, t.ko_lie_height, smoothstep(0.15, 0.9, p)) + hop
	var u := (time - t.ko_flop_time) / t.ko_land_squash_time
	var sq := t.ko_land_squash * sin(PI * u) if u > 0.0 and u < 1.0 else 0.0
	var squash := Basis.from_scale(Vector3(1.0 + sq * 0.5, 1.0 - sq, 1.0 + sq * 0.5))
	visual.transform = Transform3D(squash, Vector3.ZERO) * Transform3D(rot, Vector3(0, lift, 0)) * Transform3D(Basis(), Vector3(0, -c, 0))

## An enemy arrow just whizzed past.
func near_miss() -> void:
	if is_alive():
		model.expressions.request("shocked", 0.8)
		Sfx.play("near_miss")

# --- Quiver ----------------------------------------------------------------------

func try_pickup_arrow() -> bool:
	if not is_alive() or arrows >= t.quiver_size:
		return false
	_set_arrows(arrows + 1)
	visual.kick(0.8)
	Sfx.play("arrow_pickup")
	return true

## An arrow of ours poofed back (auto-return or lost).
func return_arrow() -> void:
	if is_alive() and arrows < t.quiver_size:
		_set_arrows(arrows + 1)
		visual.flutter()
		Sfx.play("arrow_return")

func _set_arrows(n: int) -> void:
	arrows = clampi(n, 0, t.quiver_size)
	_update_quiver()
	arrows_changed.emit(arrows)

func _build_quiver() -> void:
	# Little arrows sticking out of the bird's back, one per arrow in the quiver.
	var slot := model.stencil_slot
	var shaft_mat := ToonMaterials.character(Color("d9b27c"), false, Color.WHITE, 0.1, slot)
	var fletch_mat := ToonMaterials.character(player_color, true, Color.WHITE, 0.2, slot)
	for i in t.quiver_size:
		var pip := Node3D.new()
		pip.name = "Pip%d" % i
		pip.position = Vector3(-0.17 + (i - (t.quiver_size - 1) * 0.5) * 0.075, 0.42, 0.3)
		pip.rotation_degrees = Vector3(-55, 0, 25.0 + (i - 1) * 10.0)
		var shaft := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.016; cyl.bottom_radius = 0.016; cyl.height = 0.4; cyl.radial_segments = 6; cyl.rings = 1
		shaft.mesh = cyl
		shaft.material_override = shaft_mat
		pip.add_child(shaft)
		var fl := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(0.12, 0.14, 0.03)
		fl.mesh = prism
		fl.position.y = 0.18
		fl.material_override = fletch_mat
		pip.add_child(fl)
		quiver_pips.add_child(pip)

func _update_quiver() -> void:
	for i in quiver_pips.get_child_count():
		quiver_pips.get_child(i).visible = i < arrows
	bow.has_arrow = arrows > 0

# --- Indicators ------------------------------------------------------------------

func _update_indicators(delta: float) -> void:
	var drawing := state == State.DRAWING
	var charge := get_charge()
	bow.drawn = move_toward(bow.drawn, 1.0 if drawing else 0.0, delta * 10.0)
	bow.charge = charge
	_full_flash = move_toward(_full_flash, 0.0, delta * 4.0)

	charge_ring.visible = drawing
	charge_ring.material_override.set_shader_parameter("charge", charge)
	charge_ring.material_override.set_shader_parameter("full_flash", _full_flash)

	# CPU birds don't show an aim line (it would telegraph their shots).
	aim_line.visible = drawing and not is_cpu() and not _shrike_draw
	bow.aim_up = move_toward(bow.aim_up, 1.0 if drawing and _shrike_draw else 0.0, delta * 8.0)
	_update_shrike_preview(drawing and _shrike_draw and not is_cpu(), charge)
	if aim_line.visible:
		var speed := lerpf(t.arrow_speed_min, t.arrow_speed_max, charge)
		var range_m := speed * sqrt(2.0 * t.arrow_height / t.arrow_gravity)
		# Stop the line where the arrow would stick (tree, wall).
		var from := global_position + Vector3.UP * t.arrow_height
		var q := PhysicsRayQueryParameters3D.create(from, from + forward() * range_m, Arrow.WORLD_MASK)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit:
			range_m = from.distance_to(hit.position)
		var line_len := maxf(minf(range_m, 30.0) - 0.6, 0.1)
		aim_pivot.rotation.y = facing
		aim_line.scale = Vector3(1, 1, line_len)
		aim_line.position = Vector3(0, 0.03, -0.6 - line_len * 0.5)
		aim_line.material_override.set_shader_parameter("length_m", line_len)
		aim_line.material_override.set_shader_parameter("charge", charge)

func _on_landed(strength: float) -> void:
	if wading:
		Fx.splash(global_position, 5, 0.8)
		Sfx.play("splash")
		return
	Sfx.play("step", 1.0, lerpf(-4.0, 0.0, clampf(strength, 0.0, 1.0)))
	if strength > 0.7:
		Fx.dust(global_position + Vector3.UP * 0.05, 2, Fx.DUST_COLOR, 0.35, 0.6)
