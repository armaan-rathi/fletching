extends SceneTree
## Shrike (lob shot, arc rework) checks: a visible arc that lands shrike_range_min ahead at no charge and
## shrike_range_max at full (ring shown in flight, removed after), a lob over the tree KOs a bird behind it, a
## miss still stuns a bird near the landing, move nudges the landing spot, it lands on top of cover, a parrying
## bird can't bat it, an empty quiver doesn't fire, and CPUs use shrikes in a match on the Aviary.
## Run (windowed): Godot --path . --audio-driver Dummy --resolution 1600x900 -s tools/sim_shrike.gd -- <out_dir>

const BIRD := preload("res://scenes/birds/bird.tscn")

var out := ""
var fails := 0
var map: Node
var me: Bird
var t: Tuning

func _init() -> void:
	await process_frame
	out = OS.get_cmdline_user_args()[0]
	t = Tuning.get_default()
	var mm := root.get_node("MatchManager")
	mm.power_ups = false
	mm.setup_practice()
	map = load("res://scenes/maps/test_map.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	await _wait(0.3)
	me = map.get_node("Player1")
	me.set_process_input(false)
	me.input.include_actions = true

	# 1. A short lob (no charge): a visible arc that lands shrike_range_min ahead; ring the whole flight.
	_place(me, Vector3(-6.0, 0, 4.0))
	me.facing = Bird.yaw_of(Vector3.RIGHT)
	await _wait(0.2)
	var before := me.arrows
	var a := await _lob(0.0)
	var top := 0.0
	var seen := true
	for i in 20:
		await physics_frame
		if is_instance_valid(a):
			top = maxf(top, a.global_position.y)
			seen = seen and a.visible
	_check("shrike flies a visible arc up over cover height", a != null and top > 2.0 and seen, "peak y=%.1f" % top)
	_check("landing ring shown while airborne", a != null and a._marker != null and is_instance_valid(a._marker))
	_check("uses one arrow", me.arrows == before - 1, "%d -> %d" % [before, me.arrows])
	await _shot("shrike_marker")
	await _until_landed(a)
	var land := Vector2(a.global_position.x, a.global_position.z)
	_check("no charge: lands shrike_range_min ahead", land.distance_to(Vector2(-6.0 + t.shrike_range_min, 4.0)) < 0.7, "at %.2f,%.2f" % [land.x, land.y])
	_check("stuck point-down in the ground", a.state == Arrow.State.STUCK and a.global_basis.z.y > 0.9, "z.y=%.2f" % a.global_basis.z.y)
	_check("ring removed after landing", a._marker == null)
	_check("shooter safe", me.is_alive())

	# 2. Full charge lands much further (aim + charge set the spot).
	me._set_arrows(3)
	_place(me, Vector3(-9.0, 0, -5.0))
	me.facing = Bird.yaw_of(Vector3.RIGHT)
	await _wait(0.2)
	a = await _lob(t.full_draw_time + 0.1)
	await _until_landed(a)
	_check("full charge: lands shrike_range_max ahead", absf(a.global_position.x - (-9.0 + t.shrike_range_max)) < 0.8, "landed x=%.2f" % a.global_position.x)

	# 3. Over the tree: a bird hidden behind the trunk gets a direct hit.
	me._set_arrows(3)
	var dummy := await _dummy(Vector3(2.0, 0, -0.5))
	_place(me, Vector3(-2.6, 0, -0.5)) # the tree trunk (0, -0.5) is between us
	me.facing = Bird.yaw_of(Vector3.RIGHT)
	await _wait(0.2)
	a = await _lob(_hold_for(4.6))
	await _until_landed(a)
	_check("shrike over cover KOs the bird behind it", not dummy.is_alive(), "landed %.2f,%.2f, target 2.0,-0.5" % [a.global_position.x, a.global_position.z])
	await _shot("shrike_over_tree")

	# 4. A miss still stuns birds near where it lands (not the shooter).
	me._set_arrows(3)
	dummy = await _dummy(Vector3(-1.0 + 0.9, 0, 4.0 + 0.5))
	_place(me, Vector3(-6.0, 0, 4.0))
	me.facing = Bird.yaw_of(Vector3.RIGHT)
	await _wait(0.2)
	a = await _lob(_hold_for(5.0))
	await _until_landed(a)
	await physics_frame
	_check("landing shockwave stuns a bird nearby", dummy.is_alive() and dummy.is_stunned(), "alive=%s state=%d landed %.2f,%.2f" % [dummy.is_alive(), dummy.state, a.global_position.x, a.global_position.z])
	dummy.queue_free()

	# 5. Nudging with move while it flies moves the landing spot.
	me._set_arrows(3)
	_place(me, Vector3(-7.0, 0, -3.0))
	me.facing = Bird.yaw_of(Vector3.RIGHT)
	await _wait(0.2)
	a = await _lob(0.0)
	PlayerInput.test_press("move_down")
	await _wait(0.4)
	PlayerInput.test_release("move_down")
	await _until_landed(a)
	_check("move nudges where it lands", a.global_position.z > -3.0 + 0.5, "landed z=%.2f (launched at -3)" % a.global_position.z)

	# 6. Lands on top of cover (a crate placed on the spot after launch).
	me._set_arrows(3)
	_place(me, Vector3(3.0, 0, 4.0))
	me.facing = Bird.yaw_of(Vector3.RIGHT)
	await _wait(0.2)
	a = await _lob(0.0)
	var crate := StaticBody3D.new()
	crate.collision_layer = 1 | 32
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1, 1, 1)
	cs.shape = box
	crate.add_child(cs)
	map.add_child(crate)
	crate.global_position = Vector3(3.0 + t.shrike_range_min, 0.5, 4.0)
	await _until_landed(a)
	_check("lands on top of cover", a.global_position.y > 0.8, "stuck at y=%.2f" % a.global_position.y)
	crate.queue_free()

	# 7. A bird swinging its wing where it lands can't bat it away.
	me._set_arrows(3)
	dummy = await _dummy(Vector3(-8.5 + t.shrike_range_min, 0, -5.0))
	_place(me, Vector3(-8.5, 0, -5.0))
	me.facing = Bird.yaw_of(Vector3.RIGHT)
	await _wait(0.2)
	a = await _lob(0.0)
	while is_instance_valid(a) and a.state == Arrow.State.FLYING:
		if dummy.is_alive():
			dummy.state = Bird.State.SLAPPING # always mid-swing (parry window open)
			dummy._slap_time = 0.0
		await physics_frame
	_check("falling shrike can't be batted away", not dummy.is_alive(), "landed %.2f,%.2f y=%.2f state=%d (dummy at %.1f,-5)" % [a.global_position.x, a.global_position.z, a.global_position.y, a.state, -8.5 + t.shrike_range_min])

	# 8. Empty quiver: no shrike (clear leftovers first: stuck arrows auto-return to the quiver).
	for x in get_nodes_in_group("arrows"):
		x.queue_free()
	await _wait(0.05)
	me._set_arrows(0)
	_place(me, Vector3(-6.0, 0, 4.0))
	await _wait(0.2)
	var n0 := get_nodes_in_group("arrows").filter(func(x): return x.shrike and x.state == Arrow.State.FLYING).size()
	PlayerInput.test_press("shrike"); await _wait(0.3); PlayerInput.test_release("shrike")
	await _wait(0.2)
	var n1 := get_nodes_in_group("arrows").filter(func(x): return x.shrike and x.state == Arrow.State.FLYING).size()
	_check("empty quiver: no shrike", n1 == n0, "flying shrikes %d -> %d, arrows=%d" % [n0, n1, me.arrows])

	# 9. CPUs use shrikes (Aviary, lots of cover).
	map.free()
	mm.players.clear()
	var ids: Array[String] = []
	for d in BirdData.load_all():
		ids.append(d.id)
	for d in ["hard", "normal", "hard", "normal"]:
		mm._add_player(true, d, false, -1, mm._next_bird(ids))
	map = load("res://scenes/maps/aviary.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	var shrikes := [0]
	var hooked := {}
	Engine.time_scale = 3.0
	var tt := 0.0
	while tt < 40.0 and shrikes[0] < 2:
		await physics_frame
		tt += 1.0 / 60.0
		for b in get_nodes_in_group("birds"):
			if not hooked.has(b):
				hooked[b] = true
				b.shrike_fired.connect(func(_b): shrikes[0] += 1)
	Engine.time_scale = 1.0
	_check("CPUs lob shrikes over cover", shrikes[0] >= 1, "%d shrikes in %.0f s of CPU play" % [shrikes[0], tt * 3.0])
	print("SIM DONE: %d failure(s)" % fails)
	quit()

## Draw time that lobs a shrike `dist` m.
func _hold_for(dist: float) -> float:
	return clampf((dist - t.shrike_range_min) / (t.shrike_range_max - t.shrike_range_min), 0.0, 1.0) * t.full_draw_time

## Hold shrike for `hold` s and release; returns the new shrike arrow.
func _lob(hold: float) -> Arrow:
	PlayerInput.test_press("shrike")
	await _wait(hold)
	PlayerInput.test_release("shrike")
	await _wait(0.05)
	var mine: Arrow = null
	for x in get_nodes_in_group("arrows"):
		if x.shrike and x.owner_bird == me and x.state == Arrow.State.FLYING:
			mine = x
	return mine

func _until_landed(a: Arrow) -> void:
	for i in 60 * 4:
		if a == null or not is_instance_valid(a) or a.state != Arrow.State.FLYING:
			return
		await physics_frame

func _place(b: Bird, pos: Vector3) -> void:
	b.global_position = pos
	b.velocity = Vector3.ZERO

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
