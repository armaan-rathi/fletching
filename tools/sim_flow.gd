extends SceneTree
## Stage 4 flow test with synthetic key / gamepad events:
## title -> character select (keyboard + pad join, pick, ready) -> settings -> match (pause/resume) -> results -> title.
## Run (windowed): Godot --path . --resolution 1600x900 -s tools/sim_flow.gd -- <out_dir>

var out := ""
var fails := 0

func _init() -> void:
	await process_frame
	out = OS.get_cmdline_user_args()[0]
	var mm := root.get_node("MatchManager")
	mm.humans.clear()
	change_scene_to_file("res://scenes/ui/title.tscn")
	await _wait(1.2)
	await _shot("f1_title")
	_check("starts on the title", _scene().ends_with("title.tscn"))

	await _key(KEY_SPACE)
	await _wait(0.8)
	_check("any key -> character select", _scene().ends_with("character_select.tscn"))
	mm.controller_layout = "xbox" # deterministic: a real Switch pad on device 0 would flip A/B in "auto"
	await _key(KEY_SPACE)                    # keyboard joins as P1
	await _pad(JOY_BUTTON_A, 0)              # pad 0 joins as P2
	await _pad(JOY_BUTTON_DPAD_RIGHT, 0)     # P2: next bird
	await _pad(JOY_BUTTON_DPAD_RIGHT, 0)
	var sel := current_scene
	var p2_bird: int = sel._cards[1].bird
	await _pad(JOY_BUTTON_A, 0)              # P2: bird chosen -> now its color
	await _pad(JOY_BUTTON_DPAD_RIGHT, 0)     # P2: next color (left/right now change the color)
	_check("after choosing a bird, right changes the color, not the bird", sel._cards[1].bird == p2_bird and sel._cards[1].variant == 1, "bird %d -> %d, variant %d" % [p2_bird, sel._cards[1].bird, sel._cards[1].variant])
	await _pad(JOY_BUTTON_B, 0)              # P2: back -> picking birds again
	_check("back from color -> picking birds", not sel._cards[1].picking_color)
	await _pad(JOY_BUTTON_A, 0)              # P2: bird chosen again
	await _key(KEY_D)                        # P1: next bird
	await _key(KEY_SPACE)                    # P1: bird chosen
	await _wait(0.5)
	await _shot("f2_select")
	await _key(KEY_SPACE)                    # P1 ready
	await _pad(JOY_BUTTON_A, 0)              # P2 ready
	await _wait(0.4)
	await _shot("f3_ready")
	# Nintendo layout: A (the right face button, JOY_BUTTON_B) confirms, B (bottom, JOY_BUTTON_A) goes back.
	mm.controller_layout = "nintendo"
	var e := InputEventJoypadButton.new()
	e.button_index = JOY_BUTTON_B
	e.pressed = true
	var r1: Array = MenuInput.new().read(e)
	e.button_index = JOY_BUTTON_A
	var r2: Array = MenuInput.new().read(e)
	mm.controller_layout = "xbox"
	_check("Switch layout: A (right button) confirms, B (bottom) backs", r1[1] == "accept" and r2[1] == "back", "%s / %s" % [r1, r2])
	await _key(KEY_ENTER)                    # continue
	await _wait(0.8)
	_check("all ready -> settings", _scene().ends_with("settings.tscn"))
	_check("two humans recorded", mm.humans.size() == 2)
	await _key(KEY_DOWN)                     # CPU birds row
	await _key(KEY_LEFT)                     # fewer CPUs
	await _key(KEY_DOWN)
	await _key(KEY_RIGHT)                    # CPU difficulty -> hard
	await _wait(0.3)
	await _shot("f4_settings")
	var cpus: int = mm.cpu_count
	await _key(KEY_ENTER)                    # start
	await _wait(1.0)
	_check("settings -> arena (%s)" % mm.map_path().get_file(), _scene() == mm.map_path())
	_check("players = humans + CPUs", mm.players.size() == 2 + cpus)
	await _wait(0.6)
	await _shot("f5_countdown")

	mm.controller_layout = "nintendo"
	await _pad(JOY_BUTTON_A, 1)              # a Switch pad's B (= dash) must not open the pause menu
	_check("Switch B (dash) doesn't pause", not paused)
	await _pad(JOY_BUTTON_START, 1)          # + / Start does
	_check("Start pauses", paused)
	await _pad(JOY_BUTTON_START, 1)
	mm.controller_layout = "xbox"
	await _wait(0.1)
	await _key(KEY_ESCAPE)                   # pause
	await _wait(0.2)
	_check("Esc pauses", paused)
	await _shot("f6_pause")
	await _key(KEY_ESCAPE)                   # resume
	await _wait(0.1)
	_check("Esc resumes", not paused)

	# Let the CPUs finish the match (the humans stand still).
	var rc := current_scene.get_node("RoundController")
	var guard := 0
	while rc.phase != rc.Phase.MATCH_OVER and guard < 60 * 300:
		if rc.phase == rc.Phase.SCOREBOARD and not FileAccess.file_exists(out.path_join("f7_scoreboard.png")):
			await _shot("f7_scoreboard")
		Engine.time_scale = 1.0 if rc.phase == rc.Phase.SCOREBOARD else 4.0
		await process_frame
		guard += 1
	Engine.time_scale = 1.0
	# If humans won rounds by being left alone, the match might be long; just require it to finish.
	_check("match reaches the results screen", rc.phase == rc.Phase.MATCH_OVER)
	await _wait(1.5)
	await _shot("f8_results")
	await _key(KEY_DOWN)
	await _key(KEY_DOWN)                     # "Title screen"
	await _key(KEY_SPACE)
	await _wait(1.0)
	_check("results -> title", _scene().ends_with("title.tscn"))
	print("SFX played: ", Sfx.counts)
	print("SIM DONE: %d failure(s)" % fails)
	quit()

func _scene() -> String:
	return current_scene.scene_file_path if current_scene else ""

func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
		await process_frame
	await process_frame

func _pad(button: JoyButton, device: int) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.device = device
		e.pressed = pressed
		Input.parse_input_event(e)
		await process_frame
	await process_frame

func _wait(seconds: float) -> void:
	for i in maxi(int(seconds * 60.0), 1):
		await process_frame

func _check(label: String, ok: bool, detail := "") -> void:
	if not ok:
		fails += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])

func _shot(name: String) -> void:
	await process_frame
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
