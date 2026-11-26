class_name OwnershipItem
extends CharacterBody3D
## Requests are resolved once per physics tick. A tie alternates priority after each grant.

signal claimed(slot: int)
signal released(slot: int, reason: String)

@export var reach := 2.5
@export var caption := "ЯДРО"
var owner_slot: int = -1
var carrier: OwnershipPlayer = null
var next_priority: int = 0
var uses: int = 0
var last_reason := "свободно"
var _requests: Dictionary[int, OwnershipPlayer] = {}
var _home := Vector3.ZERO
var _previous := Vector3.ZERO
var _current := Vector3.ZERO
@onready var visual: Node3D = $Visual


func _ready() -> void:
	process_physics_priority = 30
	_home = global_position
	visual.top_level = true
	_previous = global_position
	_current = global_position


func _process(_delta: float) -> void:
	visual.global_position = _previous.lerp(_current, Engine.get_physics_interpolation_fraction())
	$Visual/Label.text = "%s · %s" % [caption,
			"P%d" % (owner_slot + 1) if owner_slot >= 0 else "свободно"]


func _physics_process(delta: float) -> void:
	_previous = _current
	resolve_requests()
	if owner_slot >= 0:
		if not is_instance_valid(carrier) or not carrier.available:
			release("носитель недоступен")
		elif global_position.distance_to(carrier.hand_position()) > 3.0:
			release("носитель слишком далеко")
	if owner_slot >= 0:
		velocity = (carrier.hand_position() - global_position) / delta
	else:
		velocity.x = move_toward(velocity.x, 0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0, 20.0 * delta)
		velocity.y -= 24.0 * delta
	move_and_slide()
	_current = global_position
	if global_position.y < -5:
		reset()


func can_reach(actor: OwnershipPlayer) -> bool:
	var distance: float = (actor.global_position + Vector3.UP).distance_to(global_position)
	if not actor.available or distance > reach:
		return false
	var query := PhysicsRayQueryParameters3D.create(
			actor.global_position + Vector3.UP, global_position, 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func request(slot: int, actor: OwnershipPlayer) -> void:
	_requests[slot] = actor


func cancel(slot: int) -> void:
	_requests.erase(slot)
	if owner_slot == slot:
		release("отмена")


func resolve_requests() -> void:
	if owner_slot < 0:
		for offset in range(2):
			var slot: int = (next_priority + offset) % 2
			if _requests.has(slot) and is_instance_valid(_requests[slot]):
				if can_reach(_requests[slot]):
					owner_slot = slot
					carrier = _requests[slot]
					next_priority = 1 - slot
					last_reason = "взял P%d" % (slot + 1)
					claimed.emit(slot)
					break
	_requests.clear()


func release(reason: String) -> void:
	if owner_slot < 0:
		return
	var former: int = owner_slot
	owner_slot = -1
	carrier = null
	velocity = Vector3.ZERO
	last_reason = reason
	released.emit(former, reason)


func can_use_at(slot: int, socket: Vector3) -> bool:
	if owner_slot != slot or not is_instance_valid(carrier):
		return false
	if not carrier.available or global_position.distance_to(socket) > 2.0:
		return false
	var query := PhysicsRayQueryParameters3D.create(global_position, socket, 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func use_at(slot: int, socket: Vector3) -> bool:
	if not can_use_at(slot, socket):
		return false
	uses += 1
	release("использовано P%d" % (slot + 1))
	global_position = socket
	_previous = socket
	_current = socket
	return true


func reset() -> void:
	_requests.clear()
	release("сброс")
	global_position = _home
	velocity = Vector3.ZERO
	_previous = _home
	_current = _home
	visual.global_position = _home
	uses = 0
	next_priority = 0
	last_reason = "свободно"
