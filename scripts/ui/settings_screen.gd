extends Control
## Game settings: rounds to win (3/5/7), CPU birds and their difficulty, power-ups on/off (Stage 5),
## map (one for now), then Start. Any joined player's device (or any device) navigates:
## up/down = row, left/right = change, accept on "Start match" = go; back = character select.

const SELECT := "res://scenes/ui/character_select.tscn"

var _menu := MenuInput.new()
var _rows: Array[Dictionary] = [] # {name, label: Label, value: Label, panel: PanelContainer}
var _sel := 0
var _leaving := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("33553a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var leaves := Control.new()
	leaves.set_script(load("res://scripts/ui/leaf_drift.gd"))
	add_child(leaves)
	var title := UiKit.label("Game settings", 54, UiKit.TEXT, 0.9)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-400, 40)
	title.custom_minimum_size = Vector2(800, 0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	MatchManager.refresh_maps()
	var humans := MatchManager.humans.size()
	MatchManager.cpu_count = clampi(MatchManager.cpu_count, 0, MatchManager.MAX_PLAYERS - humans)
	if humans + MatchManager.cpu_count < 2 and humans < MatchManager.MAX_PLAYERS:
		MatchManager.cpu_count = MatchManager.MAX_PLAYERS - humans # someone to fight

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-380, -320)
	box.custom_minimum_size = Vector2(760, 0)
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	for r in ["Rounds to win", "CPU birds", "CPU difficulty", "Power-ups", "Map", "Volume", "Display", "Controller", "Start match!"]:
		var p := UiKit.panel(Color(1, 1, 1, 0.1), UiKit.BG)
		var h := HBoxContainer.new()
		p.add_child(h)
		var l := UiKit.label(r, 32, UiKit.TEXT, 0.7)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		var val := UiKit.label("", 32, UiKit.WARM, 0.8)
		h.add_child(val)
		box.add_child(p)
		_rows.append({"name": r, "label": l, "value": val, "panel": p})
	var hint := UiKit.label("▲ ▼ choose   ◀ ▶ change   (A) / Space confirm   (B) / Esc back", 24, UiKit.TEXT_DIM, 0.5)
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-600, -80)
	hint.custom_minimum_size = Vector2(1200, 0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)
	_refresh()

func _refresh() -> void:
	var mm := MatchManager
	var human_n := mm.humans.size()
	var vals := {
		"Rounds to win": "◀  %d  ▶" % mm.rounds_to_win,
		"CPU birds": "◀  %d  ▶" % mm.cpu_count,
		"CPU difficulty": "◀  %s  ▶" % mm.cpu_difficulty.capitalize() if mm.cpu_count > 0 else "—",
		"Power-ups": "◀  %s  ▶" % ("On" if mm.power_ups else "Off"),
		"Volume": "◀  %s  ▶" % ("Off" if mm.volume == 0 else "%d" % mm.volume),
		"Display": "◀  %s  ▶" % ("Fullscreen" if mm.fullscreen else "Windowed"),
		"Controller": "◀  %s  ▶" % {"auto": "Auto", "nintendo": "Switch (A = yes)", "xbox": "Xbox (A = yes, bottom)"}[mm.controller_layout],
		"Map": "◀  %s  ▶" % mm.maps()[mm.map_index]["name"] if mm.maps().size() > 1 else mm.maps()[0]["name"],
		"Start match!": "%d player%s" % [human_n + mm.cpu_count, "" if human_n + mm.cpu_count == 1 else "s"],
	}
	for i in _rows.size():
		var r := _rows[i]
		var on := i == _sel
		r["value"].text = vals[r["name"]]
		r["panel"].add_theme_stylebox_override("panel", UiKit.panel_style(UiKit.WARM if on else Color(1, 1, 1, 0.1), UiKit.BG if not on else UiKit.BG_SOFT))
		r["label"].add_theme_color_override("font_color", UiKit.WARM if on else UiKit.TEXT)

func _input(event: InputEvent) -> void:
	if _leaving:
		return
	var a := _menu.read(event)
	if a.is_empty():
		return
	var action: String = a[1]
	var mm := MatchManager
	var row: String = _rows[_sel]["name"]
	match action:
		"up", "down":
			_sel = wrapi(_sel + (1 if action == "down" else -1), 0, _rows.size())
			UiKit.pop(_rows[_sel]["panel"], 0.04)
			Sfx.play("ui_move")
		"left", "right":
			var d := 1 if action == "right" else -1
			match row:
				"Rounds to win":
					var opts := Tuning.get_default().rounds_to_win_options
					mm.rounds_to_win = opts[wrapi(opts.find(mm.rounds_to_win) + d, 0, opts.size())]
				"CPU birds":
					mm.cpu_count = wrapi(mm.cpu_count + d, 0, mm.MAX_PLAYERS - mm.humans.size() + 1)
				"CPU difficulty":
					mm.cpu_difficulty = mm.DIFFICULTIES[wrapi(mm.DIFFICULTIES.find(mm.cpu_difficulty) + d, 0, mm.DIFFICULTIES.size())]
				"Power-ups":
					mm.power_ups = not mm.power_ups
				"Map":
					mm.map_index = wrapi(mm.map_index + d, 0, mm.maps().size())
				"Volume":
					mm.set_volume(mm.volume + d)
				"Display":
					mm.set_fullscreen(not mm.fullscreen)
				"Controller":
					mm.set_controller_layout(mm.LAYOUTS[wrapi(mm.LAYOUTS.find(mm.controller_layout) + d, 0, mm.LAYOUTS.size())])
			UiKit.pop(_rows[_sel]["value"], 0.15)
			Sfx.play("ui_change")
		"accept", "start":
			if row == "Start match!" or action == "start":
				Sfx.play("ui_confirm")
				_start()
				return
			_sel = _rows.size() - 1
			Sfx.play("ui_move")
		"back":
			_leaving = true
			Sfx.play("ui_back")
			UiKit.go_to(get_tree(), SELECT)
			return
	_refresh()

func _start() -> void:
	_leaving = true
	MatchManager.build_players_from_menu()
	UiKit.go_to(get_tree(), MatchManager.map_path())
