class_name SkyEgg
extends Node3D
## Overtime egg rain (RoundController): an egg drops out of the sky onto a spot, its shadow growing there while
## it falls (so you can see it coming and step away), and eggsplodes on landing: knocks out every bird in
## `eggsplosive_radius` (no killer: nobody gets the KO) and smashes eggs, like an Eggsplosive arrow.

const EGG_MODEL := preload("res://assets/env/egg.glb")
const START_HEIGHT := 14.0
const SHADOW_RADIUS := 0.4 ## m, the falling egg's shadow at landing

var _t: Tuning
var _time := 0.0
var _drop := 0.9
var _egg: EnvProp
var _shadow: MeshInstance3D
var _shadow_mat: StandardMaterial3D

## Drops an egg onto `spot` (y ignored).
static func drop(parent: Node, spot: Vector3) -> SkyEgg:
	var e := SkyEgg.new()
	parent.add_child(e)
	e.global_position = Vector3(spot.x, 0.0, spot.z)
	return e

func _ready() -> void:
	_t = Tuning.get_default()
	_drop = _t.overtime_egg_drop_time
	_egg = EnvProp.new()
	_egg.color_overrides = {"shell": Color("f2efe6")}
	add_child(_egg)
	_egg.model = EGG_MODEL
	_egg.scale = Vector3.ONE * 2.2
	_egg.position.y = START_HEIGHT
	_shadow = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.01
	disc.radial_segments = 24
	disc.rings = 1
	_shadow.mesh = disc
	_shadow_mat = StandardMaterial3D.new()
	_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_mat.albedo_color = Color(0.1, 0.06, 0.08, 0.0)
	_shadow.material_override = _shadow_mat
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.position.y = 0.03
	_shadow.scale = Vector3.ONE * 0.2
	add_child(_shadow)
	Sfx.play("shrike_drop") # falling whoosh

func _process(delta: float) -> void:
	_time += delta
	var k := clampf(_time / _drop, 0.0, 1.0)
	_egg.position.y = START_HEIGHT * (1.0 - k * k) # accelerating fall
	_egg.rotation.z = sin(_time * 9.0) * 0.25
	var r := SHADOW_RADIUS * lerpf(0.3, 1.0, k) # user: egg-sized, not the blast size
	_shadow.scale = Vector3(r, 1.0, r)
	_shadow_mat.albedo_color.a = lerpf(0.1, 0.5, k)
	if k >= 1.0:
		_explode()

func _explode() -> void:
	var point := global_position + Vector3.UP * 0.2
	var r := _t.eggsplosive_radius
	Sfx.play("explosion")
	Sfx.play("explosion_crack")
	Fx.explosion(point, r)
	Fx.egg_splat(point, 1.4)
	Fx.shake(0.4)
	for b in get_tree().get_nodes_in_group("birds"):
		if not b.is_alive() or b.is_invulnerable():
			continue
		var to: Vector3 = b.global_position - point
		to.y = 0.0
		if to.length() < r:
			b.knock_out(null, to.normalized() if to.length() > 0.05 else Vector3.FORWARD)
	for e in get_tree().get_nodes_in_group("eggs"):
		if e.global_position.distance_to(point) < r:
			e.smash()
	queue_free()
