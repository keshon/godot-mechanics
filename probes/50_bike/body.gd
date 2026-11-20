class_name BikeBody
extends RigidBody3D
## Two ray-suspended tyres and an explicit rider balance controller.
## This is a riding model, not a simulation of steering geometry or wheel gyroscopes.

signal landed(seconds: float, distance: float, closing_speed: float)
signal crashed

## Rear-wheel drive force at low speed, N. Power limits it at higher speeds.
@export var drive_force := 1100.0
@export var power := 22000.0
## Combined braking force, N; 72% is assigned to the front tyre.
@export var brake_force := 4200.0
@export_range(0.3, 1.5, 0.05) var grip := 0.95
@export var wheelbase := 1.45
## Aerodynamic drag coefficient in F = coefficient * speed², N/(m/s)².
@export var drag := 0.55
## Roll controller gains: N m/rad and N m per rad/s. This substitutes for rider balance.
@export var balance_strength := 1800.0
@export var balance_damping := 300.0
@export var balance_enabled := true
## Direct airborne pitch torque, N m. Deliberate gameplay assistance, not wheel momentum.
@export var air_torque := 110.0
@export var air_control := true

var throttle := 0.0
var brake := 0.0
var steering := 0.0
## Positive means move the rider back / raise the front wheel.
var rider := 0.0
var rear_brake := false
var speed := 0.0
var steer_angle := 0.0
var lean := 0.0
var pitch := 0.0
var contacts: int = 0
var airborne := 0.0
var last_airtime := 0.0
var last_distance := 0.0
var last_landing := 0.0
var bottomed: int = 0
var fallen := false

var _takeoff := Vector3.ZERO
var _reset_pending := false
var _reset_pose := Transform3D.IDENTITY
var _reset_velocity := Vector3.ZERO
var _bottomed_before := false

@onready var wheels: Array[BikeWheel] = [$Front, $Rear]
@onready var _motor: AudioStreamPlayer3D = $Motor
@onready var _rider: Node3D = $Rider


func _ready() -> void:
	var sound := _motor.stream as AudioStreamOggVorbis
	sound.loop = true


func _process(delta: float) -> void:
	_motor.pitch_scale = 0.7 + minf(absf(speed) * 0.055, 1.4) + throttle * 0.35
	_motor.volume_db = -40.0 if fallen else -24.0 + throttle * 6.0
	for wheel in wheels:
		wheel.animate(speed, steer_angle, delta)
	_rider.rotation.x = lerpf(_rider.rotation.x, rider * 0.22, 1.0 - exp(-8.0 * delta))


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _reset_pending:
		state.transform = _reset_pose
		state.linear_velocity = _reset_velocity
		state.angular_velocity = Vector3.ZERO
		state.sleeping = false
		_reset_pending = false
		return
	var basis: Basis = state.transform.basis
	var ahead: Vector3 = -basis.z
	speed = state.linear_velocity.dot(ahead)
	lean = atan2(basis.x.y, basis.y.y)
	pitch = asin(clampf(ahead.y, -1.0, 1.0))
	if fallen:
		return
	if basis.y.dot(Vector3.UP) < 0.15 or state.transform.origin.y < -8.0:
		fallen = true
		crashed.emit()
		return
	var limit: float = lerpf(0.48, 0.10, clampf(absf(speed) / 22.0, 0.0, 1.0))
	steer_angle = move_toward(steer_angle, steering * limit, 1.8 * state.step)
	contacts = 0
	var at_bottom := false
	for wheel in wheels:
		wheel.sample(state, get_rid())
		if wheel.grounded:
			contacts += 1
			_tyre(state, wheel)
		at_bottom = at_bottom or wheel.compression > wheel.travel * 0.95
	if at_bottom and not _bottomed_before:
		bottomed += 1
	_bottomed_before = at_bottom
	_flight(state)
	if contacts > 0 and balance_enabled:
		var desired: float = clampf(
				atan(speed * speed * tan(steer_angle) / (wheelbase * 9.81)), -0.70, 0.70)
		var roll_rate: float = state.angular_velocity.dot(basis.z)
		state.apply_torque(basis.z * (
				(desired - lean) * balance_strength - roll_rate * balance_damping))
	if contacts > 0 or air_control:
		var torque: float = 85.0 if contacts > 0 else air_torque
		state.apply_torque(basis.x * rider * torque)
	state.apply_central_force(-state.linear_velocity * state.linear_velocity.length() * drag)


## Queue a reset for the physics callback, which owns the rigid body's state.
func reset_at(pose: Transform3D, velocity := Vector3.ZERO) -> void:
	_reset_pose = pose
	_reset_velocity = velocity
	_reset_pending = true
	fallen = false
	contacts = 0
	speed = 0.0
	pitch = 0.0
	lean = 0.0
	airborne = 0.0
	last_airtime = 0.0
	last_distance = 0.0
	last_landing = 0.0
	bottomed = 0
	steer_angle = 0.0
	_bottomed_before = false
	for wheel in wheels:
		wheel.grounded = false
		wheel.compression = 0.0
		wheel.wheel_load = 0.0


func _tyre(state: PhysicsDirectBodyState3D, wheel: BikeWheel) -> void:
	var ahead: Vector3 = -state.transform.basis.z
	if wheel.front:
		ahead = ahead.rotated(state.transform.basis.y, steer_angle)
	ahead = ahead.slide(wheel.normal).normalized()
	var right: Vector3 = ahead.cross(wheel.normal).normalized()
	var offset: Vector3 = wheel.contact - state.transform.origin
	var velocity: Vector3 = state.get_velocity_at_local_position(offset)
	var along: float = velocity.dot(ahead)
	var across: float = velocity.dot(right)
	var budget: float = grip * wheel.wheel_load
	if rear_brake and not wheel.front:
		budget *= 0.50
	var sideways: float = -across / maxf(absf(along), 3.0) * budget * 7.0
	var forwards := 0.0
	if not wheel.front:
		forwards = throttle * minf(drive_force, power / maxf(absf(speed), 3.0))
	var braking: float = brake * brake_force * (0.72 if wheel.front else 0.28)
	if rear_brake and not wheel.front:
		braking += brake_force * 0.5
	forwards -= signf(along) * minf(braking + wheel.wheel_load * 0.02,
			absf(along) * mass * 0.5 / state.step)
	var force := Vector2(forwards, sideways)
	wheel.grip_used = minf(force.length() / maxf(budget, 1.0), 1.0)
	force = force.limit_length(budget)
	state.apply_force(ahead * force.x + right * force.y, offset)


func _flight(state: PhysicsDirectBodyState3D) -> void:
	if contacts == 0:
		if airborne == 0.0:
			_takeoff = state.transform.origin
		airborne += state.step
		return
	if airborne > 0.15:
		last_airtime = airborne
		var span: Vector3 = state.transform.origin - _takeoff
		last_distance = Vector2(span.x, span.z).length()
		var normal := Vector3.ZERO
		for wheel in wheels:
			if wheel.grounded:
				normal += wheel.normal
		last_landing = maxf(-state.linear_velocity.dot(normal.normalized()), 0.0)
		landed.emit(last_airtime, last_distance, last_landing)
	airborne = 0.0
