extends SceneTree
## Generates the floating anime symbol icons (placeholders) into res://assets/vfx/symbols/:
## ph_sweat.png, ph_anger.png, ph_sparkle.png, ph_dizzy.png — bold flat shapes with a dark outline.
## ("!", "?" and "zzz" are drawn as outlined text by AnimeSymbol.)
## Run: Godot --headless --path . -s tools/make_symbols.gd

const SIZE := 128
const OUTLINE := Color("2a2233")
const OUT_DIR := "res://assets/vfx/symbols/"

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_save("sweat", Color("8fd8ff"), _sweat, _sweat_hi)
	_save("anger", Color("ff4040"), _anger, Callable())
	_save("sparkle", Color("ffe066"), _sparkle, Callable())
	_save("dizzy", Color("ffe066"), _dizzy, Callable())
	quit()

func _save(name: String, fill: Color, shape: Callable, highlight: Callable) -> void:
	# Signed-ish coverage from a shape function f(p) -> distance (<0 inside), p in 0..1.
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var p := Vector2((x + 0.5) / SIZE, (y + 0.5) / SIZE)
			var d: float = shape.call(p)
			var inside := clampf(0.5 - d * SIZE / 1.5, 0.0, 1.0)
			var outline := clampf(0.5 - (d - 0.045) * SIZE / 1.5, 0.0, 1.0)
			var c := OUTLINE.lerp(fill, inside)
			if highlight.is_valid() and highlight.call(p) < 0.0:
				c = c.lerp(Color.WHITE, inside)
			c.a = outline
			img.set_pixel(x, y, c)
	print(name, ": ", error_string(img.save_png(OUT_DIR + "ph_%s.png" % name)))

func _circle(p: Vector2, c: Vector2, r: float) -> float:
	return p.distance_to(c) - r

func _sweat(p: Vector2) -> float:
	# Teardrop: circle at the bottom, pointed top.
	var c := Vector2(0.5, 0.62)
	var r := 0.24
	var d := _circle(p, c, r)
	var tip := Vector2(0.5, 0.12)
	var to_p := p - tip
	if p.y < c.y:
		# Cone from the tip tangent to the circle.
		var half := asin(r / tip.distance_to(c))
		var ang := absf(Vector2(0, 1).angle_to(to_p))
		d = minf(d, to_p.length() * sin(maxf(ang - half, 0.0)) if ang > half else -0.01 * (1.0 - ang / half))
	return d

func _sweat_hi(p: Vector2) -> float:
	return _circle(p, Vector2(0.42, 0.6), 0.06)

func _anger(p: Vector2) -> float:
	# Four bulging brackets around a gap (the classic anger "vein" mark).
	var d := 1.0
	for q in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var c: Vector2 = Vector2(0.5, 0.5) + q * 0.3
		var arc := absf(p.distance_to(c) - 0.2) - 0.055
		# keep only the side facing the center
		var toward: Vector2 = (Vector2(0.5, 0.5) - c).normalized()
		if (p - c).normalized().dot(toward) < 0.35:
			arc = 1.0
		d = minf(d, arc)
	return d

func _star(p: Vector2, c: Vector2, r_out: float, r_in: float, points: int, rot := 0.0) -> float:
	var v := p - c
	var a := fposmod(atan2(v.y, v.x) - rot, TAU / points) - PI / points
	var t := absf(a) / (PI / points)
	var r := lerpf(r_out, r_in, 1.0 - t) # pointed star profile
	return v.length() - lerpf(r_in, r_out, t)

func _sparkle(p: Vector2) -> float:
	var big := _star(p, Vector2(0.44, 0.5), 0.38, 0.1, 4, -PI / 2)
	var small := _star(p, Vector2(0.8, 0.22), 0.14, 0.04, 4, -PI / 2)
	return minf(big, small)

func _dizzy(p: Vector2) -> float:
	var d := 1.0
	for i in 3:
		var a := PI * (1.15 + 0.35 * i)
		var c := Vector2(0.5, 0.62) + Vector2(cos(a), sin(a) * 0.55) * 0.34
		d = minf(d, _star(p, c, 0.15, 0.065, 5, -PI / 2))
	return d
