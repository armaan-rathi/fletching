class_name ArrowTrail
extends MeshInstance3D
## Flat, player-colored ribbon behind a flying arrow (lies in the horizontal plane so it reads
## from the top-down camera). Fades out after the arrow stops.

const SHADER := preload("res://assets/shaders/trail.gdshader")

@export var lifetime := 0.22
@export var width := 0.16
@export var follow_offset := 0.75 ## m behind the tip, so the ribbon starts at the fletching

var color := Color.WHITE
var _points: Array = [] # [position, time]
var _time := 0.0
var _active := true
var _imesh := ImmediateMesh.new()

func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _imesh
	var m := ShaderMaterial.new()
	m.shader = SHADER
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func stop() -> void:
	_active = false

## Clear the ribbon and start again (a shrike reappearing high above its landing spot).
func restart() -> void:
	_points.clear()
	_active = true

func _process(delta: float) -> void:
	_time += delta
	var parent := get_parent() as Node3D
	if _active and parent:
		var p := parent.global_position + parent.global_basis.z * follow_offset
		_points.push_front([p, _time])
	while _points.size() > 0 and _time - _points.back()[1] > lifetime:
		_points.pop_back()
	_rebuild()

func _rebuild() -> void:
	_imesh.clear_surfaces()
	if _points.size() < 2:
		return
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in _points.size():
		var p: Vector3 = _points[i][0]
		var other: Vector3 = _points[mini(i + 1, _points.size() - 1)][0] if i < _points.size() - 1 else _points[i - 1][0]
		var d := (p - other) if i < _points.size() - 1 else (other - p) * -1.0
		d.y = 0.0
		var side := Vector3(-d.z, 0, d.x).normalized() if d.length() > 0.0001 else Vector3.RIGHT
		var age := clampf((_time - _points[i][1]) / lifetime, 0.0, 1.0)
		var w := width * (1.0 - age)
		var c := Color(color, (1.0 - age) * 0.75)
		_imesh.surface_set_color(c)
		_imesh.surface_add_vertex(p + side * w)
		_imesh.surface_set_color(c)
		_imesh.surface_add_vertex(p - side * w)
	_imesh.surface_end()
