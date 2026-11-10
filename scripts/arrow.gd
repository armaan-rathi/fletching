class_name Arrow
extends Node3D
## Kinematic arrow: flies with light gravity (range comes from launch speed), raycasts every frame,
## never hits its shooter, knocks out birds it passes through (and keeps flying), sticks into whatever static
## thing it hits (or lies on the ground), then becomes a pickup. Stuck arrows poof back to their owner after
## a while. For curve_window seconds after release the shooter's sideways move input bends its path.
## Origin is the arrow's tip; it points along -Z.

enum State { FLYING, STUCK }

const WORLD_MASK := 1 | 32 | 64 # world, arrow_stickable, breakables
const HIT_MASK := WORLD_MASK | 4 # + bird hitboxes
const SCALE := 1.3 ## flying arrow size (user: "a little bigger"; the model is 0.87 m)
const LENGTH := 0.87 * SCALE

@onready var wobble: Node3D = $Wobble
@onready var trail: ArrowTrail = $Trail
@onready var pickup_area: Area3D = $PickupArea

## Who the arrow belongs to for hits (never hits them; gets the KO). A batted arrow changes hands.
var owner_bird: Node
## Whose quiver it returns to (the original shooter, even after it's been batted away).
var quiver_owner: Node
## Batted away by a melee swing: no more curve steering by the original shooter.
var batted := false
## Shrike (lob shot, user rework): a visible high arc from the shooter to a landing spot (shrike_target) set by
## aim + charge; the shooter's move input nudges the spot while it's airborne. A direct hit knocks out; the
## landing always sends out a small shockwave that stuns birds near it. A ring in the shooter's color marks the
## spot the whole flight. Can't be batted away (it comes from above). Collides like any arrow on the way (a tall
## tree can catch it).
var shrike := false
var shrike_target := Vector3.ZERO
var shrike_phase := 0 # 1 climbing, 2 coming down
var _shrike_from := Vector3.ZERO
var _shrike_s := 0.0   # 0..1 along the arc
var _shrike_dur := 1.0 # s for the whole arc
var _marker: MeshInstance3D
var _marker_mat: StandardMaterial3D
var color := Color.WHITE
var velocity := Vector3.ZERO
var state := State.FLYING
var charge := 0.0
var _t: Tuning
var _age := 0.0
var _stuck_time := 0.0
var _prev_pos := Vector3.ZERO
var _wobble_amp := 0.0
var _wobble_time := 0.0
var _exclude: Array[RID] = []   # shooter's hitbox + birds already passed through
var _near_missed := {}          # birds already "shocked" by this arrow
## Eggsplosive: explodes on its first impact (bird, egg, wall, ground).
var explosive := false
## Trifecta side arrow: poofs on impact instead of becoming a pickup (doesn't change the quiver economy).
var bonus := false
## Trifecta: s into the flight when this arrow splits into three (-1 = never). User: split halfway, not a fan.
var split_at := -1.0

static var _mat_cache := {}

func _ready() -> void:
	add_to_group("arrows")
	_t = Tuning.get_default()
	wobble.scale = Vector3.ONE * SCALE
	trail.width *= SCALE
	pickup_area.monitoring = false
	pickup_area.top_level = true
	(pickup_area.get_node("Shape").shape as CylinderShape3D).radius = _t.arrow_pickup_radius

## Call right after adding the arrow to the scene.
## from: a safe point inside the shooter (the first raycast starts there, so arrows can't spawn through walls).
func launch(shooter: Node, from: Vector3, tip_pos: Vector3, vel: Vector3, arrow_color: Color, arrow_charge: float,
		is_explosive := false, is_bonus := false) -> void:
	explosive = is_explosive
	bonus = is_bonus
	owner_bird = shooter
	quiver_owner = shooter
	if shooter is Bird:
		_exclude.append((shooter as Bird).hitbox.get_rid()) # no self-hits
	color = arrow_color
	velocity = vel
	charge = arrow_charge
	apply_materials(self, color)
	trail.color = color
	_prev_pos = from
	_orient(vel)
	_step_to(tip_pos)

## Shrike launch: from a point above the shooter's head, along an arc that lands at `target` (y ignored).
func launch_shrike(shooter: Node, from: Vector3, target: Vector3, arrow_color: Color, arrow_charge: float,
		is_explosive := false, is_bonus := false) -> void:
	explosive = is_explosive
	bonus = is_bonus
	owner_bird = shooter
	quiver_owner = shooter
	if shooter is Bird:
		_exclude.append((shooter as Bird).hitbox.get_rid())
	color = arrow_color
	charge = arrow_charge
	apply_materials(self, color)
	trail.color = color
	shrike = true
	shrike_phase = 1
	_shrike_from = from
	shrike_target = Vector3(target.x, 0.0, target.z)
	var dist := Vector2(target.x - from.x, target.z - from.z).length()
	_shrike_dur = maxf(dist / _t.shrike_speed, _t.shrike_min_flight)
	global_position = from
	_prev_pos = from
	velocity = (shrike_point(0.05) - from) / (_shrike_dur * 0.05)
	_orient(velocity)
	_marker = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.78
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 4
	_marker.mesh = torus
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_mat.albedo_color = Color(color, 0.0)
	_marker.material_override = _marker_mat
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(_marker)
	_update_marker()

## Point on the arc at s (0 = launch, 1 = the landing spot on the ground; past 1 keeps going down).
func shrike_point(s: float) -> Vector3:
	var flat := Vector3(_shrike_from.x, 0.0, _shrike_from.z).lerp(shrike_target, s)
	var y := lerpf(_shrike_from.y, 0.0, s) + 4.0 * _t.shrike_apex * s * (1.0 - s)
	return Vector3(flat.x, y, flat.z)

## Where a shrike shot now would land: aim direction + charge sets the distance; stays inside the arena.
static func shrike_landing(from: Vector3, dir: Vector3, charge: float, t: Tuning) -> Vector3:
	var d := lerpf(t.shrike_range_min, t.shrike_range_max, clampf(charge, 0.0, 1.0))
	var p := from + Vector3(dir.x, 0.0, dir.z).normalized() * d
	var half: Vector2 = MapBuilder.arena_half - Vector2(0.4, 0.4)
	return Vector3(clampf(p.x, -half.x, half.x), 0.0, clampf(p.z, -half.y, half.y))

func _shrike_step(delta: float) -> void:
	if shrike_phase < 2 and owner_bird is Bird and is_instance_valid(owner_bird):
		var m: Vector3 = (owner_bird as Bird).get_move_input()
		if m.length() > 0.2:
			shrike_target += Vector3(m.x, 0.0, m.z).limit_length(1.0) * _t.shrike_steer_speed * delta
			var half: Vector2 = MapBuilder.arena_half - Vector2(0.4, 0.4)
			shrike_target.x = clampf(shrike_target.x, -half.x, half.x)
			shrike_target.z = clampf(shrike_target.z, -half.y, half.y)
	_shrike_s += delta / _shrike_dur
	if shrike_phase == 1 and _shrike_s >= 0.5:
		shrike_phase = 2
		Sfx.play("shrike_drop")
	var next := shrike_point(_shrike_s)
	velocity = (next - global_position) / maxf(delta, 0.0001)
	_step_to(next)
	if state == State.FLYING:
		_update_marker()

## Landing shockwave: stuns every other bird close to where it came down (even on a miss). Not on top of
## cover (a shrike caught by a tree canopy just sticks there).
func _shrike_shock(point: Vector3) -> void:
	if point.y > 1.2:
		return
	var r := _t.shrike_stun_radius
	Fx.ripple(point, r * 1.1)
	Fx.dust(point, 8, Fx.DUST_COLOR, 0.5, 2.2)
	Fx.shake(0.18)
	Sfx.play("shrike_land")
	for b in get_tree().get_nodes_in_group("birds"):
		if b == owner_bird or not b.is_alive():
			continue
		var to: Vector3 = b.global_position - point
		to.y = 0.0
		if to.length() < r:
			b.stun(owner_bird as Bird, to.normalized() if to.length() > 0.05 else Vector3.FORWARD)

func _update_marker() -> void:
	if _marker == null or not is_instance_valid(_marker):
		return
	var f := clampf(_shrike_s, 0.0, 1.0)
	var r := lerpf(_t.shrike_stun_radius * 1.2, _t.shrike_marker_radius, f)
	_marker.global_position = Vector3(shrike_target.x, 0.04, shrike_target.z)
	_marker.scale = Vector3(r, 0.15, r)
	var a := lerpf(0.45, 0.95, f)
	_marker_mat.albedo_color = Color(color.lerp(Color.WHITE, 0.15), a)

func _drop_marker() -> void:
	if _marker and is_instance_valid(_marker):
		_marker.queue_free()
	_marker = null

func _exit_tree() -> void:
	_drop_marker()

func _physics_process(delta: float) -> void:
	if shrike and state == State.FLYING:
		_age += delta
		_shrike_step(delta)
		return
	match state:
		State.FLYING:
			_age += delta
			if split_at > 0.0 and _age >= split_at:
				_split()
			_curve(delta)
			_home(delta)
			velocity.y -= _t.arrow_gravity * delta
			var next := global_position + velocity * delta
			if _check_parry(global_position, next):
				return
			_step_to(next)
			if state == State.FLYING and _age > _t.arrow_max_flight:
				_return_to_owner()
		State.STUCK:
			_stuck_time += delta
			_wobble_time += delta
			_wobble_amp *= exp(-6.0 * delta)
			wobble.rotation.x = sin(_wobble_time * 38.0) * _wobble_amp
			for body in pickup_area.get_overlapping_bodies():
				if body.has_method("try_pickup_arrow") and body.try_pickup_arrow():
					Fx.impact(_mid_point(), Color.WHITE, 5, 2.5)
					queue_free()
					return
			if _stuck_time > _t.arrow_auto_return:
				_return_to_owner()

func _step_to(next: Vector3) -> void:
	var from := _prev_pos
	_prev_pos = next
	# Ground: y = 0 plane.
	var end := next
	var ground := false
	if next.y <= 0.0:
		var f := from.y / maxf(from.y - next.y, 0.0001)
		end = from.lerp(next, clampf(f, 0.0, 1.0))
		end.y = 0.0
		ground = true
	# Raycast; birds hit along the way are knocked out and the arrow keeps going.
	for i in 4:
		var q := PhysicsRayQueryParameters3D.create(from, end, HIT_MASK, _exclude)
		q.collide_with_areas = true
		q.hit_from_inside = false
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit:
			break
		if hit.collider is Area3D:
			var bird = (hit.collider as Area3D).get_parent()
			if not shrike and bird is Bird and (bird as Bird).can_parry(hit.position, velocity):
				_bat(bird, hit.position)
				return
			_exclude.append((hit.collider as Area3D).get_rid())
			if bird is Bird and (bird as Bird).hit_by_arrow(self) and explosive:
				_explode(hit.position)
				return
			continue
		if hit.collider is Egg:
			_exclude.append(hit.collider.get_rid())
			hit.collider.on_arrow_hit(self) # arrows pierce eggs
			if explosive:
				_explode(hit.position)
				return
			continue
		_stick(hit.position, hit.collider, false)
		return
	_check_near_misses(from, end)
	if ground:
		_stick(end, null, true)
		return
	global_position = next
	_orient(velocity)

## A swinging bird's wing meets the arrow somewhere along this frame's path -> batted away.
## Swept along the segment so a fast arrow can't skip through the (short) parry window.
func _check_parry(from: Vector3, to: Vector3) -> bool:
	for b in get_tree().get_nodes_in_group("birds"):
		if b == owner_bird or not b.is_parrying():
			continue
		var c: Vector3 = b.global_position
		c.y = from.y
		var p := Geometry3D.get_closest_point_to_segment(c, from, Vector3(to.x, from.y, to.z))
		if Vector2(p.x - c.x, p.z - c.z).length() <= _t.parry_reach and b.can_parry(p, velocity):
			_bat(b, p)
			return true
	return false

func _bat(b: Bird, at: Vector3) -> void:
	var v := b.parry_arrow(self, at)
	velocity = Vector3(v.x, 0.0, v.z)
	owner_bird = b
	batted = true
	_age = 0.0
	_exclude.clear()
	_exclude.append(b.hitbox.get_rid()) # the original shooter is fair game now
	_near_missed.clear()
	at.y = maxf(at.y, _t.arrow_height * 0.8)
	global_position = at
	_prev_pos = at
	_orient(velocity)

## Curve shots: the shooter's sideways input (relative to the flight direction) turns the arrow.
func _curve(delta: float) -> void:
	if batted or _age > _t.curve_window or not (owner_bird is Bird) or not is_instance_valid(owner_bird):
		return
	var steer: Vector3 = (owner_bird as Bird).get_move_input()
	var flat := Vector3(velocity.x, 0, velocity.z)
	if steer.length() < 0.2 or flat.length() < 0.01:
		return
	var right := flat.normalized().cross(Vector3.UP)
	var lateral := clampf(steer.dot(right), -1.0, 1.0)
	var turn := -lateral * deg_to_rad(_t.curve_max_turn_rate) * delta
	flat = flat.rotated(Vector3.UP, turn)
	velocity = Vector3(flat.x, velocity.y, flat.z)

## Very slight homing: bend toward the closest enemy bird that's close and roughly ahead.
func _home(delta: float) -> void:
	var flat := Vector3(velocity.x, 0, velocity.z)
	if flat.length() < 0.1:
		return
	var dir := flat.normalized()
	var best_turn := 0.0
	var best_d := _t.homing_range
	for b in get_tree().get_nodes_in_group("birds"):
		if b == owner_bird or not b.is_alive():
			continue
		var to: Vector3 = b.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > best_d or d < 0.05:
			continue
		var ang := dir.signed_angle_to(to.normalized(), Vector3.UP)
		if absf(rad_to_deg(ang)) > _t.homing_max_angle:
			continue
		best_d = d
		best_turn = ang
	if best_d >= _t.homing_range:
		return
	var strength := 1.0 - best_d / _t.homing_range
	var max_step := deg_to_rad(_t.homing_turn_rate) * strength * delta
	flat = flat.rotated(Vector3.UP, clampf(best_turn, -max_step, max_step))
	velocity = Vector3(flat.x, velocity.y, flat.z)

func _check_near_misses(from: Vector3, to: Vector3) -> void:
	for b in get_tree().get_nodes_in_group("birds"):
		if b == owner_bird or _near_missed.has(b) or not b.is_alive():
			continue
		var c: Vector3 = b.global_position + Vector3.UP * _t.arrow_height
		var closest := Geometry3D.get_closest_point_to_segment(c, from, to)
		if closest.distance_to(c) < _t.near_miss_distance:
			_near_missed[b] = true
			b.near_miss()

func _stick(point: Vector3, collider: Object, ground: bool) -> void:
	_drop_marker()
	if shrike and not explosive:
		_shrike_shock(point)
	var wet := ground and Fx.in_water(point)
	if not explosive:
		Sfx.play("splash" if wet else _impact_sound(collider, ground), 1.0, 0.0 if not bonus else -4.0)
	if wet:
		Fx.splash(point, 8, 1.0)
	if explosive:
		_explode(point)
		return
	if bonus:
		Fx.impact(point, color, 5, 3.0)
		Fx.poof(point, color)
		queue_free()
		return
	state = State.STUCK
	var dir := velocity.normalized()
	if ground and shrike:
		# A shrike stands upright where it dropped (slight lean), like a planted flag.
		dir = (Vector3(0.12, 0, 0.08) + Vector3.DOWN).normalized()
		_wobble_amp = 0.1
	elif ground:
		# Lie on the ground: shallow angle, tip just under the surface.
		var flat := Vector3(dir.x, 0, dir.z).normalized()
		dir = (flat + Vector3.DOWN * 0.22).normalized()
		_wobble_amp = 0.05
	else:
		_wobble_amp = 0.12 + 0.12 * charge
		Fx.shake(_t.shake_on_stick * (0.5 + charge * 0.5))
		if charge >= 0.999:
			Fx.hit_stop(_t.hitstop_arrow_stick)
	_orient(dir)
	global_position = point + dir * _t.arrow_penetration
	trail.stop()
	Fx.impact(point, Color("fff2c0") if not ground else Color("c9a77c"), 6 if not ground else 4, 3.0 + charge * 2.0)
	if ground and not wet:
		Fx.dust(point, 3, Fx.DUST_COLOR, 0.35, 0.8)
	if collider and collider.has_method("on_arrow_hit"):
		collider.on_arrow_hit(self)
	pickup_area.global_position = Vector3(_mid_point().x, 0.0, _mid_point().z)
	pickup_area.monitoring = true

## Eggsplosive blast: knocks out birds in range (never the shooter; dash i-frames still save you),
## smashes eggs, then the arrow is gone (a regular arrow poofs back to its owner's quiver).
## Impact sound by what was hit: rocks clack, the ground and border bushes thud, everything else is wood.
static func _impact_sound(collider: Object, ground: bool) -> String:
	if ground or collider == null:
		return "stick_soft"
	var n := String((collider as Node).name) if collider is Node else ""
	if n.begins_with("Rock") or (collider as Object).get_meta("sfx_surface", "") == "stone":
		return "stick_stone"
	if n == "ArenaWalls":
		return "stick_soft"
	return "stick_wood"

func _explode(point: Vector3) -> void:
	_drop_marker()
	state = State.STUCK
	Sfx.play("explosion")
	Sfx.play("explosion_crack")
	trail.stop()
	var r := _t.eggsplosive_radius
	Fx.explosion(point, r)
	Fx.shake(0.45)
	for b in get_tree().get_nodes_in_group("birds"):
		if b == owner_bird or not b.is_alive() or b.is_invulnerable():
			continue
		var to: Vector3 = b.global_position - point
		to.y = 0.0
		if to.length() < r:
			b.knock_out(owner_bird as Bird, to.normalized() if to.length() > 0.05 else velocity.normalized())
	for e in get_tree().get_nodes_in_group("eggs"):
		if e.global_position.distance_to(point) < r:
			e.smash()
	if not bonus and is_instance_valid(quiver_owner) and quiver_owner.has_method("return_arrow"):
		# The exploded arrow poofs back after a short delay (so explosive shots can't be spammed).
		# Capture the id, not the node: the bird may be freed (scene change) before the timer fires.
		var who_id := quiver_owner.get_instance_id()
		get_tree().create_timer(1.5).timeout.connect(func():
			var who := instance_from_id(who_id)
			if who and who.has_method("return_arrow"):
				who.return_arrow())
	queue_free()

## Trifecta split: two bonus arrows peel off at +-trifecta_spread from here, same speed and drop.
func _split() -> void:
	split_at = -1.0
	if batted:
		return
	var scene := load(scene_file_path) as PackedScene
	for k in [-1.0, 1.0]:
		var v := velocity.rotated(Vector3.UP, deg_to_rad(_t.trifecta_spread) * k)
		var a: Arrow = scene.instantiate()
		get_parent().add_child(a)
		a.launch(owner_bird, global_position - velocity.normalized() * 0.05, global_position, v, color, charge, explosive, true)
		a._age = _age
	Fx.impact(global_position, color, 5, 2.5)
	Sfx.play("fire", 1.5, -6.0)

func _mid_point() -> Vector3:
	return global_position + global_basis.z * LENGTH * 0.5

func _return_to_owner() -> void:
	_drop_marker()
	Fx.poof(_mid_point() if state == State.STUCK else global_position, color)
	if is_instance_valid(quiver_owner) and quiver_owner.has_method("return_arrow"):
		quiver_owner.return_arrow()
	queue_free()

func _orient(dir: Vector3) -> void:
	if dir.length_squared() < 0.0001:
		return
	var up := Vector3.UP if absf(dir.normalized().y) < 0.98 else Vector3.FORWARD
	global_basis = Basis.looking_at(dir.normalized(), up)

## Applies toon materials (shaft, head, player-colored fletching) to an arrow model subtree.
## stencil_slot >= 0: the arrow is held by a bird (nocked) and uses that bird's stencil slot.
static func apply_materials(root: Node, fletch_color: Color, stencil_slot := -1) -> void:
	var key := "%s|%d" % [fletch_color.to_html(), stencil_slot]
	if not _mat_cache.has(key):
		if stencil_slot < 0:
			_mat_cache[key] = {
				"shaft": ToonMaterials.actor(Color("d9b27c"), 0.1),
				"head": ToonMaterials.actor(Color("a9b1bb"), 0.3),
				"fletching": ToonMaterials.actor(fletch_color, 0.2),
			}
		else:
			_mat_cache[key] = {
				"shaft": ToonMaterials.character(Color("d9b27c"), true, Color.WHITE, 0.1, stencil_slot),
				"head": ToonMaterials.character(Color("a9b1bb"), true, Color.WHITE, 0.3, stencil_slot),
				"fletching": ToonMaterials.character(fletch_color, true, Color.WHITE, 0.2, stencil_slot),
			}
	var mats: Dictionary = _mat_cache[key]
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.name == "Ribbon":
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			if src and mats.has(src.resource_name):
				mi.set_surface_override_material(i, mats[src.resource_name])
