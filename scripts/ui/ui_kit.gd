class_name UiKit
extends RefCounted
## Shared UI look and helpers (doc: UI Style — sleek and clean with a playful touch: crisp layouts, rounded
## corners, bold readable font, subtle bounce on selections, player-colored accents).
## Font: Godot's built-in font, emboldened via FontVariation (no external font yet; see CREDITS.md).

const BG := Color(0.11, 0.09, 0.15, 0.88)
const BG_SOFT := Color(0.16, 0.13, 0.21, 0.82)
const INK := Color("2a2233")
const TEXT := Color("fff6e0")
const TEXT_DIM := Color("cbbfa8")
const WARM := Color("ffd27a")

static var _fonts := {}

## Bold display font (weight 0..1).
static func font(weight := 0.6) -> Font:
	var key := snappedf(weight, 0.1)
	if not _fonts.has(key):
		var f := FontVariation.new()
		f.base_font = ThemeDB.fallback_font
		f.variation_embolden = key
		_fonts[key] = f
	return _fonts[key]

static func label(text: String, size := 24, color := TEXT, weight := 0.5, outline := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline:
		l.add_theme_color_override("font_outline_color", INK)
		l.add_theme_constant_override("outline_size", maxi(size / 6, 4))
	return l

static func panel_style(border := Color(1, 1, 1, 0.12), bg := BG, radius := 18, border_w := 3) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 4)
	return sb

static func panel(border := Color(1, 1, 1, 0.12), bg := BG) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(border, bg))
	return p

## Little scale bounce (selection changed, button pressed). Pivot is set to the control's center.
static func pop(c: Control, amount := 0.12, time := 0.18) -> void:
	if c == null or not c.is_inside_tree():
		return
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2.ONE * (1.0 + amount), time * 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2.ONE, time * 0.6).set_trans(Tween.TRANS_SINE)

# --- Scene transitions ------------------------------------------------------------------

## Fades to black, then changes scene. The new scene calls fade_in() in its _ready.
static func go_to(tree: SceneTree, path: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var rect := ColorRect.new()
	rect.color = Color(INK, 0.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	tree.root.add_child(layer)
	var tw := layer.create_tween()
	tw.tween_property(rect, "color:a", 1.0, 0.22)
	tw.tween_callback(func():
		tree.paused = false
		tree.change_scene_to_file(path)
		var tw2 := layer.create_tween()
		tw2.tween_interval(0.05)
		tw2.tween_property(rect, "color:a", 0.0, 0.25)
		tw2.tween_callback(layer.queue_free))
