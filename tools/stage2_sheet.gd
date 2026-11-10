extends SceneTree
## Stage 2 review sheets with the real bird scene:
##   faces_resting.png   the 8 birds' resting eyes, close-up (front)
##   expressions_<id>.png the expression set on one bird (3/4 view), with symbols and beak
##   animations.png       clip poses: idle, draw, release, dash, slap, squawk, KO, victory, flamingo idle
## Run: Godot --path . --resolution 1600x900 -s tools/stage2_sheet.gd -- <out_dir>

const BIRD := preload("res://scenes/birds/bird.tscn")
const EXPR := ["neutral", "focused", "determined", "shocked", "annoyed", "confused", "smug", "ko", "happy", "sad", "sleepy"]

var out := ""
var cam: Camera3D

func _init() -> void:
	await process_frame
	out = OS.get_cmdline_user_args()[0]
	var flock := BirdData.load_all()
	var world := _plain_world()
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.add_child(cam)
	cam.current = true

	# 1. Resting faces, front close-up (2 rows of 4).
	var birds := []
	for i in flock.size():
		var b := _spawn(world, flock[i], Vector3((i % 4 - 1.5) * 1.15, 0, (i / 4) * -30.0), PI)
		birds.append(b)
	cam.size = 2.9
	for row in 2:
		cam.position = Vector3(0, 0.85, 20 - row * 30.0)
		await _settle(birds, 12)
		_save("faces_resting_%d.png" % row)
	for b in birds:
		b.queue_free()

	# 2. Expressions on the eagle and the owl.
	for id in ["eagle", "owl"]:
		var data: BirdData = load("res://data/birds/%s.tres" % id)
		var grid := []
		for i in EXPR.size():
			var b := _spawn(world, data, Vector3((i % 4 - 1.5) * 1.7, 0, (i / 4) * 2.7 - 2.7), PI * 0.88)
			if EXPR[i] != "neutral":
				b.model.expressions.request(EXPR[i], 999.0)
			_label(world, EXPR[i], b.position + Vector3(0, 1.75, 0))
			grid.append(b)
		cam.rotation = Vector3(deg_to_rad(-25), 0, 0)
		cam.size = 6.6
		cam.position = Vector3(0, 0.6, 0) + cam.basis.z * 20.0
		await _settle(grid, 25)
		_save("expressions_%s.png" % id)
		for b in grid:
			b.queue_free()
		for n in world.get_children():
			if n is Label3D:
				n.queue_free()
		await process_frame

	# 3. Animation poses (eagle; flamingo for its one-leg idle).
	var eagle: BirdData = load("res://data/birds/eagle.tres")
	var poses := [["idle", "state", 0.6], ["draw", "state", 0.3], ["release", "once", 0.06], ["dash", "state", 0.2],
		["slap", "once", 0.1], ["squawk", "once", 0.15], ["ko", "state", 0.7], ["victory", "state", 0.1]]
	var anim_birds := []
	for i in poses.size():
		var b := _spawn(world, eagle, Vector3((i % 4 - 1.5) * 1.6, 0, (i / 4) * 2.7 - 1.35), PI * 0.75)
		_label(world, poses[i][0], b.position + Vector3(0, 1.75, 0))
		anim_birds.append(b)
	var flam := _spawn(world, load("res://data/birds/flamingo.tres"), Vector3(3.9, 0, -0.05), PI * 0.75)
	_label(world, "flamingo idle", flam.position + Vector3(0, 1.95, 0))
	anim_birds.append(flam)
	await _settle(anim_birds, 3)
	for i in poses.size():
		var m: BirdModel = anim_birds[i].model
		# No cross-fade here: a frozen player (speed 0) would never finish blending.
		m.anim.play(poses[i][0], 0.0)
		m.anim.seek(poses[i][2], true)
		m.anim.speed_scale = 0.0
	flam.model.anim.seek(0.6, true)
	flam.model.anim.speed_scale = 0.0
	cam.size = 6.0
	cam.position = Vector3(0.4, 0.6, 0) + cam.basis.z * 20.0
	await _settle(anim_birds, 15)
	_save("animations.png")
	print("stage 2 sheets saved")
	quit()

func _spawn(parent: Node, data: BirdData, pos: Vector3, facing: float) -> Node3D:
	var b: Node3D = BIRD.instantiate()
	b.bird_data = data
	parent.add_child(b)
	b.global_position = pos
	b.set_physics_process(false)
	b.set_process_input(false)
	b.facing = facing
	b.model._blink_timer = 999.0
	return b

func _label(parent: Node, text: String, pos: Vector3) -> void:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 40
	lbl.pixel_size = 0.004
	lbl.outline_size = 10
	lbl.modulate = Color("fff6e0")
	lbl.outline_modulate = Color("2a2233")
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = pos
	parent.add_child(lbl)

func _settle(birds: Array, frames: int) -> void:
	for f in frames:
		for b in birds:
			if is_instance_valid(b):
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
	plane.size = Vector2(120, 120)
	ground.mesh = plane
	ground.material_override = load("res://assets/materials/ground.tres")
	world.add_child(ground)
	return world
