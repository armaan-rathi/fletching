extends "res://tools/build_stage1.gd"
## Builds the "Aviary" map (design doc: compact woodland clearing ~20x14 m, bordered by dense bushes, rocks,
## stumps and trunks; a central tree as main cover plus a few low bushes, rocks and logs; 4 corner spawns;
## 2-4 nests with breakable eggs away from corners/spawns) and its prop wrapper scenes.
## Solid props (logs, stumps, rocks) block birds and catch arrows; low bushes are soft decoration.
## Run: Godot --headless --path . -s tools/build_aviary.gd

const ENV := "res://assets/env/"

func run() -> void:
	_build_solid("log", "env", ENV + "log.glb", _box(Vector3(2.2, 0.66, 0.66)), Vector3(0, 0.32, 0))
	_build_solid("stump", "env", ENV + "stump.glb", _cyl(0.5, 0.6), Vector3(0, 0.3, 0))
	_build_solid("rock_big", "kaykit", FOREST + "Rock_2_C_Color1.gltf", _cyl(0.6, 1.4), Vector3(0, 0.7, 0))
	_build_solid("rock_mid", "kaykit", FOREST + "Rock_1_D_Color1.gltf", _cyl(0.5, 1.1), Vector3(0, 0.55, 0))
	_build_aviary()

func _box(size: Vector3) -> Shape3D:
	var b := BoxShape3D.new()
	b.size = size
	return b

func _cyl(r: float, h: float) -> Shape3D:
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = h
	return c

func _build_solid(name: String, kind: String, model_path: String, shape: Shape3D, shape_pos: Vector3) -> void:
	_new_root(StaticBody3D.new(), name.to_pascal_case())
	scene_root.collision_layer = L_WORLD | L_STICKABLE
	scene_root.collision_mask = 0
	var vis := Node3D.new()
	vis.name = "Model"
	vis.set_script(load("res://scripts/env_prop.gd" if kind == "env" else "res://scripts/toon_prop.gd"))
	vis.set("model", load(model_path))
	own(vis, scene_root)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = shape
	cs.position = shape_pos
	own(cs, scene_root)
	save_scene("res://scenes/props/%s.tscn" % name)

func _place(scene: String, parent: Node, pos: Vector3, yaw: float, scale := 1.0) -> Node3D:
	var n: Node3D = load(scene).instantiate()
	n.position = pos
	n.rotation_degrees.y = yaw
	n.scale = Vector3.ONE * scale
	own(n, parent)
	return n

func _build_aviary() -> void:
	build_base("Aviary", false)
	# Trampled dirt under the big tree (project terrain).
	var ground := scene_root.get_node("Ground") as MeshInstance3D
	var gm: ShaderMaterial = (load("res://assets/materials/ground.tres") as ShaderMaterial).duplicate()
	gm.set_shader_parameter("dirt_spot", Vector3(0.0, -0.5, 2.1))
	ResourceSaver.save(gm, "res://assets/materials/ground_aviary.tres")
	ground.material_override = load("res://assets/materials/ground_aviary.tres")
	build_walls()

	var tree := _place("res://scenes/props/tree_central.tscn", scene_root, Vector3(0.0, 0.0, -0.5), 20.0, 1.15)
	tree.name = "TreeCentral"

	var cover := Node3D.new()
	cover.name = "Cover"
	own(cover, scene_root)
	_place("res://scenes/props/rock_big.tscn", cover, Vector3(-4.6, 0, -2.6), 30.0)
	_place("res://scenes/props/rock_mid.tscn", cover, Vector3(4.3, 0, 2.8), -40.0)
	_place("res://scenes/props/log.tscn", cover, Vector3(-3.2, 0, 2.4), 65.0)
	_place("res://scenes/props/log.tscn", cover, Vector3(3.4, 0, -3.6), -15.0)
	_place("res://scenes/props/stump.tscn", cover, Vector3(7.3, 0, 0.2), 0.0)
	_place("res://scenes/props/stump.tscn", cover, Vector3(-7.5, 0, 0.6), 90.0, 0.9)

	var soft := Node3D.new()
	soft.name = "LowBushes"
	own(soft, scene_root)
	prop(soft, "Bush_3_A", Vector3(-1.6, 0, -3.7), 10.0)
	prop(soft, "Bush_4_B", Vector3(2.2, 0, 1.1), 50.0, 0.8)
	prop(soft, "Bush_1_B", Vector3(-5.6, 0, 3.4), 0.0)
	prop(soft, "Bush_3_A", Vector3(8.0, 0, 3.1), 70.0, 0.9)
	prop(soft, "Grass_2_C", Vector3(1.4, 0, -2.0), 0.0)
	prop(soft, "Grass_1_B", Vector3(-2.2, 0, -0.6), 0.0)
	prop(soft, "Grass_1_C", Vector3(5.2, 0, 4.9), 0.0)
	prop(soft, "Grass_1_A", Vector3(-7.6, 0, -2.6), 0.0)
	prop(soft, "Grass_2_B", Vector3(6.4, 0, -5.4), 0.0)

	var nests := Node3D.new()
	nests.name = "Nests"
	own(nests, scene_root)
	for pos in [Vector3(-2.4, 0, -5.0), Vector3(5.6, 0, -1.6), Vector3(-1.2, 0, 5.3)]:
		var n := Node3D.new()
		n.set_script(load("res://scripts/nest.gd"))
		n.name = "Nest%d" % (nests.get_child_count() + 1)
		n.position = pos
		own(n, nests)

	var pads := Node3D.new()
	pads.name = "PowerUpPads"
	own(pads, scene_root)
	for pos in [Vector3(0.0, 0, 3.4), Vector3(-6.0, 0, -2.0), Vector3(6.0, 0, -3.8)]:
		var p := Node3D.new()
		p.set_script(load("res://scripts/power_up_pad.gd"))
		p.name = "Pad%d" % (pads.get_child_count() + 1)
		p.position = pos
		own(p, pads)

	build_match_nodes()
	var spawner := Node.new()
	spawner.name = "PowerUpSpawner"
	spawner.set_script(load("res://scripts/power_up_spawner.gd"))
	own(spawner, scene_root)
	save_scene("res://scenes/maps/aviary.tscn")
