@tool
class_name ToonProp
extends Node3D
## Instances a third-party model and swaps its materials for the project's toon material
## (with outline), without touching the source files in assets/third_party/.

const DEFAULT_MATERIAL := preload("res://assets/materials/kaykit_forest_toon.tres")

@export var model: PackedScene:
	set(value):
		model = value
		_rebuild()
@export var material: Material = DEFAULT_MATERIAL:
	set(value):
		material = value
		_rebuild()
@export var cast_shadows := true:
	set(value):
		cast_shadows = value
		_rebuild()

var _instance: Node3D
var _meshes: Array[MeshInstance3D] = []

## 0..1 screen-door fade of everything above the canopy height (trees only).
func set_canopy_fade(amount: float) -> void:
	for mi in _meshes:
		mi.set_instance_shader_parameter("canopy_fade", amount)

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
	# Internal child: not saved with the scene, rebuilt on load.
	add_child(_instance, false, INTERNAL_MODE_FRONT)
	var meshes := _instance.find_children("*", "MeshInstance3D", true, false)
	if _instance is MeshInstance3D:
		meshes.append(_instance)
	_meshes.clear()
	for mi: MeshInstance3D in meshes:
		_meshes.append(mi)
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
