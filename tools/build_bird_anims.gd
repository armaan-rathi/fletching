extends SceneTree
## Builds the shared bird animation library (res://assets/birds/anims/bird_anims.tres) for the base rig.
## Clips are authored here as skeleton-space rotations per key (readable angles), converted to each
## bone's local rotation using the rig's rest pose. Every clip keys every bone, so the mixer fully owns the
## pose each frame; procedural motion is layered on top by BirdPoseModifier.
## Skeleton space (GLB): up +Y, the bird faces +Z, its left is +X.
## Run: Godot --headless --path . -s tools/build_bird_anims.gd
## The .tres is editable in Godot's animation editor; re-running this script overwrites it.

const SKELETON_PATH := "BirdBase/bird_skeleton/Skeleton3D"
const OUT := "res://assets/birds/anims/bird_anims.tres"

var skel: Skeleton3D
var bones: PackedStringArray

# --- Angle helpers (degrees, skeleton space) ------------------------------------------

func pitch(d: float) -> Quaternion: # + tips forward (top toward +Z)
	return Quaternion(Vector3.RIGHT, deg_to_rad(d))

func roll(d: float) -> Quaternion: # + tips the top toward the bird's right (-X)
	return Quaternion(Vector3.BACK, deg_to_rad(d))

func yaw(d: float) -> Quaternion: # + turns toward the bird's left
	return Quaternion(Vector3.UP, deg_to_rad(d))

## Wing pose: lift = raise outward, swing = toward the front (+) / back (-).
func wing(side: String, lift: float, swing: float) -> Quaternion:
	var s := 1.0 if side == "L" else -1.0
	return Quaternion(Vector3.UP, deg_to_rad(-s * swing)) * Quaternion(Vector3.BACK, deg_to_rad(s * lift))

func wings(lift_l: float, swing_l: float, lift_r := INF, swing_r := INF) -> Dictionary:
	if lift_r == INF:
		lift_r = lift_l
	if swing_r == INF:
		swing_r = swing_l
	return {"wing_L": wing("L", lift_l, swing_l), "wing_R": wing("R", lift_r, swing_r)}

func merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	out.merge(b, true)
	return out

# --- Build ---------------------------------------------------------------------------

func _init() -> void:
	var inst: Node = load("res://assets/birds/bird_base.glb").instantiate()
	skel = inst.find_children("*", "Skeleton3D", true, false)[0]
	for i in skel.get_bone_count():
		bones.append(skel.get_bone_name(i))

	var lib := AnimationLibrary.new()
	var idle_keys := [[0.0, {"body": pitch(0)}], [1.2, merge({"body": pitch(2.5), "head": roll(3)}, wings(5, 0))], [2.4, {"body": pitch(0)}]]
	lib.add_animation("idle", clip(2.4, true, idle_keys))

	var flam := {"leg_R": pitch(65), "foot_R": pitch(80), "leg_L": pitch(-4)}
	lib.add_animation("idle_flamingo", clip(2.4, true, [
		[0.0, merge(flam, {"body": roll(-6)})],
		[1.2, merge(flam, merge({"body": roll(-6) * pitch(2.5), "head": roll(3)}, wings(8, 0)))],
		[2.4, merge(flam, {"body": roll(-6)})]]))

	var draw_pose := merge({"body": pitch(-5), "head": pitch(-3)}, wings(15, 70, 15, 78))
	lib.add_animation("draw", clip(0.6, true, [[0.0, draw_pose], [0.6, draw_pose]]))

	lib.add_animation("release", clip(0.3, false, [
		[0.0, draw_pose],
		[0.06, merge({"body": pitch(-12)}, wings(45, 20))],
		[0.3, {}]]))

	var dash_pose := merge({"body": pitch(22), "head": pitch(-15)}, wings(-10, -40))
	lib.add_animation("dash", clip(0.4, true, [[0.0, dash_pose], [0.4, dash_pose]]))

	lib.add_animation("slap", clip(0.35, false, [
		[0.0, merge({"body": yaw(-15)}, {"wing_R": wing("R", 50, -60)})],
		[0.1, merge({"body": yaw(20)}, {"wing_R": wing("R", 25, 100)})],
		[0.35, {}]]))

	var squawk_pose := merge({"head": pitch(-22), "body": pitch(-5)}, wings(25, 0))
	lib.add_animation("squawk", clip(0.45, false, [[0.0, {}], [0.08, squawk_pose], [0.3, squawk_pose], [0.45, {}]]))

	# Limp pose only: the procedural KO flop (bird.gd) tips the whole bird onto its back or side.
	var ko_mid := merge({"head": pitch(-15)}, wings(70, 0))
	var ko_end := merge({"head": pitch(-30), "leg_L": pitch(-40), "leg_R": pitch(-25)}, wings(85, 20))
	lib.add_animation("ko", clip(0.5, false, [[0.0, {}], [0.15, ko_mid], [0.4, ko_end], [0.5, ko_end]]))

	var v_a := merge({"body": roll(8), "head": pitch(-10)}, wings(70, 10, 20, 0))
	var v_b := merge({"body": roll(-8), "head": pitch(-10)}, wings(20, 0, 70, 10))
	lib.add_animation("victory", clip(0.8, true, [[0.0, v_a], [0.4, v_b], [0.8, v_a]]))

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/birds/anims"))
	print("bird_anims: ", error_string(ResourceSaver.save(lib, OUT)), " clips=", lib.get_animation_list())
	inst.free()
	quit()

## keys: [[time, {bone: skeleton-space delta}], ...]; bones missing from a key use the rest pose.
func clip(length: float, loop: bool, keys: Array) -> Animation:
	var a := Animation.new()
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	for b in bones:
		var idx := skel.find_bone(b)
		var rest_rot := skel.get_bone_rest(idx).basis.get_rotation_quaternion()
		var rest_global := skel.get_bone_global_rest(idx).basis
		var t := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(t, "%s:%s" % [SKELETON_PATH, b])
		a.track_set_interpolation_type(t, Animation.INTERPOLATION_CUBIC)
		for k in keys:
			var delta: Quaternion = k[1].get(b, Quaternion.IDENTITY)
			var local := Quaternion(rest_global.inverse() * Basis(delta) * rest_global)
			a.rotation_track_insert_key(t, k[0], (rest_rot * local).normalized())
	return a
