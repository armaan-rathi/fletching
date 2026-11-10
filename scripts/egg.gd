class_name Egg
extends StaticBody3D
## A breakable egg (collision layer 7, "breakables"). Arrows pierce it, explosions and wing slaps smash it.
## Pure flavor for now (open question 4): a splat + pop, nearby birds look shocked. Restored each round.

const EGG := preload("res://assets/env/egg.glb")
const SHELLS := [Color("bfe3ef"), Color("f2efe6"), Color("e9dcc2")]

var broken := false
var _prop: EnvProp
var _splat: MeshInstance3D

func _ready() -> void:
	add_to_group("eggs")
	collision_layer = 64
	collision_mask = 0
	# Generous hit volume up to arrow height (arrows fly at ~0.55 m; the egg itself is ~0.25 m tall).
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.14
	cyl.height = 0.75
	shape.shape = cyl
	shape.position.y = 0.375
	add_child(shape)
	_prop = EnvProp.new()
	_prop.color_overrides = {"shell": SHELLS[randi() % SHELLS.size()]}
	add_child(_prop)
	_prop.model = EGG
	rotation.z = randf_range(-0.25, 0.25)

func on_arrow_hit(_arrow: Node) -> void:
	smash()

func smash() -> void:
	if broken:
		return
	broken = true
	Sfx.play("egg")
	_prop.visible = false
	collision_layer = 0
	var p := global_position + Vector3.UP * 0.12
	Fx.egg_splat(p)
	_splat = Fx.yolk_decal(Vector3(global_position.x, 0.015, global_position.z))
	for b in get_tree().get_nodes_in_group("birds"):
		if b.is_alive() and b.global_position.distance_to(global_position) < 1.6:
			b.model.expressions.request("shocked", 0.6)

func restore() -> void:
	broken = false
	_prop.visible = true
	collision_layer = 64
	if _splat and is_instance_valid(_splat):
		_splat.queue_free()
	_splat = null
