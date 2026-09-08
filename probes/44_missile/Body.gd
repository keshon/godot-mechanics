extends RigidBody3D
class_name MissileBody

## THE AIRFRAME.
##
## Four things and no fifth: thrust that ends, drag that never does, fins that are the only
## authority over where the nose points, and a limiter that decides how much of that
## authority the missile is allowed to spend.
##
## Nothing here steers. The body takes `pitch_input` / `yaw_input` / `roll_input` from
## outside and obeys them; who writes those is not its business. A seeker will write them
## in the next probe, and a hand writes them in this one.
##
## Stability is NOT implemented, it is arranged. The hull's own lift is applied at the
## `Cop` node, which sits AHEAD of the centre of mass and therefore tries to tumble the
## missile; the fins sit behind it and win. Static margin is the distance between two nodes
## in the scene, so dragging either one in the editor changes the airframe's character and
## no code knows about it.

signal spent            ## propellant ran out
signal struck(where: Vector3, speed: float)

## Godot's own damping is switched OFF, and it has to be said out loud because the default is
## not zero: `linear_damp` and `angular_damp` on a `RigidBody3D` fall back to the project
## default of 0.1 per second. That is a second, invisible drag proportional to SPEED, and at
## six hundred metres per second it removes sixty metres per second squared — six g the model
## never asked for, on top of every coefficient written above. Replace mode with zero is what
## makes the numbers in this file the whole story.

## Standard sea-level air. Constant on purpose: this probe flies low, and altitude would
## be a fifth quantity for a 25% effect.
const DENSITY := 1.225

@export_group("Thrust")
## Short, violent, and over before you can aim: that is what a booster is.
@export_range(0.0, 40000.0, 100.0) var boost_thrust := 9000.0
@export_range(0.0, 10.0, 0.1) var boost_time := 1.6
## The sustainer only fights drag. Whether it exists at all is the difference between a
## missile with a long reach and one with a hard punch up close.
@export_range(0.0, 8000.0, 50.0) var sustain_thrust := 1400.0
@export_range(0.0, 30.0, 0.5) var sustain_time := 7.0

@export_group("Mass")
@export_range(1.0, 500.0, 0.5) var dry_mass := 44.0
@export_range(0.0, 500.0, 0.5) var propellant_mass := 26.0

@export_group("Air")
## Frontal area. A 200 mm missile is 0.031 m2, and that number decides the whole range.
@export_range(0.001, 0.5, 0.001) var frontal_area := 0.031
@export_range(0.05, 1.5, 0.01) var body_drag := 0.30
## Drag that only exists while turning. This is what makes a manoeuvre cost range.
@export_range(0.0, 6.0, 0.1) var induced_drag := 1.4
## Normal force the bare hull makes per radian, on frontal area. Near 2 for a slender body.
@export_range(0.0, 8.0, 0.1) var body_lift := 2.0
## Crossflow: a cylinder held sideways is a very good air brake and a very good wing. Scales
## with how long the missile is compared to how fat, and at large angles it dominates.
@export_range(0.0, 30.0, 0.5) var crossflow := 13.0
## Aerodynamic damping in pitch and yaw. The shape matters more than the number: it scales
## with the square of the body's diameter and DIVIDES by speed, because damping comes from
## the extra angle the tail meets while the missile is already rotating, and that angle
## shrinks as the missile flies faster. Written without those two factors it is off by two
## orders of magnitude and quietly holds the airframe still.
@export_range(0.0, 800.0, 5.0) var damping := 300.0
## Roll damping is a SEPARATE number, and not because aerodynamics says so first — because
## arithmetic does. The missile's inertia about its own long axis is about 0.2 kg*m2 against
## 29 across it, a factor of 130. One coefficient for both axes makes the roll term remove
## more spin than there is in a single tick, flip its sign, and grow: the airframe spins up
## instead of settling down. Aerodynamics happens to agree — C_lp is not C_mq.
@export_range(0.0, 200.0, 1.0) var roll_damping := 20.0

@export_group("Limiter")
## The autopilot refuses to pull harder than this, exactly as a real one does — the
## airframe would come apart. Turn it off with the toggle and watch the turn radius change
## character: that comparison is the point of the probe.
@export var limiter := true
@export_range(2.0, 80.0, 1.0) var structural_g := 25.0

## Written from outside, -1 to 1, and stated in terms of the NOSE, not the fins: +1 pitch is
## nose up, +1 yaw is nose right, +1 roll drops the right wing. A tail-controlled missile
## moves its tail the opposite way to do any of that, and getting the two frames confused is
## how a control ends up mirrored — which is exactly what happened to yaw here.
var pitch_input := 0.0
var yaw_input := 0.0
var roll_input := 0.0

var flying := false
var burn := 0.0             ## seconds since launch
var fuel := 1.0             ## 1 down to 0
var speed := 0.0
var alpha := 0.0            ## angle between nose and travel, radians
## Measured from how fast the VELOCITY turns, not from the forces put in. A tail-controlled
## missile pushes its tail the wrong way to make the nose go the right way, so adding up fin
## forces answers a different question than "is it turning".
var lateral_g := 0.0
var throttled := 0.0        ## how much the limiter took away, 0 to 1

var _fins: Array[MissileFin] = []
var _burn_rate := 0.0
var _was := Vector3.ZERO

## Where the hull's own lift acts. A node, so the static margin is visible and draggable.
@onready var _cop: Node3D = $Cop


func _ready() -> void:
	for c in get_children():
		var f := c as MissileFin
		if f != null:
			_fins.append(f)
	# Propellant is spent in proportion to thrust, so the boost eats most of it fast.
	var total := boost_thrust * boost_time + sustain_thrust * sustain_time
	_burn_rate = 1.0 / maxf(total, 0.001)
	mass = dry_mass + propellant_mass
	freeze = true


## Cut loose. Until this is called the missile hangs on the rail and costs nothing.
func launch(from: Transform3D, carry: Vector3) -> void:
	global_transform = from
	freeze = false
	linear_velocity = carry
	angular_velocity = Vector3.ZERO
	burn = 0.0
	fuel = 1.0
	flying = true
	# Otherwise the very first tick compares the new heading against the previous flight
	# and reads hundreds of g.
	_was = Vector3.ZERO
	lateral_g = 0.0


func _physics_process(delta: float) -> void:
	if not flying:
		return
	burn += delta
	mass = dry_mass + propellant_mass * fuel

	var v := linear_velocity
	speed = v.length()
	var nose := -global_basis.z
	alpha = 0.0 if speed < 1.0 else acos(clampf(nose.dot(v / speed), -1.0, 1.0))

	var push := _thrust()
	if push > 0.0:
		var used := push * delta * _burn_rate
		if fuel > 0.0 and fuel - used <= 0.0:
			spent.emit()
		fuel = maxf(0.0, fuel - used)
		apply_central_force(nose * push)

	var q := 0.5 * DENSITY * speed * speed
	if speed > 1.0:
		var cd := body_drag + induced_drag * sin(alpha) * sin(alpha)
		apply_central_force(-(v / speed) * q * frontal_area * cd)
		_apply_hull(v, q, nose)

	_steer()
	_apply_fins(v, q)
	_measure_turn(v, delta)


## THE HULL IS A WING, and a bad one that pulls in the wrong place. Its force is
## perpendicular to the airflow, in the plane the angle of attack lies in, and it is applied
## at `Cop` — ahead of the centre of mass, so on its own it makes the missile swap ends.
func _apply_hull(v: Vector3, q: float, nose: Vector3) -> void:
	if alpha < 0.001:
		return
	var along := v / speed
	# Perpendicular to travel, on the side the nose is pointing: that is where lift goes.
	var side := (nose - along * nose.dot(along))
	if side.length_squared() < 1e-9:
		return
	side = side.normalized()
	var sa := sin(alpha)
	var cn := body_lift * sa * cos(alpha) + crossflow * sa * sa
	apply_force(side * q * frontal_area * cn, _cop.global_position - global_position)


## Boost, then sustain, then nothing. Running dry is not a failure state — most of a
## missile's flight happens after the motor is done, and that is where range is decided.
func _thrust() -> float:
	if fuel <= 0.0:
		return 0.0
	if burn < boost_time:
		return boost_thrust
	if burn < boost_time + sustain_time:
		return sustain_thrust
	return 0.0


## Turn the command into fin angles. Pitch and yaw come from projecting the wanted TAIL
## force onto each fin's own lift axis, which is why a fin rolled 90 degrees quietly becomes
## a yaw control without a single branch. Roll is a uniform bias on top: every fin the same
## way makes a couple about the body axis.
##
## That last sentence only holds if the four mounts go round the body THE SAME WAY, and for a
## long time two of them did not: the top and bottom fins were rolled -90 and +90 instead of
## +90 and +270, so their lift axes pointed against the other two. Pitch and yaw did not care
## — a mirrored mount comes with a mirrored command and the force lands the same — but the
## roll couple cancelled to exactly zero. The ailerons moved and nothing rolled, and nothing
## said so until the blades themselves started turning on screen.
##
## Both signs are negated because the tail goes where the nose does not: to raise the nose
## the tail must go down, to swing the nose right the tail must go left.
func _steer() -> void:
	var want := Vector3(-yaw_input, -pitch_input, 0.0)
	for f in _fins:
		var d := want.dot(f.axis()) - roll_input * 0.5
		f.deflect = clampf(d, -1.0, 1.0) * f.max_deflect


## Fin forces are applied AT the fins. Everything the airframe does — turning, damping,
## weathercocking, rolling — is a consequence of where those four points are.
func _apply_fins(v: Vector3, q: float) -> void:
	var arm := Vector3.ZERO
	var lift := Vector3.ZERO
	var at: Array[Vector3] = []
	var force: Array[Vector3] = []
	for f in _fins:
		var w := f.force(-v, q)
		at.append(f.global_position - global_position)
		force.append(w)
		lift += w

	# The limiter scales the whole set, not each fin, so the missile keeps flying straight
	# while it refuses to turn harder. Scaling fins one by one would make it roll instead.
	# The autopilot clips its OWN command and not the measured load: it knows only the force
	# it put on the fins. That is exactly why a real limiter always errs on the safe side.
	var asked := lift.length() / maxf(mass, 0.001) / 9.81
	var scale := 1.0
	if limiter and asked > structural_g:
		scale = structural_g / asked
	throttled = 1.0 - scale

	for i in at.size():
		apply_force(force[i] * scale, at[i])
	_damp(q)


## Air resists rotation, and it resists it differently about each axis. Splitting the spin
## into roll and swing before damping it is the whole fix.
func _damp(q: float) -> void:
	var w := angular_velocity
	if w.is_zero_approx():
		return
	var calibre := 2.0 * sqrt(frontal_area / PI)
	var base := q * frontal_area * calibre * calibre / (2.0 * maxf(speed, 1.0))
	var axis := global_basis.z
	var roll := axis * w.dot(axis)
	apply_torque(-((w - roll) * damping + roll * roll_damping) * base)


## True lateral acceleration: turn rate times speed. Nothing in the model gets a vote.
func _measure_turn(v: Vector3, delta: float) -> void:
	if speed > 1.0 and _was.length_squared() > 0.0:
		lateral_g = _was.angle_to(v / speed) / delta * speed / 9.81
	_was = Vector3.ZERO if speed < 1.0 else v / speed


func _on_body_entered(_b: Node) -> void:
	if flying:
		flying = false
		struck.emit(global_position, speed)
