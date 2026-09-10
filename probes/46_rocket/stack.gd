class_name RocketStack
extends RigidBody3D
## THE STACK.
##
## A rocket is a pile of stages that agree to fly together until they do not: the mass is their
## sum, the centre of mass is their weighted average and moves while they burn, and separation
## is the moment a stage stops being part of the sum.
##
## Nothing here reads a key. What arrives from outside is `want_dir` and `throttle`; HOW to get
## the nose there is the vehicle own business, and it has to be, because the airframe cannot be
## flown by hand — the centre of pressure sits ahead of the centre of mass and without a loop
## closing on attitude the stack tumbles in seconds. Real launchers have the same answer.
##
## The engines are the only control below the atmosphere, and they SWIVEL: `swing_pitch` and
## `swing_yaw` turn the plume nodes, so the gimbal is a moving part and not a readout.
##
## Godot's own damping is switched off in the scene, in `Replace` mode: the project default
## of 0.1 per second is a second, invisible drag proportional to SPEED, and it held this
## rocket to half its acceleration for an entire session.

signal separated(at: Transform3D, away: Vector3, dry: float)
signal staged_out
signal struck(where: Vector3, speed: float)

## Gravity at the pad, m/s2. Only used to quote thrust as a multiple of weight.
const GRAVITY := 9.81
## Below this airspeed, in metres per second, air forces are not worth computing.
const MIN_AIRSPEED := 1.0
## How far out and back a separated block is pushed, m/s.
const SEPARATION_OUT := 7.0
const SEPARATION_BACK := 4.0

@export_group("Air")
@export_range(0.1, 40.0, 0.1) var frontal_area := 9.6
@export_range(0.05, 1.5, 0.01) var body_drag := 0.32
@export_range(0.0, 6.0, 0.1) var induced_drag := 1.2
@export_range(0.0, 8.0, 0.1) var body_lift := 2.0
@export_range(0.0, 30.0, 0.5) var crossflow := 9.0
@export_range(0.0, 800.0, 5.0) var damping := 260.0
@export_range(0.0, 200.0, 1.0) var roll_damping := 18.0

@export_group("Control")
## How fast the engines can swivel, degrees per second. A real actuator is not instant, and the
## loop is balancing an unstable body: with no rate limit it throws the engines to full travel
## every tick and the vehicle shivers itself apart.
@export_range(2.0, 120.0, 1.0) var gimbal_rate := 22.0
## Attitude hold: proportional on the angle, minus the rotation rate. The second half matters
## more — engines swivel far faster than a hundred tonnes turns, and a loop without it swings.
@export_range(0.2, 8.0, 0.1) var hold_gain := 2.4
@export_range(0.0, 8.0, 0.1) var hold_damp := 1.8

@export_group("Payload")
## Everything that is not a stage: the thing the whole vehicle exists to lift.
@export_range(0.0, 40000.0, 10.0) var payload := 1400.0

var throttle := 1.0
## Where the nose should point, in world space. Zero means nobody is asking, and then the
## gimbal obeys `pitch_input` and `yaw_input` as written.
var want_dir := Vector3.ZERO
var pitch_input := 0.0
var yaw_input := 0.0

var flying := false
## Held down: the engines run and the rocket stands still, as it does for real.
var clamped := false
## Thrust to weight; the clamps let go once it passes one.
var lift_ratio := 0.0
var speed := 0.0
## Angle between nose and travel, radians.
var alpha := 0.0
## Dynamic pressure, Pa.
var dynamic := 0.0
## Static margin: metres from the centre of mass back to the centre of pressure.
var margin := 0.0
## Which group separates next.
var group := 0
## Thrust produced this tick, newtons.
var push := 0.0

## Where the engines actually are, not what was asked of them: the gap is the actuator.
var swing_pitch := 0.0
var swing_yaw := 0.0

var stages: Array[RocketStage] = []
var planet: RocketPlanet = null

@onready var _cop: Node3D = $Cop


func _ready() -> void:
	for child in get_children():
		var stage := child as RocketStage
		if stage != null:
			stages.append(stage)
	stages.sort_custom(
			func(first: RocketStage, second: RocketStage) -> bool:
				return first.group < second.group)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	gravity_scale = 0.0
	_weigh()


func _physics_process(delta: float) -> void:
	if not flying or planet == null:
		return
	_weigh()

	var velocity := linear_velocity
	speed = velocity.length()
	var nose := -global_basis.z
	alpha = (0.0 if speed < MIN_AIRSPEED
			else acos(clampf(nose.dot(velocity / speed), -1.0, 1.0)))

	apply_central_force(planet.gravity(global_position) * mass)

	var density := planet.density(global_position)
	var air := density / maxf(planet.sea_density, 0.001)
	# Everything alight burns, not only the group that separates next. On this vehicle the
	# core is lit on the pad and goes on burning through the whole first stage and past it,
	# which is why thrust does not collapse when the boosters leave.
	push = 0.0
	for stage in stages:
		push += stage.burn(throttle, delta, air)

	lift_ratio = push / maxf(mass * GRAVITY, 1.0)
	if clamped and not _hold_clamps():
		return
	if want_dir.length_squared() > 0.5:
		_hold(want_dir)
	if push > 0.0:
		_gimbal(delta)

	dynamic = 0.5 * density * speed * speed
	if speed > MIN_AIRSPEED and density > 0.0:
		_air(velocity, density)
	_damp(dynamic)


## IGNITION IS NOT LAUNCH. The engines come up to pressure while the clamps hold the vehicle,
## and it leaves only once thrust outweighs it. Saturn V spent nine seconds between those two
## events; nowhere does a rocket leave the pad the instant a switch is thrown.
##
## THE CLAMPS BELONG TO THE PAD, and `hold` is how that is said. Lighting a stage in flight
## must not re-clamp the vehicle: re-clamping zeroes the velocity for a tick, the stack begins
## each stage from a standstill while the blocks it just released sail past it, and the ascent
## reads as short of thrust for a reason that has nothing to do with thrust.
func ignite(hold := false) -> void:
	flying = true
	clamped = hold
	for stage in stages:
		if stage.lit:
			continue
		if stage.group == group or stage.starts_lit:
			stage.lit = true
			stage.since_light = 0.0


## SEPARATION. Four side blocks share a group number and leave together, which is the whole
## reason the group is a number and not a boolean.
func drop() -> void:
	var going: Array[RocketStage] = []
	for stage in stages:
		if stage.group == group:
			going.append(stage)
	if going.is_empty():
		return
	for stage in going:
		stages.erase(stage)
		_release(stage)
	group += 1
	if stages.is_empty():
		staged_out.emit()
		_shut_down()
	else:
		ignite()
	_weigh()


## THE BAR THE WHOLE FLIGHT IS AIMED AT. Apoapsis and periapsis straight out of the two
## vectors, without integrating anything: energy gives the size of the ellipse, angular
## momentum gives its shape.
func orbit() -> Dictionary:
	if planet == null:
		return {"apo": 0.0, "peri": 0.0}
	var mu := planet.surface_gravity * planet.radius * planet.radius
	var from_centre := global_position - planet.centre
	var velocity := linear_velocity
	var range_to_centre := maxf(from_centre.length(), 1.0)
	var energy := velocity.length_squared() * 0.5 - mu / range_to_centre
	if absf(energy) < 1e-9:
		return {"apo": INF, "peri": 0.0}
	var axis := -mu / (2.0 * energy)
	var momentum := from_centre.cross(velocity).length()
	var shape := sqrt(maxf(
			0.0, 1.0 + 2.0 * energy * momentum * momentum / (mu * mu)))
	return {
		"apo": axis * (1.0 + shape) - planet.radius,
		"peri": axis * (1.0 - shape) - planet.radius,
	}


## Mass and centre of mass are the same calculation, and it has to run every tick because
## the answer changes every tick.
func _weigh() -> void:
	var total := payload
	var moment := Vector3.ZERO
	for stage in stages:
		var stage_mass := stage.mass()
		total += stage_mass
		moment += stage.position * stage_mass
	mass = maxf(total, 1.0)
	center_of_mass = moment / mass
	var lever := _cop.position - center_of_mass
	margin = lever.length() * signf(lever.dot(Vector3.BACK))


## Hold the vehicle still and report whether the clamps let go this tick. Thrust is counted
## and propellant spent while they hold, but nothing moves — standing still is the thing to see.
func _hold_clamps() -> bool:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	if lift_ratio <= 1.0:
		return false
	clamped = false
	return true


## Push a separated block clear. The outward part is taken ACROSS the body only: the block
## sits fourteen metres aft of the origin, so the raw vector to it points mostly backwards and
## the blocks leave in line astern with no cross at all.
func _release(stage: RocketStage) -> void:
	var axis := global_basis.z
	var out := stage.global_position - global_position
	out -= axis * out.dot(axis)
	out = (out.normalized() * SEPARATION_OUT if out.length() > 0.1
			else global_basis.x * 3.0)
	separated.emit(
			stage.global_transform,
			linear_velocity + out + axis * SEPARATION_BACK,
			stage.dry_mass)
	stage.get_parent().remove_child(stage)
	stage.queue_free()


## ATTITUDE HOLD, and it belongs to the VEHICLE: outside decides where to point, the stack
## decides how to get there. In the rig it makes the rocket flyable by one test stand only.
func _hold(want: Vector3) -> void:
	var local := global_basis.inverse() * want.normalized()
	var rate := global_basis.inverse() * angular_velocity
	var pitch_error := atan2(local.y, maxf(-local.z, 0.05))
	var yaw_error := atan2(local.x, maxf(-local.z, 0.05))
	pitch_input = clampf(pitch_error * hold_gain - rate.x * hold_damp, -1.0, 1.0)
	yaw_input = clampf(yaw_error * hold_gain + rate.y * hold_damp, -1.0, 1.0)


## THE ENGINES SWIVEL, and at zero airspeed that is the only control there is — a rocket
## leaving the pad has no airflow to push against.
##
## The signs are inverted for the same reason as the fins in the forty-fourth probe: the
## engines sit BEHIND the centre of mass, so pushing the tail up is what drops the nose.
func _gimbal(delta: float) -> void:
	var swing := 0.0
	for stage in stages:
		if stage.lit and stage.fuel > 0.0:
			swing = maxf(swing, stage.gimbal)
	var step := gimbal_rate * delta
	swing_pitch = move_toward(swing_pitch, swing * pitch_input, step)
	swing_yaw = move_toward(swing_yaw, swing * yaw_input, step)
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(-swing_pitch))
	tilt = tilt * Basis(Vector3.UP, deg_to_rad(swing_yaw))
	for stage in stages:
		if stage.lit:
			stage.aim(tilt)
	var direction := global_basis * tilt * Vector3.FORWARD
	apply_force(direction * push, global_basis * (Vector3.BACK * _tail()))


## Where the engines push from, and HOW FAR behind the centre of mass is the whole of the
## gimbal's authority. Guessing it — the stage's node plus two metres — puts the answer seven
## metres short, because the nozzles of the side blocks sit that much further back: six metres
## of lever instead of eleven and a half, and the rocket flips on the gravity turn.
func _tail() -> float:
	var back := 0.0
	for stage in stages:
		if stage.lit and stage.fuel > 0.0:
			back = maxf(back, stage.nozzle())
	return back


## Drag along the airflow, hull lift across it at the centre of pressure. Copied in spirit from
## the forty-fourth probe and not shared with it: probes do not lend each other code.
func _air(velocity: Vector3, density: float) -> void:
	var along := velocity / speed
	var drag := body_drag + induced_drag * sin(alpha) * sin(alpha)
	apply_central_force(-along * dynamic * frontal_area * drag)
	if alpha < 0.001:
		return
	var nose := -global_basis.z
	var side := nose - along * nose.dot(along)
	if side.length_squared() < 1e-9:
		return
	var sine := sin(alpha)
	var normal_force := body_lift * sine * cos(alpha) + crossflow * sine * sine
	# The offset is measured from the body's ORIGIN, and Godot subtracts the centre of mass
	# itself: handing it `cop - centre_of_mass` subtracts the centre twice, and the lever of
	# the one force that turns the rocket over comes out half as long again as the geometry
	# says. `margin` on the readout is the same difference taken for the eye, not the physics.
	apply_force(
			side.normalized() * dynamic * frontal_area * normal_force,
			global_basis * _cop.position)


## Roll and swing damp at different rates, and not for aerodynamic reasons first: the moment of
## inertia about the long axis is a hundred times smaller than across it, and one coefficient
## for both makes the explicit scheme spin up instead of settle.
func _damp(pressure: float) -> void:
	var spin := angular_velocity
	if spin.is_zero_approx() or pressure <= 0.0:
		return
	var calibre := 2.0 * sqrt(frontal_area / PI)
	var base := (pressure * frontal_area * calibre * calibre
			/ (2.0 * maxf(speed, MIN_AIRSPEED)))
	var axis := global_basis.z
	var roll := axis * spin.dot(axis)
	apply_torque(-((spin - roll) * damping + roll * roll_damping) * base)


## Nothing is running, so nothing should still read as if it were.
func _shut_down() -> void:
	flying = false
	push = 0.0
	lift_ratio = 0.0


## A launcher probe in which the vehicle sinks through the planet cannot show what an unstable
## ascent costs.
func _on_body_entered(_body: Node) -> void:
	if flying:
		_shut_down()
		struck.emit(global_position, speed)
