class_name PowerUps
extends RefCounted
## The prototype power-ups (design doc) and how birds hold them.
## User decisions (Stage 5): power-ups last the whole match; a bird holds up to MAX_HELD (3); picking up a
## 4th replaces the oldest. Picking up a type you already hold just makes it the newest (no duplicates), so
## the effects combine (e.g. Trifecta + Eggsplosive = three exploding arrows).

const MAX_HELD := 3
const TYPES := {
	"trifecta": {"name": "Trifecta", "blurb": "Fires 3 arrows in a fan", "color": Color("ffd23f"),
		"icon": preload("res://assets/ui/powerups/ph_trifecta.png")},
	"eggsplosive": {"name": "Eggsplosive", "blurb": "Arrows explode on impact", "color": Color("ff7a45"),
		"icon": preload("res://assets/ui/powerups/ph_eggsplosive.png")},
	"featherweight": {"name": "Featherweight", "blurb": "Faster, longer dash", "color": Color("8de0c8"),
		"icon": preload("res://assets/ui/powerups/ph_featherweight.png")},
}

static func ids() -> Array:
	return TYPES.keys()

## Returns the new held list after picking up `type`.
static func add(held: Array[String], type: String) -> Array[String]:
	var out: Array[String] = held.duplicate()
	out.erase(type)
	out.append(type)
	while out.size() > MAX_HELD:
		out.pop_front()
	return out
