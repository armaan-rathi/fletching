extends SceneTree
## One-off project setup: input map, collision layer names, display and render settings,
## toon shader globals, and the default tuning resource. Safe to re-run.
## Run: Godot --headless --path . -s tools/setup_project.gd

func key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.device = -1
	e.physical_keycode = code
	return e

func mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.device = -1
	e.button_index = button
	return e

func joy_button(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = -1
	e.button_index = button
	return e

func joy_axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.device = -1
	e.axis = axis
	e.axis_value = value
	return e

func action(name: String, events: Array, deadzone := 0.2) -> void:
	ProjectSettings.set_setting("input/" + name, {"deadzone": deadzone, "events": events})

func _init() -> void:
	# Input (device -1 = any device; per-player device mapping comes in Stage 3).
	action("move_left", [key(KEY_A), joy_axis(JOY_AXIS_LEFT_X, -1.0)])
	action("move_right", [key(KEY_D), joy_axis(JOY_AXIS_LEFT_X, 1.0)])
	action("move_up", [key(KEY_W), joy_axis(JOY_AXIS_LEFT_Y, -1.0)])
	action("move_down", [key(KEY_S), joy_axis(JOY_AXIS_LEFT_Y, 1.0)])
	action("aim_left", [joy_axis(JOY_AXIS_RIGHT_X, -1.0)], 0.3)
	action("aim_right", [joy_axis(JOY_AXIS_RIGHT_X, 1.0)], 0.3)
	action("aim_up", [joy_axis(JOY_AXIS_RIGHT_Y, -1.0)], 0.3)
	action("aim_down", [joy_axis(JOY_AXIS_RIGHT_Y, 1.0)], 0.3)
	# Gamepad buttons are positional (SDL3): JOY_BUTTON_A = bottom face button (Switch B), B = right (Switch A),
	# X = left (Switch Y), Y = top (Switch X). Layout per the user (Switch): R / ZR / X shoot, L / ZL / Y shrike,
	# B dash, A melee. Menus confirm / back by the pad's labels (MenuInput).
	action("shoot", [mouse(MOUSE_BUTTON_LEFT), key(KEY_SPACE), joy_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0), joy_button(JOY_BUTTON_RIGHT_SHOULDER), joy_button(JOY_BUTTON_Y)], 0.3)
	action("dash", [key(KEY_SHIFT), joy_button(JOY_BUTTON_A)])
	# Melee (wing slap / arrow bat) has its own button: right mouse / F, RB / X (pad).
	# Shrike (lob shot straight up): Q / middle mouse, LT / Y (pad). Hold to charge, release to launch.
	action("shrike", [key(KEY_Q), mouse(MOUSE_BUTTON_MIDDLE), joy_axis(JOY_AXIS_TRIGGER_LEFT, 1.0), joy_button(JOY_BUTTON_LEFT_SHOULDER), joy_button(JOY_BUTTON_X)], 0.3)
	action("melee", [mouse(MOUSE_BUTTON_RIGHT), key(KEY_F), joy_button(JOY_BUTTON_B)])
	action("pause", [key(KEY_ESCAPE), joy_button(JOY_BUTTON_START)])
	# Look-test helpers (debug only).
	action("debug_pitch_50", [key(KEY_1)])
	action("debug_pitch_55", [key(KEY_2)])
	action("debug_pitch_60", [key(KEY_3)])

	# Collision layer names.
	var layers := ["world", "birds", "bird_hitboxes", "arrows", "pickups", "arrow_stickable", "breakables", "bird_blockers"]
	for i in layers.size():
		ProjectSettings.set_setting("layer_names/3d_physics/layer_%d" % (i + 1), layers[i])

	# Display.
	ProjectSettings.set_setting("display/window/size/viewport_width", 1600)
	ProjectSettings.set_setting("display/window/size/viewport_height", 900)
	ProjectSettings.set_setting("display/window/stretch/mode", "canvas_items")
	ProjectSettings.set_setting("display/window/stretch/aspect", "expand")

	# Rendering: MSAA keeps the hull outlines clean; one directional shadow map tuned for a small arena.
	ProjectSettings.set_setting("rendering/anti_aliasing/quality/msaa_3d", 2)
	ProjectSettings.set_setting("rendering/lights_and_shadows/directional_shadow/size", 4096)
	ProjectSettings.set_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 0)
	ProjectSettings.set_setting("rendering/environment/defaults/default_clear_color", Color("2f5d3a"))

	# Toon shading globals (shared by every toon material).
	ProjectSettings.set_setting("shader_globals/toon_shade_color", {"type": "color", "value": Color("acafd3")})
	ProjectSettings.set_setting("shader_globals/toon_outline_color", {"type": "color", "value": Color("2a2233")})
	# Cast shadows: cooler/bluer than form shade (toward the design doc's #4A4E7A shadow tint).
	ProjectSettings.set_setting("shader_globals/toon_cast_shadow_color", {"type": "color", "value": Color("9aa0dc")})
	ProjectSettings.set_setting("shader_globals/toon_cast_shadow_lift", {"type": "color", "value": Color(0.29, 0.306, 0.478, 0.35)}) # #4A4E7A
	# Border fade: the clearing stays brightest; the tree line darkens/desaturates outward.
	ProjectSettings.set_setting("shader_globals/arena_half_size", {"type": "vec2", "value": Vector2(10.0, 7.0)})
	ProjectSettings.set_setting("shader_globals/border_darken", {"type": "float", "value": 0.35})
	ProjectSettings.set_setting("shader_globals/border_desaturate", {"type": "float", "value": 0.35})
	ProjectSettings.set_setting("shader_globals/border_fade_distance", {"type": "float", "value": 6.0})
	# Art style exploration switches (0 = baseline toon; scripts/art_style.gd sets them at runtime): one for
	# characters (birds, bows, flying arrows), one for the environment, plus option bits.
	if ProjectSettings.has_setting("shader_globals/art_style"):
		ProjectSettings.set_setting("shader_globals/art_style", null)
	ProjectSettings.set_setting("shader_globals/art_style_char", {"type": "int", "value": 0})
	ProjectSettings.set_setting("shader_globals/art_style_env", {"type": "int", "value": 0})
	ProjectSettings.set_setting("shader_globals/art_style_opts", {"type": "int", "value": 0})

	ProjectSettings.set_setting("application/run/main_scene", "res://scenes/ui/title.tscn")
	# The doc's MatchManager autoload (players, settings, scores). Tool scripts must await a frame before
	# loading scripts that reference it.
	ProjectSettings.set_setting("autoload/MatchManager", "*res://scripts/match_manager.gd")

	var err := ProjectSettings.save()
	print("project.godot saved: ", error_string(err))

	# Audio buses (Stage 7): Music, SFX (gameplay), UI (menus/editor) -> Master, with a limiter on Master so
	# stacked hits never clip. Volumes from the settings screen are applied at runtime (MatchManager).
	while AudioServer.bus_count > 1:
		AudioServer.remove_bus(1)
	for b in ["Music", "SFX", "UI"]:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, b)
		AudioServer.set_bus_send(i, "Master")
	while AudioServer.get_bus_effect_count(0) > 0:
		AudioServer.remove_bus_effect(0, 0)
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.5
	AudioServer.add_bus_effect(0, lim)
	print("default_bus_layout.tres saved: ", error_string(ResourceSaver.save(AudioServer.generate_bus_layout(), "res://default_bus_layout.tres")))

	if not FileAccess.file_exists(Tuning.PATH):
		var t := Tuning.new()
		print("tuning.tres saved: ", error_string(ResourceSaver.save(t, Tuning.PATH)))
	quit()
