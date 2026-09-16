class_name DuoNail
extends Node3D
## A NAIL: flies straight, sticks in wood, refuses everything else, and comes back when called.
##
## WOOD IS RECOGNISED BY ITS PHYSICS MATERIAL, not by the name of the node it hit. A beam can be
## called anything and live in any scene; what makes it take a nail is the `PhysicsMaterial` it
## carries, and the nail compares that resource with its own `holds_in`. This is the assembly rule
## "identify by group or by material, never by name" doing actual work.
##
## A flying nail is a ray swept one tick ahead, not a physics body: at sixty metres per second a
## small body crosses a thin beam between two ticks without ever touching it.

signal stuck(flight: float)
signal missed(why: String)
signal gone

enum State {
	FLYING,
	STUCK,
	RETURNING,
}

## Physics layers a nail can hit: the level and the bridges.
const SOLIDS := 1 | 2
## Speed of a nail called back to the hand, m/s.
const RETURN_SPEED := 40.0

## The surface that takes a nail. Anything carrying another material, or none, sends it back out.
@export var holds_in: PhysicsMaterial
## Beyond this, m, a nail that hit nothing is lost.
@export_range(5.0, 80.0, 1.0) var flight_range := 30.0

var state := State.FLYING
## Seconds from the throw to the moment it stuck.
var flight := 0.0

var _direction := Vector3.RIGHT
var _speed := 0.0
var _travelled := 0.0
var _home: DuoBody = null


func _physics_process(delta: float) -> void:
	match state:
		State.FLYING:
			_fly(delta)
		State.RETURNING:
			_come_back(delta)


## Sends the nail off. Called once the nail is in the tree: turning it to face its flight needs a
## global transform, and a node outside the tree has none. A speed of zero or less means it arrives
## the moment it leaves — the whole range is swept in one tick.
func launch(from: Vector3, direction: Vector3, speed: float) -> void:
	global_position = from
	_direction = direction.normalized()
	_speed = speed
	_point_along(_direction)


func recall(to: DuoBody) -> void:
	_home = to
	state = State.RETURNING


## The point a swinger hangs from: the tip, buried in the wood.
func tip() -> Vector3:
	return global_position


func _fly(delta: float) -> void:
	flight += delta
	var step := flight_range - _travelled if _speed <= 0.0 else _speed * delta
	var query := PhysicsRayQueryParameters3D.create(
			global_position, global_position + _direction * step, SOLIDS)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position += _direction * step
		_travelled += step
		if _travelled >= flight_range:
			missed.emit("улетел мимо, дальше %d м" % roundi(flight_range))
			_vanish()
		return

	var body: CollisionObject3D = hit.collider
	var surface: PhysicsMaterial = body.get("physics_material_override")
	if surface == null or surface != holds_in:
		missed.emit("не держит — это не дерево")
		_vanish()
		return
	var normal: Vector3 = hit.normal
	global_position = hit.position
	_point_along(-normal)
	state = State.STUCK
	stuck.emit(flight)


func _come_back(delta: float) -> void:
	var target := _home.hand()
	var offset := target - global_position
	var step := RETURN_SPEED * delta
	if offset.length() <= step:
		_vanish()
		return
	global_position += offset.normalized() * step
	_point_along(offset)


func _vanish() -> void:
	gone.emit()
	queue_free()


func _point_along(direction: Vector3) -> void:
	# The nail model points down its own −Z. `look_at` needs an up vector that is not parallel to
	# the look direction, and a nail driven into the underside of a beam looks straight up.
	var up := Vector3.BACK if absf(direction.normalized().y) > 0.9 else Vector3.UP
	look_at(global_position + direction, up)
