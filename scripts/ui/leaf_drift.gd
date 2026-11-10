extends Control
## Subtle menu background juice: a few leaves and feathers drifting down and swaying, in the palette.

const COLORS := [Color("4f7f3a"), Color("8dbf5a"), Color("6b9a45"), Color("e0c08a"), Color("fff6e0")]
const COUNT := 18

var _items: Array[Dictionary] = []

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in COUNT:
		var p := Polygon2D.new()
		var feather := i % 5 == 4
		var pts := PackedVector2Array()
		for k in 12:
			var a := TAU * k / 12.0
			pts.append(Vector2(cos(a) * (5.0 if feather else 9.0), sin(a) * (18.0 if feather else 14.0)))
		p.polygon = pts
		p.color = Color(COLORS[i % COLORS.size()], 0.35 if not feather else 0.5)
		add_child(p)
		_items.append({"node": p, "speed": randf_range(18, 45), "sway": randf_range(20, 60), "phase": randf() * TAU,
			"spin": randf_range(-1.2, 1.2), "x": randf_range(0, 1600)})
		p.position = Vector2(_items[i]["x"], randf_range(-100, 900))

func _process(delta: float) -> void:
	var h := size.y if size.y > 0 else 900.0
	var w := size.x if size.x > 0 else 1600.0
	for it in _items:
		var p: Polygon2D = it["node"]
		it["phase"] += delta
		p.position.y += it["speed"] * delta
		p.position.x = it["x"] + sin(it["phase"] * 0.9) * it["sway"]
		p.rotation += it["spin"] * delta
		if p.position.y > h + 40:
			p.position.y = -40
			it["x"] = randf_range(0, w)
