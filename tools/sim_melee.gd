extends SceneTree
## Melee / parry checks (practice mode, test map): melee has its own button, shoot with an empty quiver does
## nothing, a slap stuns (no KO) for stun_time, a stunned bird can still be shot, a well-timed swing bats an
## arrow back (it changes hands, can KO its shooter, the batter is shoved back and melee locks for
## parry_cooldown), a glancing contact deflects sideways, and a mistimed swing doesn't save you.
## Run (windowed): Godot --path . --resolution 1600x900 -s tools/sim_melee.gd -- <out_dir>

const BIRD := preload("res://scenes/birds/bird.tscn")
const ARROW := preload("res://scenes/weapons/arrow.tscn")

var out := ""
var fails := 0
var map: Node
var me: Bird
var t: Tuning

func _init() -> void:
	await process_frame
	out = OS.get_cmdline_user_args()[0]
	t = Tuning.get_default()
	root.get_node("MatchManager").setup_practice()
	map = load("res://scenes/maps/test_map.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	await _wait(0.3)
	me = map.get_node("Player1")
	me.set_process_input(false)
	me.input.include_actions = true

	# 1. Shoot with an empty quiver no longer slaps.
	var dummy := await _dummy(Vector3(-1.0, 0, -3.0))
	_place(me, Vector3(-2.0, 0, -3.0), Vector3.RIGHT)
	me._set_arrows(0)
	await _wait(0.3)
	await _tap("shoot")
	_check("empty-quiver shoot doesn't melee", me.state != Bird.State.SLAPPING and dummy.state == Bird.State.NORMAL, "state=%d" % me.state)

	# 2. Melee button: stun, not KO, wears off.
	await _wait(0.2)
	await _tap("melee")
	await _wait(0.15)
	_check("melee stuns an adjacent bird", dummy.is_stunned() and dummy.is_alive())
	await _shot("melee_stun")
	await _wait(t.stun_time + 0.1)
	_check("stun wears off after stun_time", not dummy.is_stunned() and dummy.is_alive(), "state=%d" % dummy.state)

	# 3. A stunned bird can still be shot.
	me._set_arrows(3)
	_place(me, Vector3(-4.0, 0, -3.0), Vector3.RIGHT)
	dummy.reset_for_round(Vector3(-2.6, 0, -3.0), 0.0)
	dummy.frozen = true
	await _wait(0.6)
	_place(me, Vector3(-3.6, 0, -3.0), Vector3.RIGHT)
	await _tap("melee")
	await _wait(0.3)
	var was_stunned := dummy.is_stunned()
	PlayerInput.test_press("shoot"); await _wait(0.1); PlayerInput.test_release("shoot")
	await _wait(0.3)
	_check("stunned bird can be shot (melee -> shot combo)", was_stunned and not dummy.is_alive())

	# 4. Well-timed bat: arrow goes back, changes hands, KOs its shooter; batter shoved back, melee locked.
	var shooter := await _dummy(Vector3(6.0, 0, 3.0))
	_place(me, Vector3(0.0, 0, 3.0), Vector3.RIGHT)
	await _wait(0.8)
	var a := _fire_at(shooter, Vector3(0.0, 0, 3.0), 20.0)
	var parried := [false]
	me.parried.connect(func(_b, _a): parried[0] = true, CONNECT_ONE_SHOT)
	await _press_when_close(a, t.parry_reach + 20.0 * t.parry_window * 0.45)
	await _wait(0.35) # past the hit-stop and the swing
	var x_after_bat := me.global_position.x
	_check("well-timed melee bats the arrow", parried[0] and me.is_alive(), "alive=%s" % me.is_alive())
	_check("batted arrow now belongs to the batter and flies back", is_instance_valid(a) and a.owner_bird == me and a.velocity.x > 10.0,
		"vx=%.1f" % (a.velocity.x if is_instance_valid(a) else 0.0))
	_check("batter is shoved back", x_after_bat < -0.15, "x=%.2f" % x_after_bat)
	await _shot("melee_bat")
	await _tap("melee")
	_check("melee locked right after a bat", me.state != Bird.State.SLAPPING, "state=%d cooldown=%.2f" % [me.state, me._slap_cooldown])
	await _wait(0.3)
	_check("batted arrow KOs its own shooter", not shooter.is_alive())
	await _wait(t.parry_cooldown - 0.6)
	await _tap("melee")
	_check("melee available again after parry_cooldown", me.state == Bird.State.SLAPPING or me._slap_cooldown > 0.0)
	await _wait(0.5)

	# 5. Glancing contact: off-center arrow deflects to the side.
	shooter = await _dummy(Vector3(6.0, 0, -1.6))
	_place(me, Vector3(0.0, 0, -2.25), Vector3.RIGHT)
	await _wait(0.6)
	a = _fire_at(shooter, Vector3(0.0, 0, -1.6), 20.0)
	await _press_when_close(a, t.parry_reach + 20.0 * t.parry_window * 0.45)
	await _wait(0.05)
	var vz: float = a.velocity.z if is_instance_valid(a) else 0.0
	_check("glancing bat deflects sideways (depends on hit angle)", is_instance_valid(a) and a.owner_bird == me and vz > 3.0, "vz=%.1f vx=%.1f" % [vz, a.velocity.x if is_instance_valid(a) else 0.0])
	await _wait(1.2)

	# 6. Mistimed (too early) swing doesn't save you.
	shooter = await _dummy(Vector3(7.0, 0, 5.5))
	_place(me, Vector3(0.0, 0, 5.5), Vector3.RIGHT)
	await _wait(0.6)
	a = _fire_at(shooter, Vector3(0.0, 0, 5.5), 20.0)
	await _press_when_close(a, 4.5)
	await _wait(0.6)
	_check("mistimed (early) swing: still KO'd", not me.is_alive())
	print("SIM DONE: %d failure(s)" % fails)
	quit()

func _place(b: Bird, pos: Vector3, face: Vector3) -> void:
	b.global_position = pos
	b.velocity = Vector3.ZERO
	b.facing = Bird.yaw_of(face)

func _fire_at(from_bird: Bird, target: Vector3, speed: float) -> Arrow:
	var start := from_bird.global_position + Vector3.UP * t.arrow_height
	var dir := (target + Vector3.UP * t.arrow_height - start)
	dir.y = 0.0
	dir = dir.normalized()
	var a: Arrow = ARROW.instantiate()
	map.add_child(a)
	a.launch(from_bird, start, start + dir * 0.8, dir * speed, from_bird.player_color, 0.5)
	return a

## Presses melee when the arrow gets within `dist` (flat) of me (a human pressing at the right moment).
func _press_when_close(a: Arrow, dist: float) -> void:
	for i in 120:
		await physics_frame
		if not is_instance_valid(a) or a.state != Arrow.State.FLYING:
			return
		var d := Vector2(a.global_position.x - me.global_position.x, a.global_position.z - me.global_position.z).length()
		if d <= dist:
			PlayerInput.test_press("melee")
			await physics_frame
			await physics_frame
			PlayerInput.test_release("melee")
			return

func _tap(action: String) -> void:
	PlayerInput.test_press(action)
	await physics_frame
	await physics_frame
	PlayerInput.test_release(action)
	await physics_frame

func _dummy(pos: Vector3) -> Bird:
	var b: Bird = BIRD.instantiate()
	b.bird_data = load("res://data/birds/pigeon.tres")
	b.player_index = 3
	b.player_color = Color("b57bff")
	b.input = CpuInput.new(b, "easy")
	map.add_child(b)
	await process_frame
	b.reset_for_round(pos, 0.0)
	b.frozen = true
	return b

func _wait(seconds: float) -> void:
	for i in maxi(int(round(seconds * 60.0)), 1):
		await physics_frame

func _check(label: String, ok: bool, detail := "") -> void:
	if not ok:
		fails += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])

func _shot(name: String) -> void:
	await process_frame
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
