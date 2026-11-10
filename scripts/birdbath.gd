class_name Birdbath
extends StaticBody3D
## Overflowing stone birdbath (Birdbath map; also placeable in the level editor). Solid cover: arrows stick
## in the stone column; a wide low "bird blocker" (layer 8) keeps birds from walking under the bowl without
## catching arrows. Water spills over the rim all the way around and pools in a ring-shaped puddle centered on
## the bath that spreads slowly each round (Tuning: puddle_*). Wading (puddle) slows birds (water_speed, water_dash).
## Resets with the round (group "round_reset").

const MODEL := preload("res://assets/env/birdbath.glb")
const WATER := preload("res://assets/shaders/water.gdshader")
const RIM_Y := 1.11
const RIM_R := 0.82
const STREAM_COUNT := 7 # evenly around the rim

var puddle_radius := 0.8
var _t: Tuning
var _puddle_mat: ShaderMaterial

func _ready() -> void:
	_t = Tuning.get_default()
	add_to_group("water")
	add_to_group("round_reset")
	collision_layer = 1 | 32
	collision_mask = 0
	set_meta("sfx_surface", "stone")
	var prop := EnvProp.new()
	prop.model = MODEL
	add_child(prop)
	_shape(self, 0.24, 1.15) # stone column + bowl underside: arrows stick here
	var blocker := StaticBody3D.new()
	blocker.name = "BirdBlocker"
	blocker.collision_layer = 128 # bird_blockers: birds only
	blocker.collision_mask = 0
	add_child(blocker)
	_shape(blocker, 0.72, 1.2)
	_build_water()
	reset()

func _shape(body: Node3D, r: float, h: float) -> void:
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = r
	cyl.height = h
	cs.shape = cyl
	cs.position.y = h * 0.5
	body.add_child(cs)

func _mat(mode: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WATER
	m.set_shader_parameter("mode", mode)
	return m

func _build_water() -> void:
	var basin := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = RIM_R + 0.03
	disc.bottom_radius = RIM_R + 0.03
	disc.height = 0.01
	disc.radial_segments = 24
	disc.rings = 1
	basin.mesh = disc
	basin.position.y = RIM_Y
	var bm := _mat(2)
	bm.set_shader_parameter("radius", RIM_R)
	basin.material_override = bm
	basin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(basin)
	for k in STREAM_COUNT:
		var a := TAU * k / STREAM_COUNT + 0.2
		var s := MeshInstance3D.new()
		s.mesh = _stream_mesh(a)
		s.material_override = _mat(1)
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s)
		var drops := CPUParticles3D.new()
		drops.amount = 10
		drops.lifetime = 0.45
		drops.direction = Vector3(0, 1, 0)
		drops.spread = 50.0
		drops.initial_velocity_min = 0.8
		drops.initial_velocity_max = 1.6
		drops.gravity = Vector3(0, -6, 0)
		drops.scale_amount_min = 0.5
		drops.scale_amount_max = 1.0
		var q := SphereMesh.new()
		q.radius = 0.035
		q.height = 0.07
		q.radial_segments = 6
		q.rings = 3
		var dm := StandardMaterial3D.new()
		dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dm.albedo_color = Color("eaf8ff")
		q.material = dm
		drops.mesh = q
		drops.position = Vector3(cos(a), 0, -sin(a)) * 1.22 + Vector3.UP * 0.04
		add_child(drops)
	var puddle := MeshInstance3D.new()
	puddle.name = "Puddle"
	var plane := PlaneMesh.new()
	var reach := _t.puddle_max_radius * 1.35
	plane.size = Vector2(reach * 2.0, reach * 2.0)
	puddle.mesh = plane
	puddle.position.y = 0.012
	_puddle_mat = _mat(0)
	puddle.material_override = _puddle_mat
	puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(puddle)

## A ribbon of water pouring over the rim at angle `a` (around +X), curving out and down to the ground.
func _stream_mesh(a: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var out := Vector3(cos(a), 0, -sin(a))
	var side := out.cross(Vector3.UP)
	var n := 10
	for i in n + 1:
		var s := float(i) / n
		var p := out * (0.9 + 0.32 * sin(s * PI * 0.5)) + Vector3.UP * (RIM_Y + 0.02) * (1.0 - s * s)
		var w := lerpf(0.09, 0.15, s)
		st.set_uv(Vector2(0.0, s))
		st.add_vertex(p - side * w)
		st.set_uv(Vector2(1.0, s))
		st.add_vertex(p + side * w)
	return st.commit()

## The puddle is centered on the bath (local) and spreads outward evenly.
func _puddle_center() -> Vector2:
	return Vector2.ZERO

func reset() -> void:
	puddle_radius = _t.puddle_start_radius
	_update_puddle()

func _process(delta: float) -> void:
	if puddle_radius < _t.puddle_max_radius:
		puddle_radius = minf(puddle_radius + _t.puddle_growth * delta, _t.puddle_max_radius)
		_update_puddle()

func _update_puddle() -> void:
	if _puddle_mat:
		_puddle_mat.set_shader_parameter("center", _puddle_center())
		_puddle_mat.set_shader_parameter("radius", puddle_radius)

## Is this world point in the water? (the puddle, a bit inside its wobbly edge)
func in_water(world_pos: Vector3) -> bool:
	var l := to_local(world_pos)
	var c := _puddle_center()
	return Vector2(l.x - c.x, l.z - c.y).length() < puddle_radius * 0.9
