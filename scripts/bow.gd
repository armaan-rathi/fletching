class_name Bow
extends Node3D
## The bird's bow: held at the side when idle, brought flat in front while drawing.
## Draws its own string (pulled back with charge) and a nocked arrow.

const STRING_COLOR := Color("efe6d2")
const TIP_L := Vector3(-0.38, 0.0, 0.12)   # bow-local tips (after the model's 180° turn)
const TIP_R := Vector3(0.38, 0.0, 0.12)
const NOCK_REST := Vector3(0.0, 0.0, 0.12)
const MAX_PULL := 0.24
const ARROW_LENGTH := 0.87

# Idle: held in the right wing-hand (follows the hand_R bone through animations), upright-ish,
# arc facing forward. GRIP is where the hand holds the bow, in bow-local space.
const IDLE_ROT := Vector3(deg_to_rad(-10.0), deg_to_rad(-20.0), deg_to_rad(72.0))
const GRIP := Vector3(0.0, 0.0, -0.13)
const IDLE_FALLBACK := Vector3(0.45, 0.35, -0.05)
const DRAW_POS := Vector3(0.0, 0.52, -0.42)
const DRAW_ROT := Vector3.ZERO

@onready var string_l: MeshInstance3D = $StringL
@onready var string_r: MeshInstance3D = $StringR
@onready var nocked: Node3D = $NockedArrow

var drawn := 0.0  # 0 idle (in hand) .. 1 held flat in front (centered, for aiming)
## The bird's hand_R bone attachment (set by Bird); the idle bow follows it.
var hand: Node3D
var charge := 0.0 # 0..1 pull
var has_arrow := true
## 0..1: pitch the drawn bow up to the sky (shrike draw).
var aim_up := 0.0

func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = STRING_COLOR
	for s in [string_l, string_r]:
		var box := BoxMesh.new()
		box.size = Vector3(0.018, 0.018, 1.0)
		s.mesh = box
		s.material_override = mat
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_stencil_slot(0)

var _slot := 0
var _arrow_color := Color.WHITE

## The bow is part of its bird: it uses the bird's stencil slot so the bird's x-ray never tints through it.
func set_stencil_slot(slot: int) -> void:
	_slot = slot
	var bow_mats := {"wood": ToonMaterials.character(Color("9a6136"), true, Color.WHITE, 0.15, slot),
		"grip": ToonMaterials.character(Color("4a3428"), true, Color.WHITE, 0.1, slot),
		"tips": ToonMaterials.character(Color("efe0b8"), true, Color.WHITE, 0.15, slot)}
	for mi: MeshInstance3D in $Model.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, bow_mats.get(mi.mesh.surface_get_material(i).resource_name, bow_mats["wood"]))
	Arrow.apply_materials(nocked, _arrow_color, slot)

func set_arrow_color(color: Color) -> void:
	_arrow_color = color
	Arrow.apply_materials(nocked, color, _slot)

func _process(delta: float) -> void:
	var k := 1.0 - exp(-20.0 * delta)
	var idle_basis := Basis.from_euler(IDLE_ROT)
	var idle_pos := IDLE_FALLBACK
	if hand and is_instance_valid(hand) and get_parent() is Node3D:
		idle_pos = (get_parent() as Node3D).to_local(hand.global_position) - idle_basis * GRIP
	var draw_pos := DRAW_POS + Vector3(0, 0.22, 0.3) * aim_up
	var draw_basis := Basis.from_euler(DRAW_ROT + Vector3(deg_to_rad(72.0) * aim_up, 0, 0))
	position = position.lerp(idle_pos.lerp(draw_pos, drawn), k)
	var target := idle_basis.slerp(draw_basis, drawn)
	basis = basis.slerp(target, k).orthonormalized()

	var nock := NOCK_REST + Vector3(0, 0, MAX_PULL * charge * drawn)
	_place_string(string_l, TIP_L, nock)
	_place_string(string_r, TIP_R, nock)
	nocked.visible = has_arrow and drawn > 0.5
	nocked.position = nock - Vector3(0, 0, ARROW_LENGTH)

func _place_string(s: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var mid := (a + b) * 0.5
	var d := b - a
	s.transform = Transform3D(Basis.looking_at(d.normalized(), Vector3.UP) * Basis.from_scale(Vector3(1, 1, d.length())), mid)
