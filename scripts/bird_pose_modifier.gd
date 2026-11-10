class_name BirdPoseModifier
extends SkeletonModifier3D
## Runs after the AnimationPlayer each frame and layers the bird's procedural motion on top of the
## keyframed pose (hop flaps, head tracking, neck pitch/extension, head scale, beak opening).
## The math lives in BirdModel.apply_procedural_pose().

var model: BirdModel

func _process_modification_with_delta(_delta: float) -> void:
	if model:
		model.apply_procedural_pose(get_skeleton())
