extends SceneTree
## Prints the trunk radius of a KayKit tree (max horizontal distance of vertices below a height).
## Run: Godot --headless --path . -s tools/probe_trunk.gd -- <model.gltf> <max_y>
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var inst: Node = load(a[0]).instantiate()
	var max_y := float(a[1])
	var r := 0.0; var cx := 0.0; var cz := 0.0; var n := 0
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		for v in mi.mesh.get_faces():
			if v.y < max_y and v.y > 0.1:
				cx += v.x; cz += v.z; n += 1
	cx /= n; cz /= n
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		for v in mi.mesh.get_faces():
			if v.y < max_y and v.y > 0.1:
				r = max(r, Vector2(v.x - cx, v.z - cz).length())
	print("center=(%.2f, %.2f) radius=%.2f" % [cx, cz, r])
	quit()
