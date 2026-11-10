class_name PowerUpPad
extends Node3D
## A fixed power-up spawn pad (open question 3: fixed pads). A stone disc with a glowing ring; when it holds
## a power-up, the icon (big, user: they drew no focus) floats, bobs, drifts in a small circle and pulses over a
## glowing halo, with a faint light column in the power-up's color. Walk over it to pick it up.

const RING_IDLE := Color(1, 1, 1, 0.25)

var item := ""
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _icon: Sprite3D
var _time := 0.0
var _area: Area3D
var _halo: Sprite3D
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
const ICON_SIZE := 0.9 ## m (was 0.65, then 1.15: too big)
const FLOAT_HEIGHT := 1.2 ## m

func _ready() -> void:
	add_to_group("power_up_pads")
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.55
	cyl.bottom_radius = 0.6
	cyl.height = 0.08
	cyl.radial_segments = 16
	cyl.rings = 1
	disc.mesh = cyl
	disc.position.y = 0.04
	disc.material_override = ToonMaterials.toon(Color("a8a29a"), 0.1)
	add_child(disc)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.38
	torus.outer_radius = 0.46
	torus.rings = 24
	torus.ring_segments = 6
	_ring.mesh = torus
	_ring.scale = Vector3(1, 0.25, 1)
	_ring.position.y = 0.09
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.albedo_color = RING_IDLE
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_halo = Sprite3D.new()
	_halo.texture = _halo_texture()
	_halo.pixel_size = ICON_SIZE * 1.7 / 64.0
	_halo.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_halo.shaded = false
	_halo.transparent = true
	_halo.render_priority = 4
	_halo.visible = false
	add_child(_halo)
	_beam = MeshInstance3D.new()
	var beam := CylinderMesh.new()
	beam.top_radius = 0.28
	beam.bottom_radius = 0.42
	beam.height = 2.4
	beam.radial_segments = 16
	beam.rings = 1
	beam.cap_top = false
	beam.cap_bottom = false
	_beam.mesh = beam
	_beam.position.y = 1.2
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)
	_icon = Sprite3D.new()
	_icon.pixel_size = ICON_SIZE / 128.0
	_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_icon.shaded = false
	_icon.render_priority = 5
	_icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_icon.visible = false
	add_child(_icon)
	_area = Area3D.new()
	_area.collision_layer = 16 # pickups
	_area.collision_mask = 2   # birds
	var shape := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = 0.75
	c.height = 2.0
	shape.shape = c
	shape.position.y = 1.0
	_area.add_child(shape)
	add_child(_area)

func spawn(type: String) -> void:
	item = type
	Sfx.play("powerup_spawn")
	var def: Dictionary = PowerUps.TYPES[type]
	_icon.texture = def["icon"]
	_icon.visible = true
	_halo.visible = true
	_halo.modulate = Color(def["color"], 0.8)
	_beam.visible = true
	_beam_mat.albedo_color = Color(def["color"], 0.18)
	_icon.scale = Vector3.ONE * 0.01
	_spawn_until = _time + 0.3
	var tw := create_tween()
	tw.tween_property(_icon, "scale", Vector3.ONE * 1.25, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_icon, "scale", Vector3.ONE, 0.12)
	_ring_mat.albedo_color = Color(def["color"], 0.9)
	Fx.pickup_burst(global_position + Vector3.UP * FLOAT_HEIGHT, def["color"], false)

var _spawn_until := 0.0

func _spawning() -> bool:
	return _time < _spawn_until

static var _halo_tex: Texture2D

## Soft round glow (white, tinted by modulate).
static func _halo_texture() -> Texture2D:
	if _halo_tex:
		return _halo_tex
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a * 0.9))
	_halo_tex = ImageTexture.create_from_image(img)
	return _halo_tex

func clear() -> void:
	item = ""
	_icon.visible = false
	_halo.visible = false
	_beam.visible = false
	_ring_mat.albedo_color = RING_IDLE

func _process(delta: float) -> void:
	_time += delta
	if item == "":
		return
	var drift := Vector3(cos(_time * 1.3), 0.0, sin(_time * 1.3)) * 0.12
	_icon.position = drift + Vector3.UP * (FLOAT_HEIGHT + sin(_time * 2.4) * 0.16)
	_halo.position = _icon.position + Vector3(0, 0, -0.05)
	var pulse := 1.0 + 0.07 * sin(_time * 4.0)
	if not _spawning():
		_icon.scale = Vector3.ONE * pulse
	_halo.scale = Vector3.ONE * (1.0 + 0.12 * sin(_time * 4.0 + 1.0))
	_beam_mat.albedo_color.a = 0.14 + 0.06 * sin(_time * 3.0)
	_ring.rotation.y += delta * 1.5
	_ring_mat.albedo_color.a = 0.65 + 0.3 * sin(_time * 5.0)
	for b in _area.get_overlapping_bodies():
		if b is Bird and b.is_alive():
			b.add_power_up(item)
			Fx.pickup_burst(global_position + Vector3.UP * FLOAT_HEIGHT, PowerUps.TYPES[item]["color"], true)
			clear()
			return
