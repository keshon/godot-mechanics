class_name DuoPlatform
extends AnimatableBody3D
## WHAT THE BUILDER'S CLICK TURNS INTO: a block that rises out of the surface, stands, and sinks.
##
## An `AnimatableBody3D`, so a runner standing where it rises is lifted with it instead of being
## pushed through — raising a platform under someone's feet is a lift, and a legitimate move.
##
## Its life is the knob that decides how busy the builder is. A platform that stands forever is
## built once and forgotten; one that sinks after a few seconds has to be raised again at the
## moment it is needed, and that timing is the builder's part of the game.

signal sank

## Height of the block, m.
@export_range(0.2, 4.0, 0.1) var height := 1.2
## Seconds to rise and to sink.
@export_range(0.05, 2.0, 0.05) var travel := 0.35
## Seconds it stands at full height. Zero means it never sinks.
@export_range(0.0, 60.0, 0.5) var life := 0.0

var _base := Vector3.ZERO
var _clock := 0.0


func _physics_process(delta: float) -> void:
	_clock += delta
	var up := clampf(_clock / travel, 0.0, 1.0)
	if life > 0.0 and _clock > travel + life:
		up = 1.0 - clampf((_clock - travel - life) / travel, 0.0, 1.0)
	# The block's origin is its centre; at full height its top is flush with `height` above the
	# surface it was planted on.
	position = _base + Vector3.UP * (height * (up - 0.5))
	if life > 0.0 and _clock > travel * 2.0 + life:
		sank.emit()
		queue_free()


## Plants the block on a surface point. Called before the node enters the tree, so the position is
## written as a local one: a node outside the tree has no global transform to write. The parent
## it goes into has to sit at the world origin for local and world to agree.
func plant(at: Vector3, seconds: float) -> void:
	_base = at
	life = seconds
	position = _base + Vector3.DOWN * height * 0.5
