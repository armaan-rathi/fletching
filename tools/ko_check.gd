extends SceneTree
## KO look check: shoots a dummy (mid-squawk, so a one-shot clip is playing when it dies), captures zoomed frames
## of the KO flop + spirit, and verifies: the limp KO clip starts right away (no one-shot finishing first), and
## after the flop + landing squash nothing moves at all - every bone and the body still (no "twitch", no
## "crunches"). Run (windowed): Godot --path . --audio-driver Dummy --resolution 1600x900 -s tools/ko_check.gd -- <out_dir>

const BIRD := preload("res://scenes/birds/bird.tscn")

func _init() -> void:
	await process_frame
	var out: String = OS.get_cmdline_user_args()[0]
	root.get_node("MatchManager").setup_practice()
	var map: Node = load("res://scenes/maps/test_map.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	await _wait(0.3)
	var me: Bird = map.get_node("Player1")
	me.set_process_input(false)
	me.input.include_actions = true
	var dummy: Bird = BIRD.instantiate()
	dummy.bird_data = load("res://data/birds/rooster.tres")
	dummy.player_index = 3
	dummy.player_color = Color("b57bff")
	dummy.input = CpuInput.new(dummy, "easy")
	map.add_child(dummy)
	await process_frame
	dummy.reset_for_round(Vector3(-2.0, 0, 3.0), PI)
	dummy.frozen = true
	me.reset_for_round(Vector3(-6.0, 0, 3.0), Bird.yaw_of(Vector3.RIGHT))
	await _wait(0.3)
	PlayerInput.test_press("shoot"); await _wait(0.45); PlayerInput.test_release("shoot")
	dummy.model.play_once("squawk") # dies mid one-shot (like a near-miss squawk in a real match)
	var cam := root.get_viewport().get_camera_3d()
	var tn := Tuning.get_default()
	var settle := tn.ko_flop_time + tn.ko_land_squash_time + 0.1
	var sk: Skeleton3D = dummy.model.skeleton
	var ko_at := -1.0
	var clip_after_ko := ""
	var prev := []
	var max_move := 0.0
	var t := 0.0
	var marks := [0.05, 0.25, 0.45, 0.8, 1.2, 2.5]
	var positions := {}
	while t < 4.0:
		await physics_frame
		t += 1.0 / 60.0
		if marks.size() > 0 and t >= marks[0]:
			var c := cam.unproject_position(Vector3(-1.0, 0.6, 3.0))
			var img := root.get_texture().get_image().get_region(Rect2i(int(c.x) - 220, int(c.y) - 330, 440, 420))
			img.resize(880, 840, Image.INTERPOLATE_NEAREST)
			img.save_png(out.path_join("ko_%0.2f.png" % marks[0]))
			marks.pop_front()
		if absf(t - 3.0) < 0.01 or absf(t - 3.9) < 0.01:
			positions[snappedf(t, 0.1)] = dummy.model.global_position
		if ko_at < 0.0 and not dummy.is_alive():
			ko_at = t
		elif ko_at >= 0.0 and clip_after_ko == "":
			clip_after_ko = dummy.model.anim.current_animation
		# After landing, every bone (world space) must stay put.
		var cur := []
		for b in sk.get_bone_count():
			cur.append(sk.global_transform * sk.get_bone_global_pose(b).origin)
		if ko_at >= 0.0 and t - ko_at > settle and prev.size() == cur.size():
			for b in cur.size():
				max_move = maxf(max_move, cur[b].distance_to(prev[b]))
		prev = cur
	var moved: float = positions.values()[0].distance_to(positions.values()[-1]) if positions.size() >= 2 else -1.0
	print("KO: alive=%s lying=%s spirits=%d moved_between_3s_and_3.9s=%.4f m" % [dummy.is_alive(), dummy.model.lying, root.find_children("Spirit*", "", true, false).size(), moved])
	print("KO CLIP: first clip after the KO = %s (want ko)" % clip_after_ko)
	print("KO STILL: max bone movement per frame after %.2f s = %.5f m (want < 0.0005)" % [settle, max_move])
	print("KO %s" % ("PASS" if clip_after_ko == "ko" and max_move < 0.0005 and moved < 0.0005 else "FAIL"))
	dummy.reset_for_round(Vector3(2.0, 0, 3.0), PI)
	await _wait(0.3)
	print("RESET: alive=%s lying=%s visual_upright=%s" % [dummy.is_alive(), dummy.model.lying, dummy.visual.global_basis.y.normalized().dot(Vector3.UP) > 0.95])
	quit()

func _wait(seconds: float) -> void:
	for i in maxi(int(round(seconds * 60.0)), 1):
		await physics_frame
