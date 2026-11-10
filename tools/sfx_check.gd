extends SceneTree
## Sound checks (Stage 7).
##   match  - every bank file loads; a CPU match on the Aviary (+ a scripted bat and egg) then prints how often
##            each event played / was dropped by its anti-spam limits, and which never fired.
##            Run: Godot --path . --audio-driver Dummy -s tools/sfx_check.gd -- match
##   levels - plays every event once, 1 s apart, at its bank settings, for an offline render:
##            Godot --path . --audio-driver Dummy --fixed-fps 60 --write-movie <dir>/l.png -s tools/sfx_check.gd -- levels <list.txt>
##            then measure <dir>/l.wav per second (event names in order in list.txt).

func _init() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	if args[0] == "levels":
		await _levels(args[1])
	else:
		await _match()
	quit()

func _levels(list_path: String) -> void:
	var names: Array = Sfx.BANK.keys()
	var f := FileAccess.open(list_path, FileAccess.WRITE)
	f.store_string("\n".join(names))
	f.close()
	for n in names:
		var e: Dictionary = Sfx.BANK[n]
		# Mid pitch, no randomness, through the real bus routing.
		var p := AudioStreamPlayer.new()
		root.add_child(p)
		p.stream = load(e["files"][0])
		p.bus = e.get("bus", "SFX")
		p.volume_db = e.get("vol", 0.0)
		p.pitch_scale = (e["pitch"][0] + e["pitch"][1]) * 0.5
		p.play()
		for i in 60:
			await process_frame
		p.queue_free()

func _match() -> void:
	var bad := 0
	for f in Sfx.all_files():
		if load(f) == null:
			print("MISSING ", f)
			bad += 1
	print("bank: %d events, %d files, %d missing" % [Sfx.BANK.size(), Sfx.all_files().size(), bad])
	var mm := root.get_node("MatchManager")
	mm.players.clear()
	var ids: Array[String] = []
	for d in BirdData.load_all():
		ids.append(d.id)
	for d in ["hard", "normal", "normal", "easy"]:
		mm._add_player(true, d, false, -1, mm._next_bird(ids))
	mm.power_ups = true
	var map: Node = load("res://scenes/maps/aviary.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	var rc = map.get_node("RoundController")
	var frames := 0
	while frames < 60 * 75 and rc.phase != rc.Phase.MATCH_OVER:
		await physics_frame
		frames += 1
	print("played %.0f s of CPU match (phase %d)" % [frames / 60.0, rc.phase])
	var keys: Array = Sfx.BANK.keys()
	keys.sort()
	var never := []
	for k in keys:
		var c: int = Sfx.counts.get(k, 0)
		if c == 0:
			never.append(k)
		else:
			print("  %-16s %4d played  %4d dropped" % [k, c, Sfx.dropped.get(k, 0)])
	print("never fired in the match: ", never)
