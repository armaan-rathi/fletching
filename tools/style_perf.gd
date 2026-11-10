extends SceneTree
## Art style performance log: a live 4-CPU match on the Aviary (power-ups on) with particle bursts every 0.3 s
## (feathers + explosion + dust), VSync off. For every style (both layers), tilt-shift off and on, plus a few
## character/environment hybrids: average FPS, 1% low FPS and average GPU / CPU render time per frame. Anime runs
## with its FX extras on (the CPUs dash, slap and get KO'd). Felt and claymation are also measured with the 12 fps
## stop-motion cap lifted, to show the shading cost on its own. Writes a markdown table to <out.md>.
## GPU timing isn't available on this Metal setup and the display path caps at ~80 fps, so pass a 3D render
## scale (e.g. 2.0 = 4x pixels) to make the frame GPU-bound; FPS then shows each style's relative cost.
## Run (windowed): Godot --path . --audio-driver Dummy --resolution 1600x900 -s tools/style_perf.gd -- <out.md> [seconds] [3d scale]

func _init() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var secs := float(args[1]) if args.size() > 1 else 5.0
	var scale := float(args[2]) if args.size() > 2 else 1.0
	root.scaling_3d_scale = scale
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
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	ArtStyle.anime_fx = true
	# Warm up every style once (shader compilation).
	for st in ArtStyle.NAMES.size():
		ArtStyle.set_style(st)
		for i in 30:
			await process_frame
	var rows := ["| Birds | World | Tilt-shift | Avg FPS | 1% low FPS | GPU ms/frame | CPU render ms/frame |", "|---|---|---|---|---|---|---|"]
	# [char style, env style, tilt-shift, lift the stop-motion cap]
	var configs := []
	for st in ArtStyle.NAMES.size():
		configs.append([st, st, false, false])
		configs.append([st, st, true, false])
	configs.append([2, 2, false, true]) # felt without the 12 fps cap
	configs.append([9, 9, false, true]) # claymation without the 12 fps cap
	configs.append([5, 6, false, false]) # hybrids
	configs.append([9, 7, false, true])
	configs.append([8, 0, false, false])
	configs.append([10, 4, false, false])
	for c in configs:
		ArtStyle.set_styles(c[0], c[1])
		if ArtStyle.tilt_shift != c[2]:
			ArtStyle.toggle_tilt_shift()
		if c[3]:
			Engine.max_fps = 0
		for i in 20:
			await process_frame
		var r := await _sample(secs, vp)
		var note := " (12 fps cap lifted)" if c[3] else ""
		rows.append("| %s | %s%s | %s | %.0f | %.0f | %.2f | %.2f |" % [ArtStyle.NAMES[c[0]], ArtStyle.NAMES[c[1]], note, "on" if c[2] else "off", r["fps"], r["low"], r["gpu"], r["cpu"]])
		print(rows[-1])
		if c[3]:
			ArtStyle.apply() # restore the cap state
	ArtStyle.set_style(0)
	if ArtStyle.tilt_shift:
		ArtStyle.toggle_tilt_shift()
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string("3D render scale %.1f (%.0f%% of window pixels)\n\n" % [scale, scale * scale * 100.0] + "\n".join(rows) + "\n")
	f.close()
	print("style perf written to ", out)
	quit()

func _sample(secs: float, vp: RID) -> Dictionary:
	var dts: Array[float] = []
	var gpu := 0.0
	var cpu := 0.0
	var n := 0
	var t := 0.0
	var burst := 0.0
	var last := Time.get_ticks_usec()
	while t < secs:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1000000.0
		last = now
		t += dt
		burst -= dt
		if burst <= 0.0:
			burst = 0.3
			var p := Vector3(randf_range(-7, 7), 0.3, randf_range(-4.5, 4.5))
			Fx.feathers(p, [Color.WHITE, Color("e0c08a"), Color("6b4a33")])
			Fx.explosion(p + Vector3(1.5, 0, 0), 1.2)
			Fx.dust(p, 8)
		dts.append(dt)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		n += 1
	dts.sort()
	var worst := dts.slice(int(dts.size() * 0.99))
	var avg_worst := 0.0
	for d in worst:
		avg_worst += d
	avg_worst /= maxf(worst.size(), 1)
	return {"fps": n / maxf(t, 0.001), "low": 1.0 / maxf(avg_worst, 0.0001), "gpu": gpu / maxf(n, 1), "cpu": cpu / maxf(n, 1)}
