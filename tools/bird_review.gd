extends SceneTree
## Bird model review sheets (used for the model quality pass before/after). Real bird scene + BirdData,
## game lighting, neutral face, no blinking. Each sheet is a 4 x 2 grid of per-bird close-ups:
##   front.png  three_q.png  side.png  back.png  game_cam.png (50° game pitch, 3/4 facing)
##   poses.png   eagle / owl / rooster / flamingo in draw, slap, victory and dash poses (game camera)
##   arena.png + arena_2x.png  all 8 in the test arena from the real game camera (true scale)
##   tris.txt   triangles per assembled bird (visible model meshes, bow/quiver excluded)
## Run: Godot --path . --audio-driver Dummy --resolution 1600x900 -s tools/bird_review.gd -- <out_dir>

const BIRD := preload("res://scenes/birds/bird.tscn")
const CELL := Vector2i(640, 860)
const SPACING := 4.0

var out := ""
var cam: Camera3D

func _init() -> void:
	await process_frame
	out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	var flock := BirdData.load_all()
	# The birds' and ground's border fade darkens anything outside the arena: widen it so every bird in the
	# lineup (spread along +X) is lit the same.
	RenderingServer.global_shader_parameter_set("arena_half_size", Vector2(200, 200))
	var world := _plain_world()
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.7
	world.add_child(cam)
	cam.current = true

	var birds: Array = []
	for i in flock.size():
		birds.append(_spawn(world, flock[i], 0, Vector3(i * SPACING, 0, 0), PI))
	await _settle(birds, 30)

	# Triangle counts (visible model meshes only).
	var lines := PackedStringArray()
	for i in flock.size():
		lines.append("%-9s %5d" % [flock[i].id, _tris(birds[i].model)])
	var f := FileAccess.open(out.path_join("tris.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("\n".join(lines))

	# [name, facing, camera pitch (deg), target height]
	var views := [["front", PI, 0.0, 0.72], ["three_q", PI * 0.78, 12.0, 0.7], ["side", PI * 0.5, 0.0, 0.72],
		["back", 0.0, 8.0, 0.72], ["game_cam", PI * 0.85, Tuning.get_default().camera_pitch, 0.6]]
	for v in views:
		for b in birds:
			b.facing = v[1]
		await _settle(birds, 12)
		var sheet := Image.create(CELL.x * 4, CELL.y * 2, false, Image.FORMAT_RGBA8)
		for i in birds.size():
			_aim(Vector3(i * SPACING, v[3], 0), v[2])
			await _frames(3)
			_blit(sheet, i)
		sheet.save_png(out.path_join(v[0] + ".png"))

	# Action poses at the game camera angle.
	var pose_ids := ["eagle", "owl", "rooster", "flamingo"]
	var poses := [["draw", 0.45], ["slap", 0.09], ["victory", 0.2], ["dash", 0.08]]
	var sheet := Image.create(CELL.x * 4, CELL.y * 4, false, Image.FORMAT_RGBA8)
	for r in pose_ids.size():
		var b = birds[flock.map(func(d): return d.id).find(pose_ids[r])]
		b.facing = PI * 0.8
		for c in poses.size():
			var clip: String = poses[c][0]
			b.model.anim.play(clip, 0.0)
			b.model.anim.seek(poses[c][1], true)
			b.model.anim.pause()
			b.visual.update_visual(1.0 / 60.0, Vector3.ZERO, b.facing, clip == "draw", clip == "dash")
			_aim(b.global_position + Vector3(0, 0.6, 0), Tuning.get_default().camera_pitch)
			await _frames(3)
			var img := root.get_texture().get_image()
			var cut := img.get_region(Rect2i(800 - CELL.x / 2, 20, CELL.x, CELL.y))
			cut.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(cut, Rect2i(Vector2i.ZERO, CELL), Vector2i(c * CELL.x, r * CELL.y))
		b.model.anim.play("idle")
	sheet.save_png(out.path_join("poses.png"))
	world.free()

	# In the arena at true scale, from the real game camera.
	RenderingServer.global_shader_parameter_set("arena_half_size", Vector2(10, 7))
	var map: Node = load("res://scenes/maps/test_map.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	if map.has_node("DebugHud"):
		map.get_node("DebugHud").free()
	await _frames(2)
	for n in get_nodes_in_group("birds"):
		n.free()
	var arena := []
	var rings := [Color("ff5a5a"), Color("4da6ff"), Color("ffd23f"), Color("b57bff")]
	for i in flock.size():
		var pos := Vector3((i % 4 - 1.5) * 2.6, 0, 1.6 + (i / 4) * 2.4)
		var b := _spawn(map, flock[i], 0, pos, PI + (i % 4 - 1.5) * 0.25, rings[i % 4])
		b.ring.visible = true
		arena.append(b)
	await _settle(arena, 30)
	var img := root.get_texture().get_image()
	img.save_png(out.path_join("arena.png"))
	var gc := root.get_viewport().get_camera_3d()
	var c2 := gc.unproject_position(Vector3(0, 0.5, 2.8))
	var crop := img.get_region(Rect2i(int(c2.x) - 330, int(c2.y) - 150, 660, 300))
	crop.resize(1320, 600, Image.INTERPOLATE_NEAREST)
	crop.save_png(out.path_join("arena_2x.png"))
	print("bird review saved to ", out)
	quit()

func _aim(target: Vector3, pitch_deg: float) -> void:
	cam.rotation = Vector3(-deg_to_rad(pitch_deg), 0, 0)
	cam.position = target + cam.basis.z * 20.0

func _blit(sheet: Image, i: int) -> void:
	var img := root.get_texture().get_image()
	var cut := img.get_region(Rect2i(800 - CELL.x / 2, 20, CELL.x, CELL.y))
	cut.convert(Image.FORMAT_RGBA8)
	sheet.blit_rect(cut, Rect2i(Vector2i.ZERO, CELL), Vector2i((i % 4) * CELL.x, (i / 4) * CELL.y))

func _tris(model: Node) -> int:
	var n := 0
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			n += (arr[Mesh.ARRAY_INDEX].size() if arr[Mesh.ARRAY_INDEX] else arr[Mesh.ARRAY_VERTEX].size()) / 3
	return n

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
	b.ring.visible = false
	b.model._blink_timer = 999.0
	return b

func _settle(birds: Array, frames: int) -> void:
	for f in frames:
		for b in birds:
			b.visual.look_yaw = b.facing
			b.visual.update_visual(1.0 / 60.0, Vector3.ZERO, b.facing, false, false)
		await process_frame

func _frames(n: int) -> void:
	for i in n:
		await process_frame

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
	sun.directional_shadow_max_distance = 60.0
	sun.shadow_normal_bias = 1.5
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 120)
	ground.mesh = plane
	ground.material_override = load("res://assets/materials/ground.tres")
	world.add_child(ground)
	return world
