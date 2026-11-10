extends "res://tools/build_look_test.gd"
## Generates the Stage 4 menu scenes: title (the clearing + wandering birds + logo), character select, settings.
## The UI itself is built in code by each scene's script (scripts/ui/).
## Run: Godot --headless --path . -s tools/build_stage4.gd

func run() -> void:
	build_base("Title", false)
	scene_root.set_script(load("res://scripts/ui/title_screen.gd"))
	save_scene("res://scenes/ui/title.tscn")
	for s in [["CharacterSelect", "character_select"], ["Settings", "settings_screen"]]:
		_new_control(s[0], "res://scripts/ui/%s.gd" % s[1])
		save_scene("res://scenes/ui/%s.tscn" % ("character_select" if s[1] == "character_select" else "settings"))

func _new_control(root_name: String, script: String) -> void:
	scene_root = Control.new()
	scene_root.name = root_name
	scene_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	scene_root.set_script(load(script))
