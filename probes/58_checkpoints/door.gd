class_name CheckpointDoor
extends AnimatableBody3D
## A timed gate postpones closure while a character occupies its doorway.

var opened := false
var waiting := false
var _closed_position := Vector3.ZERO


func _ready() -> void:
	_closed_position = position


func set_open(requested: bool, players: Array[CheckpointPlayer], force := false) -> void:
	waiting = false
	if not requested and not force:
		for player in players:
			var offset: Vector3 = player.position - _closed_position
			if absf(offset.x) < 1.8 and absf(offset.z) < 0.9:
				waiting = true
	opened = requested or waiting
	position = _closed_position + Vector3.UP * 4.0 if opened else _closed_position
