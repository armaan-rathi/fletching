extends SceneTree
## Writes res://data/birds/<id>.tres for the 8 prototype birds (parts, shape, look, 4 color variants).
## Run: Godot --headless --path . -s tools/build_bird_data.gd
## Edit values here (or in the .tres files directly; re-running overwrites them).

func kit(head: String, beak: String, eyes: String, extras: Array) -> PackedStringArray:
	var p := PackedStringArray(["head_" + head, "beak_%s_upper" % beak, "beak_%s_lower" % beak, "eyes_%s_L" % eyes, "eyes_%s_R" % eyes])
	p.append_array(extras)
	return p

func v(n: String, body: String, belly: String, beak: String, legs: String, accent: String, iris: String, iris_low: String) -> Dictionary:
	return {"name": n, "body": Color(body), "belly": Color(belly), "beak": Color(beak), "legs": Color(legs),
		"accent": Color(accent), "iris": Color(iris), "iris_low": Color(iris_low)}

func _init() -> void:
	var birds := [
		{"id": "eagle", "eyes": {"lid_top": 0.24, "lid_slant": 0.3, "brow_thickness": 0.08, "brow_slant": 0.35, "brow_height": 0.1}, "name": "Bald Eagle", "blurb": "Regal but a bit cranky.",
			"parts": kit("eagle", "hooked", "eagle", ["collar_scalloped", "tail_fan"]), "head": "head_eagle",
			"lid": "accent",
			"variants": [v("Classic", "553624", "553624", "f5b82e", "f5b82e", "f8f8f5", "2a1f1a", "6b4a2a"),
				v("Golden", "7a5230", "7a5230", "e9a62a", "e9a62a", "ead39a", "2a1f1a", "7a5a2a"),
				v("Storm", "4a4f5c", "4a4f5c", "f0c040", "f0c040", "f4f6fa", "1e2230", "4a5a7a"),
				v("Midnight", "2b2420", "2b2420", "e0a020", "e0a020", "d8d2c6", "1a1412", "5a3a2a")]},
		{"id": "flamingo", "eyes": {"lid_top": 0.1, "lashes": true}, "name": "Flamingo", "blurb": "Flamboyant.",
			"parts": kit("slim", "banana", "slim", ["tuft_flamingo", "neck_stretch", "tail_short"]), "head": "head_slim",
			"shape": {"slim": 1.0}, "head_scale": 0.95, "neck_extend": 0.18, "idle": "idle_flamingo",
			"variants": [v("Pink", "ff8fb1", "ffc2d4", "f4e6e2", "ff8fb1", "2a2233", "3a2030", "8a4060"),
				v("Coral", "ff7a5c", "ffb59e", "f4e6e2", "ff7a5c", "2a2233", "3a2020", "8a4030"),
				v("Lilac", "c99be8", "e6cdf6", "f4eef6", "c99be8", "2a2233", "2a2040", "6a4a9a"),
				v("Pale", "f6e6e6", "ffffff", "f0d6d6", "f2b0c0", "2a2233", "3a2030", "8a4060")]},
		{"id": "owl", "eyes": {"lid_top": 0.36, "pupil_scale": 1.1}, "name": "Owl", "blurb": "Wise but a little drowsy.",
			"parts": kit("owl", "owl", "owl", ["tail_fan"]), "head": "head_owl",
			"shape": {"round": 1.0}, "lid": "belly", "sleepy": 3.0,
			"variants": [v("Brown", "8a6240", "ead8b6", "d9a441", "c9a15a", "6e4a30", "e0a020", "ffd75e"),
				v("Snowy", "e8e8e4", "ffffff", "3a3a40", "d8d8d0", "a8a8a4", "e0b020", "fff07a"),
				v("Barn", "d9a066", "fff4e0", "e8d0b0", "e0c8a8", "b07a40", "1e1a1a", "4a3a3a"),
				v("Gray", "7a7a80", "c8c8cc", "d9b441", "a0a0a0", "55555c", "f08a20", "ffc05e")]},
		{"id": "crow", "eyes": {"lid_top": 0.3, "lid_slant": -0.12, "lid_bottom": 0.2, "pupil_scale": 0.9}, "name": "Crow", "blurb": "Mischievous and greedy.",
			"parts": kit("round", "sharp", "round", ["tail_fan_plain"]), "head": "head_round",
			"shape": {"slim": 0.6}, "head_scale": 0.95, "rim_tint": Color("8aa8ff"), "rim": 0.75,
			"variants": [v("Classic", "2e3042", "3a3d52", "4a4c5c", "4a4c5c", "2e3042", "1a1a22", "5a6aaa"),
				v("Raven", "283258", "323c66", "3a4058", "3a4058", "283258", "141828", "4a5aa0"),
				v("Ghost", "ece8e0", "f6f4f0", "d8a0a0", "d8a0a0", "ece8e0", "8a2030", "d06070"),
				v("Hooded", "4a4a52", "8a8a92", "2a2a30", "2a2a30", "4a4a52", "1a1a22", "4a4a6a")]},
		{"id": "pigeon", "eyes": {"pupil_scale": 0.45}, "name": "Pigeon", "blurb": "Wide-eyed and a bit manic.",
			"parts": kit("round", "short", "round", ["collar_ruffle", "tail_fan_plain"]), "head": "head_round",
			"shape": {"round": 0.8}, "head_scale": 0.92,
			"variants": [v("City", "5a6478", "9aa2b0", "3a3a40", "e0606a", "4a9a7a", "ff8a30", "ffc060"),
				v("Dove", "f0f0f0", "ffffff", "e8b0b0", "e8808a", "c0c8d8", "2a1a1a", "6a4a4a"),
				v("Cocoa", "7a5a4a", "a88a78", "3a3a40", "d86068", "8a5a9a", "ff8a30", "ffc060"),
				v("Charcoal", "3a3e48", "6a707c", "2a2a30", "d05058", "3a8a9a", "ff7a20", "ffb050")]},
		{"id": "rooster", "eyes": {"lid_top": 0.14, "brow_thickness": 0.055, "brow_slant": -0.2, "brow_height": 0.14, "brow_raise_left": 0.08}, "name": "Rooster", "blurb": "Cocky.",
			"parts": kit("round", "short", "round", ["comb_rooster", "wattle_rooster", "tail_sickle"]), "head": "head_round",
			"shape": {"puff": 1.0},
			"variants": [v("Classic", "b5642e", "d98a4a", "f2c230", "f2c230", "e23a2a", "3a1a10", "8a4a20"),
				v("Leghorn", "f6f2ea", "ffffff", "f2c230", "f2c230", "e23a2a", "3a1a10", "8a4a20"),
				v("Onyx", "2a2a30", "3a3a44", "e8b830", "e8b830", "d82a2a", "3a1a10", "8a4a20"),
				v("Golden", "e0a040", "f0c070", "f2c230", "f2c230", "e23a2a", "3a1a10", "8a4a20")]},
		{"id": "swan", "eyes": {"lid_top": 0.42, "lid_slant": -0.22}, "name": "Swan", "blurb": "Haughty and elegant.",
			"parts": kit("slim", "swan", "slim", ["mask_swan", "neck_stretch", "tail_short"]), "head": "head_slim",
			"shape": {"slim": 1.0}, "neck_extend": 0.24,
			"variants": [v("Mute", "f8f8f5", "ffffff", "f08a30", "3a3a40", "1f1f24", "1a1a22", "3a3a5a"),
				v("Black", "2a2a30", "34343c", "e03a3a", "3a3a40", "f0f0f0", "8a1a1a", "d04040"),
				v("Gilded", "f0e4c0", "fff8e4", "e09030", "4a4038", "2a2420", "1a1a22", "4a3a2a"),
				v("Mist", "c8c8d0", "e4e4ea", "f08a30", "3a3a40", "1f1f24", "1a1a22", "3a3a5a")]},
		{"id": "vulture", "eyes": {"lid_top": 0.4, "lid_slant": -0.32, "lid_bottom": 0.1}, "name": "Vulture", "blurb": "Gloomy and opportunistic.",
			"parts": kit("bald", "vulture", "bald", ["ruff_fluffy", "tail_fan_plain"]), "head": "head_bald",
			"shape": {"hunch": 1.0}, "neck_pitch": 18.0, "lid": "accent",
			"variants": [v("Classic", "3e2a20", "efe8dc", "d8d0c0", "8a8070", "d9706a", "2a1a14", "8a4a2a"),
				v("King", "e8e0d0", "2a2a30", "e05a30", "a09080", "e89a40", "f0e0e0", "ffffff"),
				v("Black", "26262a", "d8d4cc", "b8b0a8", "6a6460", "8a8a90", "2a1a14", "6a4a3a"),
				v("Griffon", "b08a60", "f4ecdc", "d0c8b8", "8a8070", "e0b0a0", "3a2a14", "9a6a2a")]},
	]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/birds"))
	for b in birds:
		var d := BirdData.new()
		d.id = b["id"]
		d.display_name = b["name"]
		d.blurb = b["blurb"]
		d.parts = b["parts"]
		d.head_part = b["head"]
		d.body_shape = b.get("shape", {})
		d.head_scale = b.get("head_scale", 1.0)
		d.neck_extend = b.get("neck_extend", 0.0)
		d.neck_pitch = b.get("neck_pitch", 0.0)
		d.rim_tint = b.get("rim_tint", Color.WHITE)
		d.rim_strength = b.get("rim", 0.4)
		d.lid_slot = b.get("lid", "body")
		d.resting_eye_frame = 0
		d.eye_style = b.get("eyes", {})
		d.idle_anim = b.get("idle", "idle")
		d.sleepy_delay = b.get("sleepy", 6.0)
		var vs: Array[Dictionary] = []
		vs.assign(b["variants"])
		d.variants = vs
		var path := "res://data/birds/%s.tres" % d.id
		print("%s: %s" % [path, error_string(ResourceSaver.save(d, path))])
	quit()
