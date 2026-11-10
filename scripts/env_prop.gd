@tool
class_name EnvProp
extends Node3D
## Instances a project-made prop GLB (assets/env/) and gives it toon materials by material name.

const COLORS := {
	"bark": Color("6b4a33"),
	"wood": Color("e0c08a"),
	"twig": Color("8a6a44"),
	"nest_in": Color("5a4030"),
	"shell": Color("f2efe6"),
	"stone": Color("d8cfbd"),
	"stone_dark": Color("aea38f"),
	"basin": Color("9a907e"),
}

@export var model: PackedScene:
	set(v):
		model = v
		_rebuild()
## Overrides per material name (e.g. {"shell": Color("bfe3ef")}).
@export var color_overrides: Dictionary = {}:
	set(v):
		color_overrides = v
		_rebuild()
@export var outline := true

var _instance: Node3D

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _instance:
		_instance.queue_free()
		_instance = null
	if model == null:
		return
	_instance = model.instantiate()
	add_child(_instance, false, INTERNAL_MODE_FRONT)
	for mi: MeshInstance3D in _instance.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var n: String = src.resource_name if src else "bark"
			var c: Color = color_overrides.get(n, COLORS.get(n, Color.MAGENTA))
			mi.set_surface_override_material(i, ToonMaterials.toon(c, 0.15, outline))
