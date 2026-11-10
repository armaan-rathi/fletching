extends SceneTree
## Match-win celebrations: all 8 birds in a row on the test map, each running its BirdData.victory_style,
## captured at a few moments. Saves celebrations.png (rows = moments) to <out_dir>.
## Run (windowed): Godot --path . --audio-driver Dummy --resolution 1600x900 -s tools/celebration_shots.gd -- <out_dir>

const BIRD := preload("res://scenes/birds/bird.tscn")
const MOMENTS := [0.3, 0.9, 1.5, 2.3]

func _init() -> void:
	await process_frame
	var out: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	var mm := root.get_node("MatchManager")
	mm.power_ups = false
	mm.setup_practice()
	var map: Node = load("res://scenes/maps/test_map.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	if map.has_node("DebugHud"):
		map.get_node("DebugHud").free()
	await _frames(10)
	for n in get_nodes_in_group("birds"):
		n.free()
	var flock := BirdData.load_all()
	var birds := []
	for i in flock.size():
		var b: Bird = BIRD.instantiate()
		b.bird_data = flock[i]
		b.player_index = i % 4
		b.player_color = [Color("ff5a5a"), Color("4da6ff"), Color("ffd23f"), Color("b57bff")][i % 4]
		b.input = CpuInput.new(null)
		map.add_child(b)
		await process_frame
		b.reset_for_round(Vector3(-7.0 + i * 2.0, 0, 2.0), PI)
		birds.append(b)
	await _frames(10)
	var cam := root.get_viewport().get_camera_3d()
	cam.focus_on(Vector3(0, 0, 2.0), 0.62)
	await _wait(1.0)
	for b in birds:
		b.frozen = true
		b.celebrate()
	var rows := []
	var t := 0.0
	for m in MOMENTS:
		await _wait(m - t)
		t = m
		var img := root.get_texture().get_image()
		var l := cam.unproject_position(Vector3(-8.0, 0.8, 2.0))
		var r := cam.unproject_position(Vector3(8.0, 0.8, 2.0))
		var crop := img.get_region(Rect2i(int(l.x), int(l.y) - 170, int(r.x - l.x), 260))
		rows.append(crop)
	var w: int = rows[0].get_width()
	var sheet := Image.create(w, 260 * rows.size(), false, rows[0].get_format())
	for i in rows.size():
		sheet.blit_rect(rows[i], Rect2i(0, 0, w, 260), Vector2i(0, 260 * i))
	sheet.save_png(out.path_join("celebrations.png"))
	print("celebration names: ", flock.map(func(d): return "%s=%s" % [d.id, d.victory_style]))
	quit()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _wait(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame
