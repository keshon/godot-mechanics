class_name SessionPlayer
extends CharacterBody3D
## Input-free pawn. Session suspension preserves position and collected progress.

@export var speed := 5.0
@export var lane := -3.0
@export var smooth_visuals := true
var wish := Vector2.ZERO
var active := false
var deliveries: int = 0
var carrying := false
var _facing := 0.0
var _previous_pose := Transform3D.IDENTITY
var _current_pose := Transform3D.IDENTITY
@onready var _visual: Node3D = $Body


func _ready() -> void:
	_visual.top_level = true
	_current_pose = Transform3D(Basis.IDENTITY, global_position)
	_previous_pose = _current_pose
	_visual.global_transform = _current_pose


func _process(_delta: float) -> void:
	_visual.global_transform = _previous_pose.interpolate_with(
			_current_pose, Engine.get_physics_interpolation_fraction()) if smooth_visuals else _current_pose


func _physics_process(delta: float) -> void:
	_previous_pose = _current_pose
	if not active:
		velocity = Vector3.ZERO
		return
	velocity = Vector3(wish.x, 0.0, wish.y) * speed
	velocity.y = -2.0
	move_and_slide()
	position.x = clampf(position.x, -9.0, 9.0)
	position.z = clampf(position.z, -7.0, 7.0)
	if position.distance_to(Vector3(lane, 0, -5)) < 1.2:
		carrying = true
	if carrying and position.distance_to(Vector3(lane, 0, 5)) < 1.2:
		carrying = false
		deliveries += 1
	_facing = lerp_angle(_facing,
			atan2(-velocity.x, -velocity.z), minf(delta * 10.0, 1.0))
	_current_pose = Transform3D(Basis(Vector3.UP, _facing), global_position)
