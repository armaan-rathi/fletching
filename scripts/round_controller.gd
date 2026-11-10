extends Node
## Runs a match in the arena: spawns the birds from MatchManager.players at the spawn points, counts down,
## watches KOs, decides rounds (last bird standing; simultaneous KOs = draw), shows the scoreboard, and
## ends the match at `rounds_to_win`. With a single player it runs as practice (no rounds).

const BIRD := preload("res://scenes/birds/bird.tscn")

enum Phase { PRACTICE, COUNTDOWN, PLAYING, ROUND_ENDING, SCOREBOARD, MATCH_OVER }

@export var spawns_path := NodePath("../Spawns")
@export var hud_path := NodePath("../MatchHud")

var birds: Array[Bird] = []
var phase := Phase.PRACTICE
var _timer := 0.0
var _hud: Node
var _t: Tuning
## Overtime (user: no endless rounds): after overtime_after s a overtime_countdown s timer shows; at zero eggs
## fall from the sky every overtime_egg_interval s (SkyEgg: shadow, then an eggsplosion).
var _round_time := 0.0
var _egg_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _celebrating: Bird

func _ready() -> void:
	_t = Tuning.get_default()
	_hud = get_node_or_null(hud_path)
	if MatchManager.players.is_empty():
		MatchManager.setup_quick_play()
	MatchManager.start_match()
	for p in MatchManager.players:
		_spawn(p)
	if birds.size() < 2:
		phase = Phase.PRACTICE
		_place_all()
		if _hud:
			_hud.call("set_practice", true)
	else:
		_start_round()

func _spawn(p: Dictionary) -> void:
	var b: Bird = BIRD.instantiate()
	b.name = "Player%d" % (p["slot"] + 1)
	b.player_index = p["slot"]
	b.player_color = p["color"]
	b.display_name = p["name"]
	b.bird_data = load("res://data/birds/%s.tres" % p["bird_id"])
	b.variant = p["variant"]
	if p["cpu"]:
		b.input = CpuInput.new(b, p["difficulty"])
	else:
		b.input = PlayerInput.new(p["keyboard"], p["joypad"])
	get_parent().add_child.call_deferred(b)
	birds.append(b)
	b.knocked_out.connect(_on_ko)
	b.arrow_fired.connect(func(bird: Bird): MatchManager.add_stat(bird.player_index, "arrows"))
	b.power_ups_changed.connect(_on_power_ups_changed)

func _spawn_points() -> Array[Node3D]:
	var out: Array[Node3D] = []
	var sp := get_node_or_null(spawns_path)
	if sp:
		for c in sp.get_children():
			if c is Node3D:
				out.append(c)
	return out

func _place_all() -> void:
	await get_tree().process_frame # birds are added deferred
	var pts := _spawn_points()
	pts.shuffle()
	for i in birds.size():
		var p: Node3D = pts[i % pts.size()] if pts.size() > 0 else null
		var pos := p.global_position if p else Vector3((i - 1.5) * 3.0, 0, 3.0)
		var to_center := -pos
		to_center.y = 0.0
		birds[i].reset_for_round(pos, Bird.yaw_of(to_center.normalized()))

func _start_round() -> void:
	MatchManager.round_number += 1
	for a in get_tree().get_nodes_in_group("arrows"):
		a.queue_free()
	for n in get_tree().get_nodes_in_group("nests"):
		n.reset()
	for n in get_tree().get_nodes_in_group("round_reset"): # e.g. the birdbath puddle
		n.reset()
	await _place_all()
	for b in birds:
		b.frozen = true
		Fx.spawn_poof(b.global_position, b.player_color)
	phase = Phase.COUNTDOWN
	_timer = _t.round_countdown
	_round_time = 0.0
	_egg_timer = 0.0
	_end_overtime()
	_celebrating = null
	var cam := get_viewport().get_camera_3d()
	if cam and cam.has_method("clear_focus"):
		cam.clear_focus()
	if _hud:
		_hud.call("show_countdown", _t.round_countdown, MatchManager.round_number)

func _process(delta: float) -> void:
	match phase:
		Phase.COUNTDOWN:
			_timer -= delta
			if _timer <= 0.0:
				phase = Phase.PLAYING
				for b in birds:
					b.frozen = false
		Phase.PLAYING:
			_overtime(delta)
		Phase.ROUND_ENDING:
			_timer -= delta
			if _timer <= 0.0:
				_decide_round()
		Phase.SCOREBOARD:
			_timer -= delta
			if _timer <= 0.0:
				if _hud:
					_hud.call("hide_banner")
				_start_round()

func _on_power_ups_changed(bird: Bird) -> void:
	var p := MatchManager.player(bird.player_index)
	if not p.is_empty():
		p["powers"] = bird.power_ups.duplicate()
	MatchManager.scores_changed.emit() # refreshes the score band

func _on_ko(victim: Bird, killer: Bird) -> void:
	MatchManager.add_stat(victim.player_index, "deaths")
	if _hud:
		_hud.call("player_ko", victim.player_index)
	if killer and killer != victim:
		MatchManager.add_stat(killer.player_index, "kos")
	if phase == Phase.PLAYING and _alive().size() <= 1:
		phase = Phase.ROUND_ENDING
		_timer = _t.round_end_delay
		_end_overtime()
		var alive := _alive()
		if alive.size() == 1:
			# Let it run on so the winner can celebrate (user: every round, a little longer for the match).
			var match_point: bool = MatchManager.scores.get(alive[0].player_index, 0) + 1 >= MatchManager.rounds_to_win
			_timer = _t.match_celebration_time if match_point else _t.round_celebration_time
			_celebrate(alive[0])

func _celebrate(winner: Bird) -> void:
	_celebrating = winner
	await get_tree().create_timer(_t.match_celebration_delay).timeout
	if not is_instance_valid(winner) or not winner.is_alive():
		return
	winner.frozen = true
	if winner.state == Bird.State.DRAWING:
		winner._cancel_draw()
	var cam := get_viewport().get_camera_3d()
	if cam and cam.has_method("focus_on"):
		cam.focus_on(winner.global_position, _t.match_celebration_zoom)
	winner.celebrate()

func _overtime(delta: float) -> void:
	_round_time += delta
	if _round_time < _t.overtime_after:
		return
	var left := _t.overtime_after + _t.overtime_countdown - _round_time
	if _hud:
		_hud.call("set_overtime", left, true)
	if left > 0.0:
		return
	_egg_timer -= delta
	if _egg_timer <= 0.0:
		_egg_timer = _t.overtime_egg_interval
		_drop_egg()

## A random spot in the arena; every other egg lands near a random bird that's still up (so a round between
## two birds hiding in far corners still ends).
func _drop_egg() -> void:
	var half: Vector2 = MapBuilder.arena_half - Vector2(1.0, 1.0)
	var spot := Vector3(_rng.randf_range(-half.x, half.x), 0.0, _rng.randf_range(-half.y, half.y))
	var alive := _alive()
	if not alive.is_empty() and _rng.randf() < 0.5:
		var b: Bird = alive[_rng.randi() % alive.size()]
		spot = b.global_position + Vector3(_rng.randf_range(-2.5, 2.5), 0.0, _rng.randf_range(-2.5, 2.5))
		spot.x = clampf(spot.x, -half.x, half.x)
		spot.z = clampf(spot.z, -half.y, half.y)
	var egg := SkyEgg.drop(get_parent(), spot)
	egg.add_to_group("sky_eggs")

func _end_overtime() -> void:
	for e in get_tree().get_nodes_in_group("sky_eggs"):
		e.queue_free()
	if _hud:
		_hud.call("set_overtime", 0.0, false)

func _alive() -> Array[Bird]:
	var out: Array[Bird] = []
	for b in birds:
		if b.is_alive():
			out.append(b)
	return out

func _decide_round() -> void:
	var alive := _alive()
	for b in birds:
		b.frozen = true
	var winner: Bird = alive[0] if alive.size() == 1 else null
	if winner:
		MatchManager.add_round_win(winner.player_index)
		winner.pose_override = "victory"
		if winner != _celebrating:
			winner.model.expressions.request("happy", 3.0)
	var match_winner := MatchManager.match_winner()
	if match_winner >= 0:
		phase = Phase.MATCH_OVER
		for b in birds:
			if b.player_index != match_winner:
				b.model.expressions.request("sad", 999.0)
			else:
				b.model.expressions.request(b.victory_expression(), 999.0)
		if _hud:
			_hud.call("show_results", match_winner)
		_confetti(winner)
	else:
		phase = Phase.SCOREBOARD
		_timer = _t.round_scoreboard_time
		if _hud:
			_hud.call("show_round_result", winner.player_index if winner else -1)

## Winner celebration: a few bursts of feathers in the winner's colors.
func _confetti(winner: Bird) -> void:
	if winner == null:
		return
	var cols := [winner.player_color, UiKit.WARM, Color.WHITE]
	for i in 5:
		await get_tree().create_timer(0.35).timeout
		if is_instance_valid(winner):
			Fx.feathers(winner.global_position + Vector3(randf_range(-0.6, 0.6), 1.4, randf_range(-0.3, 0.3)), cols)

## Play again with the same players and settings.
func rematch() -> void:
	get_tree().reload_current_scene()
