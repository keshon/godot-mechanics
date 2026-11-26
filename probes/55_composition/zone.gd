class_name CompositionZone
extends Node3D
## An authored camera volume, in local metres; highest priority wins overlaps.

@export var size := Vector3(8, 8, 12)
@export var yaw := 0.0
@export var pitch := -0.55
@export var distance := 7.0
@export var priority: int = 0
@export var caption := "зона"


func contains(point: Vector3) -> bool:
	var offset: Vector3 = to_local(point).abs()
	return offset.x <= size.x * 0.5 and offset.y <= size.y * 0.5 and offset.z <= size.z * 0.5
