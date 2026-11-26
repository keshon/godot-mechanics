class_name PlatformProbePlayer
extends CharacterBody3D
## Traversal controls plus native support motion. Air steering acts relative to departure momentum.

@export var speed := 7.0
@export var air_acceleration := 16.0
@export var jump_speed := 9.0
@export var coyote_time := 0.12
@export var buffer_time := 0.15
@export var dash_speed := 17.0
@export var dash_duration := 0.18
@export var double_enabled := true
@export var dash_enabled := true
var wish := Vector3.ZERO
var jump_pressed := false
var jump_held := false
var dash_pressed := false
var air_jump_left := true
var dash_left := true
var support: MovingProbePlatform
var departure := Vector3.ZERO
var jumps: int = 0
var landings: int = 0
var _facing := 0.0
var _carry := Vector3.ZERO
var _coyote := 0.0
var _buffer := 0.0
var _dash := 0.0
var _dash_direction := Vector3.FORWARD
var _was_held := false
var _previous := Transform3D.IDENTITY
var _current := Transform3D.IDENTITY
@onready var visual: Node3D = $Visual


func _ready() -> void:
	visual.top_level = true
	process_priority = -10
	reset_at(global_position)


func _process(_delta: float) -> void:
	visual.global_transform = _previous.interpolate_with(
			_current, Engine.get_physics_interpolation_fraction())


func _physics_process(delta: float) -> void:
	_previous = _current
	var grounded: bool = is_on_floor()
	_coyote = coyote_time if grounded else maxf(_coyote - delta, 0.0)
	_buffer = maxf(_buffer - delta, 0.0)
	if grounded:
		_carry = Vector3.ZERO
		air_jump_left = true
		dash_left = true
	if jump_pressed:
		_buffer = buffer_time
	var launched := false
	if _buffer > 0.0 and (grounded or _coyote > 0.0):
		_jump()
		launched = true
	elif jump_pressed and double_enabled and air_jump_left and not grounded:
		_jump()
		air_jump_left = false
		launched = true
	if not jump_held and (_was_held or launched) and velocity.y > 4.0:
		velocity.y = 4.0
	_was_held = jump_held
	if dash_pressed and dash_enabled and dash_left:
		_dash_direction = wish.normalized() if wish.length_squared() > 0.01 else (
				Basis(Vector3.UP, _facing) * Vector3.FORWARD)
		_dash = dash_duration
		dash_left = false
	var planar := Vector3(velocity.x, 0, velocity.z)
	var inherited := Vector3(_carry.x, 0, _carry.z)
	if _dash > 0.0:
		planar = _dash_direction * dash_speed + inherited
		_dash = maxf(_dash - delta, 0.0)
	else:
		planar = planar.move_toward(wish.limit_length() * speed + inherited,
				(38.0 if grounded else air_acceleration) * delta)
	velocity.x = planar.x
	velocity.z = planar.z
	velocity.y -= 24.0 * delta
	var before: Vector3 = velocity
	move_and_slide()
	if grounded and not is_on_floor():
		departure = velocity
		# The engine adds support velocity on departure. Retain it as the air-control baseline.
		_carry = velocity - before
	if not grounded and is_on_floor():
		landings += 1
	support = null
	if is_on_floor():
		for i in range(get_slide_collision_count()):
			var hit: KinematicCollision3D = get_slide_collision(i)
			if hit.get_normal().dot(Vector3.UP) > 0.7:
				var platform: MovingProbePlatform = hit.get_collider() as MovingProbePlatform
				if platform != null:
					support = platform
					platform.trigger()
	if wish.length_squared() > 0.01:
		_facing = lerp_angle(_facing, atan2(-wish.x, -wish.z), 1.0 - exp(-14.0 * delta))
	_current = Transform3D(Basis(Vector3.UP, _facing), global_position)
	jump_pressed = false
	dash_pressed = false


func reset_at(point: Vector3) -> void:
	global_position = point
	velocity = Vector3.ZERO
	wish = Vector3.ZERO
	jump_pressed = false
	jump_held = false
	dash_pressed = false
	air_jump_left = true
	dash_left = true
	_carry = Vector3.ZERO
	_coyote = 0.0
	_buffer = 0.0
	_dash = 0.0
	_was_held = false
	support = null
	departure = Vector3.ZERO
	# A teleport is not a departure: discard cached platform velocity while clearing contacts.
	var policy: int = platform_on_leave
	platform_on_leave = PLATFORM_ON_LEAVE_DO_NOTHING
	var layers: int = platform_floor_layers
	platform_floor_layers = 0
	move_and_slide()
	# The first move consumes the former support's cached motion, even with zero velocity.
	global_position = point
	velocity = Vector3.ZERO
	platform_floor_layers = layers
	move_and_slide()
	platform_on_leave = policy
	velocity = Vector3.ZERO
	_current = Transform3D(Basis(Vector3.UP, _facing), global_position)
	_previous = _current
	visual.global_transform = _current


func _jump() -> void:
	velocity.y = jump_speed
	_buffer = 0.0
	_coyote = 0.0
	jumps += 1
