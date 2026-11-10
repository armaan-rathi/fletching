class_name Fx
extends RefCounted
## Game-feel helpers (hit-stop, camera shake, punch-zoom) and small one-shot VFX. All static:
## call Fx.shake(0.2), Fx.dust(pos), ... from anywhere. (A static class instead of an autoload so
## command-line tool scripts can load game scripts without waiting for autoloads.)

const SMOKE_TEX := preload("res://assets/third_party/kenney_particles/smoke_04.png")
const DUST_COLOR := Color("c9a77c")

static var _hitstop_token := 0
static var _hitstop_active := false
static var _hitstop_restore := 1.0
static var _smoke_mat: StandardMaterial3D
static var _chunk_mat: StandardMaterial3D

static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

static func _ensure_materials() -> void:
	if _smoke_mat:
		return
	_smoke_mat = StandardMaterial3D.new()
	_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_smoke_mat.vertex_color_use_as_albedo = true
	_smoke_mat.albedo_texture = SMOKE_TEX
	_chunk_mat = StandardMaterial3D.new()
	_chunk_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_chunk_mat.vertex_color_use_as_albedo = true

# --- Time ----------------------------------------------------------------------

## Freezes gameplay for `duration` real seconds. Overlapping calls extend the freeze.
static func hit_stop(duration: float) -> void:
	if duration <= 0.0:
		return
	if not _hitstop_active:
		_hitstop_restore = Engine.time_scale # e.g. a sim running at 3x keeps its speed afterwards
	_hitstop_active = true
	_hitstop_token += 1
	var token := _hitstop_token
	Engine.time_scale = 0.02
	# Real-time timer (ignores time scale). Only the latest hit-stop restores the time scale.
	_tree().create_timer(duration, true, false, true).timeout.connect(func() -> void:
		if token == Fx._hitstop_token:
			Fx._hitstop_active = false
			Engine.time_scale = Fx._hitstop_restore)

# --- Camera --------------------------------------------------------------------

static func shake(trauma: float) -> void:
	var cam := _tree().root.get_viewport().get_camera_3d()
	if cam and cam.has_method("add_trauma"):
		cam.add_trauma(trauma)

static func punch_zoom() -> void:
	var cam := _tree().root.get_viewport().get_camera_3d()
	if cam and cam.has_method("punch_zoom"):
		cam.punch_zoom()

# --- VFX -----------------------------------------------------------------------

## Soft dust/smoke puff (Kenney smoke sprite).
static func dust(pos: Vector3, amount := 6, color := DUST_COLOR, size := 0.5, spread := 1.5) -> void:
	var p := _particles(pos, amount, 0.45)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	quad.material = _smoke_mat
	p.mesh = quad
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = spread * 0.4
	p.initial_velocity_max = spread
	p.gravity = Vector3(0, 0.5, 0)
	p.damping_min = 4.0
	p.damping_max = 6.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.1
	p.scale_amount_curve = _curve([Vector2(0, 0.6), Vector2(0.3, 1.0), Vector2(1, 0.2)])
	p.color_ramp = _fade(color)
	_fire(p)

## Bigger puff for arrows poofing back to the quiver.
static func poof(pos: Vector3, color := Color(1, 1, 1)) -> void:
	dust(pos, 10, color.lerp(Color.WHITE, 0.5), 0.7, 2.5)

## Chunky 3D impact stars (toon-shaded, outlined) for arrow hits, pickups and sparkles.
static func impact(pos: Vector3, color := Color("fff2c0"), amount := 7, speed := 4.0) -> void:
	var p := _particles(pos, amount, 0.35)
	p.mesh = _star_mesh(color)
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -12, 0)
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.particle_flag_rotate_y = true
	p.scale_amount_curve = _curve([Vector2(0, 1.0), Vector2(0.7, 1.0), Vector2(1, 0.0)])
	_fire(p)

static var _stars := {}

## A small extruded 5-point star with the toon material + outline, cached per color.
static func _star_mesh(color: Color) -> ArrayMesh:
	var key := color.to_html()
	if _stars.has(key):
		return _stars[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector2] = []
	for i in 10:
		var a := TAU * i / 10.0 - PI / 2.0
		var r := 0.075 if i % 2 == 0 else 0.032
		pts.append(Vector2(cos(a), sin(a)) * r)
	var depth := 0.025
	for side in [1.0, -1.0]:
		for i in 10:
			var a := pts[i]
			var b := pts[(i + 1) % 10]
			st.set_normal(Vector3(0, 0, side))
			if side > 0:
				st.add_vertex(Vector3(0, 0, depth)); st.add_vertex(Vector3(a.x, a.y, 0)); st.add_vertex(Vector3(b.x, b.y, 0))
			else:
				st.add_vertex(Vector3(0, 0, -depth)); st.add_vertex(Vector3(b.x, b.y, 0)); st.add_vertex(Vector3(a.x, a.y, 0))
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, ToonMaterials.toon(color, 0.3))
	_stars[key] = mesh
	return mesh

## Eggsplosive blast: flash, expanding shockwave ring, egg-shell bits, hot stars and smoke.
static func explosion(pos: Vector3, radius: float) -> void:
	var root := _parent()
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 6
	ring.mesh = torus
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color("ffd27a")
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	ring.global_position = Vector3(pos.x, 0.12, pos.z)
	ring.scale = Vector3(0.2, 0.15, 0.2)
	var tw := ring.create_tween().set_parallel()
	tw.tween_property(ring, "scale", Vector3(radius, 0.15, radius), 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(rm, "albedo_color:a", 0.0, 0.3)
	tw.chain().tween_callback(ring.queue_free)
	# Flash: an unshaded ball that pops and fades (a real light blows out the toon shading).
	var flash := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	ball.radial_segments = 16
	ball.rings = 8
	flash.mesh = ball
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.albedo_color = Color("fff1c4")
	flash.material_override = fm
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(flash)
	flash.global_position = pos + Vector3.UP * 0.4
	flash.scale = Vector3.ONE * 0.3
	var tw2 := flash.create_tween().set_parallel()
	tw2.tween_property(flash, "scale", Vector3.ONE * radius * 1.1, 0.12).set_ease(Tween.EASE_OUT)
	tw2.tween_property(fm, "albedo_color", Color(1.0, 0.6, 0.25, 0.0), 0.22)
	tw2.chain().tween_callback(flash.queue_free)
	impact(pos + Vector3.UP * 0.3, Color("ffb347"), 10, 7.0)
	impact(pos + Vector3.UP * 0.3, Color("fff2c0"), 6, 5.0)
	egg_splat(pos + Vector3.UP * 0.2, 1.5)
	dust(pos + Vector3.UP * 0.2, 9, Color("8a7a6a"), 0.9, 3.0)

## Broken egg: white shell bits and yellow yolk blobs.
static func egg_splat(pos: Vector3, power := 1.0) -> void:
	_ensure_materials()
	var shell := _particles(pos, int(8 * power), 0.6)
	var bit := PrismMesh.new()
	bit.size = Vector3(0.07, 0.06, 0.02)
	bit.material = ToonMaterials.toon(Color("f6f2e8"), 0.2)
	shell.mesh = bit
	shell.direction = Vector3.UP
	shell.spread = 75.0
	shell.initial_velocity_min = 2.0 * power
	shell.initial_velocity_max = 4.0 * power
	shell.gravity = Vector3(0, -14, 0)
	shell.angular_velocity_min = -720.0
	shell.angular_velocity_max = 720.0
	shell.particle_flag_rotate_y = true
	_fire(shell)
	var yolk := _particles(pos, int(6 * power), 0.45)
	var blob := SphereMesh.new()
	blob.radius = 0.045
	blob.height = 0.07
	blob.radial_segments = 8
	blob.rings = 4
	blob.material = ToonMaterials.toon(Color("ffc531"), 0.3, false)
	yolk.mesh = blob
	yolk.direction = Vector3.UP
	yolk.spread = 60.0
	yolk.initial_velocity_min = 1.5 * power
	yolk.initial_velocity_max = 3.0 * power
	yolk.gravity = Vector3(0, -14, 0)
	yolk.scale_amount_curve = _curve([Vector2(0, 1.0), Vector2(0.8, 1.0), Vector2(1, 0.3)])
	_fire(yolk)

## A yolk puddle on the ground (lasts until removed).
static func yolk_decal(pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var white := CylinderMesh.new()
	white.top_radius = 0.2
	white.bottom_radius = 0.2
	white.height = 0.01
	white.radial_segments = 14
	white.rings = 1
	white.material = ToonMaterials.toon(Color("fbf3dc"), 0.0, false)
	m.mesh = white
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var y := MeshInstance3D.new()
	var yc := CylinderMesh.new()
	yc.top_radius = 0.09
	yc.bottom_radius = 0.09
	yc.height = 0.02
	yc.radial_segments = 12
	yc.rings = 1
	yc.material = ToonMaterials.toon(Color("ffc531"), 0.0, false)
	y.mesh = yc
	y.position = Vector3(0.03, 0.005, -0.02)
	y.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.add_child(y)
	_parent().add_child(m)
	m.global_position = pos
	m.scale = Vector3(randf_range(0.8, 1.2), 1.0, randf_range(0.8, 1.2))
	return m

## Power-up appears (picked = false) or is picked up (picked = true).
static func pickup_burst(pos: Vector3, color: Color, picked: bool) -> void:
	impact(pos, color, 9 if picked else 5, 4.5 if picked else 2.5)
	if picked:
		impact(pos, Color("fff6e0"), 5, 3.0)
		shake(0.08)

## Melee swing: a quick flat white arc in front of the bird that grows and fades over about the parry window,
## so the (tight) timing is readable.
static func swoosh(pos: Vector3, yaw: float, arc_deg: float, reach: float, time: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _arc_mesh(arc_deg)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(1, 1, 1, 0.75)
	m.no_depth_test = true
	m.render_priority = 5
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_parent().add_child(mi)
	mi.global_position = pos
	mi.rotation.y = yaw
	mi.scale = Vector3.ONE * reach * 0.7
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3.ONE * reach * 1.05, time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(m, "albedo_color:a", 0.0, time).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)

# --- Speed lines (always) and anime style FX extras (ArtStyle.anime_fx_active(); toggled with O) ---

static var _line_mat: StandardMaterial3D
static var _line_mesh: BoxMesh

## Dash speed lines: thin white streaks trailing the dasher, stretched along the dash and fading fast.
## Every style (user: liked it in the anime exploration, wanted it in the base game).
static func speed_lines(pos: Vector3, dir: Vector3, duration: float) -> void:
	if _line_mat == null:
		_line_mat = StandardMaterial3D.new()
		_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_line_mat.albedo_color = Color(1, 1, 1)
		_line_mesh = BoxMesh.new()
		_line_mesh.size = Vector3(0.035, 0.035, 1.0)
	var d := Vector3(dir.x, 0, dir.z).normalized()
	if d == Vector3.ZERO:
		return
	var side := d.cross(Vector3.UP)
	var parent := _parent()
	for i in 7:
		var mi := MeshInstance3D.new()
		mi.mesh = _line_mesh
		mi.material_override = _line_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		var length := randf_range(0.7, 1.5)
		var start := pos + side * randf_range(-0.55, 0.55) + Vector3.UP * randf_range(0.15, 0.95) - d * randf_range(0.2, 0.7)
		mi.global_position = start
		mi.look_at(start + d, Vector3.UP)
		mi.scale = Vector3(1, 1, length * 0.3)
		var t := duration * randf_range(0.7, 1.1)
		var tw := mi.create_tween().set_parallel()
		tw.tween_property(mi, "scale:z", length, t * 0.35).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "global_position", start - d * length * 0.6, t).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "transparency", 1.0, t).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(mi.queue_free)

## Wing-slap smear: a crescent in the bird's color with a dark edge, flashed for a few frames along the swing
## (the stretched in-between drawing of anime).
static func smear(pos: Vector3, yaw: float, arc_deg: float, reach: float, color: Color) -> void:
	if not ArtStyle.anime_fx_active():
		return
	var parent := _parent()
	for layer in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = _crescent_mesh(arc_deg)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = Color("2a2233") if layer == 0 else color.lightened(0.25)
		m.render_priority = 4 + layer
		m.no_depth_test = true
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		mi.global_position = pos
		mi.rotation.y = yaw
		var s := reach * (1.0 if layer == 0 else 0.92)
		mi.scale = Vector3(s, 1, s)
		var tw := mi.create_tween().set_parallel()
		tw.tween_property(mi, "rotation:y", yaw - deg_to_rad(arc_deg) * 0.25, 0.12).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "transparency", 1.0, 0.12).set_delay(0.04).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(mi.queue_free)

static func _crescent_mesh(arc_deg: float) -> ArrayMesh:
	var key := "c%d" % int(arc_deg)
	if _arc_cache.has(key):
		return _arc_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 20
	var half := deg_to_rad(arc_deg) * 0.5
	for i in n:
		var t0 := float(i) / n
		var t1 := float(i + 1) / n
		var a0 := -half + 2.0 * half * t0
		var a1 := -half + 2.0 * half * t1
		# Thick in the middle of the swing, tapering to points at both ends.
		var w0 := 0.42 * sin(PI * t0)
		var w1 := 0.42 * sin(PI * t1)
		var p := func(a: float, r: float) -> Vector3: return Vector3(-sin(a), 0, -cos(a)) * r
		for v in [p.call(a0, 1.0 - w0), p.call(a1, 1.0 - w1), p.call(a1, 1.0), p.call(a0, 1.0 - w0), p.call(a1, 1.0), p.call(a0, 1.0)]:
			st.add_vertex(v)
	var mesh := st.commit()
	_arc_cache[key] = mesh
	return mesh

static var _arc_cache := {}

static func _arc_mesh(arc_deg: float) -> ArrayMesh:
	var key := int(arc_deg)
	if _arc_cache.has(key):
		return _arc_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 18
	var half := deg_to_rad(arc_deg) * 0.5
	for i in n:
		var a0 := -half + 2.0 * half * i / n
		var a1 := -half + 2.0 * half * (i + 1) / n
		var p := func(a: float, r: float) -> Vector3: return Vector3(-sin(a), 0, -cos(a)) * r
		for v in [p.call(a0, 0.55), p.call(a1, 0.55), p.call(a1, 1.0), p.call(a0, 0.55), p.call(a1, 1.0), p.call(a0, 1.0)]:
			st.add_vertex(v)
	var mesh := st.commit()
	_arc_cache[key] = mesh
	return mesh

## Round start: a little poof where each bird appears.
static func spawn_poof(pos: Vector3, color: Color) -> void:
	dust(pos + Vector3.UP * 0.2, 7, Color.WHITE, 0.6, 1.8)
	impact(pos + Vector3.UP * 0.5, color, 5, 2.5)

static func _parent() -> Node:
	var scene := _tree().current_scene
	return scene if scene else _tree().root

## KO feather burst: chunky toon-shaded feathers in the bird's colors that float down.
static func feathers(pos: Vector3, colors: Array) -> void:
	for i in colors.size():
		var p := _particles(pos, 7 if i == 0 else 4, 1.4)
		var feather := PrismMesh.new()
		feather.size = Vector3(0.09, 0.26, 0.025)
		feather.left_to_right = 0.5
		feather.material = ToonMaterials.character(colors[i], true)
		p.mesh = feather
		p.direction = Vector3.UP
		p.spread = 180.0
		p.initial_velocity_min = 3.0
		p.initial_velocity_max = 6.5
		p.gravity = Vector3(0, -3.5, 0)
		p.damping_min = 3.0
		p.damping_max = 5.0
		p.angular_velocity_min = -360.0
		p.angular_velocity_max = 360.0
		p.particle_flag_rotate_y = true
		p.scale_amount_min = 0.7
		p.scale_amount_max = 1.2
		p.scale_amount_curve = _curve([Vector2(0, 0.4), Vector2(0.1, 1.0), Vector2(0.8, 1.0), Vector2(1, 0.0)])
		_fire(p)

## Water: droplets flicking up plus an expanding ripple ring (wading hops, arrows landing in the puddle).
static func splash(pos: Vector3, amount := 7, power := 1.0) -> void:
	var p := _particles(pos + Vector3.UP * 0.05, amount, 0.45)
	var q := SphereMesh.new()
	q.radius = 0.04
	q.height = 0.08
	q.radial_segments = 6
	q.rings = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color("eaf8ff")
	q.material = m
	p.mesh = q
	p.direction = Vector3.UP
	p.spread = 40.0
	p.initial_velocity_min = 1.2 * power
	p.initial_velocity_max = 2.4 * power
	p.gravity = Vector3(0, -9, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.1
	_fire(p)
	ripple(pos, 0.5 * power)

static func ripple(pos: Vector3, size := 0.5) -> void:
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	torus.rings = 24
	torus.ring_segments = 3
	mi.mesh = torus
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.92, 0.97, 1.0, 0.8)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_parent().add_child(mi)
	mi.global_position = Vector3(pos.x, 0.03, pos.z)
	mi.scale = Vector3(size * 0.3, 0.05, size * 0.3)
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3(size, 0.05, size), 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.6)
	tw.chain().tween_callback(mi.queue_free)

## Is this point in any water (Birdbath puddles)?
static func in_water(pos: Vector3) -> bool:
	for w in _tree().get_nodes_in_group("water"):
		if w.in_water(pos):
			return true
	return false

static func _particles(pos: Vector3, amount: int, lifetime: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = lifetime
	p.explosiveness = 1.0
	p.local_coords = false
	_ensure_materials()
	var scene := _tree().current_scene
	(scene if scene else _tree().root).add_child(p)
	p.global_position = pos
	return p

static func _fire(p: CPUParticles3D) -> void:
	p.emitting = true
	p.finished.connect(p.queue_free)

static func _curve(points: Array) -> Curve:
	var c := Curve.new()
	for pt: Vector2 in points:
		c.add_point(pt)
	return c

static func _fade(color: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(color, 0.85))
	g.set_color(1, Color(color, 0.0))
	return g
