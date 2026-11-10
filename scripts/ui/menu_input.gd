class_name MenuInput
extends RefCounted
## Turns raw input events into per-device menu actions, so each player can drive their own card in
## character select. Device ids: -1 = keyboard, 0+ = gamepad index.
## Actions: left, right, up, down, accept, back, start.
## Keyboard: arrows / WASD, Enter / Space = accept, Esc / Backspace = back, Enter also = start.
## Gamepad: d-pad or left stick, accept / back by the pad's own labels, Start = start. Buttons are positional
## (SDL3), so a Nintendo pad (Switch) accepts with its A = the RIGHT face button and backs out with B = the
## bottom one; Xbox-style pads accept with the bottom button (A) and back with the right one (B).
## Which layout a pad uses: MatchManager.controller_layout ("auto" detects Nintendo pads by name).

const KEYBOARD := -1
const STICK_ON := 0.6
const STICK_OFF := 0.3

var _stick := {} # pad -> Vector2i last stick direction (for edge detection)

## Returns [device, action] or [] if the event isn't a menu action.
func read(event: InputEvent) -> Array:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_LEFT, KEY_A: return [KEYBOARD, "left"]
			KEY_RIGHT, KEY_D: return [KEYBOARD, "right"]
			KEY_UP, KEY_W: return [KEYBOARD, "up"]
			KEY_DOWN, KEY_S: return [KEYBOARD, "down"]
			KEY_ENTER, KEY_KP_ENTER: return [KEYBOARD, "start"]
			KEY_SPACE: return [KEYBOARD, "accept"]
			KEY_ESCAPE, KEY_BACKSPACE: return [KEYBOARD, "back"]
	elif event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_DPAD_LEFT: return [event.device, "left"]
			JOY_BUTTON_DPAD_RIGHT: return [event.device, "right"]
			JOY_BUTTON_DPAD_UP: return [event.device, "up"]
			JOY_BUTTON_DPAD_DOWN: return [event.device, "down"]
			JOY_BUTTON_A: return [event.device, "back" if is_nintendo(event.device) else "accept"]
			JOY_BUTTON_B: return [event.device, "accept" if is_nintendo(event.device) else "back"]
			JOY_BUTTON_START: return [event.device, "start"]
	elif event is InputEventJoypadMotion and (event.axis == JOY_AXIS_LEFT_X or event.axis == JOY_AXIS_LEFT_Y):
		var pad: int = event.device
		var v := Vector2(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X), Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y))
		var dir := Vector2i.ZERO
		if absf(v.x) > STICK_ON and absf(v.x) >= absf(v.y):
			dir = Vector2i(signi(int(signf(v.x))), 0)
		elif absf(v.y) > STICK_ON:
			dir = Vector2i(0, signi(int(signf(v.y))))
		var last: Vector2i = _stick.get(pad, Vector2i.ZERO)
		if dir == Vector2i.ZERO:
			if v.length() < STICK_OFF:
				_stick[pad] = Vector2i.ZERO
			return []
		if dir == last:
			return []
		_stick[pad] = dir
		if dir.x < 0: return [pad, "left"]
		if dir.x > 0: return [pad, "right"]
		if dir.y < 0: return [pad, "up"]
		return [pad, "down"]
	return []

## Does this pad use Nintendo labels (A on the right, B at the bottom)?
static func is_nintendo(device: int) -> bool:
	# Looked up at runtime (not the autoload identifier) so tool scripts can load this class before autoloads exist.
	var tree := Engine.get_main_loop() as SceneTree
	var mm: Node = tree.root.get_node_or_null("MatchManager") if tree else null
	var layout: String = mm.controller_layout if mm else "auto"
	if layout != "auto":
		return layout == "nintendo"
	var n := Input.get_joy_name(device).to_lower()
	for k in ["nintendo", "switch", "pro controller", "joy-con", "joycon"]:
		if n.contains(k):
			return true
	return false

## Any key / button press at all (title screen).
static func is_any_press(event: InputEvent) -> bool:
	return (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventJoypadButton and event.pressed) \
		or (event is InputEventMouseButton and event.pressed)

## "accept" also counts as "start" for confirming screens.
static func is_confirm(action: String) -> bool:
	return action == "accept" or action == "start"
