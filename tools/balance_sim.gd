extends SceneTree
## Balance data from CPU-only matches on the Aviary (headless, fixed 60 fps, runs faster than real time):
## per-difficulty match/round win rates, round length, and how often the round winner held the most power-ups.
## Run: Godot --headless --fixed-fps 60 --path . -s tools/balance_sim.gd -- <matches> <powerups on|off>

func _init() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var matches := int(args[0]) if args.size() > 0 else 6
	var pu := args.size() < 2 or args[1] == "on"
	var mm := root.get_node("MatchManager")
	mm.power_ups = pu
	var lineup := ["hard", "normal", "normal", "easy"]
	# Optional 3rd arg: "h2n2" lineup and hard-profile overrides like range=10,curve=false,draw=0.35:0.6,lead=0.5
	if args.size() > 2:
		lineup = ["hard", "hard", "normal", "normal"]
		var prof: Dictionary = Tuning.get_default().cpu_profiles["hard"]
		for kv in args[2].split(",", false):
			var k := kv.get_slice("=", 0)
			var v := kv.get_slice("=", 1)
			if k == "draw":
				prof["draw"] = [float(v.get_slice(":", 0)), float(v.get_slice(":", 1))]
			elif k == "curve":
				prof["curve"] = v == "true"
			elif k != "base":
				prof[k] = float(v)
		print("hard profile: ", prof)
	var match_wins := {"hard": 0, "normal": 0, "easy": 0}
	var round_wins := {"hard": 0, "normal": 0, "easy": 0}
	var rounds := 0
	var round_secs := 0.0
	var leader_wins := 0
	var leader_rounds := 0
	var melee := {"stuns": {}, "parries": {}}
	var hooked := {}
	for m in matches:
		mm.players.clear()
		var ids: Array[String] = []
		for d in BirdData.load_all():
			ids.append(d.id)
		for d in lineup:
			mm._add_player(true, d, false, -1, mm._next_bird(ids))
		mm.rounds_to_win = 3
		var map: Node = load("res://scenes/maps/aviary.tscn").instantiate()
		root.add_child(map)
		current_scene = map
		var rc := map.get_node("RoundController")
		var frames := 0
		var start := 0
		var playing := false
		var prev_scores: Dictionary = {}
		while frames < 60 * 600 and rc.phase != rc.Phase.MATCH_OVER:
			await physics_frame
			frames += 1
			for b in get_nodes_in_group("birds"):
				if not hooked.has(b):
					hooked[b] = true
					var dif: String = mm.player(b.player_index)["difficulty"]
					b.stunned.connect(_count_stun.bind(melee["stuns"], mm))
					b.parried.connect(func(_b, _a): melee["parries"][dif] = melee["parries"].get(dif, 0) + 1)
			if rc.phase == rc.Phase.PLAYING and not playing:
				playing = true
				start = frames
				prev_scores = mm.scores.duplicate()
			elif playing and rc.phase != rc.Phase.PLAYING and rc.phase != rc.Phase.ROUND_ENDING:
				playing = false
				rounds += 1
				round_secs += (frames - start) / 60.0
				for p in mm.players:
					if mm.scores.get(p["slot"], 0) > prev_scores.get(p["slot"], 0):
						round_wins[p["difficulty"]] += 1
						var most := 0
						for q in mm.players:
							most = maxi(most, q.get("powers", []).size())
						if most > 0:
							leader_rounds += 1
							if p.get("powers", []).size() == most:
								leader_wins += 1
		var w: int = mm.match_winner()
		if w >= 0:
			match_wins[mm.player(w)["difficulty"]] += 1
		map.free()
		await process_frame
	print("BALANCE power-ups=%s matches=%d rounds=%d avg_round=%.1fs" % [pu, matches, rounds, round_secs / maxf(rounds, 1)])
	print("  match wins: %s  (lineup: %s)" % [match_wins, lineup])
	print("  round wins: %s" % round_wins)
	print("  stuns dealt: %s   arrows batted: %s" % [melee["stuns"], melee["parries"]])
	if pu:
		print("  rounds won by a bird holding the most power-ups: %d / %d (when anyone held any)" % [leader_wins, leader_rounds])
	quit()

func _count_stun(_victim, by, into: Dictionary, mm) -> void:
	if by:
		var d: String = mm.player(by.player_index)["difficulty"]
		into[d] = into.get(d, 0) + 1
