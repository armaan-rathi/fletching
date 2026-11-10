extends SceneTree
## Previews static bird models (assets/birds/exploration/<name>.glb) in the real test arena from the game
## camera at true in-game scale, plus a 1:1 crop, a 3x zoom and a front view.
## Run: Godot --path . --resolution 1600x900 -s tools/render_bird_preview.gd -- <out_dir> <name> [<name>...]

const DIR := "res://assets/birds/exploration/"
const PALETTES := {
	"eagle": {"body": Color("553624"), "belly": Color("553624"), "beak": Color("f5b82e"), "legs": Color("f5b82e"), "accent": Color("f8f8f5")},
	"owl": {"body": Color("8a6240"), "belly": Color("ead8b6"), "beak": Color("d9a441"), "legs": Color("c9a15a"), "accent": Color("6e4a30")},
}
const RINGS := [Color("ff5a5a"), Color("4da6ff"), Color("ffd23f"), Color("b57bff")]

func _init() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var names: Array = args.slice(1)

	# 1. In the arena, from the map's own camera.
	var map: Node = load("res://scenes/maps/test_map.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	for n in ["Player1", "DebugHud"]:
		map.get_node(n).free()
	var spots := [Vector3(-2.2, 0, 2.6), Vector3(2.2, 0, 2.6), Vector3(-2.2, 0, 4.6), Vector3(2.2, 0, 4.6)]
	for i in names.size():
		var b := _make_bird(names[i], RINGS[i % RINGS.size()])
		map.add_child(b)
		b.position = spots[i]
		b.rotation_degrees.y = 15.0 if i % 2 == 0 else -15.0
	await _settle()
	var img := root.get_texture().get_image()
	img.save_png(out.path_join("arena_full.png"))
	var cam := root.get_viewport().get_camera_3d()
	var c := cam.unproject_position(Vector3(0, 0.5, 2.6))
	var crop := img.get_region(Rect2i(int(c.x) - 220, int(c.y) - 110, 440, 220))
	crop.save_png(out.path_join("arena_1x.png"))
	var big := crop.duplicate()
	big.resize(crop.get_width() * 3, crop.get_height() * 3, Image.INTERPOLATE_NEAREST)
	big.save_png(out.path_join("arena_3x.png"))
	map.free()
	current_scene = null

	# 2. Front view in a plain lit world.
	var world := _plain_world()
	for i in names.size():
		var b := _make_bird(names[i], RINGS[i % RINGS.size()])
		world.add_child(b)
		b.position = Vector3((i - (names.size() - 1) * 0.5) * 1.35, 0, 0)
	var fcam := Camera3D.new()
	fcam.projection = Camera3D.PROJECTION_ORTHOGONAL
	fcam.size = 1.6
	fcam.position = Vector3(0, 0.6, 20)
	world.add_child(fcam)
	fcam.current = true
	await _settle()
	root.get_texture().get_image().save_png(out.path_join("front.png"))
	# 3/4 view from the side, to judge beak projection and the collar.
	fcam.position = Vector3(14, 0.9, 14)
	fcam.look_at(Vector3(0, 0.55, 0))
	await _settle()
	root.get_texture().get_image().save_png(out.path_join("three_quarter.png"))
	print("preview saved")
	quit()

func _settle() -> void:
	for i in 20:
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
	sun.directional_shadow_max_distance = 40.0
	sun.shadow_normal_bias = 1.5
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	ground.material_override = load("res://assets/materials/ground.tres")
	world.add_child(ground)
	return world

func _make_bird(model_name: String, ring_color: Color) -> Node3D:
	var holder := Node3D.new()
	var model: Node3D = load(DIR + model_name + ".glb").instantiate()
	holder.add_child(model)
	var style := "eagle" if model_name.contains("eagle") else "owl"
	var cols: Dictionary = PALETTES[style]
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in mi.mesh.get_surface_count():
			var slot: String = mi.mesh.surface_get_material(i).resource_name
			var mat: Material = ToonMaterials.eye() if slot == "eyes" else ToonMaterials.character(cols.get(slot, Color.MAGENTA), slot != "belly")
			mi.set_surface_override_material(i, mat)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.4; cyl.bottom_radius = 0.4; cyl.height = 0.02
	disc.mesh = cyl
	disc.position.y = 0.1
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	holder.add_child(disc)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5; torus.outer_radius = 0.62
	ring.mesh = torus
	ring.scale = Vector3(1, 0.12, 1)
	ring.position.y = 0.02
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = ring_color
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(ring)
	return holder
