extends "res://tools/build_look_test.gd"
## Generates the Stage 1 gameplay scenes: arrow, bow, bird, central tree wrapper and the test map.
## Run: Godot --headless --path . -s tools/build_stage1.gd
## Scenes are generated so they stay consistent; tweak values in data/tuning.tres or re-run after edits here.

const L_WORLD := 1
const L_BIRDS := 2
const L_HITBOX := 4
const L_PICKUPS := 16
const L_STICKABLE := 32

func run() -> void:
	_build_arrow()
	_build_bow()
	_build_bird()
	_build_tree()
	_build_test_map()

func _new_root(node: Node, root_name: String) -> void:
	scene_root = node
	scene_root.name = root_name

func _instance(path: String, parent: Node, node_name: String) -> Node3D:
	var inst: Node3D = load(path).instantiate()
	inst.name = node_name
	own(inst, parent)
	return inst

func _build_arrow() -> void:
	_new_root(Node3D.new(), "Arrow")
	scene_root.set_script(load("res://scripts/arrow.gd"))
	var wobble := Node3D.new()
	wobble.name = "Wobble"
	own(wobble, scene_root)
	var model := _instance("res://assets/weapons/arrow.glb", wobble, "Model")
	model.rotation.y = PI
	var trail := MeshInstance3D.new()
	trail.name = "Trail"
	trail.set_script(load("res://scripts/arrow_trail.gd"))
	own(trail, scene_root)
	var area := Area3D.new()
	area.name = "PickupArea"
	area.collision_layer = L_PICKUPS
	area.collision_mask = L_BIRDS
	area.monitorable = false
	own(area, scene_root)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.6
	cyl.height = 2.0
	shape.shape = cyl
	own(shape, area)
	save_scene("res://scenes/weapons/arrow.tscn")

func _build_bow() -> void:
	_new_root(Node3D.new(), "Bow")
	scene_root.set_script(load("res://scripts/bow.gd"))
	var model := _instance("res://assets/weapons/bow.glb", scene_root, "Model")
	model.rotation.y = PI
	for n in ["StringL", "StringR"]:
		var s := MeshInstance3D.new()
		s.name = n
		own(s, scene_root)
	var nocked := Node3D.new()
	nocked.name = "NockedArrow"
	own(nocked, scene_root)
	var arrow_model := _instance("res://assets/weapons/arrow.glb", nocked, "Model")
	arrow_model.rotation.y = PI
	save_scene("res://scenes/weapons/bow.tscn")

func _capsule() -> CapsuleShape3D:
	var c := CapsuleShape3D.new()
	c.radius = 0.4
	c.height = 1.0
	return c

func _build_bird() -> void:
	_new_root(CharacterBody3D.new(), "Bird")
	scene_root.set_script(load("res://scripts/bird.gd"))
	scene_root.collision_layer = L_BIRDS
	scene_root.collision_mask = L_WORLD | L_BIRDS
	scene_root.add_to_group("birds", true)

	var col := CollisionShape3D.new()
	col.name = "Collision"
	col.shape = _capsule()
	col.position.y = 0.5
	own(col, scene_root)

	var hitbox := Area3D.new()
	hitbox.name = "Hitbox"
	hitbox.collision_layer = L_HITBOX
	hitbox.collision_mask = 0
	hitbox.monitoring = false
	own(hitbox, scene_root)
	var hs := CollisionShape3D.new()
	hs.name = "Shape"
	hs.shape = _capsule()
	hs.position.y = 0.5
	own(hs, hitbox)

	var ring := MeshInstance3D.new()
	ring.name = "PlayerRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5; torus.outer_radius = 0.62; torus.rings = 24; torus.ring_segments = 6
	ring.mesh = torus
	ring.scale = Vector3(1, 0.12, 1)
	ring.position.y = 0.02
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	own(ring, scene_root)

	# Ground shadow: an invisible shadow-only disc just above the ground, so it gets the same crisp,
	# cool cast-shadow shading as everything else and stays on the ground during hops.
	var blob := MeshInstance3D.new()
	blob.name = "BlobShadow"
	var disc := CylinderMesh.new()
	disc.top_radius = 0.4
	disc.bottom_radius = 0.4
	disc.height = 0.02
	disc.radial_segments = 20
	disc.rings = 1
	blob.mesh = disc
	blob.position.y = 0.1
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	own(blob, scene_root)

	var charge := MeshInstance3D.new()
	charge.name = "ChargeRing"
	var cplane := PlaneMesh.new()
	cplane.size = Vector2(1.75, 1.75)
	charge.mesh = cplane
	charge.position.y = 0.025
	var cmat := ShaderMaterial.new()
	cmat.shader = load("res://assets/shaders/charge_ring.gdshader")
	charge.material_override = cmat
	charge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	charge.visible = false
	own(charge, scene_root)

	var pivot := Node3D.new()
	pivot.name = "AimPivot"
	own(pivot, scene_root)
	var line := MeshInstance3D.new()
	line.name = "AimLine"
	var lplane := PlaneMesh.new()
	lplane.size = Vector2(0.32, 1.0)
	line.mesh = lplane
	var lmat := ShaderMaterial.new()
	lmat.shader = load("res://assets/shaders/aim_line.gdshader")
	line.material_override = lmat
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	line.visible = false
	own(line, pivot)

	var visual := Node3D.new()
	visual.name = "VisualRoot"
	visual.set_script(load("res://scripts/bird_visual.gd"))
	own(visual, scene_root)
	var squash := Node3D.new()
	squash.name = "Squash"
	own(squash, visual)
	var model := Node3D.new()
	model.name = "Model"
	model.set_script(load("res://scripts/bird_model.gd"))
	own(model, squash)
	var glb := _instance("res://assets/birds/bird_base.glb", model, "BirdBase")
	glb.rotation.y = PI
	var quiver := Node3D.new()
	quiver.name = "Quiver"
	own(quiver, squash)
	_instance("res://scenes/weapons/bow.tscn", visual, "Bow")
	save_scene("res://scenes/birds/bird.tscn")

func _build_tree() -> void:
	_new_root(StaticBody3D.new(), "TreeCentral")
	scene_root.collision_layer = L_WORLD | L_STICKABLE
	scene_root.collision_mask = 0
	var p := Node3D.new()
	p.set_script(load("res://scripts/toon_prop.gd"))
	p.name = "Model"
	p.set("model", load(FOREST + "Tree_4_A_Color1.gltf"))
	own(p, scene_root)
	var trunk := CollisionShape3D.new()
	trunk.name = "Trunk"
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.22 # Tree_4_A: slim trunk, canopy starts ~1 m up
	cyl.height = 3.0
	trunk.shape = cyl
	trunk.position = Vector3(0.0, 1.5, 0.0)
	own(trunk, scene_root)
	var fader := Node.new()
	fader.name = "CanopyFader"
	fader.set_script(load("res://scripts/canopy_fader.gd"))
	own(fader, scene_root)
	fader.set("target", p)
	fader.set("canopy_center_height", 2.7)
	fader.set("canopy_radius", 1.5)
	save_scene("res://scenes/props/tree_central.tscn")

func _build_test_map() -> void:
	build_base("TestMap", false)
	build_walls()

	var tree: Node3D = load("res://scenes/props/tree_central.tscn").instantiate()
	tree.name = "TreeCentral"
	tree.position = Vector3(0.0, 0.0, -0.5)
	tree.rotation_degrees.y = 20.0
	own(tree, scene_root)

	var deco := Node3D.new()
	deco.name = "Decor"
	own(deco, scene_root)
	prop(deco, "Grass_2_C", Vector3(2.0, 0.0, 1.5), 0.0)
	prop(deco, "Grass_1_B", Vector3(-2.5, 0.0, -2.0), 0.0)
	prop(deco, "Grass_1_C", Vector3(7.5, 0.0, 1.0), 0.0)
	prop(deco, "Grass_1_A", Vector3(-7.0, 0.0, 4.5), 0.0)

	build_match_nodes()
	save_scene("res://scenes/maps/test_map.tscn")

## Invisible arena walls (world + arrow-stickable), inner faces just inside the decorative border bushes.
func build_walls() -> void:
	var walls := StaticBody3D.new()
	walls.name = "ArenaWalls"
	walls.collision_layer = L_WORLD | L_STICKABLE
	walls.collision_mask = 0
	own(walls, scene_root)
	var hx := ARENA.x * 0.5
	var hz := ARENA.y * 0.5
	var t := 1.0
	var defs := [
		["Back", Vector3(0, 1.5, -hz - 0.1 - t * 0.5), Vector3(ARENA.x + 4, 3, t)],
		["Front", Vector3(0, 1.5, hz + 0.2 + t * 0.5), Vector3(ARENA.x + 4, 3, t)],
		["Left", Vector3(-hx - 0.1 - t * 0.5, 1.5, 0), Vector3(t, 3, ARENA.y + 4)],
		["Right", Vector3(hx + 0.1 + t * 0.5, 1.5, 0), Vector3(t, 3, ARENA.y + 4)],
	]
	for d in defs:
		var cs := CollisionShape3D.new()
		cs.name = d[0]
		var box := BoxShape3D.new()
		box.size = d[2]
		cs.shape = box
		cs.position = d[1]
		own(cs, walls)

## Corner spawn points, the round controller, match HUD and debug HUD.
func build_match_nodes() -> void:
	# Birds are spawned by the RoundController from MatchManager.players at these points (near the corners).
	var spawns := Node3D.new()
	spawns.name = "Spawns"
	own(spawns, scene_root)
	for i in 4:
		var m := Marker3D.new()
		m.name = "Spawn%d" % (i + 1)
		m.position = Vector3((-1 if i % 2 == 0 else 1) * 7.0, 0, (-1 if i < 2 else 1) * 4.3)
		own(m, spawns)

	var rounds := Node.new()
	rounds.name = "RoundController"
	rounds.set_script(load("res://scripts/round_controller.gd"))
	own(rounds, scene_root)

	var match_hud := CanvasLayer.new()
	match_hud.name = "MatchHud"
	match_hud.set_script(load("res://scripts/match_hud.gd"))
	own(match_hud, scene_root)

	var hud := CanvasLayer.new()
	hud.name = "DebugHud"
	hud.set_script(load("res://scripts/debug_hud.gd"))
	own(hud, scene_root)
