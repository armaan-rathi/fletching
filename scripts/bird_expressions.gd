class_name BirdExpressions
extends RefCounted
## Expression state for one bird (design doc: Expressions). Decides the current expression from requests
## using priority + minimum hold time, and exposes what the face should show: eye frames (left, right),
## beak mode, and which floating symbol to pop.
##
## request(name, duration): show `name` for `duration` s (0 = only this frame; call every frame to hold).
## Priority: KO > Stunned > Shocked > Smug > Happy/Sad > Annoyed > Confused > Determined > Focused > Sleepy > Neutral.
## A new expression replaces the current one only if it has >= priority, or the current one has held
## >= MIN_HOLD and expired. KO always wins.

const MIN_HOLD := 0.3

## eyes: [left frame, right frame] (frame 0 = the bird's resting eye); beak: closed/open/clenched/chatter.
const SET := {
	"neutral": {"prio": 0, "eyes": [0, 0], "beak": "closed", "symbol": ""},
	"sleepy": {"prio": 10, "eyes": [12, 12], "beak": "closed", "symbol": "zzz"},
	"focused": {"prio": 50, "eyes": [3, 3], "beak": "closed", "symbol": ""},
	"determined": {"prio": 60, "eyes": [4, 4], "beak": "clenched", "symbol": ""},
	"confused": {"prio": 65, "eyes": [7, 7], "beak": "closed", "symbol": "?"},
	"annoyed": {"prio": 70, "eyes": [6, 6], "beak": "clenched", "symbol": "anger"},
	"sad": {"prio": 75, "eyes": [11, 11], "beak": "closed", "symbol": "sweat"},
	"happy": {"prio": 75, "eyes": [10, 10], "beak": "open", "symbol": "sparkle"},
	"smug": {"prio": 80, "eyes": [8, 13], "beak": "chatter", "symbol": "sparkle"},
	"shocked": {"prio": 90, "eyes": [5, 5], "beak": "open", "symbol": "!"},
	"stunned": {"prio": 95, "eyes": [7, 7], "beak": "open", "symbol": "dizzy"},
	"ko": {"prio": 100, "eyes": [9, 9], "beak": "open", "symbol": "dizzy"},
}

signal changed(name: String)

var current := "neutral"
var _time_in := 0.0
var _until := 0.0   # absolute time the current expression stays requested
var _clock := 0.0

func request(name: String, duration := 0.0) -> void:
	if not SET.has(name):
		return
	var until := _clock + maxf(duration, 0.0) + 0.05
	if name == current:
		_until = maxf(_until, until)
		return
	var p_new: int = SET[name]["prio"]
	var p_cur: int = SET[current]["prio"]
	var cur_done := _clock >= _until and _time_in >= MIN_HOLD
	if name == "ko" or p_new > p_cur or (p_new == p_cur and _time_in >= MIN_HOLD) or cur_done:
		if current == "ko" and name != "ko" and not cur_done:
			return
		_switch_to(name, until)

## Advance time; falls back to neutral when the current expression expires (after its minimum hold).
func update(delta: float) -> void:
	_clock += delta
	_time_in += delta
	if current != "neutral" and _clock >= _until and _time_in >= MIN_HOLD:
		_switch_to("neutral", 0.0)

func clear() -> void:
	_switch_to("neutral", 0.0)

func eyes() -> Array:
	return SET[current]["eyes"]

func beak_mode() -> String:
	return SET[current]["beak"]

func symbol() -> String:
	return SET[current]["symbol"]

func _switch_to(name: String, until: float) -> void:
	current = name
	_until = until
	_time_in = 0.0
	changed.emit(name)
