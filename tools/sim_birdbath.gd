extends SceneTree
## Birdbath map checks: layout loads (bath, nests, pads, 28 x 18 arena), the puddle spreads over time and
## resets, wading slows a bird (and shortens dashes), the bird blocker keeps birds out from under the bowl,
## arrows stick in the stone column (not mid-air), arrows landing in the puddle splash, and stuck arrows take
## arrow_auto_return (7 s) to poof back. Saves overview + close-up screenshots.
## Run (windowed): Godot --path . --audio-driver Dummy --resolution 1600x900 -s tools/sim_birdbath.gd -- <out_dir>

const ARROW := preload("res://scenes/weapons/arrow.tscn")

var out := ""
var fails := 0
var me: Bird
var t: Tuning

func _init() -> void:
	await process_frame
	out = OS.get_cmdline_user_args()[0]
	t = Tuning.get_default()
	var mm := root.get_node("MatchManager")
	mm.custom_layout = MapBuilder.load_layout("res://data/maps/birdbath.json")
	mm.power_ups = false # deterministic shots (no Eggsplosive / Trifecta pickups on the way)
	mm.setup_practice()
	var map: Node = load(mm.CUSTOM_MAP_SCENE).instantiate()
	root.add_child(map)
	current_scene = map
	await _wait(0.5)
	me = map.get_node("Player1") if map.has_node("Player1") else get_nodes_in_group("birds")[0]
	me.set_process_input(false)
	me.input.include_actions = true
	var baths := get_nodes_in_group("water")
	var bb: Birdbath = baths[0] if baths.size() > 0 else null
	var cam: ArenaCamera = root.get_viewport().get_camera_3d()
	_check("Birdbath map loads (bath, 4 nests, 6 pads, 40 x 26)", bb != null and get_nodes_in_group("nests").size() == 4 \
		and get_nodes_in_group("power_up_pads").size() == 6 and cam.arena_size == Vector2(40, 26))
	await _shot("bb_overview_start")

	# Puddle grows, and resets with the round.
	var r0 := bb.puddle_radius
	await _wait(2.0)
	_check("puddle spreads over time", bb.puddle_radius > r0 + t.puddle_growth * 1.5, "%.2f -> %.2f m" % [r0, bb.puddle_radius])
	bb.puddle_radius = 3.0
	bb._update_puddle()
	call_group("round_reset", "reset")
	_check("puddle resets with the round", is_equal_approx(bb.puddle_radius, t.puddle_start_radius))
	bb.puddle_radius = t.puddle_max_radius
	bb._update_puddle()

	# Wading is slower than dry ground.
	var wet_pos := bb.to_global(Vector3(3.0, 0, 0)) # inside the ring-shaped pool, east of the bath
	var dry := await _run(Vector3(-14.0, 0, -4.5))
	var wet := await _run(wet_pos + Vector3(-1.0, 0, 0))
	_check("wading slows a bird (~%.0f%%)" % (t.water_speed * 100.0), wet / dry > t.water_speed - 0.1 and wet / dry < t.water_speed + 0.1,
		"dry %.2f m, wet %.2f m (%.2f)" % [dry, wet, wet / dry])
	me.global_position = wet_pos
	await _wait(0.1)
	_check("bird knows it's wading", me.wading)
	await _shot("bb_wading")

	# The blocker keeps birds out from under the bowl.
	me.global_position = bb.global_position + Vector3(-3.0, 0, 0)
	me.facing = Bird.yaw_of(Vector3.RIGHT)
	PlayerInput.test_press("move_right")
	await _wait(1.5)
	PlayerInput.test_release("move_right")
	var d := Vector2(me.global_position.x - bb.global_position.x, me.global_position.z - bb.global_position.z).length()
	_check("bird can't walk under the bowl", d > 0.9, "%.2f m from center" % d)
	# Water all around: a point on each side of the bath is wet.
	var sides := 0
	for dir in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		if Fx.in_water(bb.global_position + dir * 2.5):
			sides += 1
	_check("puddle surrounds the bath (all 4 sides wet)", sides == 4, "%d/4" % sides)

	# Arrows stick in the stone column, not in the air at the blocker.
	me.global_position = bb.global_position + Vector3(-5.0, 0, 0)
	me.velocity = Vector3.ZERO
	me.facing = Bird.yaw_of(Vector3.RIGHT)
	await _wait(0.2)
	PlayerInput.test_press("shoot"); await _wait(0.4); PlayerInput.test_release("shoot")
	await _wait(0.6)
	var stuck: Array = get_nodes_in_group("arrows").filter(func(a): return a.state == Arrow.State.STUCK)
	var tip_d := 99.0
	for a in stuck:
		tip_d = minf(tip_d, Vector2(a.global_position.x - bb.global_position.x, a.global_position.z - bb.global_position.z).length())
	_check("arrow sticks in the stone column", stuck.size() > 0 and tip_d < 0.45, "tip %.2f m from center" % tip_d)
	await _shot("bb_arrow_column")

	# An arrow landing in the puddle splashes.
	var before: int = Sfx.counts.get("splash", 0)
	var a := ARROW.instantiate() as Arrow
	map.add_child(a)
	var from := wet_pos + Vector3(-0.6, 0.6, 0)
	a.launch(me, from, from + Vector3(0.3, -0.2, 0), Vector3(3, -6, 0), me.player_color, 0.0)
	await _wait(0.4)
	_check("arrow landing in the water splashes", Sfx.counts.get("splash", 0) > before and a.state == Arrow.State.STUCK)

	# Stuck arrows take arrow_auto_return (7 s) to poof back.
	me._set_arrows(0)
	await _wait(t.arrow_auto_return - 0.6)
	var still := is_instance_valid(a) and not a.is_queued_for_deletion()
	await _wait(1.0)
	_check("stuck arrows return after %.0f s, not before" % t.arrow_auto_return, still and not is_instance_valid(a), "still at %.1f s: %s" % [t.arrow_auto_return - 0.6, still])

	me.global_position = Vector3(-17, 0, 10.3)
	await _wait(0.3)
	await _shot("bb_overview_full_puddle")
	print("SFX splash plays: ", Sfx.counts.get("splash", 0))
	print("SIM DONE: %d failure(s)" % fails)
	quit()

## Distance covered in 0.8 s of holding move_right from `pos`.
func _run(pos: Vector3) -> float:
	me.global_position = pos
	me.velocity = Vector3.ZERO
	await _wait(0.3)
	var x0 := me.global_position.x
	PlayerInput.test_press("move_right")
	await _wait(0.8)
	PlayerInput.test_release("move_right")
	return me.global_position.x - x0

func _wait(seconds: float) -> void:
	for i in maxi(int(round(seconds * 60.0)), 1):
		await physics_frame

func _check(label: String, ok: bool, detail := "") -> void:
	if not ok:
		fails += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])

func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
