class_name AnimeSymbol
extends Node3D
## A floating anime symbol beside a bird's head (design doc: Expressions). Always drawn on top, billboarded.
## Life: grows into existence (elastic overshoot + a little twist), does its own bit of character, then
## shrinks away by itself after a short hold (Tuning: symbol_grow_time, symbol_life) or when dismissed.
## Kinds and their bit:
##   anger   - double throb (two quick pulses) with a jitter, like a popping vein
##   !       - jumps up with a stretch, then a quick side-to-side shake
##   ?       - slow head-tilt rock
##   sweat   - slides down the side of the head like a drip
##   sparkle - twinkles (fast spin + pulses)
##   dizzy   - circles (KO); stays a little longer
##   zzz     - drifts up; stays while the bird is sleepy

const ICONS := {
	"sweat": preload("res://assets/vfx/symbols/ph_sweat.png"),
	"anger": preload("res://assets/vfx/symbols/ph_anger.png"),
	"sparkle": preload("res://assets/vfx/symbols/ph_sparkle.png"),
	"dizzy": preload("res://assets/vfx/symbols/ph_dizzy.png"),
}
const TEXT_COLORS := {"!": Color("ffd23f"), "?": Color("8fd8ff"), "zzz": Color("c9b8ff")}
const SIZE := 0.38 ## m on screen-ish
const OUT_TIME := 0.18
## Lifetime multipliers per kind (x Tuning.symbol_life); 0 = until dismissed.
const LIFE := {"dizzy": 2.2, "zzz": 0.0}

var kind := ""
var _t := 0.0
var _out := -1.0
var _life := 1.1
var _grow := 0.28
var _visual: Node3D

static func create(symbol_kind: String) -> AnimeSymbol:
	var s := AnimeSymbol.new()
	s.kind = symbol_kind
	return s

func _ready() -> void:
	var tune := Tuning.get_default()
	_grow = tune.symbol_grow_time
	_life = tune.symbol_life * float(LIFE.get(kind, 1.0))
	if ICONS.has(kind):
		var sp := Sprite3D.new()
		sp.texture = ICONS[kind]
		sp.pixel_size = SIZE / 128.0
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.no_depth_test = true
		sp.shaded = false
		sp.render_priority = 10
		sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_visual = sp
	else:
		var lb := Label3D.new()
		lb.text = kind
		lb.font_size = 96
		lb.outline_size = 22
		lb.pixel_size = SIZE / 110.0
		lb.modulate = TEXT_COLORS.get(kind, Color.WHITE)
		lb.outline_modulate = Color("2a2233")
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.no_depth_test = true
		lb.render_priority = 10
		lb.outline_render_priority = 9
		_visual = lb
	add_child(_visual)
	scale = Vector3.ONE * 0.01

func dismiss() -> void:
	if _out < 0.0:
		_out = 0.0

func is_leaving() -> bool:
	return _out >= 0.0

func _process(delta: float) -> void:
	_t += delta
	if _out < 0.0 and _life > 0.0 and _t >= _life:
		dismiss()
	var s := _grow_in(_t / _grow)
	var pos := Vector3.ZERO
	var rot := (1.0 - clampf(_t / _grow, 0.0, 1.0)) * -0.5 # untwists as it grows
	var sx := 1.0
	var sy := 1.0
	var a := _t - _grow # time since fully grown
	match kind:
		"anger":
			# Two quick throbs, then a smaller one now and then.
			s *= 1.0 + _throb(a, 0.0) * 0.35 + _throb(a, 0.16) * 0.28 + _throb(fmod(maxf(a, 0.0), 0.7), 0.55) * 0.12
			pos.x = sin(_t * 70.0) * 0.012 * clampf(1.0 - a * 2.0, 0.0, 1.0)
		"!":
			var j := clampf(a / 0.12, 0.0, 1.0)
			pos.y = sin(j * PI) * 0.12
			sy = 1.0 + sin(j * PI) * 0.25
			sx = 1.0 - sin(j * PI) * 0.12
			rot += sin(maxf(a - 0.12, 0.0) * 45.0) * 0.18 * clampf(1.0 - (a - 0.12) * 3.0, 0.0, 1.0) * (1.0 if a > 0.12 else 0.0)
		"?":
			rot += sin(_t * 4.0) * 0.25
			pos.y = sin(_t * 4.0) * 0.02
		"sweat":
			pos.y = -0.12 * clampf(a / 0.8, 0.0, 1.0)
			sy = 1.0 + 0.1 * clampf(a / 0.8, 0.0, 1.0)
		"sparkle":
			rot += _t * 4.0
			s *= 1.0 + 0.15 * absf(sin(_t * 9.0))
		"dizzy":
			rot += _t * 3.0
			pos.y = sin(_t * 5.0) * 0.03
		"zzz":
			pos.y = fmod(_t * 0.25, 0.15)
		_:
			pos.y = sin(_t * 5.0) * 0.03
	var fade := 1.0
	if _out >= 0.0:
		_out += delta
		var k := clampf(_out / OUT_TIME, 0.0, 1.0)
		# Quick anticipation bump, then shrink and fade.
		s *= (1.0 + 0.15 * sin(k * PI)) * (1.0 - k * k)
		fade = 1.0 - k
		pos.y += k * 0.06
		if _out >= OUT_TIME:
			queue_free()
			return
	scale = Vector3(sx, sy, 1.0) * maxf(s, 0.01)
	_visual.position = pos
	_visual.rotation.z = rot
	_visual.modulate.a = fade
	if _visual is Label3D:
		(_visual as Label3D).outline_modulate.a = fade

## Grow with one overshoot (ease-out-back), u 0..1: 0 -> ~1.18 -> 1.
static func _grow_in(u: float) -> float:
	if u <= 0.0:
		return 0.0
	if u >= 1.0:
		return 1.0
	const C1 := 2.5
	var v := u - 1.0
	return 1.0 + (C1 + 1.0) * v * v * v + C1 * v * v

## One quick pulse (0 -> 1 -> 0 over 0.12 s) starting at `at`.
static func _throb(t: float, at: float) -> float:
	var u := (t - at) / 0.12
	return sin(u * PI) if u > 0.0 and u < 1.0 else 0.0
