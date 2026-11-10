extends SceneTree
## Close-up review of the in-game bird scene (bird.tscn) under the game camera angle:
## eagle front, eagle 3/4 squawking, eagle back, owl looking 45° to the side, owl drawing the bow.
## Run: Godot --path . --resolution 1600x700 -s tools/bird_turntable.gd -- <out.png> [pitch]

func _init() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var pitch := float(args[1]) if args.size() > 1 else Tuning.get_default().camera_pitch
	var world := Node3D.new()
	root.add_child(world)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("8dbf5a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.ambient_light_energy = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("ffe6b0")
	sun.rotation_degrees = Vector3(-55, -70, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 40.0
	sun.shadow_normal_bias = 1.5
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	ground.mesh = plane
	ground.material_override = load("res://assets/materials/ground.tres")
	world.add_child(ground)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 3.6
	cam.rotation_degrees.x = -pitch
	cam.position = Vector3(0, 0.5, 0) + cam.basis.z * 20.0
	world.add_child(cam)
	cam.current = true

	# [style, facing, head look offset (deg), squawk, drawing]
	var setups := [["eagle", PI, 0.0, false, false], ["eagle", PI * 0.72, 0.0, true, false], ["eagle", 0.0, 0.0, false, false],
		["owl", PI, 45.0, false, false], ["owl", PI * 0.75, 0.0, false, true]]
	var scene: PackedScene = load("res://scenes/birds/bird.tscn")
	var birds := []
	for i in setups.size():
		var b: Node3D = scene.instantiate()
		b.position = Vector3((i - 2) * 1.6, 0, 0)
		world.add_child(b)
		birds.append(b)
	await process_frame
	for i in setups.size():
		var b = birds[i]
		var s: Array = setups[i]
		b.set_physics_process(false)
		b.set_process_input(false)
		b.model.style = s[0]
		b.facing = s[1]
		b.state = 1 if s[4] else 0 # Bird.State.DRAWING / NORMAL
		b._draw_time = 0.45
		if s[3]:
			b.model.squawk(10.0)
	for frame in 40:
		for i in setups.size():
			var b = birds[i]
			b.visual.look_yaw = b.facing + deg_to_rad(setups[i][2])
			b.visual.update_visual(1.0 / 60.0, Vector3.ZERO, b.facing, b.state == 1, false)
			b._update_indicators(1.0 / 60.0)
		await process_frame
	var img := root.get_texture().get_image()
	print("turntable: ", error_string(img.save_png(args[0])))
	# Front view (horizontal camera) of the same poses.
	cam.rotation = Vector3.ZERO
	cam.position = Vector3(0, 0.6, 20)
	cam.size = 2.6
	for frame in 10:
		await process_frame
	var front := args[0].get_basename() + "_front.png"
	print("front: ", error_string(root.get_texture().get_image().save_png(front)))
	quit()
