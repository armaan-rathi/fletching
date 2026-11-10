extends SceneTree
## Renders zoomed crops of the test-map bird in three spots to check the occlusion silhouette:
##   0 open ground (no x-ray expected), 1 beside the trunk (none expected), 2 behind the tree (x-ray expected).
## Run: Godot --path . --resolution 1600x900 -s tools/xray_check.gd -- <out_dir>

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
	var cam := root.get_viewport().get_camera_3d()
	var spots := [[Vector3(-5, 0, 3), -PI / 2], [Vector3(-0.62, 0, -0.5), -PI / 2], [Vector3(0.0, 0, -1.6), PI]]
	for k in spots.size():
		bird.global_position = spots[k][0]
		bird.facing = spots[k][1]
		for f in 30:
			bird.visual.look_yaw = bird.facing
			bird.visual.update_visual(1.0 / 60.0, Vector3.ZERO, bird.facing, false, false)
			await process_frame
		var img := root.get_texture().get_image()
		var c := cam.unproject_position(spots[k][0] + Vector3(0, 0.6, 0))
		var crop := img.get_region(Rect2i(int(c.x) - 50, int(c.y) - 45, 100, 90))
		crop.resize(400, 360, Image.INTERPOLATE_NEAREST)
		crop.save_png(out.path_join("xray_%d.png" % k))
	print("xray check saved")
	quit()
