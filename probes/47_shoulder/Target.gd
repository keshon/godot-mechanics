extends Node3D
class_name ShoulderTarget

## THE THING BEING SHOT AT.
##
## Drives a straight line across the front at a fixed speed, because the question here is
## about the shooter and not about the driver. What it contributes is exactly one quantity:
## how far it moves while the round is in the air.
##
## That quantity is the whole difference between the two rounds. Against something standing
## still both hit and there is nothing to measure.

@export_range(0.0, 40.0, 0.5) var speed := 11.0
## How far it runs before turning back. Kept short so the shot happens across the front and
## not away down the range.
@export_range(20.0, 400.0, 5.0) var run := 130.0

var velocity := Vector3.ZERO
var hit := false

var _home := Vector3.ZERO
var _way := 1.0

@onready var _hull: Node3D = $Hull


func _ready() -> void:
	_home = position


func reset() -> void:
	position = _home
	_way = 1.0
	hit = false
	velocity = Vector3.ZERO
	if _hull != null:
		_hull.rotation.y = 0.0


func _physics_process(delta: float) -> void:
	if hit or speed <= 0.0:
		velocity = Vector3.ZERO
		return
	velocity = global_basis.x * speed * _way
	position += (Vector3.RIGHT * speed * _way) * delta
	if absf(position.x - _home.x) > run * 0.5:
		_way = -_way
	if _hull != null:
		_hull.rotation.y = 0.0 if _way > 0.0 else PI


## Struck. Stops where it stands: a wreck is a landmark, and the next shot is aimed past it.
func wreck() -> void:
	hit = true
	velocity = Vector3.ZERO
