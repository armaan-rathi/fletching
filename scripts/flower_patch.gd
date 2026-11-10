class_name FlowerPatch
extends Node3D
## Placeholder flower cluster (ph_, see docs/placeholders.md): a few low-poly toon flowers on short stems
## in palette colors. Decoration only; no collision.

const PETALS := [Color("fff6e0"), Color("ffd23f"), Color("ff8fb1"), Color("b57bff")]
const STEM := Color("4f7f3a")
const CENTER := Color("f2b233")

@export var seed := 0

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else hash(global_position.snapped(Vector3.ONE * 0.1))
	var color: Color = PETALS[rng.randi() % PETALS.size()]
	for i in rng.randi_range(3, 5):
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.05, 0.28)
		var h := rng.randf_range(0.14, 0.26)
		var base := Vector3(cos(a) * r, 0, sin(a) * r)
		var stem := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.012
		cyl.bottom_radius = 0.016
		cyl.height = h
		cyl.radial_segments = 4
		cyl.rings = 1
		stem.mesh = cyl
		stem.material_override = ToonMaterials.toon(STEM, 0.0, false)
		stem.position = base + Vector3(0, h * 0.5, 0)
		stem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(stem)
		var head := MeshInstance3D.new()
		var petals := CylinderMesh.new() # a squat 5-sided disc reads as a little flower from above
		petals.top_radius = 0.065
		petals.bottom_radius = 0.045
		petals.height = 0.03
		petals.radial_segments = 5
		petals.rings = 1
		head.mesh = petals
		head.material_override = ToonMaterials.toon(color if i % 3 != 2 else PETALS[(rng.randi() % 3)], 0.2)
		head.position = base + Vector3(0, h, 0)
		head.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))
		head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(head)
		var dot := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.022
		sph.height = 0.03
		sph.radial_segments = 6
		sph.rings = 3
		dot.mesh = sph
		dot.material_override = ToonMaterials.toon(CENTER, 0.0, false)
		dot.position = Vector3(0, 0.018, 0)
		head.add_child(dot)
