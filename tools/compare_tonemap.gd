extends SceneTree
## Renders a scene with Linear and AgX tonemapping and saves both plus a split image
## (left half Linear, right half AgX).
## Run: Godot --path . --resolution 1600x900 -s tools/compare_tonemap.gd -- <scene> <out_dir>

func _init() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var scene: Node = load(args[0]).instantiate()
	root.add_child(scene)
	var env: Environment = (scene.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment).environment
	var imgs := {}
	for mode in [["linear", Environment.TONE_MAPPER_LINEAR], ["agx", Environment.TONE_MAPPER_AGX]]:
		env.tonemap_mode = mode[1]
		for i in 20:
			await process_frame
		var img := root.get_texture().get_image()
		img.save_png(args[1].path_join("tonemap_%s.png" % mode[0]))
		imgs[mode[0]] = img
	var split: Image = imgs["linear"].duplicate()
	var w := split.get_width()
	split.blit_rect(imgs["agx"], Rect2i(w / 2, 0, w - w / 2, split.get_height()), Vector2i(w / 2, 0))
	split.fill_rect(Rect2i(w / 2 - 1, 0, 2, split.get_height()), Color.WHITE)
	split.save_png(args[1].path_join("tonemap_split.png"))
	print("tonemap compare done")
	quit()
