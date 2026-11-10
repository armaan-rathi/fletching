extends CanvasLayer
## In-match UI: score band (player color, name, bird, round-win pips), countdown banner, between-round
## scoreboard (the new point pops in), results screen (winner, stats, Rematch / Character select / Title),
## and the pause menu (Esc / Start: Resume / Restart / Character select / Title).

const SELECT := "res://scenes/ui/character_select.tscn"
const TITLE := "res://scenes/ui/title.tscn"

var _band: HBoxContainer
var _banner: Label
var _sub: Label
var _board: PanelContainer
var _menu_panel: PanelContainer
var _menu_items: Array[Label] = []
var _menu_actions: Array[Callable] = []
var _menu_sel := 0
var _menu := MenuInput.new()
var _practice := false
var _countdown := 0.0
var _paused := false
var _rc: Node
var _down := {}       # slot -> true while that player's bird is knocked out this round
var _panels := {}     # slot -> band panel
var _last_wins := {}  # slot -> wins at last rebuild (to pop on change)
var _last_powers := {}
var _dim: ColorRect
var _overtime: Label
var _overtime_n := -1

func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rc = get_node_or_null("../RoundController")
	_band = HBoxContainer.new()
	_band.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_band.position = Vector2(-400, 10)
	_band.custom_minimum_size = Vector2(800, 0)
	_band.alignment = BoxContainer.ALIGNMENT_CENTER
	_band.add_theme_constant_override("separation", 14)
	add_child(_band)
	_overtime = UiKit.label("", 40, UiKit.WARM, 0.9)
	_overtime.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_overtime.position = Vector2(-300, 112)
	_overtime.custom_minimum_size = Vector2(600, 0)
	_overtime.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overtime.pivot_offset = Vector2(300, 28)
	_overtime.visible = false
	add_child(_overtime)
	_banner = _center_label(76, -150)
	_sub = _center_label(28, -60)
	_dim = ColorRect.new()
	_dim.color = Color(0.06, 0.05, 0.09, 0.5)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.visible = false
	add_child(_dim)
	move_child(_dim, 0)
	MatchManager.scores_changed.connect(_rebuild_band)
	_rebuild_band()
	_band.visible = not _practice

func _center_label(size: int, y: float) -> Label:
	var l := UiKit.label("", size, UiKit.TEXT, 0.9)
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.position = Vector2(-500, y)
	l.custom_minimum_size = Vector2(1000, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)
	return l

## Overtime timer under the score band: seconds left, then "EGG RAIN!" (RoundController). on = false hides it.
func set_overtime(seconds_left: float, on: bool) -> void:
	_overtime.visible = on
	if not on:
		_overtime_n = -1
		return
	var n := maxi(ceili(seconds_left), 0)
	if n == _overtime_n:
		return
	_overtime_n = n
	if n > 0:
		_overtime.text = "Overtime  0:%02d" % n
		_overtime.add_theme_color_override("font_color", UiKit.WARM if n > 10 else Color("ff6b5a"))
		if n <= 10 or n == ceili(Tuning.get_default().overtime_countdown):
			UiKit.pop(_overtime, 0.15, 0.25)
			Sfx.play("count", 0.9)
	else:
		_overtime.text = "EGG RAIN!"
		_overtime.add_theme_color_override("font_color", Color("ff6b5a"))
		UiKit.pop(_overtime, 0.3, 0.3)
		Sfx.play("go", 0.8)

func set_practice(on: bool) -> void:
	_practice = on
	if _band:
		_band.visible = not on

# --- Score band ---------------------------------------------------------------------------

func _pips(slot: int) -> String:
	var wins: int = MatchManager.scores.get(slot, 0)
	return "●".repeat(wins) + "○".repeat(maxi(MatchManager.rounds_to_win - wins, 0))

func _rebuild_band() -> void:
	for c in _band.get_children():
		c.queue_free()
	_panels.clear()
	for p in MatchManager.players:
		var panel := UiKit.panel(p["color"], UiKit.BG)
		_panels[p["slot"]] = panel
		panel.modulate = Color(1, 1, 1, 0.45) if _down.has(p["slot"]) else Color.WHITE
		var wins: int = MatchManager.scores.get(p["slot"], 0)
		var powers: int = p.get("powers", []).size()
		if wins != _last_wins.get(p["slot"], wins) or powers != _last_powers.get(p["slot"], powers):
			panel.ready.connect(func(): UiKit.pop(panel, 0.18, 0.3), CONNECT_ONE_SHOT)
		_last_wins[p["slot"]] = wins
		_last_powers[p["slot"]] = powers
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		var name := UiKit.label(_player_title(p), 18, p["color"].lerp(Color.WHITE, 0.35), 0.6)
		v.add_child(name)
		var h := HBoxContainer.new()
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_theme_constant_override("separation", 6)
		var pips := UiKit.label(_pips(p["slot"]), 20, UiKit.TEXT, 0.4)
		h.add_child(pips)
		for t in p.get("powers", []):
			var icon := TextureRect.new()
			icon.texture = PowerUps.TYPES[t]["icon"]
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(24, 24)
			h.add_child(icon)
		v.add_child(h)
		panel.add_child(v)
		_band.add_child(panel)

func _player_title(p: Dictionary) -> String:
	var bird: BirdData = load("res://data/birds/%s.tres" % p["bird_id"])
	var t := "%s · %s" % [p["name"], bird.display_name if bird else ""]
	if p["cpu"]:
		t += " (%s)" % p["difficulty"]
	return t

# --- Countdown / round result ------------------------------------------------------------

## A player's bird went down: dim their score panel for the rest of the round.
func player_ko(slot: int) -> void:
	_down[slot] = true
	if _panels.has(slot) and is_instance_valid(_panels[slot]):
		var p: Control = _panels[slot]
		var tw := p.create_tween()
		tw.tween_property(p, "modulate", Color(1, 1, 1, 0.45), 0.25)
		UiKit.pop(p, -0.08, 0.2)

func show_countdown(seconds: float, round_number: int) -> void:
	_down.clear()
	for slot in _panels:
		if is_instance_valid(_panels[slot]):
			_panels[slot].modulate = Color.WHITE
	_countdown = seconds
	_close_board()
	_sub.text = "Round %d" % round_number

func show_round_result(winner_slot: int) -> void:
	if winner_slot < 0:
		_set_banner("Draw!", UiKit.TEXT)
		Sfx.play("ui_back")
	else:
		var p := MatchManager.player(winner_slot)
		_set_banner("%s wins the round!" % p["name"], p["color"].lerp(Color.WHITE, 0.25))
		Sfx.play("round_win")
	_sub.text = ""
	_show_board(winner_slot)

func _set_banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	UiKit.pop(_banner, 0.15, 0.3)

## Between-round scoreboard: every player's pips; the round winner's new pip pops.
func _show_board(winner_slot: int) -> void:
	_close_board()
	_board = UiKit.panel(Color(1, 1, 1, 0.15))
	_board.set_anchors_preset(Control.PRESET_CENTER)
	_board.position = Vector2(-300, 0)
	_board.custom_minimum_size = Vector2(600, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_board.add_child(v)
	for p in MatchManager.players:
		var h := HBoxContainer.new()
		var name := UiKit.label(_player_title(p), 24, p["color"].lerp(Color.WHITE, 0.3), 0.6)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(name)
		var pips := UiKit.label(_pips(p["slot"]), 30, UiKit.WARM if p["slot"] == winner_slot else UiKit.TEXT, 0.6)
		h.add_child(pips)
		v.add_child(h)
		if p["slot"] == winner_slot:
			pips.ready.connect(func(): UiKit.pop(pips, 0.4, 0.4), CONNECT_ONE_SHOT)
	add_child(_board)

func _close_board() -> void:
	if _board and is_instance_valid(_board):
		_board.queue_free()
	_board = null

func hide_banner() -> void:
	_banner.text = ""
	_sub.text = ""
	_close_board()

# --- Results -----------------------------------------------------------------------------

func show_results(winner_slot: int) -> void:
	var p := MatchManager.player(winner_slot)
	_set_banner("%s wins the match!" % p["name"], p["color"].lerp(Color.WHITE, 0.25))
	Sfx.play("match_win")
	Sfx.play("coins")
	_sub.text = _player_title(p)
	_close_board()
	_board = UiKit.panel(p["color"])
	_board.set_anchors_preset(Control.PRESET_CENTER)
	_board.position = Vector2(-330, 0)
	_board.custom_minimum_size = Vector2(660, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_board.add_child(v)
	v.add_child(_row(["", "Wins", "KOs", "Arrows"], UiKit.TEXT_DIM, 20))
	var ranked := MatchManager.players.duplicate()
	ranked.sort_custom(func(a, b): return MatchManager.scores.get(a["slot"], 0) > MatchManager.scores.get(b["slot"], 0))
	for q in ranked:
		var st: Dictionary = MatchManager.stats.get(q["slot"], {})
		v.add_child(_row([q["name"], str(MatchManager.scores.get(q["slot"], 0)), str(st.get("kos", 0)), str(st.get("arrows", 0))],
			q["color"].lerp(Color.WHITE, 0.3), 26))
	add_child(_board)
	if MatchManager.editor_session.is_empty():
		_open_menu(["Rematch", "Character select", "Title screen"], [_rematch, _to_select, _to_title], Vector2(-180, 250))
	else:
		_open_menu(["Rematch", "Back to editor"], [_rematch, _to_editor], Vector2(-180, 250))

func _row(cells: Array, color: Color, size: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	for i in cells.size():
		var l := UiKit.label(cells[i], size, color, 0.6)
		l.custom_minimum_size = Vector2(240 if i == 0 else 120, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_CENTER
		h.add_child(l)
	return h

# --- Menus (results / pause) -------------------------------------------------------------

func _open_menu(items: Array, actions: Array, pos: Vector2) -> void:
	_close_menu()
	_menu_panel = UiKit.panel(UiKit.WARM)
	_menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	_menu_panel.position = pos
	_menu_panel.custom_minimum_size = Vector2(360, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_menu_panel.add_child(v)
	_menu_items.clear()
	_menu_actions.clear()
	for i in items.size():
		var l := UiKit.label(items[i], 30, UiKit.TEXT, 0.7)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		_menu_items.append(l)
		_menu_actions.append(actions[i])
	_menu_sel = 0
	add_child(_menu_panel)
	_highlight()

func _close_menu() -> void:
	if _menu_panel and is_instance_valid(_menu_panel):
		_menu_panel.queue_free()
	_menu_panel = null
	_menu_items.clear()

func _highlight() -> void:
	for i in _menu_items.size():
		var on := i == _menu_sel
		_menu_items[i].text = ("▶  %s  ◀" if on else "%s") % _menu_items[i].text.replace("▶  ", "").replace("  ◀", "")
		_menu_items[i].add_theme_color_override("font_color", UiKit.WARM if on else UiKit.TEXT)
	if _menu_sel < _menu_items.size():
		UiKit.pop(_menu_items[_menu_sel], 0.08)

func _input(event: InputEvent) -> void:
	var a := _menu.read(event)
	if a.is_empty():
		return
	var action: String = a[1]
	if _menu_panel:
		match action:
			"up", "down":
				_menu_sel = wrapi(_menu_sel + (1 if action == "down" else -1), 0, _menu_items.size())
				_highlight()
				Sfx.play("ui_move")
			"accept", "start":
				if _paused and action == "start":
					_resume()
				else:
					Sfx.play("ui_confirm")
					_menu_actions[_menu_sel].call()
			"back":
				if _paused:
					_resume()
		get_viewport().set_input_as_handled()
		return
	# Pause during a match: Start / + on a pad, Esc (or Enter) on the keyboard. A pad's "back" button is never
	# pause: on a Switch pad it's B, the dash button (user: couldn't dash without opening the menu).
	var device: int = a[0]
	if (action == "start" or (action == "back" and device == MenuInput.KEYBOARD)) and _rc and _rc.phase in [_rc.Phase.COUNTDOWN, _rc.Phase.PLAYING, _rc.Phase.PRACTICE]:
		_pause()
		get_viewport().set_input_as_handled()

func _pause() -> void:
	_paused = true
	Sfx.play("ui_pause")
	get_tree().paused = true
	_dim.visible = true
	_set_banner("Paused", UiKit.TEXT)
	if MatchManager.editor_session.is_empty():
		_open_menu(["Resume", "Restart match", "Character select", "Title screen"], [_resume, _rematch, _to_select, _to_title], Vector2(-180, -20))
	else:
		_open_menu(["Resume", "Restart match", "Back to editor"], [_resume, _rematch, _to_editor], Vector2(-180, -20))

func _resume() -> void:
	_paused = false
	Sfx.play("ui_unpause")
	get_tree().paused = false
	_dim.visible = false
	_banner.text = ""
	_close_menu()

func _rematch() -> void:
	get_tree().paused = false
	UiKit.go_to(get_tree(), get_tree().current_scene.scene_file_path)

func _to_select() -> void:
	UiKit.go_to(get_tree(), SELECT)

func _to_title() -> void:
	UiKit.go_to(get_tree(), TITLE)

## Play-test from the level editor: back to it with the layout and editor state intact.
func _to_editor() -> void:
	UiKit.go_to(get_tree(), MatchManager.EDITOR_SCENE)

func _process(delta: float) -> void:
	if _paused:
		return # the HUD keeps running while paused; the countdown must not
	if _countdown > 0.0:
		_countdown -= delta
		var n := ceili(_countdown / (Tuning.get_default().round_countdown / 3.0))
		_banner.add_theme_color_override("font_color", UiKit.TEXT)
		if _countdown > 0.0:
			if _banner.text != str(n):
				_banner.text = str(n)
				UiKit.pop(_banner, 0.2, 0.25)
				Sfx.play("count", 1.0 + 0.08 * (3 - n))
		else:
			_set_banner("GO!", UiKit.WARM)
			Sfx.play("go")
			_sub.text = ""
			get_tree().create_timer(0.5).timeout.connect(func(): if _banner.text == "GO!": _banner.text = "")
