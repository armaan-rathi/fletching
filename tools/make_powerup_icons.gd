extends SceneTree
## Generates placeholder power-up icons into res://assets/ui/powerups/ (128 px, flat colors, dark outline,
## on a round badge in the power-up's color):
##   ph_trifecta.png (three arrows in a fan), ph_eggsplosive.png (egg with a spark), ph_featherweight.png (feather).
## Run: Godot --headless --path . -s tools/make_powerup_icons.gd

const SIZE := 128
const INK := Color("2a2233")
const OUT := "res://assets/ui/powerups/"

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_save("trifecta", Color("ffd23f"), _trifecta)
	_save("eggsplosive", Color("ff7a45"), _eggsplosive)
	_save("featherweight", Color("8de0c8"), _featherweight)
	quit()

## shape(p) returns [distance (<0 inside), color] for the foreground; drawn over a round badge.
func _save(name: String, badge: Color, shape: Callable) -> void:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var p := Vector2((x + 0.5) / SIZE, (y + 0.5) / SIZE)
			var bd := p.distance_to(Vector2(0.5, 0.5)) - 0.44
			var c := Color(0, 0, 0, 0)
			if bd < 0.035:
				c = INK if bd > -0.005 else badge.lerp(Color.WHITE, 0.15 + 0.2 * (0.5 - p.y))
				c.a = clampf(0.5 - (bd - 0.035) * SIZE / 1.5, 0.0, 1.0)
			var fg: Array = shape.call(p)
			var d: float = fg[0]
			if d < 0.03:
				var ink := clampf(0.5 - (d - 0.03) * SIZE / 1.5, 0.0, 1.0)
				var fill := clampf(0.5 - d * SIZE / 1.5, 0.0, 1.0)
				var fc: Color = INK.lerp(fg[1], fill)
				c = Color(c.lerp(fc, ink), maxf(c.a, ink))
			img.set_pixel(x, y, c)
	print(name, ": ", error_string(img.save_png(OUT + "ph_%s.png" % name)))

func _seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return (p - (a + ab * t)).length()

func _arrow(p: Vector2, base: Vector2, angle: float) -> float:
	var dir := Vector2(sin(angle), -cos(angle))
	var tip := base + dir * 0.5
	var shaft := _seg(p, base, tip - dir * 0.05) - 0.022
	# triangular head
	var q := (p - tip).rotated(-angle)
	# Behind the tip, q.y > 0: a triangle that widens from the tip back to the shaft.
	var head := maxf(maxf(-q.y, q.y - 0.14), absf(q.x) - q.y * 0.55)
	return minf(shaft, head)

func _trifecta(p: Vector2) -> Array:
	var base := Vector2(0.5, 0.8)
	var d := 1.0
	for a in [-0.5, 0.0, 0.5]:
		d = minf(d, _arrow(p, base, a))
	return [d, Color("fff6e0")]

func _eggsplosive(p: Vector2) -> Array:
	var q := (p - Vector2(0.47, 0.56)) / Vector2(0.21, 0.27)
	if q.y < 0.0:
		q.x /= 1.0 - 0.18 * -q.y
	var egg := (q.length() - 1.0) * 0.21
	var spark := 1.0
	for i in 8:
		var a := TAU * i / 8.0
		spark = minf(spark, _seg(p, Vector2(0.72, 0.28), Vector2(0.72, 0.28) + Vector2(cos(a), sin(a)) * (0.11 if i % 2 == 0 else 0.07)) - 0.018)
	if spark < egg:
		return [spark, Color("ffe066")]
	return [egg, Color("fff6e0")]

func _featherweight(p: Vector2) -> Array:
	# A curved feather: an ellipse bent along an arc, with a quill.
	var q := (p - Vector2(0.5, 0.5)).rotated(-0.6)
	q.x += 0.25 * q.y * q.y
	var vane := (Vector2(q.x / 0.13, q.y / 0.34).length() - 1.0) * 0.13
	var quill := _seg(q + Vector2(0.5, 0.5), Vector2(0.5, 0.86), Vector2(0.5, 0.25)) - 0.015
	if quill < 0.0:
		return [quill, Color("2a2233")]
	return [minf(vane, quill), Color("fff6e0")]
