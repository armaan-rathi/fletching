extends Node3D
## Title screen: the clearing with birds bouncing around, a bouncy logo, "Press any button".
## Any key / button / click goes to character select.

const BIRD := preload("res://scenes/birds/bird.tscn")
const NEXT := "res://scenes/ui/character_select.tscn"

## Birds on the title wander, hop, dash and squawk now and then. Never shoot.
class WanderInput extends RefCounted:
	var bird: Bird
	var _move := Vector2.ZERO
	var _timer := 0.0
	var _dash := false
	var _rng := RandomNumberGenerator.new()
	func _init(b: Bird) -> void:
		bird = b
		_rng.randomize()
		_timer = _rng.randf_range(0.0, 1.5)
	func uses_mouse() -> bool: return false
	func get_move() -> Vector2: return _move
	func get_aim_stick() -> Vector2: return Vector2.ZERO
	func shoot_pressed() -> bool: return false
	func melee_pressed() -> bool: return false
	func shrike_pressed() -> bool: return false
	func shrike_held() -> bool: return false
	func shoot_held() -> bool: return false
	func dash_pressed() -> bool: return _dash
	func active() -> bool: return true
	func poll() -> void:
		_dash = false
		_timer -= bird.get_physics_process_delta_time()
		if _timer > 0.0:
			return
		_timer = _rng.randf_range(0.6, 2.2)
		var roll := _rng.randf()
		if roll < 0.3:
			_move = Vector2.ZERO
			if _rng.randf() < 0.5:
				bird.model.squawk()
			else:
				bird.pose_override = "victory"
		else:
			var target := Vector2(_rng.randf_range(-8, 8), _rng.randf_range(-1, 5.5))
			var here := Vector2(bird.global_position.x, bird.global_position.z)
			_move = (target - here).normalized() * _rng.randf_range(0.5, 1.0)
			_dash = _rng.randf() < 0.15

var _ui: CanvasLayer
var _letters: Array[Label] = []
var _prompt: Label
var _time := 0.0
var _leaving := false

func _ready() -> void:
	var flock := BirdData.load_all()
	flock.shuffle()
	for i in 6:
		var b: Bird = BIRD.instantiate()
		b.bird_data = flock[i % flock.size()]
		b.variant = randi() % 4
		b.player_color = MatchManager.PLAYER_COLORS[i % 4]
		b.input = WanderInput.new(b)
		add_child(b)
		b.reset_for_round(Vector3(randf_range(-7, 7), 0, randf_range(0.5, 5.0)), randf_range(-PI, PI))
		b.ring.visible = false
	_build_ui()

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.position = Vector2(-500, 150)
	box.custom_minimum_size = Vector2(1000, 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	_ui.add_child(box)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 2)
	box.add_child(row)
	var colors := [Color("ff5a5a"), Color("ffd27a"), Color("4da6ff"), Color("ffd23f"), Color("b57bff"), Color("ff8fb1"), Color("8dd96a"), Color("ff5a5a"), Color("4da6ff")]
	var word := "FLETCHING"
	for i in word.length():
		var l := UiKit.label(word[i], 120, colors[i % colors.size()], 1.0)
		l.add_theme_constant_override("outline_size", 26)
		row.add_child(l)
		_letters.append(l)
	var sub := UiKit.label("Last bird standing gets the worm", 30, UiKit.TEXT, 0.5)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	_prompt = UiKit.label("Press any button", 36, UiKit.WARM, 0.7)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-300, -170)
	_prompt.custom_minimum_size = Vector2(600, 0)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui.add_child(_prompt)
	var editor_hint := UiKit.label("E  Level editor", 24, UiKit.TEXT_DIM, 0.5)
	editor_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	editor_hint.position = Vector2(-260, -60)
	_ui.add_child(editor_hint)

func _process(delta: float) -> void:
	_time += delta
	for i in _letters.size():
		var l := _letters[i]
		l.pivot_offset = l.size * 0.5
		var t := _time * 3.0 - i * 0.45
		l.position.y = -absf(sin(t)) * 14.0
		l.rotation = sin(t * 0.5) * 0.05
	_prompt.modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(_time * 4.0))

func _input(event: InputEvent) -> void:
	if not _leaving and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		_leaving = true
		Sfx.play("ui_confirm")
		MatchManager.editor_session = {}
		UiKit.go_to(get_tree(), MatchManager.EDITOR_SCENE)
		return
	if not _leaving and MenuInput.is_any_press(event):
		_leaving = true
		Sfx.play("ui_confirm")
		UiKit.pop(_prompt, 0.2)
		UiKit.go_to(get_tree(), NEXT)
