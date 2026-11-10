extends SceneTree
## Renders a scene and saves a PNG for visual review.
## Run (not headless): Godot --path . --resolution 1600x900 -s tools/screenshot.gd -- <scene.tscn> <out.png> [pitch_deg]

func _init() -> void:
	await process_frame # autoloads (Fx) must exist before game scripts compile
	var args := OS.get_cmdline_user_args()
	var scene: Node = load(args[0]).instantiate()
	root.add_child(scene)
	if args.size() > 2:
		for cam in scene.find_children("*", "Camera3D", true, false):
			if cam.has_method("fit"):
				cam.set("pitch_override", float(args[2]))
	# Let shaders compile and shadows settle.
	for i in 20:
		await process_frame
	var img := root.get_texture().get_image()
	var err := img.save_png(args[1])
	print("screenshot %s: %s" % [args[1], error_string(err)])
	quit()
