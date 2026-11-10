extends Node
## Spawns power-ups on the map's fixed pads while a round is being played (if power-ups are on in the
## settings): the first after `powerup_first_delay`, then every `powerup_interval_min..max` seconds, at most
## `powerup_max_active` on the field, on a random free pad. Pads are cleared at the start of each round.

@export var rounds_path := NodePath("../RoundController")

var _timer := 0.0
var _rc: Node
var _t: Tuning

func _ready() -> void:
	_t = Tuning.get_default()
	_rc = get_node_or_null(rounds_path)
	reset()
	if not MatchManager.power_ups:
		for p in get_tree().get_nodes_in_group("power_up_pads"):
			p.visible = false

func reset() -> void:
	_timer = _t.powerup_first_delay
	for p in get_tree().get_nodes_in_group("power_up_pads"):
		p.clear()

func _process(delta: float) -> void:
	if not MatchManager.power_ups or _rc == null:
		return
	if _rc.phase != _rc.Phase.PLAYING and _rc.phase != _rc.Phase.PRACTICE:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = randf_range(_t.powerup_interval_min, _t.powerup_interval_max)
	var pads := get_tree().get_nodes_in_group("power_up_pads")
	var free := pads.filter(func(p): return p.item == "")
	if pads.size() - free.size() >= _t.powerup_max_active or free.is_empty():
		return
	free.pick_random().spawn(PowerUps.ids().pick_random())
