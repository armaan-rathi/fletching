extends SceneTree
## Stall hunt: CPU-only 1v1 matches (the "last 2 CPUs" case) on every map, headless and faster than real time.
## Flags any round that goes `limit` seconds without a KO and prints what both CPUs are doing (position, state,
## arrows, last decision) once a second while it lasts. Ends with a summary: rounds played, longest round, stalls.
## Run: Godot --headless --fixed-fps 60 --path . -s tools/sim_stall.gd -- <matches per map> [limit s] [overtime on|off]
## overtime off: the round timer's egg rain is disabled, so stalls can't be hidden by it.
## Repro of the playtest stall: Godot ... -s tools/sim_stall.gd -- repro
##   Birdbath, two easy CPUs far apart near the outer pads (out of range of each other), a power-up waiting on the
##   x = 15 pad. Passes if a CPU reaches the pad or a KO happens within 25 s.

func _init() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0] == "repro":
		await _repro()
		quit()
		return
	var matches := int(args[0]) if args.size() > 0 else 4
	var limit := float(args[1]) if args.size() > 1 else 40.0
	var overtime := args.size() < 3 or args[2] == "on"
	var mm := root.get_node("MatchManager")
	var t := Tuning.get_default()
	if not overtime:
		t.overtime_after = 99999.0
	var maps := [["aviary", "res://scenes/maps/aviary.tscn", ""], ["birdbath", "", "res://data/maps/birdbath.json"],
		["aviary_remix", "", "res://data/maps/aviary_remix.json"]]
	var diffs := ["easy", "normal", "hard"]
	var rounds := 0
	var stalls := 0
	var longest := 0.0
	for m in maps:
		for i in matches:
			mm.power_ups = i % 2 == 0
			mm.players.clear()
			var ids: Array[String] = []
			for d in BirdData.load_all():
				ids.append(d.id)
			for k in 2:
				mm._add_player(true, diffs[(i + k) % 3], false, -1, mm._next_bird(ids))
			mm.rounds_to_win = 2
			var path: String = m[1]
			if m[2] != "":
				mm.custom_layout = MapBuilder.load_layout(m[2])
				path = mm.CUSTOM_MAP_SCENE
			else:
				mm.custom_layout = {}
			var map: Node = load(path).instantiate()
			root.add_child(map)
			current_scene = map
			var rc := map.get_node("RoundController")
			var frames := 0
			var since_ko := 0.0
			var round_t := 0.0
			var alive_prev := 2
			var flagged := false
			while frames < 60 * 900 and rc.phase != rc.Phase.MATCH_OVER:
				await physics_frame
				frames += 1
				if rc.phase != rc.Phase.PLAYING:
					if round_t > 0.0:
						rounds += 1
						longest = maxf(longest, round_t)
					round_t = 0.0
					since_ko = 0.0
					flagged = false
					alive_prev = 2
					continue
				round_t += 1.0 / 60.0
				since_ko += 1.0 / 60.0
				var birds := get_nodes_in_group("birds")
				var alive := 0
				for b in birds:
					if b.is_alive():
						alive += 1
				if alive != alive_prev:
					since_ko = 0.0
					alive_prev = alive
				if since_ko > limit:
					if not flagged:
						flagged = true
						stalls += 1
						print("STALL on %s match %d (%.0f s without a KO, round %.0f s)" % [m[0], i, since_ko, round_t])
					if frames % 60 == 0 and since_ko < limit + 12.0:
						for b in birds:
							if b.is_alive() and b.input is CpuInput:
								var ci: CpuInput = b.input
								print("  %s [%s] pos=(%.1f, %.1f) state=%d arrows=%d move=(%.2f, %.2f) last=%s" % [
									b.bird_data.id, ci.difficulty, b.global_position.x, b.global_position.z, b.state,
									b.arrows, ci._move.x, ci._move.y, ci.last_branch])
			if rc.phase != rc.Phase.MATCH_OVER:
				print("TIMEOUT on %s match %d" % [m[0], i])
				stalls += 1
			map.queue_free()
			await process_frame
			await process_frame
	print("rounds=%d longest=%.0f s stalls=%d" % [rounds, longest, stalls])
	print("STALL CHECK %s" % ("PASS" if stalls == 0 else "FAIL"))
	quit()

func _repro() -> void:
	var mm := root.get_node("MatchManager")
	Tuning.get_default().overtime_after = 99999.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var fails := 0
	var trials := 24
	for trial in trials:
		mm.power_ups = trial % 2 == 0
		mm.players.clear()
		var ids: Array[String] = []
		for d in BirdData.load_all():
			ids.append(d.id)
		for k in 2:
			mm._add_player(true, ["easy", "normal", "hard"][(trial + k) % 3], false, -1, mm._next_bird(ids))
		mm.rounds_to_win = 2
		mm.custom_layout = MapBuilder.load_layout("res://data/maps/birdbath.json")
		var map: Node = load(mm.CUSTOM_MAP_SCENE).instantiate()
		root.add_child(map)
		current_scene = map
		var rc := map.get_node("RoundController")
		while rc.phase != rc.Phase.PLAYING:
			await physics_frame
		var birds := get_nodes_in_group("birds")
		var half: Vector2 = MapBuilder.arena_half - Vector2(1.5, 1.5)
		for b in birds:
			var p := Vector3.ZERO
			while Vector2(p.x, p.z).length() < 5.0: # not inside the bath
				p = Vector3(rng.randf_range(-half.x, half.x), 0, rng.randf_range(-half.y, half.y))
			b.global_position = p
		var start := [birds[0].global_position, birds[1].global_position]
		var t := 0.0
		var ok := false
		while t < 30.0:
			await physics_frame
			t += 1.0 / 60.0
			if not birds[0].is_alive() or not birds[1].is_alive():
				ok = true
				break
		if not ok:
			fails += 1
			print("STUCK trial %d from %s / %s" % [trial, start[0], start[1]])
			for b in birds:
				var ci: CpuInput = b.input
				print("  [%s] pos=(%.1f, %.1f) move=(%.2f, %.2f) arrows=%d last=%s" % [ci.difficulty, b.global_position.x, b.global_position.z, ci._move.x, ci._move.y, b.arrows, ci.last_branch])
		map.queue_free()
		await process_frame
		await process_frame
	print("REPRO %s: %d / %d trials without a KO in 30 s" % ["PASS" if fails == 0 else "FAIL", fails, trials])
