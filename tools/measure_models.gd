extends SceneTree
## Prints the AABB size (m) and triangle count of every glTF in a folder.
## Run: Godot --headless --path . -s tools/measure_models.gd -- res://assets/third_party/kaykit_forest
func _init() -> void:
	var dir: String = OS.get_cmdline_user_args()[0]
	for f in DirAccess.get_files_at(dir):
		if not (f.ends_with(".gltf") or f.ends_with(".glb")):
			continue
		var inst: Node = load(dir.path_join(f)).instantiate()
		var aabb := AABB(); var first := true; var tris := 0
		for mi in inst.find_children("*", "MeshInstance3D", true, false) + ([inst] if inst is MeshInstance3D else []):
			var box: AABB = mi.mesh.get_aabb()
			aabb = box if first else aabb.merge(box); first = false
			for s in mi.mesh.get_surface_count():
				var arr = mi.mesh.surface_get_arrays(s)
				tris += (arr[Mesh.ARRAY_INDEX].size() if arr[Mesh.ARRAY_INDEX] else arr[Mesh.ARRAY_VERTEX].size()) / 3
		print("%-36s size=(%.2f, %.2f, %.2f) min_y=%.2f tris=%d" % [f, aabb.size.x, aabb.size.y, aabb.size.z, aabb.position.y, tris])
		inst.free()
	quit()
