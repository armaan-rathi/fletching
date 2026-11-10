extends CanvasLayer
## Playtest overlay: controls cheat-sheet, current bird and quiver count. No function keys
## (they clash with the editor / macOS): H help, T reload tuning, R restart, B / N next / previous bird, V variant,
## E preview the next expression, G preview the next animation clip (slap, squawk, victory, KO).

var _label: Label
var _style_label: Label
var _style_t := 0.0
var _birds: Array[BirdData] = []
var _expr_i := -1
var _clip_i := -1
var _preview := ""
const EXPRESSIONS := ["focused", "determined", "shocked", "annoyed", "confused", "smug", "ko", "happy", "sad", "sleepy"]
const CLIPS := ["slap", "squawk", "victory", "ko"]

func _ready() -> void:
	_birds = BirdData.load_all()
	ArtStyle.apply.call_deferred() # a reloaded scene brings a fresh Environment (anime glow) and camera
	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color("fff6e0"))
	_label.add_theme_color_override("font_outline_color", Color("2a2233"))
	_label.add_theme_constant_override("outline_size", 6)
	add_child(_label)
	_label.visible = false # dev overlay: H toggles it
	_style_label = Label.new()
	_style_label.add_theme_font_override("font", UiKit.font(0.7))
	_style_label.add_theme_font_size_override("font_size", 30)
	_style_label.add_theme_color_override("font_color", Color("ffd27a"))
	_style_label.add_theme_color_override("font_outline_color", Color("2a2233"))
	_style_label.add_theme_constant_override("outline_size", 10)
	_style_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_style_label.offset_left = -500
	_style_label.offset_right = 500
	_style_label.offset_top = -120
	_style_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label.modulate.a = 0.0
	add_child(_style_label)
	var hint := Label.new()
	hint.text = "H  help"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(12, -26)
	add_child(hint)

func _player() -> Bird:
	for b in get_tree().get_nodes_in_group("birds"):
		if b.player_index == 0:
			return b
	return null

func _process(delta: float) -> void:
	if _style_t > 0.0:
		_style_t -= delta
		_style_label.modulate.a = clampf(_style_t / 0.5, 0.0, 1.0)
	var b := _player()
	var arrows := "-"
	var who := ""
	if b:
		arrows = "●".repeat(b.arrows) + "○".repeat(b.t.quiver_size - b.arrows)
		if b.bird_data:
			who = "%s · %s" % [b.bird_data.display_name, b.bird_data.variant(b.variant).get("name", "")]
	_label.text = "%s\nArrows %s\n\nMove  WASD / left stick\nAim  mouse / right stick (or move keys while drawing)\nDraw + shoot  hold LMB / Space / R, ZR or X (Switch), release\nDash  Shift / B (Switch)\nMelee  RMB / F / A (Switch) (stuns; time it to bat arrows away)\nShrike  Q / MMB / L, ZL or Y (Switch) (aim + charge set where it lands; nudge it with move)\nStyle (exploration): U cycle both (Shift = back) · Y birds only · P world only · O style option · I tilt-shift\nH help · B / N bird · V colors · E expression · G animation · T reload tuning\nMatch: R restart · quick-play: C CPUs (%d) · K CPU level (%s) · J %s" % [who, arrows, MatchManager.cpu_count, MatchManager.cpu_difficulty, "keyboard and pad 0 are separate players" if MatchManager.split_devices else "P1 = keyboard + pad 0"] + (("\nPreview: " + _preview) if _preview != "" else "")

## New match with the current quick-play settings (players are re-detected from connected pads).
func _restart() -> void:
	MatchManager.setup_quick_play()
	get_tree().reload_current_scene()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var b := _player()
	match event.physical_keycode:
		KEY_H:
			_label.visible = not _label.visible
		KEY_U:
			ArtStyle.cycle(-1 if event.shift_pressed else 1)
			_show_style()
		KEY_Y:
			ArtStyle.cycle_char(-1 if event.shift_pressed else 1)
			_show_style()
		KEY_P:
			ArtStyle.cycle_env(-1 if event.shift_pressed else 1)
			_show_style()
		KEY_O:
			ArtStyle.toggle_option()
			_show_style()
		KEY_I:
			ArtStyle.toggle_tilt_shift()
			_show_style()
		KEY_T:
			Tuning.reload()
			print("tuning.tres reloaded")
		KEY_R:
			get_tree().reload_current_scene() # same players and settings
		KEY_C:
			MatchManager.cpu_count = wrapi(MatchManager.cpu_count + 1, 0, 4)
			_restart()
		KEY_K:
			var i := MatchManager.DIFFICULTIES.find(MatchManager.cpu_difficulty)
			MatchManager.cpu_difficulty = MatchManager.DIFFICULTIES[wrapi(i + 1, 0, MatchManager.DIFFICULTIES.size())]
			_restart()
		KEY_J:
			MatchManager.split_devices = not MatchManager.split_devices
			_restart()
		KEY_B, KEY_N:
			if b and _birds.size() > 0:
				var i := maxi(_birds.find(b.bird_data), 0)
				i = wrapi(i + (1 if event.physical_keycode == KEY_B else -1), 0, _birds.size())
				b.set_bird(_birds[i], 0)
		KEY_V:
			if b and b.bird_data:
				b.set_bird(b.bird_data, wrapi(b.variant + 1, 0, maxi(b.bird_data.variants.size(), 1)))
		KEY_E:
			if b:
				_expr_i = wrapi(_expr_i + 1, 0, EXPRESSIONS.size())
				_preview = "expression " + EXPRESSIONS[_expr_i]
				b.model.expressions.request(EXPRESSIONS[_expr_i], 2.0)
		KEY_G:
			if b:
				_clip_i = wrapi(_clip_i + 1, 0, CLIPS.size())
				var clip: String = CLIPS[_clip_i]
				_preview = "animation " + clip
				if clip in ["victory", "ko"]:
					b.pose_override = clip # held until any input
				else:
					b.model.play_once(clip)

func _show_style() -> void:
	_style_label.text = "Style: " + ArtStyle.label()
	_style_t = 2.0
	_style_label.modulate.a = 1.0
