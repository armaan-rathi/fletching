extends Node3D
## Builds an editor-made map (MatchManager.custom_layout) when the custom map scene loads: world, border,
## walls and items, with spawns/pads/nests where the RoundController and PowerUpSpawner expect them.
## This node comes first in scenes/maps/custom_map.tscn, so everything exists before the match nodes are ready.

func _ready() -> void:
	var layout: Dictionary = MatchManager.custom_layout
	if layout.is_empty():
		layout = MapBuilder.new_layout()
	var size := MapBuilder.size_of(layout)
	var world := MapBuilder.build_world(self, size)
	MapBuilder.apply_dirt(world["ground_material"], layout["items"])
	var border := Node3D.new()
	border.name = "Border"
	add_child(border)
	MapBuilder.build_border(border, size, int(layout.get("seed", 7)))
	MapBuilder.build_walls(self, size)
	var groups := {}
	for g in ["Props", "Spawns", "PowerUpPads", "Nests"]:
		var n := Node3D.new()
		n.name = g
		add_child(n)
		groups[g] = n
	for it in layout["items"]:
		var parent: Node3D = groups["Props"]
		match it["type"]:
			"spawn":
				parent = groups["Spawns"]
			"pad":
				parent = groups["PowerUpPads"]
			"nest":
				parent = groups["Nests"]
		MapBuilder.place(parent, it)

func _exit_tree() -> void:
	MapBuilder.set_arena(MapBuilder.DEFAULT_ARENA) # the hand-built maps use the project default
