class_name OrbitPlayer
extends CharacterBody3D
## Third-person mover. The body never rotates — its `Body` child does.
##
## That split IS third person. In probe 01 the camera was the body's yaw: turn
## the mouse and the body turned with it. Here the camera orbits freely while
## the body turns toward wherever it happens to be going, and arrives late.
## The lateness is one number, `turn_speed`, and it decides almost everything
## about whether the character reads as heavy or as weightless.
##
## The rig hangs off this node, so it inherits position and nothing else.
## That only works because this node's rotation stays identity forever.

## True while the aim button is held. The camera rig listens (wired in the
## scene, see the [connection] block at the bottom of orbit.tscn).
signal mode_changed(aiming: bool)


@export_group("Move")
## Top speed on the ground, m/s.
@export_range(1.0, 15.0, 0.1) var max_speed := 6.0
## How fast velocity climbs toward max_speed, m/s².
##
## Deliberately NOT probe 01's Quake accelerator. This is a plain move_toward:
## linear, predictable, no dot product, no way to cheat the cap. Most
## third-person games want exactly that — you are watching the character from
## outside, and a body that gains speed you did not ask for looks broken
## rather than skilful.
@export_range(1.0, 200.0, 1.0) var acceleration := 45.0
## How fast it bleeds off once you let go, m/s². Higher than acceleration =
## crisp stops.
@export_range(1.0, 200.0, 1.0) var brake := 60.0


@export_group("Turn")
## THE number of this probe, in radians per second. How fast the body swings to
## face its own motion. 3 is a tank turning in mud. 25 is instant and
## weightless. The whole feel of a third-person character lives between those.
@export_range(1.0, 30.0, 0.5) var turn_speed := 10.0
## Below this speed, m/s, the body keeps its current facing instead of snapping
## around. Without it, the last centimetre of a stop makes the character
## twitch as the leftover velocity vector wanders.
@export_range(0.0, 2.0, 0.05) var turn_deadzone := 0.4


@export_group("Jump")
## Upward speed given at takeoff, m/s.
@export_range(1.0, 15.0, 0.1) var jump_velocity := 5.5
## Local gravity, m/s².
@export_range(1.0, 60.0, 0.5) var gravity := 20.0

var _spawn: Transform3D
var _aiming := false

@onready var _rig: Node3D = $CameraRig
@onready var _body: Node3D = $Body


func _ready() -> void:
	_spawn = global_transform
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed(&"respawn"):
		_respawn()
		return

	var aim_held := Input.is_action_pressed(&"aim")
	if aim_held != _aiming:
		_aiming = aim_held
		mode_changed.emit(_aiming)

	velocity.y -= gravity * delta

	var wish := _wish_direction()
	var planar := Vector3(velocity.x, 0.0, velocity.z)
	planar = planar.move_toward(
			wish * max_speed,
			(acceleration if wish != Vector3.ZERO else brake) * delta)
	velocity.x = planar.x
	velocity.z = planar.z

	if is_on_floor() and Input.is_action_just_pressed(&"jump"):
		velocity.y = jump_velocity

	move_and_slide()
	_face(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif (
			event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed
	):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Horizontal speed, m/s.
func speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Signed degrees between where the body points and where the camera points.
## Watch this readout: in free mode it swings wildly, and the moment you hold
## aim it collapses to zero and stays there. That number is the whole probe.
func facing_error() -> float:
	var body_direction := _horizontal_direction(-_body.global_basis.z)
	var camera_direction := _horizontal_direction(-_rig.global_basis.z)
	if body_direction == Vector3.ZERO or camera_direction == Vector3.ZERO:
		return 0.0
	return rad_to_deg(body_direction.signed_angle_to(camera_direction, Vector3.UP))


func is_aiming() -> bool:
	return _aiming


## Movement is read in the CAMERA's frame, not the body's. W means "away from
## the camera", which is why you can run in a circle around the character
## without ever touching a movement key — just swing the mouse.
func _wish_direction() -> Vector3:
	var input: Vector2 = Input.get_vector(
			&"move_left", &"move_right", &"move_forward", &"move_back")
	if input == Vector2.ZERO:
		return Vector3.ZERO
	# Flatten the camera basis onto the ground first. Skip this and looking at
	# your own feet would ask the character to walk into the floor.
	var basis := _rig.global_basis
	return (
			_horizontal_direction(basis.x) * input.x
			+ _horizontal_direction(-basis.z) * -input.y
	).normalized()


func _face(delta: float) -> void:
	var target := Vector3.ZERO
	if _aiming:
		# Aiming welds the body to the camera. You stop turning and start
		# strafing, and that single swap is what every over-the-shoulder
		# shooter is built on.
		target = _horizontal_direction(-_rig.global_basis.z)
	else:
		# The deadzone is measured on real speed, so this one must NOT
		# normalise before the length is checked.
		var motion := _horizontal(velocity)
		if motion.length() >= turn_deadzone:
			target = motion.normalized()

	if target == Vector3.ZERO:
		return

	var want := Basis.looking_at(target, Vector3.UP)
	# Slerp on quaternions, never lerp on euler angles: euler wraps at ±180°,
	# and a body crossing behind itself would spin the long way round.
	_body.global_basis = Basis(_body.global_basis.get_rotation_quaternion().slerp(
			want.get_rotation_quaternion(),
			clampf(turn_speed * delta, 0.0, 1.0)))


func _respawn() -> void:
	global_transform = _spawn
	velocity = Vector3.ZERO
	# The rig trails the body instead of being welded to it, so a teleport has
	# to be told about — otherwise the camera sweeps across the whole level to
	# catch up.
	_rig.snap()


## Drop the vertical component, keep the length.
func _horizontal(v: Vector3) -> Vector3:
	v.y = 0.0
	return v


## Drop the vertical component and normalise. Godot 4's normalized() already
## returns zero for a zero vector, so no guard is needed here.
func _horizontal_direction(v: Vector3) -> Vector3:
	v.y = 0.0
	return v.normalized()
