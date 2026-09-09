class_name CommandUnit
extends Area3D
## One commanded thing. An Area3D rather than a body, because nothing here
## needs to be pushed — it needs to be POINTED AT, and an area is the cheapest
## node that a raycast can hit.
##
## It knows nothing about selection rectangles, cameras or orders. It knows a
## list of places to be, in order. Everything else is somebody else's job.

## How fast it walks, m/s.
@export_range(1.0, 20.0, 0.5) var speed := 6.0
## How fast it swings to face where it is going, rad/s.
@export_range(0.5, 20.0, 0.5) var turn_speed := 7.0
## How close counts as arrived, m. Too small and the unit hunts around the spot
## forever, never quite getting there.
@export_range(0.1, 3.0, 0.05) var arrive_radius := 0.7

var selected := false:
	set(value):
		selected = value
		if _ring:
			_ring.visible = value

## Which command this unit is carrying out. Everyone told to move by the same
## click shares it — and keeps sharing it even when their destinations differ,
## which they will the moment anything like a formation exists. Grouping by the
## COMMAND survives that; grouping by matching coordinates does not.
var order_id := -1

var _path: Array[Vector3] = []

@onready var _ring: MeshInstance3D = $Ring


func _ready() -> void:
	_ring.visible = false


## Nothing in here checks whether the game is paused. It does not need to: this
## node sits under World, which obeys the pause, so _physics_process simply
## stops being called. The unit is not "told" to freeze — it is just not asked
## to move. That is the whole of Godot's pause.
func _physics_process(delta: float) -> void:
	if _path.is_empty():
		return
	var target := _path[0]
	var to_target := target - global_position
	to_target.y = 0.0
	if to_target.length() < arrive_radius:
		_path.pop_front()
	else:
		var direction := to_target.normalized()
		global_position += direction * speed * delta
		var want := Basis.looking_at(direction, Vector3.UP)
		global_basis = Basis(global_basis.get_rotation_quaternion().slerp(
				want.get_rotation_quaternion(),
				clampf(turn_speed * delta, 0.0, 1.0)))


## `queued` is what makes a tactical pause worth having: with the world frozen
## you can lay down a whole route, then let time run and watch it happen.
func order(point: Vector3, queued: bool, id: int = -1) -> void:
	if not queued:
		_path.clear()
		order_id = id
	_path.append(point)


func path() -> Array[Vector3]:
	return _path


func is_busy() -> bool:
	return not _path.is_empty()
