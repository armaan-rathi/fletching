extends Node
## Autoload "MatchManager": who is playing (devices, birds, colors, CPU difficulty), match settings,
## scores and stats. Persists across scenes (character select / settings in Stage 4 fill it in).
## The arena's RoundController spawns from `players` and reports results back here.

const PLAYER_COLORS := [Color("ff5a5a"), Color("4da6ff"), Color("ffd23f"), Color("b57bff")]
const MAX_PLAYERS := 4
const DIFFICULTIES := ["easy", "normal", "hard"]

signal scores_changed

## Each: {slot, name, color, cpu, difficulty, keyboard, joypad, bird_id, variant}
var players: Array[Dictionary] = []
var rounds_to_win := 3
var scores := {}   # slot -> round wins
var stats := {}    # slot -> {"kos": int, "arrows": int, "deaths": int}
var round_number := 0

## Menu flow (Stage 4): humans picked in character select, settings from the settings screen.
## Each human: {keyboard: bool, joypad: int, bird_id: String, variant: int}
var humans: Array[Dictionary] = []
var cpu_count := 3
var cpu_difficulty := "normal"
var power_ups := true          # takes effect in Stage 5
const MAPS := [{"name": "Aviary", "path": "res://scenes/maps/aviary.tscn"},
	{"name": "Test Clearing", "path": "res://scenes/maps/test_map.tscn"}]
const CUSTOM_MAP_SCENE := "res://scenes/maps/custom_map.tscn"
const EDITOR_SCENE := "res://scenes/ui/level_editor.tscn"
var map_index := 0
## Editor-made maps: the layout the custom map scene builds, and the editor's state while play-testing
## ({layout, path, dirty}; empty when the match didn't come from the editor).
var custom_layout := {}
var editor_session := {}
var _maps := []

## Quick-play (debug keys in the arena): P1 = keyboard + pad 0 unless split.
var split_devices := false

## Sound volume 0..10 (Master bus), saved in user://settings.cfg.
const SETTINGS_PATH := "user://settings.cfg"
var volume := 8
## Fullscreen (Game settings "Display", or Alt+Enter / Ctrl+Cmd+F anywhere), saved in user://settings.cfg.
var fullscreen := false
## Menu confirm / back buttons: "auto" (Nintendo pads detected by name), "nintendo" or "xbox". Saved.
var controller_layout := "auto"
const LAYOUTS := ["auto", "nintendo", "xbox"]

func _ready() -> void:
	rounds_to_win = Tuning.get_default().rounds_to_win
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		volume = clampi(int(cfg.get_value("audio", "volume", volume)), 0, 10)
		fullscreen = bool(cfg.get_value("display", "fullscreen", false))
		controller_layout = str(cfg.get_value("input", "controller_layout", "auto"))
		if not controller_layout in LAYOUTS:
			controller_layout = "auto"
	apply_volume()
	if fullscreen and not _headless():
		apply_fullscreen.call_deferred()

func _headless() -> bool:
	return DisplayServer.get_name() == "headless"

func _save_setting(section: String, key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(section, key, value)
	cfg.save(SETTINGS_PATH)

func set_volume(v: int) -> void:
	volume = clampi(v, 0, 10)
	apply_volume()
	_save_setting("audio", "volume", volume)

func set_controller_layout(layout: String) -> void:
	controller_layout = layout
	_save_setting("input", "controller_layout", layout)

func set_fullscreen(on: bool) -> void:
	fullscreen = on
	apply_fullscreen()
	_save_setting("display", "fullscreen", fullscreen)

## The whole game scales with the window (stretch mode canvas_items + expand; the camera refits on resize).
## Note: a game started from the Godot editor runs embedded in the editor's Game tab, where fullscreen can't
## take over the screen. Run it outside the editor (or turn embedding off) to go truly fullscreen.
func apply_fullscreen() -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if (k.physical_keycode == KEY_ENTER and k.alt_pressed) or (k.physical_keycode == KEY_F and k.ctrl_pressed and k.meta_pressed):
			set_fullscreen(DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN)
			get_viewport().set_input_as_handled()

func apply_volume() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(bus, volume == 0)
	AudioServer.set_bus_volume_db(bus, linear_to_db(volume / 10.0) if volume > 0 else -80.0)

## Fills `players` from connected devices: P1 on keyboard (+ the first pad unless split), one player per
## remaining pad, then CPU birds up to 4. Birds are assigned without repeats.
func setup_quick_play() -> void:
	players.clear()
	var pads := Input.get_connected_joypads()
	var flock := BirdData.load_all()
	var ids: Array[String] = []
	for d in flock:
		ids.append(d.id)
	var first_pad: int = pads[0] if pads.size() > 0 and not split_devices else -1
	_add_player(false, "", true, first_pad, "eagle")
	for p in pads:
		if p == first_pad or players.size() >= MAX_PLAYERS:
			continue
		_add_player(false, "", false, p, _next_bird(ids))
	for i in cpu_count:
		if players.size() >= MAX_PLAYERS:
			break
		_add_player(true, cpu_difficulty, false, -1, _next_bird(ids))

## Builds `players` from the menu picks: humans in join order, then CPU birds (different birds where possible).
func build_players_from_menu() -> void:
	players.clear()
	var ids: Array[String] = []
	for d in BirdData.load_all():
		ids.append(d.id)
	for h in humans:
		if players.size() >= MAX_PLAYERS:
			break
		_add_player(false, "", h["keyboard"], h["joypad"], h["bird_id"])
		players.back()["variant"] = h["variant"]
	for i in cpu_count:
		if players.size() >= MAX_PLAYERS:
			break
		_add_player(true, cpu_difficulty, false, -1, _next_bird(ids))
		# CPUs avoid a human's exact bird + color.
		var cpu: Dictionary = players.back()
		for h in humans:
			if h["bird_id"] == cpu["bird_id"] and h["variant"] == cpu["variant"]:
				cpu["variant"] = (cpu["variant"] + 1) % 4

## Built-in maps followed by saved editor maps ({name, path} or {name, layout}). refresh_maps() rescans.
func maps() -> Array:
	if _maps.is_empty():
		refresh_maps()
	return _maps

func refresh_maps() -> void:
	_maps = MAPS.duplicate()
	for m in MapBuilder.list_layouts():
		_maps.append({"name": m["name"], "layout": m["path"]})
	map_index = clampi(map_index, 0, _maps.size() - 1)

func map_path() -> String:
	var m: Dictionary = maps()[clampi(map_index, 0, maps().size() - 1)]
	editor_session = {}
	if m.has("layout"):
		custom_layout = MapBuilder.load_layout(m["layout"])
		return CUSTOM_MAP_SCENE
	return m["path"]

## Practice: just P1, no rounds.
func setup_practice() -> void:
	players.clear()
	var pads := Input.get_connected_joypads()
	_add_player(false, "", true, pads[0] if pads.size() > 0 else -1, "eagle")

func _next_bird(ids: Array[String]) -> String:
	var used := players.map(func(p): return p["bird_id"])
	var free := ids.filter(func(i): return not used.has(i))
	return free.pick_random() if free.size() > 0 else ids.pick_random()

func _add_player(cpu: bool, difficulty: String, keyboard: bool, joypad: int, bird_id: String) -> void:
	var slot := players.size()
	players.append({
		"slot": slot,
		"name": ("CPU %d" % (slot + 1)) if cpu else ("P%d" % (slot + 1)),
		"color": PLAYER_COLORS[slot],
		"cpu": cpu,
		"difficulty": difficulty,
		"keyboard": keyboard,
		"joypad": joypad,
		"bird_id": bird_id,
		"variant": 0,
	})

func start_match() -> void:
	scores.clear()
	stats.clear()
	round_number = 0
	for p in players:
		p["powers"] = []
		scores[p["slot"]] = 0
		stats[p["slot"]] = {"kos": 0, "arrows": 0, "deaths": 0}
	scores_changed.emit()

func add_round_win(slot: int) -> void:
	scores[slot] = scores.get(slot, 0) + 1
	scores_changed.emit()

func match_winner() -> int:
	for slot in scores:
		if scores[slot] >= rounds_to_win:
			return slot
	return -1

func add_stat(slot: int, key: String, amount := 1) -> void:
	if stats.has(slot):
		stats[slot][key] = stats[slot].get(key, 0) + amount

func player(slot: int) -> Dictionary:
	for p in players:
		if p["slot"] == slot:
			return p
	return {}
