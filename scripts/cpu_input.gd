class_name CpuInput
extends RefCounted
## CPU "player": a small state machine that drives a Bird through the same interface as PlayerInput
## (get_move / get_aim_stick / shoot_* / dash_pressed). Behavior per difficulty comes from
## Tuning.cpu_profiles (easy / normal / hard):
##   - pick the nearest living enemy; keep a comfortable range; strafe around cover for line of sight
##   - draw for a random charge time, aiming with lead and a per-shot error; hard CPUs curve shots around cover
##   - dash away from incoming arrows (chance + reaction delay)
##   - melee: wing-slap (stun) enemies that get close, then shoot them point-blank
##   - bat incoming arrows away with a timed melee (chance + timing jitter per difficulty)
##   - when empty: collect the nearest stuck arrow
##   - patience: a CPU that hasn't attacked for a while (cpu_patience) goes hunting: no power-up detours or
##     range-keeping, walks the clear direction that closes in on its target, shoots at any range it can reach
##     and lobs over cover. Fixes the playtest stall (two CPUs pacing back and forth out of each other's sight).

var bird: Bird
var difficulty := "normal"
var p: Dictionary

var _move := Vector2.ZERO
var _aim := Vector2.ZERO
var _shoot := false
var _shoot_prev := false
var _dash := false
var _melee := false
var _shrike := false
var _shrike_prev := false
var _shrike_steer := 0.0 # s left steering our airborne shrike onto the target
var _parry_in := -1.0
var _parry_dir := Vector3.ZERO
var _think := 0.0
var _draw_for := 0.0
var _draw_target := 0.0
var _aim_error := 0.0
var _curve_side := 0.0
var _curve_left := 0.0
var _strafe := 1.0
var _dodge_in := -1.0
var _dodge_dir := Vector3.ZERO
var _seen_arrows := {}
var _target: Bird
var _rng := RandomNumberGenerator.new()
var _idle := 0.0 # s since this CPU last attacked (shot, lob, slap)
var _strafe_hold := 0.0 # s before the strafe direction may flip again
var last_branch := "" # debug: what the last decision was (stall diagnosis in tools/sim_stall.gd)

func _init(b: Bird, diff := "normal") -> void:
	bird = b
	difficulty = diff
	p = Tuning.get_default().cpu_profiles.get(diff, Tuning.get_default().cpu_profiles["normal"])
	_rng.randomize()
	_strafe = 1.0 if _rng.randf() < 0.5 else -1.0

# --- PlayerInput interface -----------------------------------------------------------

func uses_mouse() -> bool:
	return false

func get_move() -> Vector2:
	return _move

func get_aim_stick() -> Vector2:
	return _aim

func shoot_pressed() -> bool:
	return _shoot and not _shoot_prev

func shoot_held() -> bool:
	return _shoot

func dash_pressed() -> bool:
	return _dash

func melee_pressed() -> bool:
	return _melee

func shrike_pressed() -> bool:
	return _shrike and not _shrike_prev

func shrike_held() -> bool:
	return _shrike

func active() -> bool:
	return true

# --- Brain ---------------------------------------------------------------------------

func poll() -> void:
	_shoot_prev = _shoot
	_shrike_prev = _shrike
	_dash = false
	_melee = false
	if bird == null or not is_instance_valid(bird) or bird.frozen or not bird.is_alive():
		_move = Vector2.ZERO
		_aim = Vector2.ZERO
		_shoot = false
		_shrike = false
		_shrike_steer = 0.0
		return
	var dt := bird.get_physics_process_delta_time()
	_think -= dt
	_idle += dt
	_strafe_hold -= dt
	if bird.is_stunned():
		_move = Vector2.ZERO
		_shoot = false
		return
	if _parry_in >= 0.0:
		_parry_in -= dt
		if _parry_in < 0.0 and bird.can_melee():
			bird.facing = Bird.yaw_of(_parry_dir)
			_melee = true
			_shoot = false
			return
	_watch_arrows(dt)
	if _dash:
		return

	# After a curve shot: steer the arrow toward the target with the move input.
	if _curve_left > 0.0:
		_curve_left -= dt
		if _target and is_instance_valid(_target):
			var d := _flat(_to(_target)).normalized()
			_move = Vector2(d.x, d.z)
		return

	if bird.state == Bird.State.DRAWING:
		_draw_for += dt
		if _target and is_instance_valid(_target) and _target.is_alive():
			var dir := _aim_dir(_target)
			_aim = Vector2(dir.x, dir.z)
		_move = Vector2.ZERO
		if _draw_for >= _draw_target:
			if _shrike:
				_shrike = false # release the lob, then nudge it onto the target
				_shrike_steer = 0.9
			_shoot = false # release
			if _curve_side != 0.0:
				_curve_left = Tuning.get_default().curve_window
		return

	# Steer our airborne shrike's landing spot onto the target (we walk the same way, like a curve shot).
	if _shrike_steer > 0.0:
		_shrike_steer -= dt
		var mine: Arrow = null
		for a in bird.get_tree().get_nodes_in_group("arrows"):
			if a.shrike and a.owner_bird == bird and a.state == Arrow.State.FLYING and a.shrike_phase < 2:
				mine = a
		if mine and _target and is_instance_valid(_target) and _target.is_alive():
			var to := _flat(_target.global_position + _target.velocity * 0.4 - mine.shrike_target)
			_move = Vector2(to.x, to.z).normalized() if to.length() > 0.35 else Vector2.ZERO
			return
		_shrike_steer = 0.0

	if _shoot and bird.state != Bird.State.DRAWING:
		_shoot = false # one-frame press (slap) or draw was interrupted
	if _shrike and bird.state != Bird.State.DRAWING:
		_shrike = false
	if _think <= 0.0:
		_think = p["think"] * _rng.randf_range(0.8, 1.25)
		_decide()

func _decide() -> void:
	_target = _nearest_enemy()
	_aim = Vector2.ZERO
	if _target == null:
		last_branch = "wander"
		_set_move(_wander())
		return
	var to := _flat(_to(_target))
	var dist := to.length()
	# Up close: wing-slap to stun (then shoot them point-blank next think).
	var slap_r := Tuning.get_default().slap_range * 0.9
	if dist < slap_r and not _target.is_stunned() and bird.can_melee() and _rng.randf() < float(p.get("melee", 0.5)):
		bird.facing = Bird.yaw_of(to.normalized())
		_move = Vector2.ZERO
		_melee = true
		_idle = 0.0
		last_branch = "slap"
		return
	if bird.arrows > 0 and _target.is_stunned() and dist < 4.0:
		_begin_draw(0.0)
		_aim_error = 0.0
		_draw_target = 0.12 # quick point-blank shot while they're dazed
		return
	if bird.arrows > 0 and _idle > float(Tuning.get_default().cpu_patience):
		_hunt(to, dist)
		return
	if bird.arrows > 0:
		var los := _clear(bird.global_position, _target.global_position)
		if dist < p["range"] and los and _rng.randf() < 0.85:
			last_branch = "shoot"
			_begin_draw(0.0)
			return
		if not los and p["curve"] and dist < p.get("curve_range", p["range"]) and _rng.randf() < p.get("curve_chance", 1.0):
			# Aim off to one side of the cover and bend the arrow back in.
			var side := _strafe
			var off_dir := to.normalized().rotated(Vector3.UP, side * deg_to_rad(32.0))
			if _clear(bird.global_position, bird.global_position + off_dir * minf(dist, 4.0)):
				last_branch = "curve"
				_begin_draw(side)
				return
		# No line of sight: lob a shrike over the cover and steer it down onto them.
		if not los and dist < minf(float(p.get("shrike_range", 9.0)), Tuning.get_default().shrike_range_max) and _rng.randf() < float(p.get("shrike", 0.0)):
			last_branch = "shrike"
			_begin_shrike(dist)
			return
		# No good shot: grab a nearby power-up if one is waiting.
		var pad := _nearest_power_up(7.0)
		if pad != Vector3.INF:
			last_branch = "powerup"
			_set_move(_flat(pad - bird.global_position))
			return
		# Reposition: keep ~65% of range, strafe around for line of sight.
		last_branch = "reposition los=%s d=%.1f" % [los, dist]
		var want: float = p["range"] * 0.65
		var radial := to.normalized() * clampf(dist - want, -1.0, 1.0)
		var tangent := to.normalized().cross(Vector3.UP) * _strafe * (1.0 if los else 1.6)
		# Keep a strafe direction for a while (random flips every think made CPUs pace back and forth).
		if _strafe_hold <= 0.0 and _rng.randf() < 0.1:
			_flip_strafe()
		_set_move(radial + tangent * 0.7)
	else:
		# Out of arrows: go get one (slaps up close are handled above); keep away from the target meanwhile.
		last_branch = "no arrows"
		var pick := _nearest_stuck_arrow()
		if pick != Vector3.INF:
			_set_move(_flat(pick - bird.global_position))
		elif dist < 3.0:
			_set_move(-to.normalized())
		else:
			_set_move(_wander())

## Out of patience: close in on the target by the clear direction that gets nearest to it; shoot as soon as
## there's a line at any reachable range, lob over cover when there isn't.
func _hunt(to: Vector3, dist: float) -> void:
	var t := Tuning.get_default()
	var los := _clear(bird.global_position, _target.global_position)
	if los and dist < t.cpu_hunt_range:
		last_branch = "hunt shoot"
		_begin_draw(0.0)
		_draw_target = maxf(_draw_target, t.full_draw_time * 0.85) # far shots need the speed
		return
	if not los and dist < Tuning.get_default().shrike_range_max and _rng.randf() < 0.5:
		last_branch = "hunt shrike"
		_begin_shrike(dist)
		return
	last_branch = "hunt move d=%.1f" % dist
	var best := to.normalized()
	var best_score := INF
	for i in 12:
		var dir := to.normalized().rotated(Vector3.UP, TAU * i / 12.0)
		var probe := bird.global_position + dir * 1.6
		if not _clear(bird.global_position, probe, 0.4) or not _inside(probe):
			continue
		var score := _flat(_target.global_position - probe).length()
		if score < best_score:
			best_score = score
			best = dir
	_move = Vector2(best.x, best.z)

## Lob a shrike at a target `dist` away: charge just enough for the distance (aiming is done while drawing).
func _begin_shrike(dist: float) -> void:
	var t := Tuning.get_default()
	_begin_draw(0.0)
	_shoot = false
	_shrike = true
	var c := clampf((dist - t.shrike_range_min) / (t.shrike_range_max - t.shrike_range_min), 0.0, 1.0)
	_draw_target = c * t.full_draw_time + _rng.randf_range(-0.04, 0.04)
	_aim_error *= 0.5

func _flip_strafe() -> void:
	_strafe = -_strafe
	_strafe_hold = 1.5

func _inside(pos: Vector3) -> bool:
	var half: Vector2 = MapBuilder.arena_half - Vector2(0.8, 0.8)
	return absf(pos.x) < half.x and absf(pos.z) < half.y

func _begin_draw(curve_side: float) -> void:
	_idle = 0.0
	_shoot = true
	_move = Vector2.ZERO
	_draw_for = 0.0
	_draw_target = _rng.randf_range(p["draw"][0], p["draw"][1])
	_aim_error = deg_to_rad(_rng.randf_range(-p["aim_error"], p["aim_error"]))
	_curve_side = curve_side

func _aim_dir(target: Bird) -> Vector3:
	var t := Tuning.get_default()
	var charge := clampf(_draw_target / t.full_draw_time, 0.0, 1.0)
	var speed := lerpf(t.arrow_speed_min, t.arrow_speed_max, charge)
	var to := _flat(_to(target))
	var lead := _flat(target.velocity) * (to.length() / speed) * float(p["lead"])
	var dir := _flat(to + lead).normalized()
	if _curve_side != 0.0:
		dir = dir.rotated(Vector3.UP, _curve_side * deg_to_rad(32.0))
	return dir.rotated(Vector3.UP, _aim_error)

## Dodge: dash sideways away from enemy arrows about to pass close by.
func _watch_arrows(dt: float) -> void:
	if _dodge_in >= 0.0:
		_dodge_in -= dt
		if _dodge_in < 0.0:
			_dash = true
			_move = Vector2(_dodge_dir.x, _dodge_dir.z)
			if bird.state == Bird.State.DRAWING:
				_shoot = false
		return
	for a in bird.get_tree().get_nodes_in_group("arrows"):
		if a.state != Arrow.State.FLYING or a.owner_bird == bird or _seen_arrows.has(a):
			continue
		if a.shrike:
			# An enemy shrike's landing ring around us: step (dash) out of it, by reaction/chance like dodges.
			if a.shrike_phase >= 1 and _flat(bird.global_position - a.shrike_target).length() < Tuning.get_default().shrike_stun_radius + 0.3:
				_seen_arrows[a] = true
				if _rng.randf() < float(p["dodge"]):
					var away := _flat(bird.global_position - a.shrike_target)
					_dodge_dir = away.normalized() if away.length() > 0.05 else Vector3.RIGHT
					_dodge_in = float(p["react"])
				return
			continue
		var v := _flat(a.velocity)
		if v.length() < 0.1:
			continue
		var rel := _flat(bird.global_position - a.global_position)
		var tc := rel.dot(v) / v.length_squared()
		if tc < 0.0 or tc > 0.5:
			continue
		var miss := (rel - v * tc).length()
		if miss > 1.0:
			continue
		_seen_arrows[a] = true
		# Try to bat it away: swing so the wing meets it mid-window (timing error per difficulty).
		if bird.can_melee() and _rng.randf() < float(p.get("parry", 0.0)):
			var t := Tuning.get_default()
			var contact := tc - t.parry_reach / v.length()
			_parry_in = maxf(contact - t.parry_window * 0.5 + _rng.randf_range(-1.0, 1.0) * float(p.get("parry_jitter", 0.05)), 0.0)
			_parry_dir = -v.normalized()
			return
		if _rng.randf() < float(p["dodge"]):
			var side := v.normalized().cross(Vector3.UP)
			if side.dot(rel) < 0.0:
				side = -side
			_dodge_dir = side
			_dodge_in = float(p["react"])
		return

# --- Helpers -------------------------------------------------------------------------

func _set_move(v: Vector3) -> void:
	v = _avoid(_flat(v))
	_move = Vector2(v.x, v.z).limit_length(1.0)
	if _move.length() > 0.05:
		_move = _move.normalized()

## Steer away from walls and around obstacles in the way.
func _avoid(v: Vector3) -> Vector3:
	var pos := bird.global_position
	var push := Vector3.ZERO
	# The edge of THIS map (was the Aviary's 20 x 14 hard-coded: CPUs paced at x = 8.3 on the Birdbath).
	var edge: Vector2 = MapBuilder.arena_half - Vector2(1.7, 1.7)
	if pos.x > edge.x: push.x -= 1.0
	if pos.x < -edge.x: push.x += 1.0
	if pos.z > edge.y: push.z -= 1.0
	if pos.z < -edge.y: push.z += 1.0
	v += push * 1.5
	if v.length() > 0.1:
		var ahead := pos + v.normalized() * 1.1
		if not _clear(pos, ahead, 0.4):
			v = v.rotated(Vector3.UP, _strafe * deg_to_rad(75.0)) # same way round each time (no dithering)
	return v

func _to(b: Bird) -> Vector3:
	return b.global_position - bird.global_position

func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)

func _clear(from: Vector3, to: Vector3, height := -1.0) -> bool:
	var h := Tuning.get_default().arrow_height if height < 0.0 else height
	var q := PhysicsRayQueryParameters3D.create(from + Vector3.UP * h, to + Vector3.UP * h, Arrow.WORLD_MASK)
	return bird.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _nearest_enemy() -> Bird:
	var best: Bird = null
	var best_d := INF
	for b: Bird in bird.get_tree().get_nodes_in_group("birds"):
		if b == bird or not b.is_alive():
			continue
		var d := _to(b).length()
		if d < best_d:
			best_d = d
			best = b
	return best

func _nearest_stuck_arrow() -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	for a in bird.get_tree().get_nodes_in_group("arrows"):
		if a.state != Arrow.State.STUCK or a.is_queued_for_deletion():
			continue
		var mid: Vector3 = a.global_position + a.global_basis.z * Arrow.LENGTH * 0.5
		var d := _flat(mid - bird.global_position).length()
		if d < best_d:
			best_d = d
			best = mid
	return best

func _nearest_power_up(max_dist: float) -> Vector3:
	var best := Vector3.INF
	var best_d := max_dist
	for p in bird.get_tree().get_nodes_in_group("power_up_pads"):
		if p.item == "" or not p.visible:
			continue
		var d := _flat(p.global_position - bird.global_position).length()
		if d < best_d:
			best_d = d
			best = p.global_position
	return best

func _wander() -> Vector3:
	return Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)) - _flat(bird.global_position) * 0.08
