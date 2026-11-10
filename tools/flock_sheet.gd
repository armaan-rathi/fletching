extends SceneTree
## Flock approval sheets using the real bird scene (bird.tscn + BirdData):
##   flock_front.png    all 8 birds (variant 0), front view
##   flock_three_q.png  all 8, 3/4 view
##   flock_arena.png    all 8 in the test arena from the game camera (true scale) + flock_arena_2x.png crop
##   flock_variants.png 8 birds x 4 color variants, game-camera angle close-up
## Run: Godot --path . --resolution 1600x900 -s tools/flock_sheet.gd -- <out_dir>

const BIRD := preload("res://scenes/birds/bird.tscn")

var out := ""

func _init() -> void:
	await process_frame
	out = OS.get_cmdline_user_args()[0]
	var flock := BirdData.load_all()

	# --- Lineups in a plain lit world --------------------------------------------------
	var world := _plain_world()
	var line := []
	for i in flock.size():
		var b := _spawn(world, flock[i], 0, Vector3((i - 3.5) * 1.0, 0, 0), PI)
		_label(b, flock[i].display_name, Vector3(0, 1.4, 0))
		line.append(b)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.add_child(cam)
	cam.current = true
	cam.size = 4.7
	cam.position = Vector3(0, 0.8, 20)
	await _settle(line)
	_save("flock_front.png")
	for b in line:
		b.facing = PI * 0.78
	await _settle(line)
	_save("flock_three_q.png")

	# Variants grid at the game camera angle: one column per bird, one row per variant.
	for b in line:
		b.queue_free()
	var grid := []
	for i in flock.size():
		for vi in 4:
			grid.append(_spawn(world, flock[i], vi, Vector3((i - 3.5) * 1.45, 0, (vi - 1.5) * 1.6), PI * 0.85))
		var lbl := Label3D.new()
		lbl.text = flock[i].display_name
		lbl.font_size = 56
		lbl.pixel_size = 0.004
		lbl.outline_size = 12
		lbl.modulate = Color("fff6e0")
		lbl.outline_modulate = Color("2a2233")
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = Vector3((i - 3.5) * 1.45, 1.3, -3.4)
		world.add_child(lbl)
	var pitch := deg_to_rad(Tuning.get_default().camera_pitch)
	cam.rotation = Vector3(-pitch, 0, 0)
	cam.size = 7.4
	cam.position = Vector3(0, 0.6, -0.3) + cam.basis.z * 30.0
	await _settle(grid)
	_save("flock_variants.png")
	world.free()

	# --- In the arena, true scale -------------------------------------------------------
	var map: Node = load("res://scenes/maps/test_map.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	map.get_node("DebugHud").free()
	map.get_node("Player1").free()
	var arena := []
	var rings := [Color("ff5a5a"), Color("4da6ff"), Color("ffd23f"), Color("b57bff")]
	for i in flock.size():
		var pos := Vector3((i % 4 - 1.5) * 2.6, 0, 1.6 + (i / 4) * 2.4)
		var b := _spawn(map, flock[i], 0, pos, PI + (i % 4 - 1.5) * 0.25, rings[i % 4])
		arena.append(b)
	await _settle(arena)
	var img := root.get_texture().get_image()
	img.save_png(out.path_join("flock_arena.png"))
	var c := root.get_viewport().get_camera_3d().unproject_position(Vector3(0, 0.5, 2.8))
	var crop := img.get_region(Rect2i(int(c.x) - 330, int(c.y) - 150, 660, 300))
	crop.resize(1320, 600, Image.INTERPOLATE_NEAREST)
	crop.save_png(out.path_join("flock_arena_2x.png"))
	print("flock sheets saved")
	quit()

func _spawn(parent: Node, data: BirdData, vi: int, pos: Vector3, facing: float, ring := Color("ff5a5a")) -> Node3D:
	var b: Node3D = BIRD.instantiate()
	b.bird_data = data
	b.variant = vi
	b.player_color = ring
	parent.add_child(b)
	b.global_position = pos
	b.set_physics_process(false)
	b.set_process_input(false)
	b.facing = facing
	b.model._blink_timer = 999.0
	return b

func _label(b: Node3D, text: String, offset: Vector3) -> void:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 48
	lbl.pixel_size = 0.004
	lbl.outline_size = 10
	lbl.modulate = Color("fff6e0")
	lbl.outline_modulate = Color("2a2233")
	lbl.position = offset
	b.add_child(lbl)

func _settle(birds: Array) -> void:
	for f in 30:
		for b in birds:
			b.visual.look_yaw = b.facing
			b.visual.update_visual(1.0 / 60.0, Vector3.ZERO, b.facing, false, false)
		await process_frame

func _save(name: String) -> void:
	root.get_texture().get_image().save_png(out.path_join(name))

func _plain_world() -> Node3D:
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("8dbf5a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.ambient_light_energy = 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
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
	plane.size = Vector2(80, 80)
	ground.mesh = plane
	ground.material_override = load("res://assets/materials/ground.tres")
	world.add_child(ground)
	return world
