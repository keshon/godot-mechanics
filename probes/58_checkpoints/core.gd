class_name CheckpointCore
extends CharacterBody3D
## A single puzzle key. Restore releases the carrier before relocating this existing body.

var carrier: CheckpointPlayer = null
var locked := false
var _previous := Vector3.ZERO
var _current := Vector3.ZERO
@onready var visual: Node3D = $Visual


func _ready() -> void:
	process_physics_priority = 10
	visual.top_level = true
	restore(position, false)


func _process(_delta: float) -> void:
	visual.global_position = _previous.lerp(_current, Engine.get_physics_interpolation_fraction())
	$Visual/Label.text = "ПИТАНИЕ" if locked else ("В РУКАХ" if carrier != null else "ЯДРО")


func _physics_process(delta: float) -> void:
	_previous = _current
	if locked:
		return
	if is_instance_valid(carrier):
		var target: Vector3 = carrier.hand_position()
		if global_position.distance_to(target) > 3.0:
			carrier = null
		else:
			velocity = (target - global_position) / delta
	else:
		carrier = null
	if carrier == null:
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		velocity.y -= 24.0 * delta
	move_and_slide()
	_current = global_position


func reachable(player: CheckpointPlayer) -> bool:
	var start: Vector3 = player.global_position + Vector3.UP
	if start.distance_to(global_position) > 2.5:
		return false
	var query := PhysicsRayQueryParameters3D.create(start, global_position, 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func restore(point: Vector3, installed: bool) -> void:
	carrier = null
	locked = installed
	velocity = Vector3.ZERO
	global_position = point
	_previous = point
	_current = point
	visual.global_position = point
