extends SceneTree
## Scripted Stage 1 playtest: drives the input actions on the test map and checks the results.
## Run (windowed, for screenshots): Godot --path . --resolution 1600x900 -s tools/sim_playtest.gd -- <out_dir>
## Add "quick" after <out_dir> for a short smoke test (walk, dash, one shot into the tree, pickup).
## Prints PASS/FAIL lines and saves screenshots into <out_dir>.

var out_dir := ""
var map: Node
var bird: Bird
var fails := 0

func _init() -> void:
	await process_frame
	out_dir = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	root.get_node("MatchManager").setup_practice() # single bird, no rounds (autoload looked up at runtime)
	map = load("res://scenes/maps/test_map.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	await wait(0.3)
	bird = map.get_node("Player1")
	bird.set_process_input(false) # ignore the real mouse
	bird.input.include_actions = true # drive it with Input.action_press
	bird.global_position = Vector3(-5.0, 0.0, 3.0)

	# 1. Movement: walk right.
	var start := bird.global_position
	press("move_right")
	await wait(0.25)
	shot("01_walking")
	await wait(0.35)
	check("top speed ~move_speed", absf(bird.velocity.length() - bird.t.move_speed) < 0.3, "speed=%.2f" % bird.velocity.length())
	release("move_right")
	await wait(0.4)
	check("stops after release", bird.velocity.length() < 0.05, "speed=%.2f" % bird.velocity.length())
	check("walked right", bird.global_position.x - start.x > 2.5, "dx=%.2f" % (bird.global_position.x - start.x))

	# 2. Dash: distance and cooldown.
	start = bird.global_position
	press("move_down")
	await wait(0.02)
	tap("dash")
	await wait(0.07)
	shot("02_dash")
	await wait(0.25)
	release("move_down")
	var dash_dist := bird.last_dash_distance
	check("dash covers ~dash_distance", absf(dash_dist - bird.t.dash_distance) < 0.3, "dist=%.2f" % dash_dist)
	tap("dash")
	await wait(0.1)
	check("dash on cooldown", bird.state != Bird.State.DASHING, "state=%d" % bird.state)
	await wait(1.0)

	# 3. Shoot into the tree (trunk at ~(0.08, -0.5)) from the left.
	bird.global_position = Vector3(-5.0, 0, -0.5)
	bird.facing = Bird.yaw_of(Vector3.RIGHT)
	await wait(0.1)
	press("shoot")
	await wait(0.35)
	shot("03_drawing")
	check("rooted while drawing", bird.velocity.length() < 0.01 and bird.state == Bird.State.DRAWING, "")
	await wait(0.35)
	release("shoot")
	await wait(0.08)
	shot("04_arrow_flying")
	await wait(0.4)
	var stuck := arrows_in(Arrow.State.STUCK)
	check("arrow stuck in tree", stuck.size() == 1 and absf(stuck[0].global_position.x) < 0.6 and stuck[0].global_position.y > 0.3, describe(stuck))
	check("quiver 3 -> 2", bird.arrows == 2, "arrows=%d" % bird.arrows)

	if OS.get_cmdline_user_args().has("quick"):
		press("move_right")
		await wait(1.0)
		release("move_right")
		await wait(0.2)
		check("picked the arrow back up", bird.arrows == 3, "arrows=%d" % bird.arrows)
		shot("quick_after_pickup")
		print("SIM DONE: %d failure(s)" % fails)
		quit()
		return

	# 4. Dash cancels a draw (no arrow spent). Dash away from the tree so we don't pick anything up.
	await wait(0.8) # dash cooldown
	press("shoot")
	await wait(0.2)
	press("move_left")
	tap("dash")
	await wait(0.05)
	release("shoot")
	release("move_left")
	await wait(0.3)
	check("dash cancelled draw, arrow kept", bird.arrows == 2 and arrows_in(Arrow.State.FLYING).size() == 0, "arrows=%d" % bird.arrows)

	# 5. Two more into the tree, then empty.
	for i in 2:
		bird.global_position = Vector3(-4.0, 0, -0.5 + (i * 0.3 - 0.15))
		bird.facing = Bird.yaw_of(Vector3(4.0, 0, 0.15 - i * 0.3).normalized())
		await wait(0.05)
		press("shoot")
		await wait(0.5)
		release("shoot")
		await wait(0.6)
	shot("05_three_in_tree")
	check("all 3 arrows stuck in the tree", arrows_in(Arrow.State.STUCK).size() == 3, describe(arrows_in(Arrow.State.STUCK)))
	check("quiver empty", bird.arrows == 0, "arrows=%d" % bird.arrows)
	tap("shoot")
	await wait(0.2)
	check("empty quiver fires nothing", arrows_in(Arrow.State.FLYING).size() == 0, "")

	# 6. Walk into the tree to collect them (well before the 5 s auto-return).
	press("move_right")
	await wait(1.0)
	release("move_right")
	await wait(0.2)
	shot("06_collected")
	check("picked up arrows at the tree", bird.arrows >= 2, "arrows=%d, left=%d" % [bird.arrows, arrows_in(Arrow.State.STUCK).size()])
	# Sweep around the trunk for any arrow on the far side.
	for dir in ["move_up", "move_down"]:
		if bird.arrows < 3:
			bird.global_position = Vector3(-0.9, 0, -0.5)
			press(dir); await wait(0.25); release(dir)
			press("move_right"); await wait(0.5); release("move_right")
	check("quiver refilled to 3", bird.arrows == 3, "arrows=%d" % bird.arrows)

	# 7. Weak shot lands on the ground, then auto-returns after 5 s.
	bird.global_position = Vector3(-6.0, 0, 3.0)
	bird.facing = Bird.yaw_of(Vector3(1, 0, 0.2).normalized())
	await wait(0.05)
	tap("shoot")
	await wait(1.0)
	var lying := arrows_in(Arrow.State.STUCK)
	check("tap shot lies on the ground", lying.size() == 1 and lying[0].global_position.y < 0.05, describe(lying))
	shot("07_on_ground")
	await wait(3.0)
	check("still lying before 5 s", lying.size() == 1 and is_instance_valid(lying[0]) and not lying[0].is_queued_for_deletion(), "")
	await wait(2.0)
	check("auto-return after 5 s", bird.arrows == 3 and arrows_in(Arrow.State.STUCK).size() == 0, "arrows=%d" % bird.arrows)

	# 8. Full-charge shot into the back wall.
	bird.global_position = Vector3(5.0, 0, 4.0)
	bird.facing = Bird.yaw_of(Vector3.FORWARD)
	await wait(0.05)
	press("shoot"); await wait(0.7); release("shoot")
	await wait(0.6)
	var wall := arrows_in(Arrow.State.STUCK)
	check("full shot sticks in back wall", wall.size() == 1 and wall[0].global_position.z < -6.9, describe(wall))
	shot("08_wall")

	# 9. Mouse aim math: the cursor over a world point aims at that point.
	var cam := root.get_viewport().get_camera_3d()
	for target_off in [Vector3(3, 0, -2), Vector3(-4, 0, 1), Vector3(0.5, 0, 5)]:
		var tp: Vector3 = bird.global_position + target_off + Vector3.UP * bird.t.arrow_height
		var d: Vector3 = bird._cursor_dir(cam.unproject_position(tp))
		var want: Vector3 = Vector3(target_off.x, 0, target_off.z).normalized()
		check("mouse aim toward %s" % target_off, d.dot(want) > 0.999, "got %s" % d)

	# 10. A bird behind the tree: canopy fades, silhouette shows.
	bird.global_position = Vector3(0.6, 0, -3.0)
	bird.facing = PI
	await wait(0.4)
	shot("09_behind_tree")

	print("SIM DONE: %d failure(s)" % fails)
	quit()

# --- helpers ---------------------------------------------------------------------

func wait(seconds: float) -> void:
	var frames := int(round(seconds * 60.0))
	for i in maxi(frames, 1):
		await physics_frame

func press(action: String) -> void:
	PlayerInput.test_press(action)

func release(action: String) -> void:
	PlayerInput.test_release(action)

func tap(action: String) -> void:
	PlayerInput.test_press(action)
	await physics_frame
	await physics_frame
	PlayerInput.test_release(action)

func arrows_in(state: int) -> Array:
	var out := []
	for n in map.get_children():
		if n is Arrow and n.state == state and not n.is_queued_for_deletion():
			out.append(n)
	return out

func describe(arrows: Array) -> String:
	var s := []
	for a in arrows:
		s.append("(%.2f, %.2f, %.2f)" % [a.global_position.x, a.global_position.y, a.global_position.z])
	return "n=%d %s" % [arrows.size(), ", ".join(s)]

func check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])

func shot(name: String) -> void:
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
