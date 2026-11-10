extends SceneTree
## Generates the placeholder expression atlas: 4x4 grid of 128 px frames, channel-packed masks:
##   R = iris, G = pupil (dark), B = white (highlights / sclera), A = eye coverage (0 = eyelid/skin shows).
## Where A = 1 and R = G = B = 0 the line color is drawn (lids, brows, lashes, X eyes...).
## UV (u, v): u = 0 is the eye's inner side (toward the beak), v = 0 is the top.
## Frame 0 (resting) is drawn procedurally in eye.gdshader with per-bird parameters; frames 1+ are shared:
##   1 blink half, 2 blink closed, 3 focused (squint), 4 determined, 5 shocked, 6 annoyed, 7 confused (dots),
##   8 smug (left eye: brow up), 9 KO (X), 10 happy (^ ^), 11 sad, 12 sleepy, 13 smug (right eye: flat brow).
## Run: Godot --headless --path . -s tools/make_eye_atlas.gd

const CELL := 128
const GRID := 4
const OUT := "res://assets/birds/eyes/ph_eye_atlas.png"
const FRAMES := 14

func _init() -> void:
	var img := Image.create(CELL * GRID, CELL * GRID, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for f in range(1, FRAMES):
		var ox := (f % GRID) * CELL
		var oy := (f / GRID) * CELL
		for y in CELL:
			for x in CELL:
				img.set_pixel(ox + x, oy + y, _frame(f, (x + 0.5) / CELL, (y + 0.5) / CELL))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/birds/eyes"))
	print("eye atlas: ", error_string(img.save_png(OUT)))
	quit()

# --- mask helpers --------------------------------------------------------------------

func aa(d: float, w := 0.012) -> float:
	return clampf(0.5 - d / w, 0.0, 1.0)

func ell(u: float, v: float, cx: float, cy: float, rx: float, ry: float) -> float:
	return (Vector2((u - cx) / rx, (v - cy) / ry).length() - 1.0) * minf(rx, ry)

func seg(u: float, v: float, a: Vector2, b: Vector2) -> float:
	var p := Vector2(u, v)
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return (p - (a + ab * t)).length()

## Base resting eye: iris disc with a thin rim, pupil, two highlights.
func eye(u: float, v: float, pupil_r := 0.21) -> Dictionary:
	var r := Vector2(u - 0.5, v - 0.5).length()
	return {
		"a": aa(r - 0.5),
		"r": aa(r - 0.455),
		"g": aa(ell(u, v, 0.5, 0.56, pupil_r, pupil_r * 1.12)),
		"b": maxf(aa(ell(u, v, 0.36, 0.33, 0.14, 0.12)), aa(ell(u, v, 0.65, 0.68, 0.06, 0.06))),
	}

## Upper lid: everything above y(u) becomes skin, with a lid line on the edge.
func lid_top(e: Dictionary, u: float, v: float, y: float, line := 0.035) -> void:
	var ln := aa(absf(v - y) - line)
	if v < y - line:
		e["a"] = 0.0
	_ink(e, ln)

func lid_bottom(e: Dictionary, u: float, v: float, y: float, line := 0.03) -> void:
	var ln := aa(absf(v - y) - line)
	if v > y + line:
		e["a"] = 0.0
	_ink(e, ln)

## Ink stroke (line color) drawn over whatever is there, even on skin.
func _ink(e: Dictionary, amount: float) -> void:
	if amount <= 0.0:
		return
	e["a"] = maxf(e["a"], amount)
	for k in ["r", "g", "b"]:
		e[k] *= 1.0 - amount

func stroke(e: Dictionary, u: float, v: float, a: Vector2, b: Vector2, thick: float) -> void:
	_ink(e, aa(seg(u, v, a, b) - thick))

func skin_only() -> Dictionary:
	return {"a": 0.0, "r": 0.0, "g": 0.0, "b": 0.0}

# --- frames --------------------------------------------------------------------------

func _frame(f: int, u: float, v: float) -> Color:
	var e := eye(u, v)
	match f:
		1: # blink half
			lid_top(e, u, v, 0.46)
			if v < 0.49: e["b"] = 0.0
		2: # blink closed
			e = skin_only()
			var x := (u - 0.5) * 2.0
			_ink(e, aa(absf(v - (0.5 + 0.12 * (1.0 - x * x))) - 0.04) * aa(absf(x) - 0.82))
		3: # focused squint
			lid_top(e, u, v, 0.36)
			lid_bottom(e, u, v, 0.74)
		4: # determined: lid slants down to the inner side, brow above
			lid_top(e, u, v, 0.34 + 0.3 * (0.5 - u))
			stroke(e, u, v, Vector2(0.12, 0.24), Vector2(0.88, 0.08), 0.045)
		5: # shocked: white eye, tiny pupil
			var r := Vector2(u - 0.5, v - 0.5).length()
			e = {"a": aa(r - 0.5), "r": 0.0, "g": aa(r - 0.075), "b": aa(r - 0.44) * (1.0 - aa(r - 0.075))}
		6: # annoyed: heavy slanted lid, thick angry brow
			e = eye(u, v, 0.17)
			lid_top(e, u, v, 0.42 + 0.36 * (0.5 - u))
			stroke(e, u, v, Vector2(0.1, 0.3), Vector2(0.9, 0.06), 0.06)
		7: # confused: dot eyes
			e = skin_only()
			_ink(e, aa(ell(u, v, 0.5, 0.56, 0.11, 0.13)))
		8, 13: # smug: half lid; left eye's brow is raised (8), right eye's is flat (13)
			lid_top(e, u, v, 0.5)
			if v < 0.53: e["b"] = 0.0
			if f == 8:
				stroke(e, u, v, Vector2(0.18, 0.2), Vector2(0.82, 0.07), 0.04)
			else:
				stroke(e, u, v, Vector2(0.18, 0.24), Vector2(0.82, 0.24), 0.04)
		9: # KO: X eyes
			e = skin_only()
			stroke(e, u, v, Vector2(0.22, 0.24), Vector2(0.78, 0.8), 0.055)
			stroke(e, u, v, Vector2(0.78, 0.24), Vector2(0.22, 0.8), 0.055)
		10: # happy: ^ arcs
			e = skin_only()
			var x := (u - 0.5) * 2.0
			_ink(e, aa(absf(v - (0.62 - 0.26 * (1.0 - x * x))) - 0.045) * aa(absf(x) - 0.8))
		11: # sad: droopy lid (outer side low), worried brow (inner side up), a big tear highlight
			lid_top(e, u, v, 0.36 - 0.26 * (0.5 - u))
			stroke(e, u, v, Vector2(0.15, 0.06), Vector2(0.85, 0.2), 0.04)
			e["b"] = maxf(e["b"], aa(ell(u, v, 0.72, 0.82, 0.09, 0.12)))
		12: # sleepy: heavy lids top and bottom, pupil peeking
			lid_top(e, u, v, 0.56)
			lid_bottom(e, u, v, 0.86)
			if v < 0.6: e["b"] = 0.0
	return Color(e["r"], e["g"] * e["r"] if f != 5 else e["g"], e["b"], e["a"])
