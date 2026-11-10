extends SceneTree
## Level editor check: drives the editor with synthetic mouse/keyboard input (place, drag, rotate, scale,
## undo/redo, resize, save + reload), play-tests the map in the custom map scene, returns to the editor,
## and saves screenshots. Run (windowed): Godot --path . --resolution 1600x900 -s tools/editor_check.gd -- <out_dir>

var out := ""
var fails := 0

func _check(what: String, ok: bool, info := "") -> void:
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", what, info])
	if not ok:
		fails += 1

func _wait(frames := 10) -> void:
	for i in frames:
		await process_frame

func _shot(name: String) -> void:
	await _wait(6)
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))

func _click(ed: Node, world: Vector3, button := MOUSE_BUTTON_LEFT, release := true) -> void:
	var p: Vector2 = ed._cam.unproject_position(world)
	var m := InputEventMouseMotion.new()
	m.position = p
	Input.parse_input_event(m)
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.position = p
	e.pressed = true
	Input.parse_input_event(e)
	await _wait(2)
	if release:
		var r := e.duplicate()
		r.pressed = false
		Input.parse_input_event(r)
		await _wait(2)

func _move(ed: Node, world: Vector3) -> void:
	var m := InputEventMouseMotion.new()
	m.position = ed._cam.unproject_position(world)
	Input.parse_input_event(m)
	await _wait(2)

func _key(code: Key, ctrl := false, shift := false) -> void:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	k.ctrl_pressed = ctrl and OS.get_name() != "macOS"
	k.meta_pressed = ctrl and OS.get_name() == "macOS"
	k.shift_pressed = shift
	Input.parse_input_event(k)
	await _wait(2)

func _editor() -> Node:
	change_scene_to_file(MatchManager_path())
	await _wait(30)
	return current_scene

func MatchManager_path() -> String:
	return root.get_node("MatchManager").EDITOR_SCENE

func _init() -> void:
	await process_frame
	out = OS.get_cmdline_user_args()[0]
	var mm := root.get_node("MatchManager")
	mm.editor_session = {}
	var ed := await _editor()
	_check("editor opens with a new map", ed.layout["items"].size() == 4 and ed._nodes.size() == 4, "items=%d" % ed.layout["items"].size())
	await _shot("ed_1_new")

	ed._open_map("res://data/maps/aviary_remix.json")
	await _wait(20)
	var n0: int = ed.layout["items"].size()
	_check("opens Aviary Remix", n0 > 20, "items=%d" % n0)
	await _shot("ed_2_aviary_remix")

	# Place a big rock with the palette brush, then drag it.
	ed._set_brush("rock_big")
	await _click(ed, Vector3(-6.0, 0, 5.0))
	_check("click places the brush item", ed.layout["items"].size() == n0 + 1 and ed.layout["items"].back()["type"] == "rock_big",
		"at %.1f,%.1f" % [ed.layout["items"].back()["x"], ed.layout["items"].back()["z"]])
	ed._set_brush("")
	var i: int = ed.layout["items"].size() - 1
	await _click(ed, Vector3(-6.0, 0.7, 5.0), MOUSE_BUTTON_LEFT, false)
	_check("click selects the item under the cursor", ed.selected == i, "selected=%d" % ed.selected)
	await _move(ed, Vector3(-4.0, 0, 5.5))
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = ed._cam.unproject_position(Vector3(-4.0, 0, 5.5))
	Input.parse_input_event(up)
	await _wait(3)
	var it: Dictionary = ed.layout["items"][i]
	_check("drag moves it (snapped to 0.5 m)", absf(it["x"] - -4.0) < 0.3 and fmod(absf(it["x"]), 0.5) < 0.01, "x=%.2f z=%.2f" % [it["x"], it["z"]])
	await _key(KEY_E)
	await _key(KEY_E)
	_check("E rotates +15° per press", is_equal_approx(it["yaw"], 30.0), "yaw=%.1f" % it["yaw"])
	await _key(KEY_BRACKETRIGHT)
	_check("] scales up", is_equal_approx(it["scale"], 1.1), "scale=%.2f" % it["scale"])
	await _key(KEY_Z, true)
	await _key(KEY_Z, true)
	await _key(KEY_Z, true)
	_check("undo x3 restores the unrotated rock", is_equal_approx(ed.layout["items"][i]["yaw"], 0.0) and is_equal_approx(ed.layout["items"][i]["scale"], 1.0))
	await _key(KEY_Y, true)
	_check("redo reapplies a rotation", is_equal_approx(ed.layout["items"][i]["yaw"], 15.0), "yaw=%.1f" % ed.layout["items"][i]["yaw"])
	ed.selected = i
	await _key(KEY_DELETE)
	_check("delete removes it", ed.layout["items"].size() == n0)

	# Spawn limit.
	ed._set_brush("spawn")
	await _click(ed, Vector3(0, 0, 0))
	_check("5th spawn is refused", MapBuilder.count(ed.layout, "spawn") == 4)
	ed._set_brush("")

	# Bigger arena: camera and border follow, items stay inside.
	ed._resize(Vector2(6, 4))
	await _wait(20)
	_check("arena resizes to 26 x 18", MapBuilder.size_of(ed.layout) == Vector2(26, 18) and ed._cam.arena_size == Vector2(26, 18))
	ed._set_brush("dirt")
	await _click(ed, Vector3(10.0, 0, -6.0))
	ed._set_brush("flowers")
	await _click(ed, Vector3(-11.0, 0, 7.0))
	ed._set_brush("")
	await _shot("ed_3_resized")

	# Save, reload, compare.
	ed._name_edit.text = "zz editor test"
	ed._save()
	var p := MapBuilder.file_for("zz editor test")
	_check("save writes the JSON", FileAccess.file_exists(p), p)
	var back := MapBuilder.load_layout(p)
	_check("reloaded layout matches", back.get("items", []).size() == ed.layout["items"].size() and MapBuilder.size_of(back) == Vector2(26, 18))
	mm.refresh_maps()
	_check("saved map appears in the map list", mm.maps().any(func(m): return m.get("layout", "") == p))

	# Play-test, then come back.
	mm.players.clear()
	mm.cpu_count = 3
	ed._play()
	await _wait(90)
	var map := current_scene
	_check("play opens the custom map", map.scene_file_path == mm.CUSTOM_MAP_SCENE, map.scene_file_path)
	var rc = map.get_node("RoundController")
	var t := 0.0
	while t < 6.0 and rc.phase != rc.Phase.PLAYING:
		await process_frame
		t += 1.0 / 60.0
	_check("round starts", rc.phase == rc.Phase.PLAYING)
	_check("4 birds, 3 pads, 3 nests", rc.birds.size() == 4 and get_nodes_in_group("power_up_pads").size() == 3 and get_nodes_in_group("nests").size() == 3,
		"birds=%d pads=%d nests=%d" % [rc.birds.size(), get_nodes_in_group("power_up_pads").size(), get_nodes_in_group("nests").size()])
	var inside := true
	for b in rc.birds:
		inside = inside and absf(b.global_position.x) < 13.0 and absf(b.global_position.z) < 9.0
	_check("birds spawn inside the 26 x 18 arena", inside)
	await _shot("ed_4_playtest")
	map.get_node("MatchHud")._to_editor()
	await _wait(60)
	ed = current_scene
	_check("back in the editor with the same map", ed.scene_file_path == mm.EDITOR_SCENE and ed.layout.get("name", "") == "zz editor test" and MapBuilder.size_of(ed.layout) == Vector2(26, 18))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("SFX played: ", Sfx.counts)
	print("SIM DONE: %d failure(s)" % fails)
	quit()
