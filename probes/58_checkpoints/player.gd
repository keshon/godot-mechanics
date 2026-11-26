class_name CheckpointPlayer
extends CharacterBody3D
## A carrier accepts movement intentions; availability is controlled by the session rig.

@export var caption := "P1"
@export var tint := Color(1, 0.55, 0.2)
@export var speed := 5.0
var available := true
var wish := Vector3.ZERO
var facing := 0.0
var _previous := Transform3D.IDENTITY
var _current := Transform3D.IDENTITY
@onready var visual: Node3D = $Body


func _ready() -> void:
	visual.top_level = true
	process_priority = -10
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	$Body/Mesh.material_override = material
	$Body/Label.text = caption
	reset_at(position)


func _process(_delta: float) -> void:
	visual.global_transform = _previous.interpolate_with(
			_current, Engine.get_physics_interpolation_fraction())


func _physics_process(delta: float) -> void:
	_previous = _current
	var direction: Vector3 = wish.limit_length() if available else Vector3.ZERO
	velocity.x = move_toward(velocity.x, direction.x * speed, 35.0 * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, 35.0 * delta)
	velocity.y -= 24.0 * delta
	move_and_slide()
	if direction.length_squared() > 0.01:
		facing = lerp_angle(facing, atan2(-direction.x, -direction.z), 1.0 - exp(-14.0 * delta))
	_current = Transform3D(Basis(Vector3.UP, facing), global_position)


func hand_position() -> Vector3:
	return global_position + Vector3.UP * 1.1 + Basis(Vector3.UP, facing) * Vector3.FORWARD


func reset_at(point: Vector3) -> void:
	global_position = point
	velocity = Vector3.ZERO
	wish = Vector3.ZERO
	facing = 0.0
	_current = Transform3D(Basis.IDENTITY, point)
	_previous = _current
	visual.global_transform = _current
