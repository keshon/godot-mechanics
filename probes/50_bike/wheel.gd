class_name BikeWheel
extends Node3D
## A suspension mount and a moving wheel. The rig never reads input here.

## Uncompressed suspension travel, m.
@export_range(0.12, 0.5, 0.01) var travel := 0.30
## Spring rate, N/m; damping, N per m/s.
@export var stiffness := 18000.0
@export var damping := 1600.0
@export var radius := 0.34
@export var front := false

var grounded := false
var compression := 0.0
var wheel_load := 0.0
var contact := Vector3.ZERO
var normal := Vector3.UP
var grip_used := 0.0

@onready var _visual: Node3D = $Hub
@onready var _spin: Node3D = $Hub/Spin


func sample(state: PhysicsDirectBodyState3D, exclude: RID) -> void:
	var up: Vector3 = state.transform.basis.y
	var mount: Vector3 = state.transform * position
	var query := PhysicsRayQueryParameters3D.create(
			mount, mount - up * (travel + radius), 1, [exclude])
	var hit: Dictionary = state.get_space_state().intersect_ray(query)
	grounded = not hit.is_empty()
	compression = 0.0
	wheel_load = 0.0
	grip_used = 0.0
	if not grounded:
		return
	contact = hit.position
	normal = hit.normal
	compression = clampf(travel - (mount.distance_to(contact) - radius), 0.0, travel)
	var offset: Vector3 = mount - state.transform.origin
	var velocity: Vector3 = state.get_velocity_at_local_position(offset)
	# The spring cannot pull the ground. Limit the impact force at the end of travel.
	wheel_load = clampf(compression * stiffness - velocity.dot(up) * damping, 0.0, 12000.0)
	state.apply_force(up * wheel_load, offset)


func animate(speed: float, steering: float, delta: float) -> void:
	_visual.position.y = -(travel - compression)
	_visual.rotation.y = steering if front else 0.0
	_spin.rotation.x = wrapf(_spin.rotation.x - speed * delta / radius, -PI, PI)
