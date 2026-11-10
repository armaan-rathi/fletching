extends SceneTree
## Stage 3 checks: arrow KO (no self-hit), wing slap stun, curve shot bending, then a full CPU-only match.
## Run (windowed, for screenshots): Godot --path . --resolution 1600x900 -s tools/sim_stage3.gd -- <out_dir>

const BIRD := preload("res://scenes/birds/bird.tscn")

var out := ""
var fails := 0
var mm: Node
var map: Node

func _init() -> void:
	await process_frame
	out = OS.get_cmdline_user_args()[0]
	mm = root.get_node("MatchManager")

	# --- Mechanics in practice mode ------------------------------------------------------
	mm.setup_practice()
	await _load_map()
	var me: Bird = map.get_node("Player1")
	me.set_process_input(false)
	me.input.include_actions = true
	var dummy := await _dummy(Vector3(-2.0, 0, 3.0))

	# 1. Arrow KO; the shooter is never hit by its own arrow.
	me.global_position = Vector3(-6.0, 0, 3.0)
	me.facing = Bird.yaw_of(Vector3.RIGHT)
	await _wait(0.1)
	PlayerInput.test_press("shoot"); await _wait(0.4); PlayerInput.test_release("shoot")
	await _wait(0.4)
	_check("arrow knocks out the target", not dummy.is_alive(), "")
	_check("shooter unharmed by its own arrow", me.is_alive(), "")
	await _shot("s3_arrow_ko")

	# 2. Wing slap (own melee button since the melee rework): stuns, doesn't KO. Details: tools/sim_melee.gd.
	dummy = await _dummy(Vector3(-1.0, 0, -3.0))
	me.global_position = Vector3(-2.0, 0, -3.0)
	me.facing = Bird.yaw_of(Vector3.RIGHT)
	me._set_arrows(0)
	await _wait(0.6)
	PlayerInput.test_press("melee"); await _wait(0.05); PlayerInput.test_release("melee")
	await _wait(0.3)
	_check("wing slap stuns an adjacent bird", dummy.is_stunned() and dummy.is_alive(), "")
	await _wait(0.6)
	_check("slap has a cooldown and roots briefly", me.state == Bird.State.NORMAL, "state=%d" % me.state)

	# 3. Curve: shoot north, hold right -> the arrow bends east.
	me._set_arrows(3)
	me.global_position = Vector3(-8.0, 0, 5.0)
	me.facing = Bird.yaw_of(Vector3.FORWARD)
	await _wait(0.1)
	PlayerInput.test_press("shoot"); await _wait(0.65); PlayerInput.test_release("shoot")
	PlayerInput.test_press("move_right")
	await _wait(0.25)
	var flying: Array = get_nodes_in_group("arrows").filter(func(a): return a.state == Arrow.State.FLYING)
	var vx: float = flying[0].velocity.x if flying.size() > 0 else 0.0
	PlayerInput.test_release("move_right")
	_check("curve: holding right bends a northbound arrow east", vx > 3.0, "vx=%.2f" % vx)
	await _wait(0.6)
	await _shot("s3_curve")

	# --- Full CPU match --------------------------------------------------------------------
	mm.players.clear()
	for d in ["hard", "normal", "normal", "easy"]:
		mm._add_player(true, d, false, -1, mm._next_bird(_ids()))
	mm.rounds_to_win = 3
	await _load_map()
	var rc := map.get_node("RoundController")
	Engine.time_scale = 3.0
	var shot_taken := false
	var t := 0.0
	while t < 200.0 and rc.phase != rc.Phase.MATCH_OVER:
		await process_frame
		t += 1.0 / 60.0
		if not shot_taken and rc.phase == rc.Phase.PLAYING and t > 12.0:
			shot_taken = true
			Engine.time_scale = 1.0
			await _shot("s3_cpu_battle")
			Engine.time_scale = 3.0
	Engine.time_scale = 1.0
	_check("CPU match finishes", rc.phase == rc.Phase.MATCH_OVER, "rounds=%d after %.0f s" % [mm.round_number, t * 3.0])
	var line := []
	for p in mm.players:
		var st: Dictionary = mm.stats.get(p["slot"], {})
		line.append("%s(%s) wins=%d kos=%d arrows=%d" % [p["name"], p["difficulty"], mm.scores.get(p["slot"], 0), st.get("kos", 0), st.get("arrows", 0)])
	print("MATCH  ", " | ".join(line))
	await _wait(1.0)
	await _shot("s3_results")
	print("SIM DONE: %d failure(s)" % fails)
	quit()

func _ids() -> Array[String]:
	var ids: Array[String] = []
	for d in BirdData.load_all():
		ids.append(d.id)
	return ids

func _load_map() -> void:
	if map:
		map.free()
	map = load("res://scenes/maps/test_map.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	await _wait(0.3)

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

func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])

func _shot(name: String) -> void:
	await process_frame
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
