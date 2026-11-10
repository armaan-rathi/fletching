extends SceneTree
## Stage 5 checks on the Aviary (practice mode): power-up holding rules, pad pickup, Featherweight, Trifecta,
## Eggsplosive (direct + splash KO, shooter safe), eggs, persistence across rounds; plus screenshots.
## Run (windowed): Godot --path . --resolution 1600x900 -s tools/sim_stage5.gd -- <out_dir>

const BIRD := preload("res://scenes/birds/bird.tscn")

var out := ""
var fails := 0
var map: Node
var me: Bird

func _init() -> void:
	await process_frame
	out = OS.get_cmdline_user_args()[0]
	var mm := root.get_node("MatchManager")
	mm.power_ups = true
	mm.setup_practice()
	map = load("res://scenes/maps/aviary.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	await _wait(0.4)
	me = map.get_node("Player1")
	me.set_process_input(false)
	me.input.include_actions = true
	_check("Aviary loads with nests, pads and cover", get_nodes_in_group("nests").size() == 3 and get_nodes_in_group("power_up_pads").size() == 3, "")

	# Holding rules: max 3, newest last, duplicates move to newest.
	var held: Array[String] = []
	for t in ["trifecta", "eggsplosive", "featherweight", "trifecta"]:
		held = PowerUps.add(held, t)
	_check("power-ups: max 3, re-pickup moves to newest", held == ["eggsplosive", "featherweight", "trifecta"], str(held))

	# Pad pickup.
	var pad: PowerUpPad = get_nodes_in_group("power_up_pads")[0]
	pad.spawn("featherweight")
	await _wait(0.3)
	await _shot("s5_pad")
	me.global_position = pad.global_position + Vector3(0.3, 0, 0)
	await _wait(0.2)
	_check("walking onto a pad picks up its power-up", me.has_power("featherweight") and pad.item == "", str(me.power_ups))

	# Featherweight: longer dash.
	me.global_position = Vector3(-4.0, 0, 0.8)
	me.facing = Bird.yaw_of(Vector3.RIGHT)
	await _wait(0.9)
	PlayerInput.test_press("dash"); await _wait(0.05); PlayerInput.test_release("dash")
	await _wait(0.4)
	_check("Featherweight dash ~4.9 m", absf(me.last_dash_distance - 4.9) < 0.35, "%.2f" % me.last_dash_distance)

	# Persistence across rounds.
	me.reset_for_round(Vector3(-6, 0, 4), 0.0)
	_check("power-ups survive a round reset", me.has_power("featherweight"), "")

	# Trifecta: one arrow that splits into 3 halfway (user rework), only 1 from the quiver; side arrows poof.
	me.add_power_up("trifecta")
	me.global_position = Vector3(-7.0, 0, 4.6)
	me.facing = Bird.yaw_of(Vector3.RIGHT)
	await _wait(0.2)
	var before := me.arrows
	PlayerInput.test_press("shoot"); await _wait(0.3); PlayerInput.test_release("shoot")
	await _wait(0.05)
	var flying0 := get_nodes_in_group("arrows").filter(func(a): return a.state == Arrow.State.FLYING).size()
	await _wait(Tuning.get_default().trifecta_split_time + 0.05)
	var flying := get_nodes_in_group("arrows").filter(func(a): return a.state == Arrow.State.FLYING).size()
	await _shot("s5_trifecta")
	_check("Trifecta: 1 arrow at release, splits into 3 mid-flight, 1 quiver arrow", flying0 == 1 and flying == 3 and me.arrows == before - 1, "at release %d, after split %d, arrows=%d" % [flying0, flying, me.arrows])
	await _wait(1.2)
	var stuck := get_nodes_in_group("arrows").filter(func(a): return is_instance_valid(a) and a.state == Arrow.State.STUCK and not a.is_queued_for_deletion()).size()
	_check("side arrows poof, middle one stays as a pickup", stuck == 1, "stuck=%d" % stuck)

	# Eggs: an arrow at normal height smashes an egg (and keeps going).
	var nest: Nest = get_nodes_in_group("nests").filter(func(n): return n.global_position.z > 4.0)[0]
	me.power_ups.clear()
	me._set_arrows(3)
	me.global_position = nest.global_position + Vector3(-3.0, 0, nest.eggs[0].position.z)
	me.facing = Bird.yaw_of(Vector3.RIGHT)
	await _wait(0.1)
	PlayerInput.test_press("shoot"); await _wait(0.3); PlayerInput.test_release("shoot")
	await _wait(0.5)
	var broken := nest.eggs.filter(func(e): return e.broken).size()
	_check("arrows smash eggs", broken >= 1, "broken=%d" % broken)
	await _shot("s5_egg")

	# Eggsplosive: direct hit + splash KO, shooter unharmed.
	me.add_power_up("eggsplosive")
	var d1 := await _dummy(Vector3(-2.0, 0, 4.0))
	var d2 := await _dummy(Vector3(-2.3, 0, 5.0))
	me.global_position = Vector3(-6.0, 0, 4.0) # clear line (the log is further north)
	var arrows_before := me.arrows
	me.facing = Bird.yaw_of(Vector3.RIGHT)
	await _wait(0.1)
	PlayerInput.test_press("shoot"); await _wait(0.4); PlayerInput.test_release("shoot")
	await _wait(0.24)
	await _shot("s5_explosion")
	await _wait(0.2)
	_check("Eggsplosive: direct hit KOs", not d1.is_alive(), "")
	_check("Eggsplosive: splash KOs a bird 1.1 m away", not d2.is_alive(), "")
	_check("Eggsplosive: shooter unharmed", me.is_alive(), "")
	await _wait(1.6)
	_check("exploded arrow returns to the quiver", me.arrows == arrows_before, "arrows=%d (before %d)" % [me.arrows, arrows_before])

	# Overview with power-ups waiting.
	for p in get_nodes_in_group("power_up_pads"):
		p.spawn(PowerUps.ids().pick_random())
	me.global_position = Vector3(-7, 0, 4.3)
	await _wait(0.6)
	await _shot("s5_aviary")
	print("SIM DONE: %d failure(s)" % fails)
	quit()

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
