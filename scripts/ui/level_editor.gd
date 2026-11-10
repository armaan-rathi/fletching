extends Node3D
## In-game level editor (title screen: E). Seen through the real arena camera, so what you build is what
## you play. Layouts are JSON (MapBuilder); saved maps show up in Game settings, and Play test-runs the map
## with CPU birds and comes back here (MatchManager.editor_session keeps the unsaved state).
##
## Mouse: pick an item in the palette, click to place (keeps placing; right-click or Esc to stop).
##        With no item picked: click to select, drag to move. Wheel rotates the selection.
## Keys:  Q / E rotate (Shift: fine) · [ / ] scale · Delete / X delete · Ctrl+D duplicate · G grid snap
##        Ctrl+Z undo · Ctrl+Y / Ctrl+Shift+Z redo · Ctrl+S save · P play · Esc stop / deselect / leave

const TITLE := "res://scenes/ui/title_screen.tscn"
const GRID_SHADER := preload("res://assets/shaders/editor_grid.gdshader")
const ROT_STEP := 15.0
const ROT_FINE := 5.0
const SCALE_STEP := 0.1
const MAX_UNDO := 60
const HELP := "Drag: move   Wheel / Q E: rotate (Shift fine)   [ ]: scale   Del: delete   Ctrl+D: duplicate   G: grid   Ctrl+Z / Y: undo / redo   Ctrl+S: save   P: play   Esc: back"

var layout := {}
var path := ""
var dirty := false
var brush := ""
var selected := -1
var hovered := -1
var snap := true

var _cam: ArenaCamera
var _ground_mat: ShaderMaterial
var _border: Node3D
var _items_root: Node3D
var _nodes: Array[Node3D] = []
var _undo: Array = []
var _redo: Array = []
var _dragging := false
var _drag_offset := Vector2.ZERO
var _drag_before := {}
var _drag_moved := false
var _last_mouse := Vector2.ZERO
var _last_pose := {} # type -> [yaw, scale] used for new items of that type
var _sel_ring: MeshInstance3D
var _hover_ring: MeshInstance3D
var _brush_ring: MeshInstance3D
var _brush_label: Label3D
var _grid: MeshInstance3D
var _confirm := ""
var _confirm_t := 0.0

var _ui: CanvasLayer
var _title: Label
var _name_edit: LineEdit
var _w_label: Label
var _d_label: Label
var _palette := {}
var _select_btn: Button
var _snap_btn: Button
var _status: Label
var _toast: Label
var _toast_t := 0.0
var _open_panel: Control

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var sess: Dictionary = MatchManager.editor_session
	if sess.is_empty():
		layout = MapBuilder.new_layout()
	else:
		layout = sess["layout"].duplicate(true)
		path = sess.get("path", "")
		dirty = sess.get("dirty", false)
	MatchManager.editor_session = {}
	var world := MapBuilder.build_world(self, MapBuilder.size_of(layout))
	_cam = world["camera"]
	_ground_mat = world["ground_material"]
	_border = Node3D.new()
	_border.name = "Border"
	add_child(_border)
	_items_root = Node3D.new()
	_items_root.name = "Items"
	add_child(_items_root)
	_build_overlays()
	_build_ui()
	_rebuild_arena()
	_rebuild_items()
	_refresh_ui()

func _exit_tree() -> void:
	MapBuilder.set_arena(MapBuilder.DEFAULT_ARENA)

# --- Scene ----------------------------------------------------------------------------------

func _ring(color: Color, thickness := 0.1) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.0 - thickness
	torus.outer_radius = 1.0
	torus.rings = 40
	torus.ring_segments = 4
	mi.mesh = torus
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.render_priority = 20
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi

func _build_overlays() -> void:
	_sel_ring = _ring(UiKit.WARM, 0.14)
	_hover_ring = _ring(Color(1, 1, 1, 0.55), 0.08)
	_brush_ring = _ring(Color(0.75, 1.0, 0.7, 0.8), 0.1)
	_brush_label = Label3D.new()
	_brush_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_brush_label.no_depth_test = true
	_brush_label.render_priority = 21
	_brush_label.font = UiKit.font(0.7)
	_brush_label.font_size = 64
	_brush_label.outline_size = 16
	_brush_label.pixel_size = 0.004
	_brush_label.visible = false
	add_child(_brush_label)
	_grid = MeshInstance3D.new()
	_grid.mesh = PlaneMesh.new()
	_grid.position.y = 0.015
	var gm := ShaderMaterial.new()
	gm.shader = GRID_SHADER
	_grid.material_override = gm
	_grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_grid)

func _size() -> Vector2:
	return MapBuilder.size_of(layout)

func _rebuild_arena() -> void:
	var size := _size()
	for c in _border.get_children():
		c.queue_free()
	MapBuilder.build_border(_border, size, int(layout.get("seed", 7)))
	MapBuilder.set_arena(size)
	_cam.arena_size = size
	(_grid.mesh as PlaneMesh).size = size
	(_grid.material_override as ShaderMaterial).set_shader_parameter("half_size", size * 0.5)

func _rebuild_items() -> void:
	for c in _items_root.get_children():
		c.queue_free()
	_nodes.clear()
	var spawn_i := 0
	for it in layout["items"]:
		var n := MapBuilder.place(_items_root, it)
		if it["type"] == "spawn":
			_decorate_spawn(n, spawn_i)
			spawn_i += 1
		_nodes.append(n)
	MapBuilder.apply_dirt(_ground_mat, layout["items"])
	selected = clampi(selected, -1, _nodes.size() - 1)
	_update_rings()

## Spawns are invisible in game; in the editor they get a player-colored ring and a label.
func _decorate_spawn(n: Node3D, i: int) -> void:
	var col: Color = MatchManager.PLAYER_COLORS[i % 4]
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.55
	torus.rings = 24
	torus.ring_segments = 4
	ring.mesh = torus
	ring.scale = Vector3(1, 0.15, 1)
	ring.position.y = 0.03
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(ring)
	var l := Label3D.new()
	l.text = "Spawn %d" % (i + 1)
	l.font = UiKit.font(0.7)
	l.font_size = 56
	l.outline_size = 14
	l.pixel_size = 0.004
	l.modulate = col
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position.y = 0.5
	n.add_child(l)

## Updates one item's node in place (move / rotate / scale) without rebuilding everything.
func _sync(i: int) -> void:
	var it: Dictionary = layout["items"][i]
	var n := _nodes[i]
	var info := MapCatalog.info(it["type"])
	n.position = Vector3(it["x"], 0, it["z"])
	n.rotation_degrees.y = it["yaw"]
	if not info.get("fixed_scale", false) and info.get("kind", "") != "dirt":
		n.scale = Vector3.ONE * float(info.get("base", 1.0)) * float(it["scale"])
	if it["type"] == "dirt":
		MapBuilder.apply_dirt(_ground_mat, layout["items"])
	_update_rings()

func _place_ring(ring: MeshInstance3D, i: int) -> void:
	if i < 0 or i >= layout["items"].size():
		ring.visible = false
		return
	var it: Dictionary = layout["items"][i]
	var r := maxf(MapCatalog.pick_radius(it), 0.35) + 0.12
	ring.visible = true
	ring.position = Vector3(it["x"], 0.04, it["z"])
	ring.scale = Vector3(r, 0.2, r)

func _update_rings() -> void:
	_place_ring(_sel_ring, selected)
	_place_ring(_hover_ring, hovered if hovered != selected and brush == "" else -1)

# --- Picking ----------------------------------------------------------------------------------

func _ground_point(screen: Vector2) -> Variant:
	var o := _cam.project_ray_origin(screen)
	var d := _cam.project_ray_normal(screen)
	if absf(d.y) < 1e-4:
		return null
	var t := -o.y / d.y
	if t < 0.0:
		return null
	var p := o + d * t
	return Vector2(p.x, p.z)

## Item under the cursor: the ray is tested against each item's pick cylinder at a few heights.
func _pick(screen: Vector2) -> int:
	var o := _cam.project_ray_origin(screen)
	var d := _cam.project_ray_normal(screen)
	if absf(d.y) < 1e-4:
		return -1
	var best := -1
	var best_score := INF
	for i in layout["items"].size():
		var it: Dictionary = layout["items"][i]
		var r := maxf(MapCatalog.pick_radius(it), 0.3)
		var h := MapCatalog.pick_height(it)
		for y: float in [0.0, h * 0.5, h]:
			var p := o + d * ((y - o.y) / d.y)
			var score := Vector2(p.x - it["x"], p.z - it["z"]).length() / r
			if score < 1.0 and score < best_score:
				best_score = score
				best = i
	return best

func _snapped(p: Vector2) -> Vector2:
	if snap:
		p = p.snapped(Vector2.ONE * MapCatalog.SNAP)
	var half := _size() * 0.5 - Vector2(0.4, 0.4)
	return p.clamp(-half, half)

# --- Editing ----------------------------------------------------------------------------------

func _snapshot() -> Dictionary:
	return {"items": layout["items"].duplicate(true), "size": layout["size"].duplicate()}

func _push_undo(snap_before: Dictionary = {}) -> void:
	_undo.append(snap_before if not snap_before.is_empty() else _snapshot())
	if _undo.size() > MAX_UNDO:
		_undo.pop_front()
	_redo.clear()
	dirty = true

func _restore(s: Dictionary) -> void:
	var resized: bool = s["size"] != layout["size"]
	layout["items"] = s["items"].duplicate(true)
	layout["size"] = s["size"].duplicate()
	selected = -1
	if resized:
		_rebuild_arena()
	_rebuild_items()
	dirty = true
	_refresh_ui()

func _undo_step(redo := false) -> void:
	var from: Array = _redo if redo else _undo
	var to: Array = _undo if redo else _redo
	if from.is_empty():
		_show_toast("Nothing to redo" if redo else "Nothing to undo")
		Sfx.play("ui_error")
		return
	Sfx.play("ui_change", 1.1 if redo else 0.9)
	to.append(_snapshot())
	_restore(from.pop_back())

func _add_item(type: String, at: Vector2) -> int:
	var info := MapCatalog.info(type)
	if info.has("max") and MapBuilder.count(layout, type) >= int(info["max"]):
		_show_toast("Max %d %s" % [info["max"], info["label"].to_lower() + ("s" if int(info["max"]) > 1 else "")])
		Sfx.play("ui_error")
		return -1
	_push_undo()
	var pose: Array = _last_pose.get(type, [0.0, 1.0])
	var p := _snapped(at)
	layout["items"].append(MapBuilder.item(type, p.x, p.y, pose[0], pose[1]))
	_rebuild_items()
	Sfx.play("ed_place")
	return layout["items"].size() - 1

func _delete_selected() -> void:
	if selected < 0:
		return
	_push_undo()
	layout["items"].remove_at(selected)
	Sfx.play("ed_delete")
	selected = -1
	_rebuild_items()
	_refresh_ui()

func _duplicate_selected() -> void:
	if selected < 0:
		return
	var it: Dictionary = layout["items"][selected]
	var i := _add_item(it["type"], Vector2(it["x"] + 1.0, it["z"] + 0.5))
	if i >= 0:
		layout["items"][i]["yaw"] = it["yaw"]
		layout["items"][i]["scale"] = it["scale"]
		_sync(i)
		selected = i
		_refresh_ui()

func _rotate_selected(deg: float) -> void:
	if selected < 0:
		return
	_push_undo()
	var it: Dictionary = layout["items"][selected]
	it["yaw"] = wrapf(snappedf(it["yaw"] + deg, 0.1), 0.0, 360.0)
	Sfx.play("ed_tick", 1.0 + (0.05 if deg > 0.0 else -0.05))
	_last_pose[it["type"]] = [it["yaw"], it["scale"]]
	_sync(selected)
	_refresh_ui()

func _scale_selected(d: float) -> void:
	if selected < 0:
		return
	var it: Dictionary = layout["items"][selected]
	var rng := MapCatalog.scale_range(it["type"])
	var s := clampf(snappedf(it["scale"] + d, 0.01), rng.x, rng.y)
	if is_equal_approx(s, it["scale"]):
		_show_toast("%s can't be scaled further" % MapCatalog.info(it["type"])["label"] if rng.x != rng.y else "%s has a fixed size" % MapCatalog.info(it["type"])["label"])
		Sfx.play("ui_error")
		return
	_push_undo()
	it["scale"] = s
	Sfx.play("ed_tick", 0.9 + 0.2 * s)
	_last_pose[it["type"]] = [it["yaw"], it["scale"]]
	_sync(selected)
	_refresh_ui()

func _resize(d: Vector2) -> void:
	var s := (_size() + d).clamp(MapCatalog.MIN_SIZE, MapCatalog.MAX_SIZE)
	if s == _size():
		_show_toast("Arena size limits: %d-%d × %d-%d m" % [MapCatalog.MIN_SIZE.x, MapCatalog.MAX_SIZE.x, MapCatalog.MIN_SIZE.y, MapCatalog.MAX_SIZE.y])
		Sfx.play("ui_error")
		return
	_push_undo()
	layout["size"] = [s.x, s.y]
	# Keep everything inside the new walls.
	var half := s * 0.5 - Vector2(0.4, 0.4)
	for it in layout["items"]:
		var p := Vector2(it["x"], it["z"]).clamp(-half, half)
		it["x"] = p.x
		it["z"] = p.y
	_rebuild_arena()
	_rebuild_items()
	_refresh_ui()

func _toggle_snap() -> void:
	snap = not snap
	_show_toast("Grid snap %s" % ("on (0.5 m)" if snap else "off"))
	_refresh_ui()

func _set_brush(type: String) -> void:
	brush = type if brush != type else ""
	if brush != "":
		selected = -1
	_refresh_ui()
	_update_brush_preview()

# --- Files / play ---------------------------------------------------------------------------

## Returns true if it's fine to throw away unsaved changes (asks for a second press first).
func _confirm_discard(action: String) -> bool:
	if not dirty or (_confirm == action and _confirm_t > 0.0):
		_confirm = ""
		return true
	_confirm = action
	_confirm_t = 2.5
	_show_toast("Unsaved changes - press %s again to discard them" % action)
	return false

func _save() -> void:
	var name := _name_edit.text.strip_edges()
	if name == "":
		name = "Untitled"
	layout["name"] = name
	layout["version"] = MapBuilder.VERSION
	var target := MapBuilder.file_for(name)
	var err := MapBuilder.save_layout(layout, target)
	if err != OK:
		_show_toast("Couldn't save: %s" % error_string(err))
		return
	path = target
	dirty = false
	Sfx.play("ed_save")
	MatchManager.refresh_maps()
	var warn := MapBuilder.problems(layout)
	_show_toast("Saved %s%s" % [target.replace("res://", ""), ("  (" + warn[0] + ")") if warn.size() > 0 else ""])
	_refresh_ui()

func _new_map() -> void:
	if not _confirm_discard("New"):
		return
	layout = MapBuilder.new_layout("New map", _size())
	path = ""
	dirty = false
	_undo.clear()
	_redo.clear()
	selected = -1
	_rebuild_arena()
	_rebuild_items()
	_refresh_ui()
	_show_toast("New map: 4 spawn points to start with")

func _open_map(p: String) -> void:
	_close_open_panel()
	var l := MapBuilder.load_layout(p)
	if l.is_empty():
		_show_toast("Couldn't read %s" % p)
		return
	layout = l
	path = p
	dirty = false
	_undo.clear()
	_redo.clear()
	selected = -1
	_rebuild_arena()
	_rebuild_items()
	_refresh_ui()
	_show_toast("Opened %s" % layout.get("name", p.get_file()))

func _play() -> void:
	layout["name"] = _name_edit.text.strip_edges() if _name_edit.text.strip_edges() != "" else "Untitled"
	var probs := MapBuilder.problems(layout)
	if probs.size() > 0:
		_show_toast(probs[0])
		Sfx.play("ui_error")
		return
	MatchManager.editor_session = {"layout": layout.duplicate(true), "path": path, "dirty": dirty}
	MatchManager.custom_layout = layout.duplicate(true)
	if MatchManager.players.is_empty():
		MatchManager.setup_quick_play()
	UiKit.go_to(get_tree(), MatchManager.CUSTOM_MAP_SCENE)

func _leave() -> void:
	if not _confirm_discard("Esc"):
		return
	set_process_unhandled_input(false)
	UiKit.go_to(get_tree(), TITLE)

# --- Input ------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_last_mouse = event.position
		if _dragging and selected >= 0:
			var g = _ground_point(event.position)
			if g != null:
				var p: Vector2 = _snapped(g + _drag_offset)
				var it: Dictionary = layout["items"][selected]
				if p != Vector2(it["x"], it["z"]):
					it["x"] = snappedf(p.x, 0.01)
					it["z"] = snappedf(p.y, 0.01)
					_drag_moved = true
					_sync(selected)
					_refresh_status()
		else:
			hovered = _pick(event.position) if brush == "" else -1
			_update_rings()
			_update_brush_preview()
		return
	if event is InputEventMouseButton:
		_on_mouse_button(event)
		return
	if event is InputEventKey and event.pressed:
		_on_key(event)

func _on_mouse_button(e: InputEventMouseButton) -> void:
	if e.pressed:
		get_viewport().gui_release_focus()
		_close_open_panel()
	match e.button_index:
		MOUSE_BUTTON_LEFT:
			if e.pressed:
				var g = _ground_point(e.position)
				if brush != "":
					if g == null:
						return
					var i := _add_item(brush, g)
					if i >= 0:
						selected = i
						_start_drag(g, {})
				else:
					var i := _pick(e.position)
					if i >= 0 and i != selected:
						Sfx.play("ui_move")
					selected = i
					if i >= 0 and g != null:
						_start_drag(g, _snapshot())
				_update_rings()
				_refresh_ui()
			elif _dragging:
				_dragging = false
				if _drag_moved and not _drag_before.is_empty():
					_push_undo(_drag_before)
					_refresh_ui()
		MOUSE_BUTTON_RIGHT:
			if e.pressed:
				if brush != "":
					_set_brush("")
				else:
					selected = -1
					_update_rings()
					_refresh_ui()
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed and selected >= 0:
				var dir := 1.0 if e.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
				if e.is_command_or_control_pressed():
					_scale_selected(dir * SCALE_STEP)
				else:
					_rotate_selected(dir * (ROT_FINE if e.shift_pressed else ROT_STEP))

func _start_drag(ground: Vector2, before: Dictionary) -> void:
	var it: Dictionary = layout["items"][selected]
	_dragging = true
	_drag_moved = false
	_drag_before = before
	_drag_offset = Vector2(it["x"], it["z"]) - ground if not before.is_empty() else Vector2.ZERO

func _on_key(e: InputEventKey) -> void:
	var ctrl := e.is_command_or_control_pressed()
	match e.keycode:
		KEY_Z when ctrl:
			_undo_step(e.shift_pressed)
		KEY_Y when ctrl:
			_undo_step(true)
		KEY_S when ctrl:
			_save()
		KEY_D when ctrl:
			_duplicate_selected()
		KEY_Q:
			_rotate_selected(-(ROT_FINE if e.shift_pressed else ROT_STEP))
		KEY_E:
			_rotate_selected(ROT_FINE if e.shift_pressed else ROT_STEP)
		KEY_BRACKETLEFT:
			_scale_selected(-SCALE_STEP)
		KEY_BRACKETRIGHT:
			_scale_selected(SCALE_STEP)
		KEY_DELETE, KEY_BACKSPACE, KEY_X:
			_delete_selected()
		KEY_G:
			_toggle_snap()
		KEY_P:
			_play()
		KEY_ESCAPE:
			if _open_panel:
				_close_open_panel()
			elif brush != "":
				_set_brush("")
			elif selected >= 0:
				selected = -1
				_update_rings()
				_refresh_ui()
			else:
				_leave()
		_:
			return
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	_confirm_t = maxf(_confirm_t - delta, 0.0)
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t / 0.4, 0.0, 1.0)

func _update_brush_preview() -> void:
	var g = _ground_point(_last_mouse) if brush != "" else null
	if g == null:
		_brush_ring.visible = false
		_brush_label.visible = false
		return
	var p: Vector2 = _snapped(g)
	var r := maxf(float(MapCatalog.info(brush).get("r", 0.5)) * float(_last_pose.get(brush, [0.0, 1.0])[1]), 0.35)
	_brush_ring.visible = true
	_brush_ring.position = Vector3(p.x, 0.04, p.y)
	_brush_ring.scale = Vector3(r, 0.2, r)
	_brush_label.visible = true
	_brush_label.text = MapCatalog.info(brush)["label"]
	_brush_label.position = Vector3(p.x, 0.9, p.y)

# --- UI -----------------------------------------------------------------------------------------

func _button(text: String, cb: Callable, size := 20, pad := 5) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", UiKit.font(0.6))
	b.add_theme_font_size_override("font_size", size)
	for st in ["normal", "hover", "pressed", "disabled"]:
		var border := UiKit.WARM if st == "hover" or st == "pressed" else Color(1, 1, 1, 0.12)
		var sb := UiKit.panel_style(border, UiKit.BG_SOFT if st != "pressed" else Color(UiKit.WARM, 0.25), 10, 2)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = pad
		sb.content_margin_bottom = pad
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", UiKit.TEXT)
	b.add_theme_color_override("font_hover_color", UiKit.WARM)
	b.add_theme_color_override("font_pressed_color", UiKit.WARM)
	b.pressed.connect(func(): Sfx.play("ui_confirm"))
	b.pressed.connect(cb)
	return b

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)

	# Top bar: name, arena size, file + play buttons.
	var top := UiKit.panel(Color(1, 1, 1, 0.12), UiKit.BG)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 12
	top.offset_right = -12
	top.offset_top = 10
	root.add_child(top)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	top.add_child(bar)
	_title = UiKit.label("Level editor", 26, UiKit.WARM, 0.8)
	bar.add_child(_title)
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(240, 0)
	_name_edit.placeholder_text = "Map name"
	_name_edit.add_theme_font_override("font", UiKit.font(0.6))
	_name_edit.add_theme_font_size_override("font_size", 20)
	_name_edit.text_changed.connect(_on_name_changed)
	_name_edit.text_submitted.connect(func(_t): get_viewport().gui_release_focus())
	bar.add_child(_name_edit)
	bar.add_child(UiKit.label("  Width", 20, UiKit.TEXT_DIM, 0.5))
	bar.add_child(_button("−", func(): _resize(Vector2(-1, 0))))
	_w_label = UiKit.label("20 m", 20, UiKit.TEXT, 0.6)
	bar.add_child(_w_label)
	bar.add_child(_button("+", func(): _resize(Vector2(1, 0))))
	bar.add_child(UiKit.label("  Depth", 20, UiKit.TEXT_DIM, 0.5))
	bar.add_child(_button("−", func(): _resize(Vector2(0, -1))))
	_d_label = UiKit.label("14 m", 20, UiKit.TEXT, 0.6)
	bar.add_child(_d_label)
	bar.add_child(_button("+", func(): _resize(Vector2(0, 1))))
	_snap_btn = _button("Grid: on", _toggle_snap)
	bar.add_child(_snap_btn)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	bar.add_child(_button("New", _new_map))
	bar.add_child(_button("Open", _show_open_panel))
	bar.add_child(_button("Save", _save))
	bar.add_child(_button("▶ Play", _play))
	bar.add_child(_button("Exit", _leave))

	# Palette on the left.
	var pal := UiKit.panel(Color(1, 1, 1, 0.12), UiKit.BG)
	pal.position = Vector2(12, 84)
	pal.custom_minimum_size = Vector2(210, 0)
	root.add_child(pal)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	pal.add_child(v)
	_select_btn = _button("Select / move", func(): _set_brush(""), 16, 3)
	v.add_child(_select_btn)
	for c in MapCatalog.CATEGORIES:
		v.add_child(UiKit.label(c[1], 16, UiKit.TEXT_DIM, 0.6))
		for type in MapCatalog.types_in(c[0]):
			var b := _button(MapCatalog.info(type)["label"], _set_brush.bind(type), 15, 2)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			v.add_child(b)
			_palette[type] = b

	# Status + help at the bottom, toast above it.
	var bottom := UiKit.panel(Color(1, 1, 1, 0.12), UiKit.BG)
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 12
	bottom.offset_right = -12
	bottom.offset_bottom = -10
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(bottom)
	var bv := VBoxContainer.new()
	bottom.add_child(bv)
	_status = UiKit.label("", 20, UiKit.TEXT, 0.6)
	bv.add_child(_status)
	bv.add_child(UiKit.label(HELP, 16, UiKit.TEXT_DIM, 0.5))
	_toast = UiKit.label("", 26, UiKit.WARM, 0.8)
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_left = -700
	_toast.offset_right = 700
	_toast.offset_top = -150
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast)

func _show_open_panel() -> void:
	if _open_panel:
		_close_open_panel()
		return
	var maps := MapBuilder.list_layouts()
	var p := UiKit.panel(UiKit.WARM, UiKit.BG)
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.custom_minimum_size = Vector2(420, 0)
	p.position = Vector2(-210, -200)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	v.add_child(UiKit.label("Open a map", 28, UiKit.WARM, 0.8))
	if maps.is_empty():
		v.add_child(UiKit.label("No saved maps yet.", 20, UiKit.TEXT_DIM, 0.5))
	for m in maps:
		var b := _button(m["name"], _try_open.bind(m["path"]), 20)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(b)
	v.add_child(_button("Cancel", _close_open_panel, 18))
	_ui.add_child(p)
	_open_panel = p

func _try_open(p: String) -> void:
	if _confirm_discard("Open"):
		_open_map(p)

func _close_open_panel() -> void:
	if _open_panel:
		_open_panel.queue_free()
		_open_panel = null

func _show_toast(text: String) -> void:
	_toast.text = text
	_toast_t = 2.6
	_toast.modulate.a = 1.0
	UiKit.pop(_toast, 0.08)

func _on_name_changed(_t: String) -> void:
	dirty = true
	_refresh_title()

func _refresh_title() -> void:
	_title.text = "Level editor" + (" •" if dirty else "")

func _refresh_ui() -> void:
	_refresh_title()
	if not _name_edit.has_focus():
		_name_edit.text = layout.get("name", "")
	var s := _size()
	_w_label.text = "%d m" % s.x
	_d_label.text = "%d m" % s.y
	for type in _palette:
		_palette[type].add_theme_color_override("font_color", UiKit.WARM if type == brush else UiKit.TEXT)
		_palette[type].add_theme_stylebox_override("normal", _palette[type].get_theme_stylebox("pressed") if type == brush else _palette[type].get_theme_stylebox("disabled"))
	_select_btn.add_theme_color_override("font_color", UiKit.WARM if brush == "" else UiKit.TEXT)
	_snap_btn.text = "Grid: %s" % ("on" if snap else "off")
	_grid.visible = snap
	_refresh_status()
	_update_rings()

func _refresh_status() -> void:
	var counts := "Spawns %d/4   Pads %d   Nests %d   Items %d" % [MapBuilder.count(layout, "spawn"), MapBuilder.count(layout, "pad"), MapBuilder.count(layout, "nest"), layout["items"].size()]
	var what := ""
	if brush != "":
		what = "Placing: %s - click to place, right-click / Esc to stop" % MapCatalog.info(brush)["label"]
	elif selected >= 0:
		var it: Dictionary = layout["items"][selected]
		what = "%s   x %.1f  z %.1f   %d°   ×%.2f" % [MapCatalog.info(it["type"])["label"], it["x"], it["z"], int(it["yaw"]), it["scale"]]
	else:
		what = "Pick something on the left to place it, or click an item to select it"
	_status.text = what + "      " + counts
