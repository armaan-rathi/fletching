extends SceneTree
## Anime symbol check: triggers each symbol's expression on the test-map bird and saves a contact sheet
## (one row per symbol, one column per moment) to <out>/symbols_sheet.png, plus a per-frame scale log.
## Run (windowed): Godot --path . --resolution 1600x900 -s tools/symbol_check.gd -- <out_dir>

const ROWS := [["annoyed", "anger"], ["shocked", "!"], ["confused", "?"], ["sad", "sweat"], ["happy", "sparkle"]]
const MOMENTS := [0.06, 0.14, 0.3, 0.42, 0.55, 0.8, 1.2, 1.32]
const CW := 300
const CH := 260

func _init() -> void:
	await process_frame
	var out: String = OS.get_cmdline_user_args()[0]
	root.get_node("MatchManager").setup_practice()
	var map: Node = load("res://scenes/maps/test_map.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	map.get_node("DebugHud").free()
	for i in 10:
		await physics_frame
	var bird = map.get_node("Player1")
	bird.set_physics_process(false)
	bird.set_process_input(false)
	bird.global_position = Vector3(-5, 0, 3)
	var cam := root.get_viewport().get_camera_3d()
	var sheet := Image.create(CW * MOMENTS.size(), CH * ROWS.size(), false, Image.FORMAT_RGBA8)
	for r in ROWS.size():
		bird.model.expressions.clear()
		for i in 30:
			await process_frame
		bird.model.expressions.request(ROWS[r][0], 3.0)
		var t := 0.0
		var t0 := Time.get_ticks_msec()
		var col := 0
		var gone_at := -1.0
		while col < MOMENTS.size() or (gone_at < 0.0 and t < 2.5):
			await process_frame
			t = (Time.get_ticks_msec() - t0) / 1000.0
			var sym = bird.model.get("_symbol")
			if gone_at < 0.0 and t > 0.3 and not is_instance_valid(sym):
				gone_at = t
			if col < MOMENTS.size() and t >= MOMENTS[col]:
				var c := cam.unproject_position(bird.global_position + Vector3(0.35, 1.15, 0))
				var img := root.get_texture().get_image().get_region(Rect2i(int(c.x) - CW / 4, int(c.y) - CH / 4, CW / 2, CH / 2))
				img.convert(Image.FORMAT_RGBA8)
				img.resize(CW, CH, Image.INTERPOLATE_NEAREST)
				sheet.blit_rect(img, Rect2i(0, 0, CW, CH), Vector2i(col * CW, r * CH))
				col += 1
		print("%-8s gone after %.2f s (expression still held)" % [ROWS[r][1], gone_at])
	sheet.save_png(out.path_join("symbols_sheet.png"))
	print("symbol sheet saved")
	quit()
