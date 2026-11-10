class_name MapBuilder
extends RefCounted
## Builds editor-made maps at runtime from a layout (used by the level editor preview and the custom map
## scene), plus layout file I/O. The world/border code mirrors tools/build_look_test.gd (build_base and
## _build_border), so custom maps look like the hand-built ones; the decorative border scales with the arena.
##
## Layout: {"name": String, "version": 1, "size": [w, d], "seed": int, "items": [item...]}
## (items: see MapCatalog). Saved as JSON in res://data/maps/ when running from the project, user://maps/
## in an exported build.

const VERSION := 1
const PROJECT_DIR := "res://data/maps/"
const USER_DIR := "user://maps/"
const DEFAULT_ARENA := Vector2(20.0, 14.0)
const L_WORLD := 1
const L_STICKABLE := 32
const TALL := ["Tree_1_A", "Tree_1_B", "Tree_2_A", "Tree_2_B", "Tree_2_C", "Tree_3_A", "Tree_3_B", "Tree_4_A", "Tree_4_B"]
const MID := ["Tree_1_A", "Tree_3_A", "Tree_Bare_1_B", "Tree_2_A"]
const BUSHES := ["Bush_1_C", "Bush_1_D", "Bush_2_C", "Bush_3_B", "Bush_4_C", "Bush_1_E", "Bush_4_D"]
const LOW := ["Bush_1_B", "Bush_3_A", "Bush_3_B", "Bush_4_B", "Bush_2_B", "Rock_1_A", "Rock_1_C", "Rock_2_B", "Bush_1_C"]

# --- Layouts ----------------------------------------------------------------------------

static func new_layout(name := "New map", size := DEFAULT_ARENA) -> Dictionary:
	var l := {"name": name, "version": VERSION, "size": [size.x, size.y], "seed": 7, "items": []}
	var sx := size.x * 0.5 - 3.0
	var sz := size.y * 0.5 - 2.7
	for c in [Vector2(-sx, -sz), Vector2(sx, -sz), Vector2(-sx, sz), Vector2(sx, sz)]:
		l["items"].append(item("spawn", c.x, c.y, 0.0))
	return l

static func item(type: String, x: float, z: float, yaw := 0.0, scale := 1.0) -> Dictionary:
	return {"type": type, "x": snappedf(x, 0.01), "z": snappedf(z, 0.01), "yaw": snappedf(yaw, 0.1), "scale": snappedf(scale, 0.01)}

static func size_of(layout: Dictionary) -> Vector2:
	var s: Array = layout.get("size", [DEFAULT_ARENA.x, DEFAULT_ARENA.y])
	return Vector2(float(s[0]), float(s[1]))

static func maps_dir() -> String:
	return PROJECT_DIR if OS.has_feature("editor") else USER_DIR

static func file_for(name: String) -> String:
	var slug := name.strip_edges().to_snake_case().validate_filename().replace(" ", "_")
	if slug == "":
		slug = "untitled"
	return maps_dir() + slug + ".json"

static func save_layout(layout: Dictionary, path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(layout, "\t"))
	return OK

static func load_layout(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	if not data is Dictionary or not data.has("items"):
		return {}
	var items: Array = []
	for it in data["items"]:
		if it is Dictionary and MapCatalog.ITEMS.has(it.get("type", "")):
			items.append(item(it["type"], float(it.get("x", 0)), float(it.get("z", 0)), float(it.get("yaw", 0)), float(it.get("scale", 1))))
	data["items"] = items
	return data

## Every saved layout: [{name, path}], sorted by name (project maps, then user maps).
static func list_layouts() -> Array:
	var out := []
	for dir in [PROJECT_DIR, USER_DIR]:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for f in d.get_files():
			if f.get_extension() != "json":
				continue
			var l := load_layout(dir + f)
			if not l.is_empty():
				out.append({"name": l.get("name", f.get_basename()), "path": dir + f})
	out.sort_custom(func(a, b): return a["name"].naturalnocasecmp_to(b["name"]) < 0)
	return out

static func count(layout: Dictionary, type: String) -> int:
	return layout["items"].filter(func(i): return i["type"] == type).size()

## Problems that stop a layout from being played (empty = fine).
static func problems(layout: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if count(layout, "spawn") < 2:
		out.append("Needs at least 2 spawn points (4 for a full match).")
	return out

# --- World --------------------------------------------------------------------------------

## Current arena half-size for gameplay code (the shader global can't be read back at runtime).
static var arena_half := DEFAULT_ARENA * 0.5

## Sets the arena size the ground/border shaders use (global; restore with DEFAULT_ARENA when leaving).
static func set_arena(size: Vector2) -> void:
	arena_half = size * 0.5
	RenderingServer.global_shader_parameter_set("arena_half_size", size * 0.5)

## Environment, sun, arena camera, ground and vignette (the approved look). Returns {camera, ground_material}.
static func build_world(root: Node3D, size: Vector2) -> Dictionary:
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
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color("ffe6b0")
	sun.rotation_degrees = Vector3(-55.0, -70.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 40.0 + maxf(size.x - 20.0, 0.0)
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 1.5
	root.add_child(sun)

	var cam := ArenaCamera.new()
	cam.name = "ArenaCamera"
	cam.arena_size = size
	root.add_child(cam)
	cam.current = true

	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(160.0, 160.0)
	ground.mesh = plane
	var gm: ShaderMaterial = (load("res://assets/materials/ground.tres") as ShaderMaterial).duplicate()
	ground.material_override = gm
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ground)

	var vig_layer := CanvasLayer.new()
	vig_layer.name = "Vignette"
	vig_layer.layer = -1
	root.add_child(vig_layer)
	var vig := ColorRect.new()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vmat := ShaderMaterial.new()
	vmat.shader = load("res://assets/shaders/vignette.gdshader")
	vig.material = vmat
	vig_layer.add_child(vig)
	set_arena(size)
	return {"camera": cam, "ground_material": gm}

## Trampled dirt patches from the layout's "dirt" items.
static func apply_dirt(gm: ShaderMaterial, items: Array) -> void:
	var spots: Array[Vector3] = []
	for it in items:
		if it["type"] == "dirt" and spots.size() < 16:
			spots.append(Vector3(it["x"], it["z"], MapCatalog.pick_radius(it)))
	while spots.size() < 16:
		spots.append(Vector3.ZERO)
	gm.set_shader_parameter("dirt_spots", spots)
	gm.set_shader_parameter("dirt_count", items.filter(func(i): return i["type"] == "dirt").size())

static func _prop(parent: Node, model: String, pos: Vector3, yaw_deg: float, scale := 1.0, shadows := true) -> ToonProp:
	var p := ToonProp.new()
	p.model = load(MapCatalog.FOREST + model + "_Color1.gltf")
	p.cast_shadows = shadows
	p.position = pos
	p.rotation_degrees.y = yaw_deg
	p.scale = Vector3.ONE * scale
	parent.add_child(p)
	return p

## Decorative forest border around the arena (same recipe as the hand-built maps, sized to the arena).
static func build_border(parent: Node3D, size: Vector2, seed := 7) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var pick := func(options: Array) -> String: return options[rng.randi() % options.size()]
	var j := func(a: float) -> float: return rng.randf_range(-a, a)
	var x := -hx - 7.0
	while x < hx + 7.0:
		_prop(parent, pick.call(TALL), Vector3(x + j.call(0.6), 0, -hz - 1.6 + j.call(0.5)), rng.randf() * 360.0, rng.randf_range(0.9, 1.15))
		_prop(parent, pick.call(TALL), Vector3(x + 1.3 + j.call(0.6), 0, -hz - 4.2 + j.call(0.8)), rng.randf() * 360.0, rng.randf_range(1.0, 1.25))
		_prop(parent, pick.call(BUSHES), Vector3(x + 0.8 + j.call(0.7), 0, -hz - 0.4 + j.call(0.5)), rng.randf() * 360.0, rng.randf_range(0.8, 1.25))
		if rng.randf() < 0.5:
			_prop(parent, pick.call(LOW), Vector3(x + 2.0 + j.call(0.4), 0, -hz - 0.1 + j.call(0.3)), rng.randf() * 360.0, rng.randf_range(0.7, 1.0))
		x += rng.randf_range(2.0, 3.0)
	for side in [-1.0, 1.0]:
		var z := -hz + 0.5
		while z < hz + 3.0:
			_prop(parent, pick.call(BUSHES), Vector3(side * (hx + 0.6 + j.call(0.3)), 0, z + j.call(0.4)), rng.randf() * 360.0)
			if z < hz - 1.0:
				_prop(parent, pick.call(MID), Vector3(side * (hx + 2.6 + j.call(0.6)), 0, z + 0.9 + j.call(0.5)), rng.randf() * 360.0)
			_prop(parent, pick.call(TALL), Vector3(side * (hx + 5.0 + j.call(0.8)), 0, z + j.call(0.8)), rng.randf() * 360.0)
			z += 2.2
	x = -hx - 1.5
	while x < hx + 1.5:
		_prop(parent, pick.call(LOW), Vector3(x + j.call(0.6), 0, hz + 0.7 + j.call(0.5)), rng.randf() * 360.0, rng.randf_range(0.8, 1.2), false)
		if rng.randf() < 0.6:
			_prop(parent, pick.call(LOW), Vector3(x + 0.9 + j.call(0.4), 0, hz + 1.3 + j.call(0.4)), rng.randf() * 360.0, rng.randf_range(0.7, 1.1), false)
		_prop(parent, pick.call(BUSHES), Vector3(x + 1.0 + j.call(0.6), 0, hz + 2.4 + j.call(0.7)), rng.randf() * 360.0, rng.randf_range(0.9, 1.2), false)
		x += rng.randf_range(1.4, 2.2)

## Invisible arena walls (world + arrow-stickable), just inside the border bushes.
static func build_walls(parent: Node3D, size: Vector2) -> StaticBody3D:
	var walls := StaticBody3D.new()
	walls.name = "ArenaWalls"
	walls.collision_layer = L_WORLD | L_STICKABLE
	walls.collision_mask = 0
	parent.add_child(walls)
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var t := 1.0
	for d in [
		[Vector3(0, 1.5, -hz - 0.1 - t * 0.5), Vector3(size.x + 4, 3, t)],
		[Vector3(0, 1.5, hz + 0.2 + t * 0.5), Vector3(size.x + 4, 3, t)],
		[Vector3(-hx - 0.1 - t * 0.5, 1.5, 0), Vector3(t, 3, size.y + 4)],
		[Vector3(hx + 0.1 + t * 0.5, 1.5, 0), Vector3(t, 3, size.y + 4)],
	]:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = d[1]
		cs.shape = box
		cs.position = d[0]
		walls.add_child(cs)
	return walls

## Builds one layout item under `parent` and returns its node. Spawns are bare Marker3Ds (the editor adds
## its own marker visual); dirt patches are drawn by the ground shader (empty node).
static func place(parent: Node, it: Dictionary) -> Node3D:
	var info := MapCatalog.info(it["type"])
	var n: Node3D
	if info.has("scene"):
		n = load(info["scene"]).instantiate()
	elif info.has("model"):
		n = ToonProp.new()
		n.model = load(MapCatalog.FOREST + info["model"] + "_Color1.gltf")
	else:
		match info.get("kind", ""):
			"spawn":
				n = Marker3D.new()
			"pad":
				n = PowerUpPad.new()
			"nest":
				n = Nest.new()
			"flowers":
				n = FlowerPatch.new()
			"birdbath":
				n = Birdbath.new()
			_:
				n = Node3D.new()
	n.position = Vector3(it["x"], 0, it["z"])
	n.rotation_degrees.y = it["yaw"]
	if not info.get("fixed_scale", false) and info.get("kind", "") != "dirt":
		n.scale = Vector3.ONE * float(info.get("base", 1.0)) * float(it["scale"])
	parent.add_child(n)
	return n
