extends SceneTree
## Performance check: a 4-CPU match on the Aviary with power-ups, VSync off, sampling frame time, draw calls,
## primitives, objects and memory for ~25 s, plus a VFX stress burst (repeated explosions + feathers).
## Run (windowed): Godot --path . --resolution 1600x900 -s tools/perf_check.gd

func _init() -> void:
	await process_frame
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var mm := root.get_node("MatchManager")
	mm.power_ups = true
	mm.players.clear()
	var ids: Array[String] = []
	for d in BirdData.load_all():
		ids.append(d.id)
	for d in ["hard", "hard", "normal", "normal"]:
		mm._add_player(true, d, false, -1, mm._next_bird(ids))
	mm.rounds_to_win = 99
	var map: Node = load("res://scenes/maps/aviary.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	# Optional variants: shadow=<size> msaa=<0|2> shadows=off seconds=<n> nostress
	var args := OS.get_cmdline_user_args()
	var seconds := 25.0
	for a in args:
		if a.begins_with("shadow="):
			RenderingServer.directional_shadow_atlas_set_size(int(a.get_slice("=", 1)), true)
		elif a.begins_with("msaa="):
			root.msaa_3d = Viewport.MSAA_DISABLED if a.ends_with("0") else Viewport.MSAA_2X
		elif a == "shadows=off":
			for l in map.find_children("*", "DirectionalLight3D", true, false):
				l.shadow_enabled = false
		elif a.begins_with("seconds="):
			seconds = float(a.get_slice("=", 1))
	for i in 120:
		await process_frame # warm-up (shader compilation)
	var normal := await _sample(seconds)
	if args.has("nostress"):
		print("PERF %s: %s" % [" ".join(args), normal])
		quit()
		return
	# VFX stress: an explosion + feather burst every 0.15 s for 3 s.
	var stress := {"frames": []}
	var t := 0.0
	var frames: Array[float] = []
	var peak_draws := 0
	while t < 3.0:
		var p := Vector3(randf_range(-8, 8), 0.3, randf_range(-5, 5))
		Fx.explosion(p, 1.6)
		Fx.feathers(p, [Color.WHITE, Color.ORANGE, Color.BROWN])
		for k in 9:
			await process_frame
			var dt := get_root().get_process_delta_time() if false else Performance.get_monitor(Performance.TIME_PROCESS)
			frames.append(1.0 / maxf(Engine.get_frames_per_second(), 1.0))
			peak_draws = maxi(peak_draws, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
			t += 1.0 / maxf(Engine.get_frames_per_second(), 1.0)
	print("PERF normal: %s" % normal)
	print("PERF vfx stress: min_fps=%d peak_draw_calls=%d" % [int(Engine.get_frames_per_second()), peak_draws])
	quit()

func _sample(seconds: float) -> Dictionary:
	var fps: Array[float] = []
	var draws: Array[int] = []
	var prims: Array[int] = []
	var t := 0.0
	while t < seconds:
		await process_frame
		var dt := 1.0 / maxf(Engine.get_frames_per_second(), 1.0)
		t += dt
		fps.append(Engine.get_frames_per_second())
		draws.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		prims.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	fps.sort()
	return {
		"fps_avg": int(fps.reduce(func(a, b): return a + b, 0.0) / fps.size()),
		"fps_1pct_low": int(fps[int(fps.size() * 0.01)]),
		"draw_calls_avg": int(draws.reduce(func(a, b): return a + b, 0) / draws.size()),
		"draw_calls_max": draws.max(),
		"primitives_avg": int(prims.reduce(func(a, b): return a + b, 0) / prims.size()),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"static_mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
		"physics_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01),
	}
