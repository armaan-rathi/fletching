extends SceneTree
## Overtime check: two birds that never move or shoot (the playtest's stalled CPUs), overtime shortened via
## tuning (after 3 s, 3 s countdown). The timer must show, eggs must fall with a shadow, an egg must knock a bird
## out (no killer) and the round must end. Saves overtime_timer.png and overtime_eggs.png.
## Run (windowed): Godot --path . --audio-driver Dummy --resolution 1600x900 -s tools/sim_overtime.gd -- <out_dir>

var fails := 0

func _init() -> void:
	await process_frame
	var out: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	var t := Tuning.get_default()
	t.overtime_after = 3.0
	t.overtime_countdown = 3.0
	var mm := root.get_node("MatchManager")
	mm.power_ups = false
	mm.players.clear()
	var ids: Array[String] = []
	for d in BirdData.load_all():
		ids.append(d.id)
	for k in 2:
		mm._add_player(true, "easy", false, -1, mm._next_bird(ids))
	mm.rounds_to_win = 3
	var map: Node = load("res://scenes/maps/aviary.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	var rc := map.get_node("RoundController")
	var egg_kos := [0]
	await process_frame
	for b in get_nodes_in_group("birds"):
		b.input = CpuInput.new(null) # idle: never moves, never shoots
		b.knocked_out.connect(func(_v, killer): if killer == null: egg_kos[0] += 1)
	while rc.phase != rc.Phase.PLAYING:
		await process_frame
	var hud := map.get_node("MatchHud")
	await _wait(3.6)
	_check("overtime timer shows after overtime_after", hud._overtime.visible and hud._overtime.text.begins_with("Overtime"), hud._overtime.text)
	root.get_texture().get_image().save_png(out.path_join("overtime_timer.png"))
	await _wait(2.9)
	_check("then: EGG RAIN!", hud._overtime.text == "EGG RAIN!", hud._overtime.text)
	_check("eggs falling", get_nodes_in_group("sky_eggs").size() > 0)
	await _wait(0.25)
	root.get_texture().get_image().save_png(out.path_join("overtime_eggs.png"))
	var waited := 0.0
	while rc.phase == rc.Phase.PLAYING and waited < 40.0:
		await _wait(0.5)
		waited += 0.5
	_check("an egg knocks a bird out and the round ends", egg_kos[0] > 0 and rc.phase != rc.Phase.PLAYING, "egg KOs %d after %.0f s of egg rain" % [egg_kos[0], waited])
	await _wait(1.5)
	_check("eggs cleared and timer hidden after the round", get_nodes_in_group("sky_eggs").is_empty() and not hud._overtime.visible)
	print("OVERTIME %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit()

func _wait(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame

func _check(label: String, ok: bool, detail := "") -> void:
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		fails += 1
