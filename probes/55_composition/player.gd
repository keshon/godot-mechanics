class_name CompositionPlayer
extends CharacterBody3D
## Camera-independent movement intentions. Visual facing never rotates the collision body.

@export var run_speed := 7.0
@export var acceleration := 38.0
@export var air_acceleration := 16.0
@export var gravity := 24.0
@export var jump_speed := 9.0
@export var coyote_time := 0.12
@export var buffer_time := 0.15
@export var dash_speed := 17.0
@export var dash_duration := 0.18
@export var coyote_enabled := true
@export var buffer_enabled := true
@export var variable_jump := true
@export var double_enabled := true
@export var dash_enabled := true
@export var smooth_visuals := true

@export var caption := "P1"
@export var tint := Color(1.0, 0.55, 0.2)

var wish := Vector3.ZERO
var jump_pressed := false
var jump_held := false
var dash_pressed := false
var air_jump_left := true
var dash_left := true
var last_jump := "—"
var jumps: int = 0
var falls: int = 0
var airtime := 0.0
var last_airtime := 0.0
var last_distance := 0.0
var peak_height := 0.0
var spawn := Vector3(0, 0.1, 5)
var _coyote := 0.0
var _buffer := 0.0
var _dash := 0.0
var _dash_direction := Vector3.FORWARD
var _was_held := false
var _takeoff := Vector3.ZERO
var _facing := 0.0
var _previous_pose := Transform3D.IDENTITY
var _current_pose := Transform3D.IDENTITY
@onready var _visual: Node3D = $Body


func _ready() -> void:
	# Local render interpolation avoids changing the other probes' physics configuration.
	_visual.top_level = true
	process_priority = -10
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	$Body/Mesh.material_override = material
	$Body/Label.text = caption
	_snap_visual()


func _process(_delta: float) -> void:
	_visual.global_transform = _previous_pose.interpolate_with(
			_current_pose, Engine.get_physics_interpolation_fraction()) if smooth_visuals else _current_pose


func _physics_process(delta: float) -> void:
	_previous_pose = _current_pose
	var grounded: bool = is_on_floor()
	_coyote = coyote_time if grounded else maxf(_coyote - delta, 0.0)
	_buffer = maxf(_buffer - delta, 0.0)
	if grounded:
		air_jump_left = true
		dash_left = true
	if jump_pressed:
		_buffer = buffer_time if buffer_enabled else delta
	var launched := false
	if _buffer > 0.0 and (grounded or (coyote_enabled and _coyote > 0.0)):
		last_jump = "с земли" if grounded else "после края"
		_jump()
		launched = true
	elif jump_pressed and double_enabled and air_jump_left and not grounded:
		last_jump = "второй"
		_jump()
		air_jump_left = false
		launched = true
	if variable_jump and not jump_held and (_was_held or launched) and velocity.y > 4.0:
		velocity.y = 4.0
	_was_held = jump_held
	if dash_pressed and dash_enabled and dash_left:
		_dash_direction = wish.normalized() if wish.length_squared() > 0.01 else (
				Basis(Vector3.UP, _facing) * Vector3.FORWARD)
		_dash = dash_duration
		dash_left = false
	var planar := Vector3(velocity.x, 0.0, velocity.z)
	if _dash > 0.0:
		planar = _dash_direction * dash_speed
		_dash = maxf(_dash - delta, 0.0)
	else:
		planar = planar.move_toward(wish.limit_length() * run_speed,
				(acceleration if grounded else air_acceleration) * delta)
	velocity.x = planar.x
	velocity.z = planar.z
	velocity.y -= gravity * delta
	var before: Vector3 = global_position
	move_and_slide()
	if not is_on_floor():
		if airtime == 0.0:
			_takeoff = before
			peak_height = 0.0
		airtime += delta
		peak_height = maxf(peak_height, global_position.y - _takeoff.y)
	elif airtime > 0.0:
		if airtime > 0.1:
			last_airtime = airtime
			last_distance = Vector2(position.x - _takeoff.x, position.z - _takeoff.z).length()
		airtime = 0.0
	if planar.length_squared() > 0.1:
		_facing = lerp_angle(_facing,
				atan2(-planar.x, -planar.z), 1.0 - exp(-14.0 * delta))
	_current_pose = Transform3D(Basis(Vector3.UP, _facing), global_position)
	if position.y < -8.0:
		falls += 1
		reset_at(spawn)
	jump_pressed = false
	dash_pressed = false


func reset_at(point: Vector3) -> void:
	spawn = point
	wish = Vector3.ZERO
	global_position = point
	velocity = Vector3.ZERO
	_coyote = 0.0
	_buffer = 0.0
	_dash = 0.0
	airtime = 0.0
	last_airtime = 0.0
	last_distance = 0.0
	peak_height = 0.0
	last_jump = "—"
	air_jump_left = true
	dash_left = true
	jump_pressed = false
	dash_pressed = false
	jump_held = false
	_was_held = false
	# Clear stale floor contact from the previous position before accepting another jump.
	move_and_slide()
	_snap_visual()


func visual_position() -> Vector3:
	return _visual.global_position


func _snap_visual() -> void:
	_current_pose = Transform3D(Basis(Vector3.UP, _facing), global_position)
	_previous_pose = _current_pose
	_visual.global_transform = _current_pose


func _jump() -> void:
	velocity.y = jump_speed
	_buffer = 0.0
	_coyote = 0.0
	jumps += 1
