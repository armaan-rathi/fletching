extends SceneTree
## Generates the shared toon materials and the Stage 1 look-test scene.
## Run: Godot --headless --path . -s tools/build_look_test.gd
## Re-running overwrites assets/materials/{outline,kaykit_forest_toon,ground}.tres and scenes/maps/look_test.tscn.

const FOREST := "res://assets/third_party/kaykit_forest/"
const ARENA := Vector2(20.0, 14.0)
const PLAYER_COLORS := [Color("ff5a5a"), Color("4da6ff"), Color("ffd23f"), Color("b57bff")]

var outline_mat: ShaderMaterial
var scene_root: Node
var rng := RandomNumberGenerator.new()

func _init() -> void:
	# Autoloads (e.g. Fx) only exist after the first frame; game scripts need them to compile.
	await process_frame
	rng.seed = 7
	_build_materials()
	run()
	quit()

## Subclasses (e.g. build_stage1.gd) override this to build other scenes with the same kit.
func run() -> void:
	_build_scene()

# --- Materials ---------------------------------------------------------------

func _build_materials() -> void:
	outline_mat = ShaderMaterial.new()
	outline_mat.shader = load("res://assets/shaders/outline.gdshader")
	outline_mat.set_shader_parameter("outline_width", 0.03)
	_save(outline_mat, "res://assets/materials/outline.tres")
	outline_mat = load("res://assets/materials/outline.tres")

	var forest := ShaderMaterial.new()
	forest.shader = load("res://assets/shaders/toon.gdshader")
	forest.set_shader_parameter("use_texture", true)
	forest.set_shader_parameter("albedo_texture", load(FOREST + "forest_texture.png"))
	forest.set_shader_parameter("rim_strength", 0.12)
	# Pull KayKit's orange bark toward the palette's bark brown (#6B4A33).
	forest.set_shader_parameter("band_tint_1", Color(0.66, 0.68, 0.78))
	forest.next_pass = outline_mat
	_save(forest, "res://assets/materials/kaykit_forest_toon.tres")

	var ground := ShaderMaterial.new()
	ground.shader = load("res://assets/shaders/ground.gdshader")
	_save(ground, "res://assets/materials/ground.tres")

func _save(res: Resource, path: String) -> void:
	var err := ResourceSaver.save(res, path)
	print("saved %s: %s" % [path, error_string(err)])

func toon(color: Color, rim := 0.2, outline := true) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/toon.gdshader")
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("rim_strength", rim)
	if outline:
		m.next_pass = outline_mat
	return m

# --- Scene -------------------------------------------------------------------

func own(node: Node, parent: Node) -> Node:
	parent.add_child(node)
	node.owner = scene_root
	return node

func _build_scene() -> void:
	build_base("LookTest", true)

	var arena := Node3D.new()
	arena.name = "ArenaProps"
	own(arena, scene_root)
	prop(arena, "Tree_1_A", Vector3(0.0, 0.0, -0.5), 20.0)
	prop(arena, "Rock_1_D", Vector3(-5.5, 0.0, 3.0), 40.0)
	prop(arena, "Rock_2_B", Vector3(-4.8, 0.0, 3.8), 10.0)
	prop(arena, "Bush_2_B", Vector3(6.0, 0.0, -3.0), 0.0)
	prop(arena, "Bush_4_B", Vector3(-6.5, 0.0, -3.2), 30.0)
	prop(arena, "Bush_3_A", Vector3(5.5, 0.0, 4.2), 0.0)
	prop(arena, "Grass_2_C", Vector3(2.0, 0.0, 1.5), 0.0)
	prop(arena, "Grass_1_B", Vector3(-2.5, 0.0, -2.0), 0.0)
	prop(arena, "Grass_1_C", Vector3(7.5, 0.0, 1.0), 0.0)

	var prims := Node3D.new()
	prims.name = "Primitives"
	own(prims, scene_root)
	_build_primitives(prims)

	save_scene("res://scenes/maps/look_test.tscn")

func save_scene(path: String) -> void:
	var packed := PackedScene.new()
	var err := packed.pack(scene_root)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	print("saved %s: %s" % [path, error_string(err)])
	scene_root.free()

## Environment, sun, camera, ground and decorative border: everything the approved look shares.
func build_base(scene_name: String, debug_pitch_keys: bool) -> void:
	scene_root = Node3D.new()
	scene_root.name = scene_name

	# Environment: flat colors, no ambient (toon lighting supplies the shade band).
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("2f5d3a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.ambient_light_energy = 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	own(we, scene_root)

	# Warm key light from the front-left, shadows fall right and slightly back.
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color("ffe6b0")
	sun.light_energy = 1.0
	sun.rotation_degrees = Vector3(-55.0, -70.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 40.0
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 1.5
	own(sun, scene_root)

	var cam := Camera3D.new()
	cam.name = "ArenaCamera"
	cam.set_script(load("res://scripts/arena_camera.gd"))
	cam.set("arena_size", ARENA)
	cam.set("debug_pitch_keys", debug_pitch_keys)
	cam.current = true
	own(cam, scene_root)

	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(140.0, 140.0)
	ground.mesh = plane
	ground.material_override = load("res://assets/materials/ground.tres")
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	own(ground, scene_root)

	var border := Node3D.new()
	border.name = "Border"
	own(border, scene_root)
	_build_border(border)

	# Subtle screen vignette (the world-space border fade does most of the work).
	var vig_layer := CanvasLayer.new()
	vig_layer.name = "Vignette"
	vig_layer.layer = -1
	own(vig_layer, scene_root)
	var vig := ColorRect.new()
	vig.name = "Rect"
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vmat := ShaderMaterial.new()
	vmat.shader = load("res://assets/shaders/vignette.gdshader")
	vig.material = vmat
	own(vig, vig_layer)

func prop(parent: Node, model: String, pos: Vector3, yaw_deg: float, scale := 1.0, shadows := true) -> Node3D:
	var p := Node3D.new()
	p.set_script(load("res://scripts/toon_prop.gd"))
	p.name = model
	p.set("model", load(FOREST + model + "_Color1.gltf"))
	p.set("cast_shadows", shadows)
	p.position = pos
	p.rotation_degrees.y = yaw_deg
	p.scale = Vector3.ONE * scale
	own(p, parent)
	return p

func pick(options: Array) -> String:
	return options[rng.randi() % options.size()]

func _build_border(parent: Node3D) -> void:
	var hx := ARENA.x * 0.5
	var hz := ARENA.y * 0.5
	var tall := ["Tree_1_A", "Tree_1_B", "Tree_2_A", "Tree_2_B", "Tree_2_C", "Tree_3_A", "Tree_3_B", "Tree_4_A", "Tree_4_B"]
	var mid := ["Tree_1_A", "Tree_3_A", "Tree_Bare_1_B", "Tree_2_A"]
	var bushes := ["Bush_1_C", "Bush_1_D", "Bush_2_C", "Bush_3_B", "Bush_4_C", "Bush_1_E", "Bush_4_D"]
	var low := ["Bush_1_B", "Bush_3_A", "Bush_3_B", "Bush_4_B", "Bush_2_B", "Rock_1_A", "Rock_1_C", "Rock_2_B", "Bush_1_C"]
	var j := func(a: float) -> float: return rng.randf_range(-a, a)

	# Back edge: dense tall tree line, two rows, bushes in front.
	var x := -hx - 7.0
	while x < hx + 7.0:
		prop(parent, pick(tall), Vector3(x + j.call(0.6), 0, -hz - 1.6 + j.call(0.5)), rng.randf() * 360.0, rng.randf_range(0.9, 1.15))
		prop(parent, pick(tall), Vector3(x + 1.3 + j.call(0.6), 0, -hz - 4.2 + j.call(0.8)), rng.randf() * 360.0, rng.randf_range(1.0, 1.25))
		prop(parent, pick(bushes), Vector3(x + 0.8 + j.call(0.7), 0, -hz - 0.4 + j.call(0.5)), rng.randf() * 360.0, rng.randf_range(0.8, 1.25))
		if rng.randf() < 0.5:
			prop(parent, pick(low), Vector3(x + 2.0 + j.call(0.4), 0, -hz - 0.1 + j.call(0.3)), rng.randf() * 360.0, rng.randf_range(0.7, 1.0))
		x += rng.randf_range(2.0, 3.0)

	# Sides: mid-height trees and bushes.
	for side in [-1.0, 1.0]:
		var z := -hz + 0.5
		while z < hz + 3.0:
			prop(parent, pick(bushes), Vector3(side * (hx + 0.6 + j.call(0.3)), 0, z + j.call(0.4)), rng.randf() * 360.0)
			if z < hz - 1.0:
				prop(parent, pick(mid), Vector3(side * (hx + 2.6 + j.call(0.6)), 0, z + 0.9 + j.call(0.5)), rng.randf() * 360.0)
			prop(parent, pick(tall), Vector3(side * (hx + 5.0 + j.call(0.8)), 0, z + j.call(0.8)), rng.randf() * 360.0)
			z += 2.2

	# Front edge: low bushes and rocks only, so nothing covers the arena from the camera.
	x = -hx - 1.5
	while x < hx + 1.5:
		prop(parent, pick(low), Vector3(x + j.call(0.6), 0, hz + 0.7 + j.call(0.5)), rng.randf() * 360.0, rng.randf_range(0.8, 1.2), false)
		if rng.randf() < 0.6:
			prop(parent, pick(low), Vector3(x + 0.9 + j.call(0.4), 0, hz + 1.3 + j.call(0.4)), rng.randf() * 360.0, rng.randf_range(0.7, 1.1), false)
		prop(parent, pick(bushes), Vector3(x + 1.0 + j.call(0.6), 0, hz + 2.4 + j.call(0.7)), rng.randf() * 360.0, rng.randf_range(0.9, 1.2), false)
		x += rng.randf_range(1.4, 2.2)

func _build_primitives(parent: Node3D) -> void:
	var spots := [Vector3(-3.5, 0, 2.0), Vector3(3.0, 0, 1.5), Vector3(-1.2, 0, -2.6), Vector3(3.5, 0, -4.5)]
	var facings := [20.0, -35.0, 160.0, 200.0]
	for i in 4:
		var bird := Node3D.new()
		bird.name = "ph_TestBird%d" % (i + 1)
		bird.position = spots[i]
		bird.rotation_degrees.y = facings[i]
		own(bird, parent)
		_build_test_bird(bird, PLAYER_COLORS[i])

	# A log and a stump as chunky project-style props.
	var bark := toon(Color("6b4a33"), 0.1)
	var log_mi := MeshInstance3D.new()
	log_mi.name = "ph_Log"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35; cyl.bottom_radius = 0.38; cyl.height = 2.6; cyl.radial_segments = 12; cyl.rings = 1
	log_mi.mesh = cyl
	log_mi.material_override = bark
	log_mi.position = Vector3(-6.0, 0.35, 0.2)
	log_mi.rotation_degrees = Vector3(0, 70, 90)
	own(log_mi, parent)

	var stump := MeshInstance3D.new()
	stump.name = "ph_Stump"
	var scyl := CylinderMesh.new()
	scyl.top_radius = 0.45; scyl.bottom_radius = 0.55; scyl.height = 0.6; scyl.radial_segments = 12; scyl.rings = 1
	stump.mesh = scyl
	stump.material_override = bark
	stump.position = Vector3(6.5, 0.3, 1.0)
	own(stump, parent)

func _build_test_bird(bird: Node3D, color: Color) -> void:
	var ring := MeshInstance3D.new()
	ring.name = "PlayerRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5; torus.outer_radius = 0.62; torus.rings = 24; torus.ring_segments = 6
	ring.mesh = torus
	ring.scale = Vector3(1, 0.12, 1)
	ring.position.y = 0.02
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = color
	ring.material_override = ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	own(ring, bird)

	var body := MeshInstance3D.new()
	body.name = "Body"
	var egg := SphereMesh.new()
	egg.radius = 0.42; egg.height = 0.95; egg.radial_segments = 24; egg.rings = 12
	body.mesh = egg
	body.position.y = 0.52
	body.material_override = toon(color.lerp(Color("8a6a50"), 0.25), 0.25)
	own(body, bird)

	var belly := MeshInstance3D.new()
	belly.name = "Belly"
	var bs := SphereMesh.new()
	bs.radius = 0.3; bs.height = 0.6; bs.radial_segments = 16; bs.rings = 8
	belly.mesh = bs
	belly.position = Vector3(0, 0.42, 0.17)
	belly.material_override = toon(Color("f4ead8"), 0.2, false)
	own(belly, bird)

	var beak := MeshInstance3D.new()
	beak.name = "Beak"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0; cone.bottom_radius = 0.1; cone.height = 0.22; cone.radial_segments = 8; cone.rings = 1
	beak.mesh = cone
	beak.position = Vector3(0, 0.66, 0.43)
	beak.rotation_degrees.x = 90
	beak.material_override = toon(Color("f2b233"), 0.1)
	own(beak, bird)

	for s in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.name = "Eye" + ("L" if s < 0 else "R")
		var es := SphereMesh.new()
		es.radius = 0.075; es.height = 0.13; es.radial_segments = 12; es.rings = 6
		eye.mesh = es
		eye.position = Vector3(s * 0.15, 0.78, 0.34)
		eye.material_override = toon(Color("1d1a24"), 0.0, false)
		own(eye, bird)
		var glint := MeshInstance3D.new()
		glint.name = "Glint"
		var gs := SphereMesh.new()
		gs.radius = 0.025; gs.height = 0.05; gs.radial_segments = 8; gs.rings = 4
		glint.mesh = gs
		glint.position = Vector3(0.02, 0.03, 0.06)
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glint.material_override = gm
		own(glint, eye)

	for s in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		wing.name = "Wing" + ("L" if s < 0 else "R")
		var ws := SphereMesh.new()
		ws.radius = 0.14; ws.height = 0.38; ws.radial_segments = 12; ws.rings = 6
		wing.mesh = ws
		wing.position = Vector3(s * 0.42, 0.5, 0.0)
		wing.rotation_degrees.z = s * 25.0
		wing.material_override = toon(color.lerp(Color("2a2233"), 0.2), 0.2)
		own(wing, bird)
