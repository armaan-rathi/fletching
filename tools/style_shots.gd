extends SceneTree
## Art style exploration captures: the same frozen Aviary scene (4 birds, feathers/explosion particles, an arrow
## in flight) in every style, tilt-shift on baseline and field guide, character/environment hybrids, the style
## options, and the anime FX extras (speed lines, smear, impact frame). Saves <name>.png (full view) and
## <name>_2x.png (close-up of the birds) to <out_dir>. Optional 2nd arg: only configs whose name contains it.
## Run: Godot --path . --audio-driver Dummy --resolution 1600x900 -s tools/style_shots.gd -- <out_dir> [filter]

const BIRD := preload("res://scenes/birds/bird.tscn")
const ARROW := preload("res://scenes/weapons/arrow.tscn")
const SLUGS := ["00_baseline", "01_field_guide", "02_felt", "03_risograph", "04_sketchbook", "05_anime",
	"06_watercolor", "07_woodblock", "08_pixel", "09_clay", "10_colored_line"]

func _init() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var only: String = args[1] if args.size() > 1 else ""
	DirAccess.make_dir_recursive_absolute(out)
	var mm := root.get_node("MatchManager")
	mm.power_ups = true
	mm.setup_practice()
	var map: Node = load("res://scenes/maps/aviary.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	if map.has_node("DebugHud"):
		map.get_node("DebugHud").free()
	await _frames(10)
	for n in get_nodes_in_group("birds"):
		n.free()
	var flock := BirdData.load_all()
	var colors := [Color("ff5a5a"), Color("4da6ff"), Color("ffd23f"), Color("b57bff")]
	var picks := [0, 2, 5, 6] # eagle, owl, rooster, swan
	var birds := []
	for i in 4:
		var b: Bird = BIRD.instantiate()
		b.bird_data = flock[picks[i]]
		b.player_color = colors[i]
		b.player_index = i
		b.input = CpuInput.new(b, "easy")
		map.add_child(b)
		await process_frame
		b.reset_for_round(Vector3(-3.0 + i * 2.0, 0, 1.6 + (i % 2) * 0.8), PI + (i - 1.5) * 0.3)
		b.frozen = true
		birds.append(b)
	for p in get_nodes_in_group("power_up_pads"):
		p.spawn(PowerUps.ids()[0])
	# [char style, env style, tilt-shift, name, extra]
	var configs := []
	for i in SLUGS.size():
		configs.append([i, i, false, SLUGS[i], ""])
	configs.append([0, 0, true, "00_baseline_tiltshift", ""])
	configs.append([1, 1, true, "01_field_guide_tiltshift", ""])
	configs.append([6, 6, false, "06_watercolor_pencil", "pencil"])
	configs.append([5, 5, false, "05_anime_fx_dash_smear", "fx"])
	configs.append([5, 5, false, "05_anime_fx_impact", "impact"])
	configs.append([5, 6, false, "hybrid_anime_birds_watercolor_world", ""])
	configs.append([9, 7, false, "hybrid_clay_birds_woodblock_world", ""])
	configs.append([8, 0, false, "hybrid_pixel_birds_baseline_world", ""])
	configs.append([0, 6, false, "hybrid_baseline_birds_watercolor_world", ""])
	configs.append([10, 4, false, "hybrid_colored_line_birds_sketchbook_world", ""])
	for c in configs:
		if only != "" and not (c[3] as String).contains(only):
			continue
		ArtStyle.pencil_lines = c[4] == "pencil"
		ArtStyle.anime_fx = true
		ArtStyle.set_styles(c[0], c[1])
		if ArtStyle.tilt_shift != c[2]:
			ArtStyle.toggle_tilt_shift()
		# Same moment each time: fresh particles + an arrow in flight.
		for a in get_nodes_in_group("arrows"):
			a.queue_free()
		Fx.feathers(Vector3(2.5, 0.6, 3.5), [Color.WHITE, Color("e0c08a"), Color("6b4a33")])
		Fx.explosion(Vector3(-5.5, 0.3, 4.2), 1.2)
		var arrow: Arrow = ARROW.instantiate()
		map.add_child(arrow)
		var from := Vector3(-6.0, 0.55, 0.5)
		arrow.launch(birds[0], from, from + Vector3.RIGHT * 0.8, Vector3.RIGHT * 2.0, colors[0], 0.5)
		await _frames(14)
		if c[4] == "fx":
			Fx.speed_lines(birds[0].global_position, Vector3.LEFT, 0.6)
			Fx.smear(birds[2].global_position + Vector3.UP * 0.55, birds[2].facing, 140.0, 1.0, Color("e8e2d0"))
			await _frames(2)
		elif c[4] == "impact":
			ArtStyle.impact_frame(birds[1].global_position + Vector3.UP * 0.5)
			await _frames(2)
		else:
			await _frames(2)
		var img := root.get_texture().get_image()
		img.save_png(out.path_join(c[3] + ".png"))
		var cam := root.get_viewport().get_camera_3d()
		var ctr := cam.unproject_position(Vector3(0.0, 0.5, 2.0))
		var crop := img.get_region(Rect2i(int(ctr.x) - 330, int(ctr.y) - 160, 660, 320))
		crop.resize(1320, 640, Image.INTERPOLATE_NEAREST)
		crop.save_png(out.path_join(c[3] + "_2x.png"))
		print("captured ", c[3])
		await _frames(14) # let an impact frame finish
	ArtStyle.set_style(0)
	if ArtStyle.tilt_shift:
		ArtStyle.toggle_tilt_shift()
	quit()

func _frames(n: int) -> void:
	for i in n:
		await process_frame
