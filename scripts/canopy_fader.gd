class_name CanopyFader
extends Node
## Put under a tree. Dithers the tree's canopy (see canopy_fade.gdshaderinc) while a bird or a
## stuck arrow is hidden behind it on screen, so nothing important disappears under the leaves.
## The canopy is approximated as a sphere; occlusion is tested in screen space with the live camera.

@export var target: ToonProp
@export var canopy_center_height := 2.6 ## m above the tree origin
@export var canopy_radius := 1.7 ## m
@export var max_fade := 0.55
@export var speed := 5.0

var _fade := 0.0

func _process(delta: float) -> void:
	if target == null:
		return
	var want := false
	var cam := get_viewport().get_camera_3d()
	if cam:
		var center := target.global_position + Vector3.UP * canopy_center_height
		var c2 := cam.unproject_position(center)
		var r2 := (cam.unproject_position(center + cam.global_basis.x * canopy_radius) - c2).length()
		var cam_depth := func(p: Vector3) -> float: return -(cam.global_transform.affine_inverse() * p).z
		var canopy_depth: float = cam_depth.call(center)
		for b: Node3D in get_tree().get_nodes_in_group("birds"):
			var p := b.global_position + Vector3.UP * 0.5
			if cam.unproject_position(p).distance_to(c2) < r2 * 1.1 and cam_depth.call(p) > canopy_depth - canopy_radius:
				want = true
				break
		if not want:
			for a in get_tree().get_nodes_in_group("arrows"):
				if a.state == Arrow.State.STUCK:
					var p: Vector3 = a.global_position
					if cam.unproject_position(p).distance_to(c2) < r2 and cam_depth.call(p) > canopy_depth - canopy_radius:
						want = true
						break
	var prev := _fade
	_fade = move_toward(_fade, max_fade if want else 0.0, delta * speed)
	if not is_equal_approx(prev, _fade):
		target.set_canopy_fade(_fade)
