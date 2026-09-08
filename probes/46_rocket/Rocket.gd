extends RigidBody3D
class_name RocketStack

## THE STACK.
##
## A rocket is a pile of stages that agree to fly together until they do not. Everything
## here follows from that: the mass is their sum, the centre of mass is their weighted
## average and moves while they burn, and separation is the moment a stage stops being part
## of the sum.
##
## Nothing here reads a key. The intent that arrives from outside is `want_dir` — where the
## nose should point — and `throttle`. HOW to get the nose there is the vehicle's own
## business, and it has to be, because the airframe cannot be flown by hand: the centre of
## pressure sits ahead of the centre of mass, the static margin is negative, and without a
## loop closing on attitude the stack tumbles in seconds. Real launchers are the same shape
## of problem and have the same answer.
##
## The engines are the only control below the atmosphere, and they SWIVEL: `swing_pitch` and
## `swing_yaw` turn the plume nodes, so the gimbal is a moving part and not a readout.

signal separated(at: Transform3D, away: Vector3, dry: float)
signal staged_out
signal struck(where: Vector3, speed: float)

## Godot's own damping is switched off in the scene, and it has to be said out loud because
## the default is not zero: `linear_damp` and `angular_damp` fall back to the project default
## of 0.1 per second. That is a second, invisible drag proportional to SPEED, and it is what
## held this rocket to half its acceleration for an entire session — at a hundred metres per
## second it takes ten metres per second squared, more than the planet does.
@export_group("Air")
@export_range(0.1, 40.0, 0.1) var frontal_area := 9.6
@export_range(0.05, 1.5, 0.01) var body_drag := 0.32
@export_range(0.0, 8.0, 0.1) var body_lift := 2.0
@export_range(0.0, 30.0, 0.5) var crossflow := 9.0
@export_range(0.0, 800.0, 5.0) var damping := 260.0
@export_range(0.0, 200.0, 1.0) var roll_damping := 18.0

@export_group("Control")
## How fast the engines can swivel, degrees per second. A real actuator is not instant, and
## that is not a detail: the loop is balancing an unstable body, and with no rate limit it
## throws the engines to full travel every tick. The result is a self-sustained oscillation,
## and it looks like the whole vehicle shivering.
@export_range(2.0, 120.0, 1.0) var gimbal_rate := 22.0
## Attitude hold: proportional on the angle, minus the rotation rate. Both halves are needed
## and the second one more, because engines swivel far faster than a hundred tonnes turns and
## a loop without it sails past the angle it wanted and swings.
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
var roll_input := 0.0

var flying := false
## Held down: the engines run and the rocket stands still. That is what happens for real —
## seconds pass between ignition and release, and the clamps carry the vehicle for all of it.
var clamped := false
var lift_ratio := 0.0     ## thrust to weight; the clamps let go once it passes one
var speed := 0.0
var alpha := 0.0
var dynamic := 0.0        ## dynamic pressure, Pa
var margin := 0.0         ## static margin: metres from centre of mass back to centre of pressure
var group := 0            ## which group separates next
var push := 0.0           ## thrust produced this tick

## Where the engines actually are, not what was asked of them. The gap between the two is
## the actuator, and it is the reason the rate limit above matters.
var swing_pitch := 0.0
var swing_yaw := 0.0

var stages: Array[RocketStage] = []
var planet: RocketPlanet = null

@onready var _cop: Node3D = $Cop


func _ready() -> void:
	for c in get_children():
		var st := c as RocketStage
		if st != null:
			stages.append(st)
	stages.sort_custom(func(a, b): return a.group < b.group)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	gravity_scale = 0.0
	_weigh()


## IGNITION IS NOT LAUNCH. The engines come up to pressure while the clamps hold the vehicle,
## and it leaves only once thrust outweighs it. Saturn V spent nine seconds between those two
## events; on a Soyuz the clamps swing open under the weight of the rocket itself, the moment
## the thrust unloads them. Nowhere does a rocket leave the pad the instant a switch is thrown.
##
## THE CLAMPS BELONG TO THE PAD, and `hold` is how that is said. Lighting a stage in flight
## must not re-clamp the vehicle: the first version did, so every separation zeroed the
## velocity for a tick. The stack began each stage from a standstill while the blocks it had
## just released kept their speed and sailed past it — and the ascent read as short of thrust
## for a reason that had nothing to do with thrust.
func ignite(hold := false) -> void:
	flying = true
	clamped = hold
	for st in stages:
		if st.lit:
			continue
		if st.group == group or st.starts_lit:
			st.lit = true
			st.since_light = 0.0


## SEPARATION. Four side blocks share a group number and leave together, which is the whole
## reason the group is a number and not a boolean.
func drop() -> void:
	var going: Array[RocketStage] = []
	for st in stages:
		if st.group == group:
			going.append(st)
	if going.is_empty():
		return
	for st in going:
		stages.erase(st)
		# Outward and back, and the outward part is taken ACROSS the body only. The block sits
		# fourteen metres aft of the origin, so the raw vector to it points mostly backwards:
		# the blocks used to leave in line astern with no cross at all.
		var axis := global_basis.z
		var out := st.global_position - global_position
		out -= axis * out.dot(axis)
		out = out.normalized() * 7.0 if out.length() > 0.1 else global_basis.x * 3.0
		separated.emit(st.global_transform, linear_velocity + out + axis * 4.0, st.dry_mass)
		st.get_parent().remove_child(st)
		st.queue_free()
	group += 1
	if stages.is_empty():
		staged_out.emit()
		_shut_down()
	else:
		ignite()
	_weigh()


## Mass and centre of mass are the same calculation, and it has to run every tick because
## the answer changes every tick.
func _weigh() -> void:
	var total := payload
	var moment := Vector3.ZERO
	for st in stages:
		var m := st.mass()
		total += m
		moment += st.position * m
	mass = maxf(total, 1.0)
	center_of_mass = moment / mass
	margin = (_cop.position - center_of_mass).length() * signf(
		(_cop.position - center_of_mass).dot(Vector3.BACK))


func _physics_process(delta: float) -> void:
	if not flying or planet == null:
		return
	_weigh()

	var v := linear_velocity
	speed = v.length()
	var nose := -global_basis.z
	alpha = 0.0 if speed < 1.0 else acos(clampf(nose.dot(v / speed), -1.0, 1.0))

	apply_central_force(planet.gravity(global_position) * mass)

	var rho := planet.density(global_position)
	var air := rho / maxf(planet.sea_density, 0.001)
	# Everything alight burns, not only the group that separates next. On this vehicle the
	# core is lit on the pad and goes on burning through the whole first stage and past it,
	# which is why thrust does not collapse when the boosters leave.
	push = 0.0
	for st in stages:
		push += st.burn(throttle, delta, air)

	lift_ratio = push / maxf(mass * 9.81, 1.0)
	if clamped:
		# The clamps hold. Thrust is counted and propellant is spent, but the vehicle does not
		# move — and standing still is the thing to see.
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		if lift_ratio > 1.0:
			clamped = false
		else:
			return
	if want_dir.length_squared() > 0.5:
		_hold(want_dir)
	if push > 0.0:
		_gimbal(delta)

	dynamic = 0.5 * rho * speed * speed
	if speed > 1.0 and rho > 0.0:
		_air(v, rho)
	_damp(dynamic)


## ATTITUDE HOLD, and it belongs to the VEHICLE. It used to live in the rig, which made the
## rocket a thing only that one rig could fly; the split that works is that outside decides
## where to point and the stack decides how to get there.
func _hold(want: Vector3) -> void:
	var local := global_basis.inverse() * want.normalized()
	var rate := global_basis.inverse() * angular_velocity
	var pitch_err := atan2(local.y, maxf(-local.z, 0.05))
	var yaw_err := atan2(local.x, maxf(-local.z, 0.05))
	pitch_input = clampf(pitch_err * hold_gain - rate.x * hold_damp, -1.0, 1.0)
	yaw_input = clampf(yaw_err * hold_gain + rate.y * hold_damp, -1.0, 1.0)


## THE ENGINES SWIVEL, and at zero airspeed that is the only control there is — a rocket
## leaving the pad has no airflow to push against.
##
## The signs are inverted for the same reason as the fins in the forty-fourth probe: the
## engines sit BEHIND the centre of mass, so pushing the tail up is what drops the nose.
func _gimbal(delta: float) -> void:
	var swing := 0.0
	for st in stages:
		if st.lit and st.fuel > 0.0:
			swing = maxf(swing, st.gimbal)
	var step := gimbal_rate * delta
	swing_pitch = move_toward(swing_pitch, swing * pitch_input, step)
	swing_yaw = move_toward(swing_yaw, swing * yaw_input, step)
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(-swing_pitch))
	tilt = tilt * Basis(Vector3.UP, deg_to_rad(swing_yaw))
	for st in stages:
		if st.lit:
			st.aim(tilt)
	var dir := global_basis * tilt * Vector3.FORWARD
	apply_force(dir * push, global_basis * (Vector3.BACK * _tail()))


## Where the engines push from. Behind the centre of mass, which is what makes a gimbal a
## steering device rather than a nudge — and HOW FAR behind is the whole of that authority.
##
## The first version took the stage's own node and added two metres by hand. The nozzles of
## the side blocks sit seven metres further back than that, so the lever came out at six
## metres instead of eleven and a half: the gimbal had half the moment the geometry gives it,
## lost to the airframe at max q every time, and the rocket flipped on the gravity turn. Ask
## the scene where the engines are.
func _tail() -> float:
	var back := 0.0
	for st in stages:
		if st.lit and st.fuel > 0.0:
			back = maxf(back, st.nozzle())
	return back


## Drag along the airflow, hull lift across it at the centre of pressure. Copied in spirit
## from the forty-fourth probe and not shared with it: probes do not lend each other code.
func _air(v: Vector3, rho: float) -> void:
	var along := v / speed
	var cd := body_drag + 1.2 * sin(alpha) * sin(alpha)
	apply_central_force(-along * dynamic * frontal_area * cd)
	if alpha < 0.001:
		return
	var nose := -global_basis.z
	var side := nose - along * nose.dot(along)
	if side.length_squared() < 1e-9:
		return
	var sa := sin(alpha)
	var cn := body_lift * sa * cos(alpha) + crossflow * sa * sa
	# The offset is measured from the body's ORIGIN, and Godot subtracts the centre of mass
	# itself. Handing it `cop - centre_of_mass` subtracts the centre twice: the lever of the
	# one force that tries to turn the rocket over came out half as long again as the geometry
	# says, and the engines could not answer it. `margin` on the readout was right the whole
	# time — it is the same difference, taken for the eye and not for the physics.
	apply_force(side.normalized() * dynamic * frontal_area * cn,
		global_basis * _cop.position)


## Roll and swing damp at different rates, and not for aerodynamic reasons first: the
## moment of inertia about a long rocket's own axis is a hundred times smaller than across
## it, and one coefficient for both makes the explicit scheme spin up instead of settle.
func _damp(q: float) -> void:
	var w := angular_velocity
	if w.is_zero_approx() or q <= 0.0:
		return
	var calibre := 2.0 * sqrt(frontal_area / PI)
	var base := q * frontal_area * calibre * calibre / (2.0 * maxf(speed, 1.0))
	var axis := global_basis.z
	var roll := axis * w.dot(axis)
	apply_torque(-((w - roll) * damping + roll * roll_damping) * base)


## THE BAR THE WHOLE FLIGHT IS AIMED AT. Apoapsis and periapsis straight out of the two
## vectors, without integrating anything: energy gives the size of the ellipse, angular
## momentum gives its shape.
func orbit() -> Dictionary:
	if planet == null:
		return {"apo": 0.0, "peri": 0.0}
	var mu := planet.surface_gravity * planet.radius * planet.radius
	var r := global_position - planet.centre
	var v := linear_velocity
	var rl := maxf(r.length(), 1.0)
	var energy := v.length_squared() * 0.5 - mu / rl
	if absf(energy) < 1e-9:
		return {"apo": INF, "peri": 0.0}
	var a := -mu / (2.0 * energy)
	var h := r.cross(v).length()
	var e := sqrt(maxf(0.0, 1.0 + 2.0 * energy * h * h / (mu * mu)))
	return {"apo": a * (1.0 + e) - planet.radius, "peri": a * (1.0 - e) - planet.radius}


## The ground is a thing now, and hitting it ends the flight. A launcher probe in which the
## vehicle sinks through the planet cannot show what an unstable ascent costs.
func _on_body_entered(_b: Node) -> void:
	if flying:
		_shut_down()
		struck.emit(global_position, speed)


## Nothing is running, so nothing should still read as if it were: the last tick's thrust left
## on the readout describes a rocket that no longer exists.
func _shut_down() -> void:
	flying = false
	push = 0.0
	lift_ratio = 0.0
