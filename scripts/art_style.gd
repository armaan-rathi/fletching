class_name ArtStyle
extends RefCounted
## Art style exploration switcher (debug keys, during play): U cycles both layers together (Shift+U back),
## Y characters only, P environment only, O the shown styles' option (anime FX extras / watercolor pencil lines),
## I tilt-shift.
## Characters (birds, bows, quivers, flying arrows) and the environment each have a style, so hybrids can be
## tested. Styles live in the shared shaders (art_style.gdshaderinc via toon lighting, toon surfaces, ground,
## outlines) behind the global shader uniforms `art_style_char` / `art_style_env`, plus:
## - two stencil-gated full-screen scene passes (style_scene_env / style_scene_char): per-layer effects that need
##   the rendered image (watercolor bleeding, anime inner lines, pixelated birds);
## - one full-screen post pass (style_post.gdshader) under the HUD for frame-level effects, which follow the
##   environment style (paper, grain, bokashi, the pixel-art palette), plus tilt-shift and anime impact frames.
## Frame-level switches: felt or claymation on either layer steps rendering at 12 fps (physics and input keep
## running at 60 Hz); a pixel-art environment renders 3D at 1/3 resolution and snaps the camera to its pixel grid;
## anime on either layer turns on the environment glow (bloom on the rim light). No assets are rebuilt.

const NAMES := ["Baseline toon", "Field guide", "Felt stop-motion", "Risograph", "Sketchbook", "Anime",
	"Watercolor", "Woodblock print", "3D pixel art", "Claymation", "Colored line art"]
const ANIME := 5
const WATERCOLOR := 6
const PIXEL := 8
const STEPPED := [2, 9] # felt, claymation
const SCENE_PASS := [5, 6, 10] # styles with work in the scene passes
const POST_SHADER := preload("res://assets/shaders/style_post.gdshader")
const SCENE_ENV := preload("res://assets/shaders/style_scene_env.gdshader")
const SCENE_CHAR := preload("res://assets/shaders/style_scene_char.gdshader")
const STOP_MOTION_FPS := 12
const PIXEL_SIZE := 3

static var char_style := 0
static var env_style := 0
static var tilt_shift := false
static var anime_fx := true    # wing-slap smears, KO impact frames (anime characters); speed lines are always on
static var pencil_lines := false # watercolor
static var _layer: CanvasLayer
static var _rect: ColorRect
static var _scene_env: MeshInstance3D
static var _scene_char: MeshInstance3D
static var _saved_max_fps := 0
static var _stepping := false
static var _saved_scale := 1.0
static var _pixelated := false
static var _impact_tween: Tween

static func cycle(step := 1) -> void:
	set_style(char_style + step)

static func cycle_char(step := 1) -> void:
	set_styles(char_style + step, env_style)

static func cycle_env(step := 1) -> void:
	set_styles(char_style, env_style + step)

## Same style on both layers.
static func set_style(i: int) -> void:
	set_styles(i, i)

static func set_styles(character: int, environment: int) -> void:
	char_style = wrapi(character, 0, NAMES.size())
	env_style = wrapi(environment, 0, NAMES.size())
	apply()

static func toggle_tilt_shift() -> void:
	tilt_shift = not tilt_shift
	apply()

## Toggles the option of the styles on screen (anime FX extras, watercolor pencil lines). Returns false if the
## shown styles have none.
static func toggle_option() -> bool:
	var any := false
	if char_style == ANIME or env_style == ANIME:
		anime_fx = not anime_fx
		any = true
	if char_style == WATERCOLOR or env_style == WATERCOLOR:
		pencil_lines = not pencil_lines
		any = true
	apply()
	return any

static func label() -> String:
	var s: String = NAMES[char_style] if char_style == env_style else "Birds: %s · World: %s" % [NAMES[char_style], NAMES[env_style]]
	if char_style == ANIME or env_style == ANIME:
		s += " (FX extras %s)" % ("on" if anime_fx else "off")
	if char_style == WATERCOLOR or env_style == WATERCOLOR:
		s += " (pencil lines %s)" % ("on" if pencil_lines else "off")
	return s + (" + tilt-shift" if tilt_shift else "")

## Anime FX extras (speed lines, smears, impact frames) are on: anime characters with the option enabled.
static func anime_fx_active() -> bool:
	return char_style == ANIME and anime_fx

## Pixel-art environment: the camera snaps its offsets to this many meters (one low-res pixel). 0 = no snapping.
static func pixel_snap(cam: Camera3D) -> float:
	if env_style != PIXEL or cam == null:
		return 0.0
	var h := cam.get_viewport().get_visible_rect().size.y
	return cam.size / maxf(h, 1.0) * PIXEL_SIZE

static func apply() -> void:
	RenderingServer.global_shader_parameter_set("art_style_char", char_style)
	RenderingServer.global_shader_parameter_set("art_style_env", env_style)
	RenderingServer.global_shader_parameter_set("art_style_opts", 1 if pencil_lines else 0)
	_ensure_nodes()
	var tree := Engine.get_main_loop() as SceneTree
	if _rect:
		_rect.visible = env_style != 0 or tilt_shift or (_impact_tween != null and _impact_tween.is_running())
		var m := _rect.material as ShaderMaterial
		m.set_shader_parameter("style", env_style)
		m.set_shader_parameter("tilt_shift", tilt_shift)
		m.set_shader_parameter("pixel_size", float(PIXEL_SIZE))
	if _scene_env:
		_scene_env.visible = env_style in SCENE_PASS
		(_scene_env.material_override as ShaderMaterial).set_shader_parameter("style", env_style)
	if _scene_char:
		var pixel_birds := char_style == PIXEL and env_style != PIXEL # a pixel environment pixelates the whole frame
		_scene_char.visible = char_style in SCENE_PASS or pixel_birds
		(_scene_char.material_override as ShaderMaterial).set_shader_parameter("style", char_style)
	# Felt / claymation: stop-motion stepping.
	var want := char_style in STEPPED or env_style in STEPPED
	if want and not _stepping:
		_saved_max_fps = Engine.max_fps
		Engine.max_fps = STOP_MOTION_FPS
		_stepping = true
	elif not want and _stepping:
		Engine.max_fps = _saved_max_fps
		_stepping = false
	# Pixel-art environment: low-res 3D render (the post pass samples it on the same pixel grid).
	if tree and tree.root:
		var px := env_style == PIXEL
		if px and not _pixelated:
			_saved_scale = tree.root.scaling_3d_scale
			tree.root.scaling_3d_scale = 1.0 / PIXEL_SIZE
			_pixelated = true
		elif not px and _pixelated:
			tree.root.scaling_3d_scale = _saved_scale
			_pixelated = false
		_apply_glow(tree.root.find_world_3d())

## Anime: bloom the rim light (it goes over 1.0 in the shader) with the environment's glow. The scene's own glow
## settings are kept on the Environment as metadata and restored when anime is switched off.
static func _apply_glow(world: World3D) -> void:
	if world == null or world.environment == null:
		return
	var env := world.environment
	var want := char_style == ANIME or env_style == ANIME
	if want and not env.has_meta("as_glow"):
		env.set_meta("as_glow", [env.glow_enabled, env.glow_hdr_threshold, env.glow_intensity, env.glow_strength, env.glow_bloom, env.glow_blend_mode])
		env.glow_enabled = true
		env.glow_hdr_threshold = 1.0
		env.glow_intensity = 1.1
		env.glow_strength = 1.0
		env.glow_bloom = 0.0
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	elif not want and env.has_meta("as_glow"):
		var g: Array = env.get_meta("as_glow")
		env.glow_enabled = g[0]
		env.glow_hdr_threshold = g[1]
		env.glow_intensity = g[2]
		env.glow_strength = g[3]
		env.glow_bloom = g[4]
		env.glow_blend_mode = g[5]
		env.remove_meta("as_glow")

## Anime KO impact frame (a few frames of black-and-white with radial lines), centered on `world_pos`.
static func impact_frame(world_pos: Vector3) -> void:
	if not anime_fx_active():
		return
	_ensure_nodes()
	if _rect == null:
		return
	var cam := _rect.get_viewport().get_camera_3d()
	var m := _rect.material as ShaderMaterial
	if cam:
		m.set_shader_parameter("impact_center", cam.unproject_position(world_pos) / _rect.get_viewport_rect().size)
	if _impact_tween:
		_impact_tween.kill()
	_rect.visible = true
	# Real time: the KO's hit-stop slows the game clock to a crawl.
	_impact_tween = _rect.create_tween().set_ignore_time_scale(true)
	_impact_tween.tween_method(func(v: float) -> void: m.set_shader_parameter("impact", v), 1.0, 0.001, 0.2)
	_impact_tween.tween_callback(func() -> void:
		m.set_shader_parameter("impact", 0.0)
		ArtStyle.apply())

static func _ensure_nodes() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	if not (_layer and is_instance_valid(_layer)):
		_layer = CanvasLayer.new()
		_layer.name = "ArtStylePost"
		_layer.layer = -2 # over the 3D view, under the vignette (-1) and all HUD/UI layers
		_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		_rect = ColorRect.new()
		_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()
		m.shader = POST_SHADER
		_rect.material = m
		_rect.visible = false
		_layer.add_child(_rect)
		tree.root.add_child.call_deferred(_layer)
	if not (_scene_env and is_instance_valid(_scene_env)):
		_scene_env = _make_scene_pass("ArtStyleSceneEnv", SCENE_ENV, false)
		tree.root.add_child.call_deferred(_scene_env)
	if not (_scene_char and is_instance_valid(_scene_char)):
		_scene_char = _make_scene_pass("ArtStyleSceneChar", SCENE_CHAR, true)
		tree.root.add_child.call_deferred(_scene_char)

## A full-screen quad (its vertex shader writes clip space) that never gets culled and draws first among
## transparent things (render priority -128), so particles and x-ray silhouettes stay on top.
static func _make_scene_pass(node_name: String, shader: Shader, character: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = QuadMesh.new()
	mi.custom_aabb = AABB(Vector3(-1e4, -1e4, -1e4), Vector3(2e4, 2e4, 2e4))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = shader
	m.render_priority = Material.RENDER_PRIORITY_MIN
	m.set_shader_parameter("character_layer", character)
	m.set_shader_parameter("pixel_size", float(PIXEL_SIZE))
	mi.material_override = m
	mi.visible = false
	return mi
