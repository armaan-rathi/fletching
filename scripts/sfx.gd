class_name Sfx
extends RefCounted
## Sound effects (Stage 7). Static, like Fx: Sfx.play("event"). Every event is one row in BANK:
##   files  - variations (one picked at random, never the same one twice in a row)
##   vol    - dB. Set per event from measured loudness (tools/sfx_check.gd; packs differ by up to 25 dB) so
##            events sit on a loudness ladder (KO/explosion on top, footsteps at the bottom), with frequent sounds
##            low and no event boosted more than +4 dB over its file's own level (quiet files stay quiet).
##   pitch  - random pitch range (variation), multiplied by play()'s pitch argument
##   bus    - "SFX" (gameplay) or "UI" (menus, editor); both route to Master (with a limiter)
##   max    - most simultaneous voices of this event; gap - minimum seconds between two plays (anti-spam)
## Players live in a pool under the scene tree root (process always), so a sound started on a scene change or
## while paused plays out. Packs: Kenney RPG Audio, Kenney UI Audio, Kenney Impact Sounds (folder
## kenney_ui_sounds), all CC0. No bird voices, string twang or explosion in the packs: substitutes noted below.

const RPG := "res://assets/third_party/kenney_rpg_audio/"
const UI := "res://assets/third_party/kenney_ui_audio/"
const IMP := "res://assets/third_party/kenney_ui_sounds/" # Kenney "Impact Sounds"
const POOL_SIZE := 32

static func _n(base: String, count: int) -> Array:
	var out := []
	for i in count:
		out.append("%s_%03d.ogg" % [base, i])
	return out

static var BANK := {
	# --- Bow and arrows ---
	# (no "draw" sound: the pitched-up wood creak was the playtest's "awful squeaky wheel"; Sfx.play skips it)
	"fire": {"files": [RPG + "knifeSlice.ogg", RPG + "knifeSlice2.ogg"], "vol": -10.0, "pitch": [0.95, 1.05], "max": 4}, # swish (no twang in the packs)
	"stick_wood": {"files": _n(IMP + "impactWood_light", 5), "vol": -3.0, "pitch": [0.95, 1.1], "max": 4},
	"stick_stone": {"files": _n(IMP + "impactMining", 5), "vol": -13.0, "pitch": [1.05, 1.2], "max": 4},
	"stick_soft": {"files": _n(IMP + "impactSoft_medium", 5), "vol": -12.0, "pitch": [1.1, 1.25], "max": 4}, # ground, border bushes
	"shrike_drop": {"files": [RPG + "drawKnife1.ogg", RPG + "drawKnife2.ogg", RPG + "drawKnife3.ogg"], "vol": 4.0, "pitch": [0.7, 0.8], "max": 3}, # falling whoosh
	"shrike_land": {"files": _n(IMP + "impactSoft_heavy", 5), "vol": -9.0, "pitch": [0.85, 0.95], "max": 2}, # landing shockwave thump
	"near_miss": {"files": [RPG + "drawKnife1.ogg", RPG + "drawKnife2.ogg", RPG + "drawKnife3.ogg"], "vol": 4.0, "pitch": [1.3, 1.5], "max": 2, "gap": 0.12},
	"arrow_pickup": {"files": [RPG + "handleSmallLeather.ogg", RPG + "handleSmallLeather2.ogg"], "vol": 4.0, "pitch": [1.0, 1.15], "max": 3},
	"arrow_return": {"files": [RPG + "beltHandle1.ogg", RPG + "beltHandle2.ogg"], "vol": -5.0, "pitch": [1.1, 1.25], "max": 3},
	"empty": {"files": [RPG + "metalClick.ogg"], "vol": 2.0, "pitch": [1.2, 1.35], "max": 2, "gap": 0.15},
	# --- Movement ---
	"step": {"files": _n(IMP + "footstep_grass", 5), "vol": -22.0, "pitch": [1.1, 1.3], "max": 2, "gap": 0.14},
	"dash": {"files": [RPG + "clothBelt.ogg", RPG + "clothBelt2.ogg"], "vol": -3.5, "pitch": [1.3, 1.5], "max": 3},
	"splash": {"files": _n(IMP + "impactSoft_medium", 5), "vol": -20.5, "pitch": [1.7, 2.0], "max": 3, "gap": 0.06}, # no water sounds in the packs: high soft plip
	"bonk": {"files": _n(IMP + "impactSoft_medium", 5), "vol": -12.0, "pitch": [0.9, 1.0], "max": 2, "gap": 0.3},
	# --- Melee ---
	"swing": {"files": [RPG + "cloth1.ogg", RPG + "cloth2.ogg", RPG + "cloth3.ogg", RPG + "cloth4.ogg"], "vol": -1.0, "pitch": [1.25, 1.45], "max": 4},
	"stun": {"files": _n(IMP + "impactPunch_medium", 5), "vol": -7.5, "pitch": [1.1, 1.25], "max": 3},
	"parry": {"files": _n(IMP + "impactMetal_light", 5), "vol": -0.5, "pitch": [1.1, 1.25], "max": 3},
	"parry_ring": {"files": _n(IMP + "impactBell_heavy", 5), "vol": -7.5, "pitch": [1.7, 1.9], "max": 2},
	# --- KOs, eggs, power-ups ---
	"ko": {"files": _n(IMP + "impactPunch_heavy", 5), "vol": -1.5, "pitch": [0.95, 1.05], "max": 3},
	"egg": {"files": _n(IMP + "impactPlate_light", 5), "vol": -5.0, "pitch": [1.2, 1.4], "max": 4}, # shell crack
	"explosion": {"files": _n(IMP + "impactSoft_heavy", 5), "vol": -1.0, "pitch": [0.55, 0.65], "max": 2}, # no explosion in the packs: pitched-down thump
	"explosion_crack": {"files": _n(IMP + "impactWood_heavy", 5), "vol": -5.5, "pitch": [0.6, 0.7], "max": 2},
	"powerup_spawn": {"files": [UI + "rollover2.ogg", UI + "rollover4.ogg"], "vol": 0.0, "pitch": [0.8, 0.9], "max": 2},
	"powerup_pickup": {"files": [RPG + "handleCoins.ogg", RPG + "handleCoins2.ogg"], "vol": 2.0, "pitch": [1.1, 1.2], "max": 2},
	# --- Round flow ---
	"count": {"files": [UI + "click3.ogg"], "vol": 2.0, "pitch": [1.0, 1.0], "max": 1},
	"go": {"files": [IMP + "impactBell_heavy_002.ogg"], "vol": -2.0, "pitch": [1.3, 1.3], "max": 1},
	"round_win": {"files": [IMP + "impactBell_heavy_000.ogg"], "vol": -1.5, "pitch": [1.0, 1.0], "max": 1},
	"match_win": {"files": [IMP + "impactBell_heavy_004.ogg"], "vol": 3.0, "pitch": [0.85, 0.85], "max": 1},
	"coins": {"files": [RPG + "handleCoins.ogg", RPG + "handleCoins2.ogg"], "vol": 0.0, "pitch": [1.0, 1.1], "max": 2},
	# --- Menus (UI bus) ---
	"ui_move": {"files": [UI + "rollover1.ogg", UI + "rollover3.ogg", UI + "rollover5.ogg"], "vol": -8.0, "pitch": [1.0, 1.1], "max": 2, "bus": "UI"},
	"ui_change": {"files": [UI + "switch2.ogg", UI + "switch3.ogg"], "vol": -5.5, "pitch": [1.0, 1.1], "max": 2, "bus": "UI"},
	"ui_confirm": {"files": [UI + "click1.ogg", UI + "click2.ogg"], "vol": -0.5, "pitch": [1.0, 1.05], "max": 2, "bus": "UI"},
	"ui_back": {"files": [UI + "click4.ogg", UI + "click5.ogg"], "vol": -3.5, "pitch": [0.75, 0.8], "max": 2, "bus": "UI"},
	"ui_join": {"files": [RPG + "metalLatch.ogg"], "vol": -10.0, "pitch": [1.1, 1.2], "max": 2, "bus": "UI"},
	"ui_ready": {"files": [RPG + "handleCoins.ogg"], "vol": -1.5, "pitch": [1.2, 1.25], "max": 2, "bus": "UI"},
	"ui_pause": {"files": [RPG + "bookOpen.ogg"], "vol": 4.0, "pitch": [1.0, 1.0], "max": 1, "bus": "UI"},
	"ui_unpause": {"files": [RPG + "bookClose.ogg"], "vol": -13.0, "pitch": [1.1, 1.1], "max": 1, "bus": "UI"},
	"ui_error": {"files": [RPG + "metalClick.ogg"], "vol": 0.0, "pitch": [0.8, 0.85], "max": 1, "bus": "UI", "gap": 0.1},
	# --- Level editor (UI bus) ---
	"ed_place": {"files": [RPG + "bookPlace1.ogg", RPG + "bookPlace2.ogg", RPG + "bookPlace3.ogg"], "vol": -16.0, "pitch": [0.95, 1.1], "max": 3, "bus": "UI"},
	"ed_delete": {"files": [RPG + "cloth1.ogg", RPG + "cloth3.ogg"], "vol": -6.5, "pitch": [0.8, 0.9], "max": 2, "bus": "UI"},
	"ed_tick": {"files": [UI + "click3.ogg"], "vol": -9.0, "pitch": [1.2, 1.3], "max": 2, "bus": "UI", "gap": 0.03},
	"ed_save": {"files": [RPG + "handleCoins2.ogg"], "vol": 4.0, "pitch": [1.0, 1.0], "max": 1, "bus": "UI"},
}

static var _pool: Node
static var _players: Array[AudioStreamPlayer] = []
static var _cache := {}
static var _last_time := {}
static var _last_file := {}
static var muted := false ## tests can silence everything
## Plays per event since start (and ones dropped by max/gap), for checks.
static var counts := {}
static var dropped := {}

## Plays an event. pitch_scale multiplies the random pitch; vol_offset adds dB (e.g. louder full-charge shots).
static func play(event: String, pitch_scale := 1.0, vol_offset := 0.0) -> void:
	if muted or not BANK.has(event):
		return
	var e: Dictionary = BANK[event]
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_time.get(event, -10.0)) < float(e.get("gap", 0.0)):
		dropped[event] = dropped.get(event, 0) + 1
		return
	if not _ensure_pool():
		return
	var active := 0
	var free: AudioStreamPlayer = null
	var oldest: AudioStreamPlayer = null
	for p in _players:
		if p.playing or float(p.get_meta("t", -1.0)) == now: # started this frame (maybe not playing yet)
			if p.get_meta("event", "") == event:
				active += 1
			if oldest == null or p.get_meta("t", 0.0) < oldest.get_meta("t", 0.0):
				oldest = p
		elif free == null:
			free = p
	if active >= int(e.get("max", 4)):
		dropped[event] = dropped.get(event, 0) + 1
		return
	var player := free if free else oldest
	var files: Array = e["files"]
	var i := randi() % files.size()
	if files.size() > 1 and i == _last_file.get(event, -1):
		i = (i + 1) % files.size()
	_last_file[event] = i
	player.stream = _stream(files[i])
	player.bus = e.get("bus", "SFX")
	player.volume_db = float(e.get("vol", 0.0)) + vol_offset
	player.pitch_scale = randf_range(e["pitch"][0], e["pitch"][1]) * pitch_scale
	player.set_meta("event", event)
	player.set_meta("t", now)
	if player.is_inside_tree():
		player.play()
	else:
		player.play.call_deferred() # first sound: the pool joins the tree at the end of this frame
	_last_time[event] = now
	counts[event] = counts.get(event, 0) + 1

static func _stream(path: String) -> AudioStream:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]

static func _ensure_pool() -> bool:
	if _pool and is_instance_valid(_pool):
		return true
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return false
	_pool = Node.new()
	_pool.name = "SfxPool"
	_pool.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child.call_deferred(_pool)
	_players.clear()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		_pool.add_child(p)
		_players.append(p)
	return true

## Every file the bank uses (for checks).
static func all_files() -> Array:
	var out := []
	for k in BANK:
		for f in BANK[k]["files"]:
			if not out.has(f):
				out.append(f)
	return out
