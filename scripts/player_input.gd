class_name PlayerInput
extends RefCounted
## Reads one player's input from one device (open question 7: one keyboard player; everyone else on gamepads).
## Bindings come from the project's input map, filtered by device, so remapping actions still works:
##   keyboard = true  -> key / mouse-button events of each action (and mouse aim)
##   joypad >= 0      -> joypad button / axis events of each action, read from that pad only
## A solo tester can have both (keyboard + pad 0). Call poll() once per physics frame.

var keyboard := true
var joypad := 0 ## -1 = no gamepad
## Also read the raw action state (any device). Used by scripted tests that drive Input.action_press().
var include_actions := false

## Test-only forced action strengths (see test_press). Read when include_actions is on.
static var test_forced := {}
## Set by test_press: scripted players then read only the forced actions, so a real gamepad, keyboard or
## mouse near the test window can't nudge them (stick drift made Stage 5 checks flaky).
static var test_mode := false

var _now := {}
var _prev := {}

func _init(use_keyboard := true, pad := 0) -> void:
	keyboard = use_keyboard
	joypad = pad

func uses_mouse() -> bool:
	return keyboard and not (test_mode and include_actions)

func poll() -> void:
	_prev = _now
	_now = {}
	for a in ["shoot", "dash", "melee", "shrike"]:
		_now[a] = strength(a) > 0.5

## Action strength 0..1 from this player's device(s) only.
func strength(action: String) -> float:
	if not InputMap.has_action(action):
		return 0.0
	if test_mode and include_actions:
		return test_forced.get(action, 0.0)
	var dz := InputMap.action_get_deadzone(action)
	var best := maxf(Input.get_action_strength(action), test_forced.get(action, 0.0)) if include_actions else 0.0
	for e in InputMap.action_get_events(action):
		if keyboard and e is InputEventKey:
			if Input.is_physical_key_pressed(e.physical_keycode) or (e.keycode != KEY_NONE and Input.is_key_pressed(e.keycode)):
				best = 1.0
		elif keyboard and e is InputEventMouseButton:
			if Input.is_mouse_button_pressed(e.button_index):
				best = 1.0
		elif joypad >= 0 and e is InputEventJoypadButton:
			if Input.is_joy_button_pressed(joypad, e.button_index):
				best = 1.0
		elif joypad >= 0 and e is InputEventJoypadMotion:
			var v := Input.get_joy_axis(joypad, e.axis) * signf(e.axis_value)
			if v > dz:
				best = maxf(best, (v - dz) / (1.0 - dz))
	return best

func _vector(neg_x: String, pos_x: String, neg_y: String, pos_y: String) -> Vector2:
	var v := Vector2(strength(pos_x) - strength(neg_x), strength(pos_y) - strength(neg_y))
	return v.limit_length(1.0)

## 2D vectors use screen axes: x = right, y = down (toward the camera, +Z in the world).
func get_move() -> Vector2:
	return _vector("move_left", "move_right", "move_up", "move_down")

func get_aim_stick() -> Vector2:
	return _vector("aim_left", "aim_right", "aim_up", "aim_down")

func shoot_pressed() -> bool:
	return _now.get("shoot", false) and not _prev.get("shoot", false)

func shoot_held() -> bool:
	return _now.get("shoot", false)

func dash_pressed() -> bool:
	return _now.get("dash", false) and not _prev.get("dash", false)

func shrike_pressed() -> bool:
	return _now.get("shrike", false) and not _prev.get("shrike", false)

func shrike_held() -> bool:
	return _now.get("shrike", false)

func melee_pressed() -> bool:
	return _now.get("melee", false) and not _prev.get("melee", false)

## Controller rumble on this player's pad (no-op for keyboard-only players and in tests).
func rumble(weak: float, strong: float, duration: float) -> void:
	if joypad >= 0 and not test_mode:
		Input.start_joy_vibration(joypad, weak, strong, duration)

## Any input at all this frame (for the sleepy timer).
func active() -> bool:
	return get_move().length() > 0.2 or get_aim_stick().length() > 0.35 or shoot_held() or _now.get("dash", false) or _now.get("melee", false) or _now.get("shrike", false)

## Scripted tests: press / release an action in a way a window focus change can't undo.
static func test_press(action: String) -> void:
	test_mode = true
	test_forced[action] = 1.0
	Input.action_press(action)

static func test_release(action: String) -> void:
	test_forced.erase(action)
	Input.action_release(action)

static func to_world(v: Vector2) -> Vector3:
	return Vector3(v.x, 0.0, v.y)
