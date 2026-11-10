extends Control
## Character select: up to 4 players join with their own device (keyboard: Space/Enter, gamepad: A/Start),
## pick a bird (left/right), accept, then pick its color (left/right; the bird is locked in), accept to ready up.
## Back steps back one stage (ready -> color -> bird -> leave). Up/down also change the color while picking it.
## When everyone who joined is ready, Start/Enter (or accept again) goes to the game settings.
## Two players can pick the same bird but never the same bird + color.

const BIRD := preload("res://scenes/birds/bird.tscn")
const SETTINGS := "res://scenes/ui/settings.tscn"
const TITLE := "res://scenes/ui/title.tscn"

class NullInput extends RefCounted:
	func uses_mouse() -> bool: return false
	func poll() -> void: pass
	func get_move() -> Vector2: return Vector2.ZERO
	func get_aim_stick() -> Vector2: return Vector2.ZERO
	func shoot_pressed() -> bool: return false
	func melee_pressed() -> bool: return false
	func shrike_pressed() -> bool: return false
	func shrike_held() -> bool: return false
	func shoot_held() -> bool: return false
	func dash_pressed() -> bool: return false
	func active() -> bool: return false

class Card extends RefCounted:
	var index := 0
	var joined := false
	var device := 0          # MenuInput.KEYBOARD (-1) or pad index
	var bird := 0
	var variant := 0
	var ready := false
	var picking_color := false # bird locked in; left/right change the color
	var root: PanelContainer
	var header: Label
	var name_label: Label
	var blurb: Label
	var color_label: Label
	var swatches: HBoxContainer
	var status: Label
	var preview: SubViewportContainer
	var preview_bird: Bird
	var join_hint: Label

var _flock: Array[BirdData] = []
var _cards: Array[Card] = []
var _menu := MenuInput.new()
var _footer: Label
var _leaving := false

func _ready() -> void:
	_flock = BirdData.load_all()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("33553a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var leaves := Control.new()
	leaves.set_script(load("res://scripts/ui/leaf_drift.gd"))
	add_child(leaves)
	var title := UiKit.label("Choose your bird", 54, UiKit.TEXT, 0.9)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-400, 28)
	title.custom_minimum_size = Vector2(800, 0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_CENTER)
	row.position = Vector2(-760, -330)
	row.custom_minimum_size = Vector2(1520, 640)
	row.add_theme_constant_override("separation", 20)
	add_child(row)
	for i in MatchManager.MAX_PLAYERS:
		var c := _make_card(i)
		row.add_child(c.root)
		_cards.append(c)
	_footer = UiKit.label("", 30, UiKit.WARM, 0.7)
	_footer.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_footer.position = Vector2(-600, -70)
	_footer.custom_minimum_size = Vector2(1200, 0)
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_footer)
	# Coming back from settings / a match: restore everyone's picks.
	for h in MatchManager.humans:
		var c := _free_card()
		if c:
			_join(c, MenuInput.KEYBOARD if h["keyboard"] else h["joypad"])
			c.bird = maxi(_flock.map(func(d): return d.id).find(h["bird_id"]), 0)
			c.variant = h["variant"]
			_refresh(c)
	_update_footer()

func _make_card(i: int) -> Card:
	var c := Card.new()
	c.index = i
	var col: Color = MatchManager.PLAYER_COLORS[i]
	c.root = UiKit.panel(col, UiKit.BG)
	c.root.custom_minimum_size = Vector2(365, 640)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	c.root.add_child(v)
	c.header = UiKit.label("P%d" % (i + 1), 34, col.lerp(Color.WHITE, 0.2), 0.9)
	c.header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(c.header)

	c.preview = SubViewportContainer.new()
	c.preview.custom_minimum_size = Vector2(325, 300)
	c.preview.stretch = true
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_2X
	c.preview.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.BLACK
	env.environment.ambient_light_energy = 0.0
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("ffe6b0")
	sun.rotation_degrees = Vector3(-40, -60, 0)
	world.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 28.0
	cam.position = Vector3(0, 1.05, 3.6)
	cam.rotation_degrees.x = -8.0
	world.add_child(cam)
	c.preview_bird = BIRD.instantiate()
	c.preview_bird.player_color = col
	c.preview_bird.input = NullInput.new()
	world.add_child(c.preview_bird)
	c.preview_bird.frozen = true
	c.preview_bird.facing = PI * 0.82
	v.add_child(c.preview)

	c.join_hint = UiKit.label("Press\nSpace / Enter\nor (A) to join", 30, UiKit.TEXT_DIM, 0.6)
	c.join_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.join_hint.custom_minimum_size = Vector2(0, 300)
	c.join_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.add_child(c.join_hint)

	c.name_label = UiKit.label("", 34, UiKit.TEXT, 0.8)
	c.name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(c.name_label)
	c.blurb = UiKit.label("", 20, UiKit.TEXT_DIM, 0.3, false)
	c.blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(c.blurb)
	c.swatches = HBoxContainer.new()
	c.swatches.alignment = BoxContainer.ALIGNMENT_CENTER
	c.swatches.add_theme_constant_override("separation", 10)
	v.add_child(c.swatches)
	c.color_label = UiKit.label("", 20, UiKit.TEXT_DIM, 0.4, false)
	c.color_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(c.color_label)
	c.status = UiKit.label("", 26, UiKit.WARM, 0.8)
	c.status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(c.status)
	_refresh(c)
	return c

func _free_card() -> Card:
	for c in _cards:
		if not c.joined:
			return c
	return null

func _card_for(device: int) -> Card:
	for c in _cards:
		if c.joined and c.device == device:
			return c
	return null

func _join(c: Card, device: int) -> void:
	c.joined = true
	c.device = device
	c.ready = false
	c.picking_color = false
	c.bird = c.index % _flock.size()
	c.variant = 0
	_fix_variant(c, 1)
	_refresh(c)
	UiKit.pop(c.root, 0.06)

func _input(event: InputEvent) -> void:
	if _leaving:
		return
	var a := _menu.read(event)
	if a.is_empty():
		return
	var device: int = a[0]
	var action: String = a[1]
	var c := _card_for(device)
	if c == null:
		if MenuInput.is_confirm(action):
			var free := _free_card()
			if free:
				_join(free, device)
				Sfx.play("ui_join")
		elif action == "back" and _joined_count() == 0:
			Sfx.play("ui_back")
			_leave(TITLE)
		_update_footer()
		return
	match action:
		"left", "right", "up", "down":
			if c.ready:
				pass
			elif c.picking_color:
				var step := 1 if action in ["right", "down"] else -1
				c.variant = wrapi(c.variant + step, 0, 4)
				_fix_variant(c, step)
				_refresh(c, true)
				Sfx.play("ui_change")
			elif action in ["left", "right"]:
				c.bird = wrapi(c.bird + (1 if action == "right" else -1), 0, _flock.size())
				c.variant = 0
				_fix_variant(c, 1)
				_refresh(c, true)
				Sfx.play("ui_move")
		"accept", "start":
			if c.ready and _all_ready():
				Sfx.play("ui_confirm")
				_continue()
				return
			if not c.picking_color and not c.ready:
				c.picking_color = true # bird chosen: now its color
				_refresh(c)
				_celebrate(c)
				UiKit.pop(c.color_label, 0.15)
				Sfx.play("ui_confirm")
			elif not c.ready:
				c.ready = true
				c.picking_color = false
				c.preview_bird.pose_override = "victory"
				c.preview_bird.model.squawk()
				_refresh(c)
				UiKit.pop(c.root, 0.05)
				Sfx.play("ui_ready")
		"back":
			Sfx.play("ui_back")
			if c.ready:
				c.ready = false
				c.picking_color = true
				c.preview_bird.pose_override = ""
				_refresh(c)
			elif c.picking_color:
				c.picking_color = false
				c.preview_bird.pose_override = ""
				_refresh(c)
			else:
				c.joined = false
				_refresh(c)
	_update_footer()

## Skip colors another player already has on the same bird.
func _fix_variant(c: Card, step: int) -> void:
	for i in 4:
		var taken := false
		for o in _cards:
			if o != c and o.joined and o.bird == c.bird and o.variant == c.variant:
				taken = true
		if not taken:
			return
		c.variant = wrapi(c.variant + step, 0, 4)

func _refresh(c: Card, changed := false) -> void:
	c.preview.visible = c.joined
	c.join_hint.visible = not c.joined
	c.name_label.visible = c.joined
	c.blurb.visible = c.joined
	c.swatches.visible = c.joined
	c.color_label.visible = c.joined
	if not c.joined:
		c.status.text = ""
		c.header.text = "P%d" % (c.index + 1)
		return
	var d := _flock[c.bird]
	c.header.text = "P%d  ·  %s" % [c.index + 1, "Keyboard" if c.device == MenuInput.KEYBOARD else "Pad %d" % (c.device + 1)]
	var picking_bird := not c.ready and not c.picking_color
	c.name_label.text = "◀  %s  ▶" % d.display_name if picking_bird else d.display_name
	c.blurb.text = d.blurb
	var cname: String = d.variant(c.variant).get("name", "")
	c.color_label.text = "◀  %s  ▶" % cname if c.picking_color else cname
	c.color_label.add_theme_color_override("font_color", UiKit.WARM if c.picking_color else UiKit.TEXT)
	for s in c.swatches.get_children():
		s.queue_free()
	for vi in 4:
		var sw := Panel.new()
		var on := vi == c.variant
		sw.custom_minimum_size = Vector2(34, 34) if on else Vector2(24, 24)
		sw.add_theme_stylebox_override("panel", UiKit.panel_style(Color.WHITE if on else UiKit.INK, d.variant(vi).get("body", Color.GRAY), 17, 3))
		c.swatches.add_child(sw)
	c.status.text = "READY!" if c.ready else ("(A) / Space  ready" if c.picking_color else "(A) / Space  pick color")
	c.preview_bird.set_bird(d, c.variant)
	if changed:
		_react(c)
		UiKit.pop(c.name_label, 0.15)

const REACTIONS := ["happy", "smug", "shocked", "confused", "determined", "annoyed", "focused", "sad"]

## Scrolling birds / colors: the preview bird pulls a random face and does a little something.
func _react(c: Card) -> void:
	var b := c.preview_bird
	b.model.expressions.request(REACTIONS[randi() % REACTIONS.size()], 1.2)
	match randi() % 4:
		0: b.model.squawk()
		1: b.visual.hop(2.4)
		2: b.visual.kick(1.0)
		3:
			b.model.head_yaw_target = randf_range(-0.5, 0.5)
			get_tree().create_timer(0.8).timeout.connect(func(): if is_instance_valid(b): b.model.head_yaw_target = 0.0)

## Locking in a bird: it does its own match-win celebration (BirdData.victory_style).
func _celebrate(c: Card) -> void:
	c.preview_bird.model.head_yaw_target = 0.0
	c.preview_bird.celebrate()

func _joined_count() -> int:
	return _cards.filter(func(c): return c.joined).size()

func _all_ready() -> bool:
	return _joined_count() > 0 and _cards.all(func(c): return not c.joined or c.ready)

func _update_footer() -> void:
	if _joined_count() == 0:
		_footer.text = "Press Space / Enter or (A) to join   ·   Esc / (B) back"
	elif _all_ready():
		_footer.text = "Everyone's ready!  Press Start / Enter"
	else:
		_footer.text = "◀ ▶ bird, then (A) / Space   ◀ ▶ color, then (A) / Space ready   (B) / Esc back"

func _continue() -> void:
	MatchManager.humans.clear()
	for c in _cards:
		if c.joined:
			MatchManager.humans.append({"keyboard": c.device == MenuInput.KEYBOARD, "joypad": c.device if c.device >= 0 else -1,
				"bird_id": _flock[c.bird].id, "variant": c.variant})
	_leave(SETTINGS)

func _leave(path: String) -> void:
	_leaving = true
	UiKit.go_to(get_tree(), path)
