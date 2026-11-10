class_name Tuning
extends Resource
## Every gameplay tunable lives here. The single instance is res://data/tuning.tres.
## Load it with `Tuning.get_default()`.

const PATH := "res://data/tuning.tres"

@export_group("Movement")
@export var move_speed := 6.0 ## m/s
@export var acceleration := 40.0 ## m/s²
@export var deceleration := 50.0 ## m/s²
@export var turn_speed := 1080.0 ## deg/s the body turns toward its facing while moving
@export var aim_turn_rate := 720.0 ## deg/s while drawing (rooted; move input aims)

@export_group("Dash")
@export var dash_distance := 3.5 ## m
@export var dash_duration := 0.15 ## s
@export var dash_cooldown := 0.8 ## s
@export var dash_invulnerability := 0.06 ## s, centered mid-dash

@export_group("Bow")
@export var full_draw_time := 0.9 ## s (user: longer to charge; was 0.6)
@export var arrow_speed_min := 14.0 ## m/s at zero charge
@export var arrow_speed_max := 28.0 ## m/s at full charge
@export var quiver_size := 3
@export var full_charge_rumble_weak := 0.35 ## controller rumble when the draw reaches full charge (0..1)
@export var full_charge_rumble_strong := 0.55
@export var full_charge_rumble_time := 0.16 ## s
@export var curve_window := 0.6 ## s after release; steering starts immediately (open question 1)
@export var curve_max_turn_rate := 120.0 ## deg/s at full sideways input (user picked the gentler option)
@export var arrow_auto_return := 7.0 ## s stuck before it poofs back (user: 7, was 5)

@export var arrow_height := 0.55 ## m above ground where arrows fly (and where mouse aim is projected)
@export var arrow_gravity := 2.4 ## m/s²; sets range: ~10 m at min charge, ~20 m at full
@export var arrow_penetration := 0.12 ## m the tip sinks into what it hits
@export var arrow_max_flight := 3.0 ## s before a lost arrow returns to its owner
@export var arrow_pickup_radius := 0.6 ## m
@export var homing_range := 3.2 ## m (user: stronger; was 2.5): slight homing toward a bird this close ahead of the arrow
@export var homing_max_angle := 45.0 ## (was 35) degrees off the flight direction a target can be
@export var homing_turn_rate := 100.0 ## (was 60) deg/s at point blank, fading to 0 at homing_range
@export var recoil_speed := 3.0 ## m/s pushed backwards on release
@export var recoil_hop := 1.4 ## m/s upward visual hop on release

@export_group("Hits")
@export var hitstop_ko := 0.08 ## s
@export var symbol_grow_time := 0.28 ## s for an anime symbol to grow in
@export var symbol_life := 1.1 ## s an anime symbol stays before shrinking away (dizzy x2.2, zzz stays while sleepy)
@export var ko_knockback := 7.0 ## m/s the KO'd bird is knocked back along the hit direction (decays over the flop)
@export var ko_flop_time := 0.4 ## s from the hit to landing on its back/side
@export var ko_flop_hop := 0.35 ## m peak height of the flop arc
@export var ko_flop_turns := 0.5 ## yaw spins during the flop (was 1: too whippy at 60 Hz)
@export var ko_body_center := 0.4 ## m, pivot height the bird tips over around
@export var ko_lie_height := 0.3 ## m, that pivot's height once lying down
@export var ko_land_squash := 0.15 ## landing squash amount (was 0.3: read as a twitch)
@export var ko_land_squash_time := 0.25 ## s
@export var ko_spirit_delay := 0.5 ## s after the hit the spirit starts rising
@export var ko_spirit_time := 3.0 ## s the spirit is visible (user: rise more slowly; was 1.5)
@export var ko_spirit_height := 7.0 ## m it travels up the screen on its own
@export var ko_spirit_steer_speed := 3.2 ## m/s the KO'd player can drift their spirit with the move input
@export var ko_spirit_steer_rise := 2.2 ## m/s extra (stick up) or less (stick down) rise speed
@export var ko_spirit_steer_max := 5.0 ## m the spirit can drift sideways from its path
@export var ko_spirit_alpha := 0.55 ## body opacity (edges glow brighter)
@export var near_miss_distance := 0.9 ## m: an enemy arrow passing this close makes a bird "shocked"

@export_group("Melee (wing slap)")
@export var slap_range := 1.3 ## m (open question 6)
@export var slap_arc := 120.0 ## degrees, centered on facing
@export var slap_cooldown := 0.5 ## s after a whiff or a stun hit
@export var slap_root_time := 0.25 ## s the slapper is rooted
@export var slap_hit_time := 0.08 ## s into the slap when it connects
@export var stun_time := 1.0 ## s a slapped bird can't move, shoot, dash or melee
@export var stun_push := 4.0 ## m/s the slapped bird is shoved along the hit
@export var stun_immunity := 0.6 ## s after a stun ends before the bird can be stunned again (no stun-lock)
@export var parry_window := 0.08 ## s from the press during which the wing bats arrows away (tight on purpose)
@export var parry_reach := 0.9 ## m from the bird's center where the wing can meet an arrow
@export var parry_arc := 150.0 ## degrees, centered on facing
@export var parry_speed_scale := 1.0 ## batted arrow speed vs incoming
@export var parry_knockback := 9.0 ## m/s the batter is pushed back (decays with deceleration, ~0.8 m)
@export var parry_cooldown := 1.0 ## s before the batter can melee again
@export var parry_hitstop := 0.05 ## s
@export var hitstop_arrow_stick := 0.04 ## s of hit-stop when a full-charge arrow sticks (0 = off)

@export_group("Juice")
@export var shake_max_offset := 0.35 ## m at trauma 1
@export var shake_decay := 2.5 ## trauma lost per second
@export var shake_on_fire := 0.12 ## trauma at zero charge (+ same again at full charge)
@export var shake_on_stick := 0.15 ## trauma when an arrow sticks into something
@export var punch_zoom_amount := 0.03 ## fraction the ortho size shrinks on a KO

@export_group("Match")
@export var rounds_to_win := 3
@export var rounds_to_win_options: Array[int] = [3, 5, 7]
@export var round_countdown := 1.5 ## s birds are frozen before "Go!"
@export var round_end_delay := 0.9 ## s after the last KO before the round is decided
@export var round_scoreboard_time := 2.5 ## s the between-round scoreboard shows
@export var round_celebration_time := 3.0 ## s from a round's last KO to the scoreboard: the winner celebrates
@export var match_celebration_time := 3.8 ## s from the match-deciding KO to the results: the winner celebrates
@export var match_celebration_delay := 0.5 ## s after that KO before the celebration starts
@export var match_celebration_zoom := 0.55 ## camera view size while it zooms in on the winner (1 = whole arena)
@export var overtime_after := 120.0 ## s into a round before the overtime countdown appears (user: 2 min)
@export var overtime_countdown := 30.0 ## s the countdown runs before eggs start falling (user: 30 s)
@export var overtime_egg_interval := 1.0 ## s between falling eggs once it hits zero
@export var overtime_egg_drop_time := 0.9 ## s an egg falls (its shadow grows on the landing spot meanwhile)

@export_group("Power-ups")
@export var powerup_first_delay := 4.0 ## s into a round before the first spawn
@export var powerup_interval_min := 7.0 ## s between spawns
@export var powerup_interval_max := 11.0
@export var powerup_max_active := 2 ## power-ups waiting on pads at once
@export var trifecta_spread := 14.0 ## degrees the two extra arrows peel off at when a Trifecta shot splits
@export var trifecta_split_time := 0.33 ## s into the flight when it splits into three (an arrow reaches the ground ~0.68 s after release: halfway)
@export var eggsplosive_radius := 1.6 ## m
@export var featherweight_speed := 1.25 ## move speed multiplier
@export var featherweight_dash := 1.4 ## dash distance multiplier

@export_group("CPU")
## Per-difficulty CPU behavior (open question 8: easy / normal / hard).
##   think: s between decisions; aim_error: deg; draw: [min, max] s; dodge: chance to dash away from
##   incoming arrows; react: s before reacting; lead: fraction of target motion led; curve: uses curve shots.
@export var cpu_profiles := {
	"easy": {"think": 0.45, "aim_error": 22.0, "draw": [0.22, 0.68], "dodge": 0.15, "react": 0.35, "lead": 0.0, "curve": false, "range": 8.0, "melee": 0.3, "parry": 0.0, "parry_jitter": 0.1, "shrike": 0.15, "shrike_range": 9.0},
	"normal": {"think": 0.25, "aim_error": 9.0, "draw": [0.52, 0.98], "dodge": 0.55, "react": 0.2, "lead": 0.5, "curve": false, "range": 10.0, "melee": 0.6, "parry": 0.12, "parry_jitter": 0.06, "shrike": 0.3, "shrike_range": 9.0},
	"hard": {"think": 0.12, "aim_error": 3.0, "draw": [0.82, 1.05], "dodge": 0.9, "react": 0.1, "lead": 1.0, "curve": true, "curve_chance": 0.3, "curve_range": 7.0, "range": 13.0, "melee": 0.9, "parry": 0.3, "parry_jitter": 0.03, "shrike": 0.45, "shrike_range": 9.0},
}

@export var cpu_patience := 6.0 ## s without attacking before a CPU goes hunting (anti-stall)
@export var cpu_hunt_range := 17.0 ## m: a hunting CPU shoots at anything in sight this close

@export_group("Shrike (lob shot)")
@export var shrike_range_min := 4.0 ## m it lands ahead at zero charge (aim + charge set the landing spot)
@export var shrike_range_max := 11.0 ## m at full charge
@export var shrike_apex := 3.5 ## m above the straight line at the top of the arc (clears logs, rocks, most cover)
@export var shrike_speed := 9.0 ## m/s along the ground (sets the flight time)
@export var shrike_min_flight := 0.55 ## s, even for short lobs
@export var shrike_steer_speed := 2.5 ## m/s the landing spot moves with the shooter's move input while airborne
@export var shrike_stun_radius := 1.3 ## m: the landing shockwave stuns other birds this close (even on a miss)
@export var shrike_trifecta_offset := 1.1 ## m sideways for Trifecta's extra shrikes
@export var shrike_marker_radius := 0.55 ## m, the landing ring at its smallest (just before impact)

@export_group("Water (Birdbath)")
@export var water_speed := 0.6 ## move speed multiplier while wading
@export var water_dash := 0.75 ## dash distance multiplier when starting a dash in water
@export var puddle_start_radius := 1.4 ## m around the bath at the start of each round (bath-local, scales with it)
@export var puddle_max_radius := 4.5 ## m (bath-local)
@export var puddle_growth := 0.05 ## m/s the overflow puddle spreads (reaches max in about a minute)

@export_group("Bird body")
@export var hitbox_radius := 0.4 ## m
@export var hitbox_height := 1.0 ## m

@export_group("Bounce")
@export var hop_height_min := 0.08 ## m
@export var hop_height_max := 0.12 ## m
@export var hop_rate_min := 4.0 ## hops/s at low speed
@export var hop_rate_max := 6.0 ## hops/s at full speed
@export var squash_scale := Vector2(1.1, 0.85) ## (xz, y) on landing
@export var stretch_scale := Vector2(0.95, 1.1) ## (xz, y) on take-off
@export var lean_degrees := 12.0

@export_group("Camera")
@export var camera_pitch := 50.0 ## degrees down from horizontal
@export var camera_margin := 1.0 ## m of breathing room around the arena
@export var camera_top_ui_margin := 1.2 ## m of extra space at the top for the score UI

static var _default: Tuning

static func get_default() -> Tuning:
	if _default == null:
		_default = load(PATH)
	return _default

## Re-reads tuning.tres from disk into the shared instance, so running code sees new values.
static func reload() -> void:
	var fresh: Resource = ResourceLoader.load(PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	var current := get_default()
	for p in fresh.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			current.set(p.name, fresh.get(p.name))
