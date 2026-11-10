extends SceneTree
## Renders the chibi shape exploration (assets/birds/exploration/*.glb) with the toon look:
##  1. game camera (orthographic, tuning pitch, in-game ortho size) -> crop at 1:1 and 3x zoom
##  2. front view (orthographic, horizontal)
## Run: Godot --path . --resolution 1600x900 -s tools/render_exploration.gd -- <out_dir>

const DIR := "res://assets/birds/exploration/"
const STYLES := ["eagle", "owl"]
const RATIOS := [40, 50, 60]
const COLORS := {
	"eagle": {"body": Color("5a3a28"), "belly": Color("6b4630"), "beak": Color("f2b233"), "legs": Color("f2b233"), "accent": Color("f4f1ea")},
	"owl": {"body": Color("8a6240"), "belly": Color("ead8b6"), "beak": Color("d9a441"), "legs": Color("c9a15a"), "accent": Color("6e4a30")},
}
const RING := Color("ff5a5a")

var world: Node3D
var birds := {}

func _init() -> void:
	await process_frame
	var out: String = OS.get_cmdline_user_args()[0]
	_build_world()
	for style in STYLES:
		for r in RATIOS:
			birds["%s_%d" % [style, r]] = _make_bird(style, r)

	# 1. Game camera at in-game scale.
	var t := Tuning.get_default()
	for i in STYLES.size():
		for j in RATIOS.size():
			var b: Node3D = birds["%s_%d" % [STYLES[i], RATIOS[j]]]
			b.position = Vector3((j - 1) * 2.2, 0, (i - 0.5) * 2.4)
			b.rotation_degrees.y = 20.0
			b.get_node("Label").position = Vector3(0, 0.02, 0.85)
			b.get_node("Label").rotation_degrees = Vector3(-90, -20, 0)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	# Same fit as ArenaCamera for a 20x14 arena at 16:9.
	var pitch := deg_to_rad(t.camera_pitch)
	cam.size = maxf((14.0 + 2.0 * t.camera_margin) * sin(pitch) + 1.5 * cos(pitch), (20.0 + 2.0 * t.camera_margin) / (16.0 / 9.0)) + t.camera_top_ui_margin
	cam.rotation = Vector3(-pitch, 0, 0)
	cam.position = Vector3(0, 0.4, 0) + cam.basis.z * 30.0
	cam.near = 1.0
	cam.far = 100.0
	world.add_child(cam)
	cam.current = true
	await _settle()
	var img := root.get_texture().get_image()
	img.save_png(out.path_join("game_full.png"))
	var c := cam.unproject_position(Vector3(0, 0.4, 0))
	var crop := img.get_region(Rect2i(int(c.x) - 260, int(c.y) - 170, 520, 340))
	crop.save_png(out.path_join("game_1x.png"))
	var big := crop.duplicate()
	big.resize(1560, 1020, Image.INTERPOLATE_NEAREST)
	big.save_png(out.path_join("game_3x.png"))

	# 2. Front view: one line, horizontal ortho camera.
	var k := 0
	for style in STYLES:
		for r in RATIOS:
			var b: Node3D = birds["%s_%d" % [style, r]]
			b.position = Vector3((k - 2.5) * 1.3, 0, 0)
			b.rotation_degrees.y = 0.0
			b.get_node("Label").position = Vector3(0, 1.25, 0)
			b.get_node("Label").rotation_degrees = Vector3.ZERO
			k += 1
	cam.rotation = Vector3.ZERO
	cam.size = 4.6
	cam.position = Vector3(0, 0.75, 20)
	await _settle()
	root.get_texture().get_image().save_png(out.path_join("front.png"))
	print("exploration renders saved")
	quit()

func _settle() -> void:
	for i in 20:
		await process_frame

func _build_world() -> void:
	world = Node3D.new()
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
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 1.5
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	ground.material_override = load("res://assets/materials/ground.tres")
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(ground)

func _make_bird(style: String, ratio: int) -> Node3D:
	var holder := Node3D.new()
	world.add_child(holder)
	var model: Node3D = load(DIR + "ph_shape_%s_%d.glb" % [style, ratio]).instantiate()
	holder.add_child(model)
	var cols: Dictionary = COLORS[style]
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in mi.mesh.get_surface_count():
			var slot: String = mi.mesh.surface_get_material(i).resource_name
			var mat: Material
			if slot == "eyes":
				mat = ToonMaterials.eye()
			elif slot == "belly":
				mat = ToonMaterials.toon(cols[slot], 0.35, false, 0.45)
			else:
				mat = ToonMaterials.toon(cols.get(slot, Color.MAGENTA), 0.4, true, 0.45)
			mi.set_surface_override_material(i, mat)
	# Ground shadow disc + player ring, as in game.
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
	rm.albedo_color = RING
	ring.material_override = rm
	holder.add_child(ring)
	var label := Label3D.new()
	label.name = "Label"
	label.text = "%s %d%%" % [style.capitalize(), ratio]
	label.font_size = 48
	label.pixel_size = 0.004
	label.outline_size = 10
	label.modulate = Color("fff6e0")
	label.outline_modulate = Color("2a2233")
	holder.add_child(label)
	return holder
