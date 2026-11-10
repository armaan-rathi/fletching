extends SceneTree
## KO spirit checks: it rises slowly (lasts ko_spirit_time) and the KO'd player's move input steers it
## (right drifts it right on screen, up makes it rise faster). Saves spirit_steer.png.
## Run (windowed): Godot --path . --audio-driver Dummy --resolution 1600x900 -s tools/sim_spirit.gd -- <out_dir>

var fails := 0

func _init() -> void:
	await process_frame
	var out: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	var t := Tuning.get_default()
	var mm := root.get_node("MatchManager")
	mm.power_ups = false
	mm.setup_practice()
	var map: Node = load("res://scenes/maps/test_map.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	await _wait(0.3)
	var me: Bird = map.get_node("Player1")
	me.set_process_input(false)
	me.input.include_actions = true
	var cam := root.get_viewport().get_camera_3d()
	# 1. Untouched spirit: path for reference.
	me.reset_for_round(Vector3.ZERO, 0.0)
	await _wait(0.3)
	var a := await _ko_and_track(me, "", t)
	# 2. Steered right + up.
	me.reset_for_round(Vector3.ZERO, 0.0)
	await _wait(0.3)
	var b := await _ko_and_track(me, "steer", t, out)
	var db: Vector3 = b["mid"] - b["start"]
	var da: Vector3 = a["mid"] - a["start"]
	var dx: float = (db - da).dot(cam.global_basis.x)
	var dy: float = (db - da).dot(cam.global_basis.y)
	_check("spirit lasts ko_spirit_time (slower rise)", absf(a["life"] - t.ko_spirit_time) < 0.3, "%.1f s" % a["life"])
	_check("move right drifts the spirit right", dx > 1.5, "dx=%.2f m" % dx)
	_check("move up makes it rise faster", dy > 1.0, "dy=%.2f m" % dy)
	print("SPIRIT %s" % ("PASS" if fails == 0 else "FAIL"))
	quit()

func _ko_and_track(me: Bird, mode: String, t: Tuning, out := "") -> Dictionary:
	me.knock_out(null, Vector3.RIGHT)
	await _wait(t.ko_spirit_delay + 0.1)
	var spirit: Node3D = null
	for c in current_scene.find_children("Spirit*", "", true, false):
		spirit = c
	if spirit == null:
		_check("spirit spawned", false)
		return {"mid": Vector3.ZERO, "start": Vector3.ZERO, "life": 0.0}
	var found_ms := Time.get_ticks_msec()
	var start := spirit.global_position
	var age := 0.0
	if mode == "steer":
		PlayerInput.test_press("move_right")
		PlayerInput.test_press("move_up")
	await _wait(1.2)
	var mid := spirit.global_position
	if out != "":
		root.get_texture().get_image().save_png(out.path_join("spirit_steer.png"))
	PlayerInput.test_release("move_right")
	PlayerInput.test_release("move_up")
	while is_instance_valid(spirit) and Time.get_ticks_msec() - found_ms < 10000:
		age = spirit._t # the spirit's own (game-time) clock
		await process_frame
	return {"mid": mid, "start": start, "life": age}

func _wait(s: float) -> void:
	for i in maxi(int(round(s * 60.0)), 1):
		await physics_frame

func _check(label: String, ok: bool, detail := "") -> void:
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		fails += 1
