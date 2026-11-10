class_name Nest
extends Node3D
## A twig nest with a few breakable eggs. Birds walk over it; arrows only hit the eggs. reset() refills it.

const NEST := preload("res://assets/env/nest.glb")

@export_range(1, 4) var egg_count := 3

var eggs: Array[Egg] = []

func _ready() -> void:
	add_to_group("nests")
	var prop := EnvProp.new()
	add_child(prop)
	prop.model = NEST
	for i in egg_count:
		var e := Egg.new()
		var a := TAU * i / egg_count + randf() * 0.4
		e.position = Vector3(cos(a), 0, sin(a)) * (0.13 if egg_count > 1 else 0.0) + Vector3(0, 0.05, 0)
		add_child(e)
		eggs.append(e)

func reset() -> void:
	for e in eggs:
		e.restore()
