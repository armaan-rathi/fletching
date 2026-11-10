extends SceneTree
## Prints a scene's node tree, skeleton bones and mesh surface materials.
## Run: Godot --headless --path . -s tools/inspect_scene.gd -- <scene>
func _init() -> void:
	var inst: Node = load(OS.get_cmdline_user_args()[0]).instantiate()
	_print(inst, 0)
	quit()
func _print(n: Node, d: int) -> void:
	var extra := ""
	if n is Skeleton3D:
		var names := []
		for i in n.get_bone_count(): names.append(n.get_bone_name(i))
		extra = " bones=" + str(names)
	if n is MeshInstance3D:
		var mats := []
		for i in n.mesh.get_surface_count(): mats.append(n.mesh.surface_get_material(i).resource_name if n.mesh.surface_get_material(i) else "-")
		extra = " mats=" + str(mats) + " aabb=" + str(n.mesh.get_aabb())
	print("  ".repeat(d), n.name, " <", n.get_class(), ">", extra)
	for c in n.get_children(): _print(c, d + 1)
