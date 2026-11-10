class_name MapCatalog
extends RefCounted
## Everything the level editor can place, and how each item is built. Layout items are dictionaries:
##   {"type": String, "x": float, "z": float, "yaw": float (degrees), "scale": float}
## Categories: cover (solid: blocks birds, catches arrows), soft (bushes: walk-through, arrows fly over),
## gameplay (spawns, power-up pads, nests) and decor (no effect on play).
## Per item: label, cat, one of scene / model (KayKit Forest name) / kind, base scale, pick radius + height (m),
## scale range, and optional max count.

const FOREST := "res://assets/third_party/kaykit_forest/"
const CATEGORIES := [["cover", "Cover"], ["soft", "Soft cover"], ["gameplay", "Gameplay"], ["decor", "Decoration"]]

const ITEMS := {
	"tree": {"label": "Tree", "cat": "cover", "scene": "res://scenes/props/tree_central.tscn", "base": 1.15, "r": 0.8, "h": 4.0},
	"rock_big": {"label": "Big rock", "cat": "cover", "scene": "res://scenes/props/rock_big.tscn", "r": 0.7, "h": 1.4},
	"rock_mid": {"label": "Rock", "cat": "cover", "scene": "res://scenes/props/rock_mid.tscn", "r": 0.55, "h": 1.1},
	"log": {"label": "Log", "cat": "cover", "scene": "res://scenes/props/log.tscn", "r": 1.1, "h": 0.7},
	"birdbath": {"label": "Birdbath", "cat": "cover", "kind": "birdbath", "r": 0.8, "h": 1.2, "min": 0.8, "max_scale": 1.3},
	"stump": {"label": "Stump", "cat": "cover", "scene": "res://scenes/props/stump.tscn", "r": 0.55, "h": 0.6},
	"bush": {"label": "Bush", "cat": "soft", "model": "Bush_3_A", "r": 0.6, "h": 0.8},
	"bush_round": {"label": "Round bush", "cat": "soft", "model": "Bush_4_B", "r": 0.6, "h": 0.8},
	"bush_low": {"label": "Low bush", "cat": "soft", "model": "Bush_1_B", "r": 0.55, "h": 0.6},
	"spawn": {"label": "Spawn point", "cat": "gameplay", "kind": "spawn", "r": 0.5, "h": 0.4, "max": 4, "fixed_scale": true},
	"pad": {"label": "Power-up pad", "cat": "gameplay", "kind": "pad", "r": 0.6, "h": 0.4, "fixed_scale": true},
	"nest": {"label": "Nest + eggs", "cat": "gameplay", "kind": "nest", "r": 0.45, "h": 0.4, "fixed_scale": true},
	"dirt": {"label": "Dirt patch", "cat": "decor", "kind": "dirt", "r": 1.5, "h": 0.05, "min": 0.4, "max_scale": 2.5, "max": 16},
	"grass": {"label": "Grass tuft", "cat": "decor", "model": "Grass_2_C", "r": 0.4, "h": 0.4},
	"grass_small": {"label": "Small grass", "cat": "decor", "model": "Grass_1_B", "r": 0.35, "h": 0.35},
	"flowers": {"label": "Flowers", "cat": "decor", "kind": "flowers", "r": 0.4, "h": 0.4},
	"pebbles": {"label": "Pebbles", "cat": "decor", "model": "Rock_1_A", "base": 0.45, "r": 0.3, "h": 0.3},
}

## Editor limits for the arena (m) and grid snap step.
const MIN_SIZE := Vector2(12, 8)
const MAX_SIZE := Vector2(44, 30)
const SNAP := 0.5

static func info(type: String) -> Dictionary:
	return ITEMS.get(type, {})

static func types_in(cat: String) -> Array:
	return ITEMS.keys().filter(func(k): return ITEMS[k]["cat"] == cat)

static func scale_range(type: String) -> Vector2:
	var i := info(type)
	if i.get("fixed_scale", false):
		return Vector2.ONE
	return Vector2(i.get("min", 0.6), i.get("max_scale", 1.5))

static func pick_radius(item: Dictionary) -> float:
	return float(info(item["type"]).get("r", 0.5)) * float(item.get("scale", 1.0))

static func pick_height(item: Dictionary) -> float:
	return float(info(item["type"]).get("h", 0.5)) * float(item.get("scale", 1.0))
