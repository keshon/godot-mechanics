class_name SeekerHead
extends Node3D
## THE SEEKER.
##
## Everything the missile knows about the world arrives here, and it is much less than one
## would think. The head sees a direction and how fast that direction is turning. Not range,
## not the target's speed, not its heading. Whether that is enough is the question.
##
## The head is a node because it points somewhere, and where it points is not where the
## missile points: it slews to follow the target and it can run out of both angle and rate.
## Both limits are what makes a lock something you can lose.
##
## And because it is a node, it TURNS. Keeping `sight` as a variable and never touching the
## node's basis leaves the one moving part of the probe existing only in the readout. Two
## lines fix that, and the ring the head carries makes the lag visible in its own window.

enum Law {
	## Point at the target and keep pointing at it.
	PURSUIT,
	## Turn as fast as the line of sight turns, times a constant.
	PROPORTIONAL,
}

## Gravity, m/s2. Demand is reported in g, so it is divided out here.
const GRAVITY := 9.81
## Below this range, in metres, the geometry is degenerate and there is nothing to steer by.
const MIN_RANGE := 1.0

## How far off the missile's nose the head can look at all. Past this the target is simply
## not visible, no matter how bright. Degrees.
@export_range(5.0, 90.0, 1.0) var cone := 45.0
## How fast the head can move, degrees per second. A target that crosses faster than this
## walks out from under the seeker even while it is still well inside the cone.
@export_range(5.0, 360.0, 5.0) var slew := 90.0
## N in proportional navigation, and the proportional constant in pursuit. Textbooks put N
## between 3 and 5; below 2 the missile arrives late, above 6 it wastes itself on noise.
@export_range(1.0, 8.0, 0.1) var gain := 4.0
@export var law := Law.PROPORTIONAL

var locked := false
## Where the head is actually pointing, world space.
var sight := Vector3.FORWARD
## Radians between nose and sight.
var off_bore := 0.0
## How fast the line of sight rotates, rad/s.
var turn_rate := 0.0
## Metres per second, positive while the gap shrinks.
var closing := 0.0
## The load the law is asking for, g.
var demand := 0.0

## Line-of-sight rotation as a vector.
var _spin := Vector3.ZERO


## Take a lock if the target is inside the cone. Called once, by hand or by the rail.
func acquire(nose: Vector3, to_target: Vector3) -> bool:
	if to_target.length_squared() < MIN_RANGE:
		return false
	var direction := to_target.normalized()
	locked = nose.angle_to(direction) <= deg_to_rad(cone)
	# Caged to the missile's nose when there is nothing to look at: a seeker that keeps
	# pointing at a target it never took is a lie told by the geometry.
	sight = direction if locked else nose
	_point()
	return locked


## One tick of tracking. Returns the lateral acceleration the law wants, in world space and
## in metres per second squared. Returns zero when there is nothing to steer by.
func track(
		nose: Vector3,
		here: Vector3,
		my_velocity: Vector3,
		there: Vector3,
		its_velocity: Vector3,
		delta: float) -> Vector3:
	if not locked:
		return Vector3.ZERO

	var to_target := there - here
	if to_target.length_squared() < MIN_RANGE:
		return Vector3.ZERO
	var truth := to_target.normalized()

	# The head follows the target, but only so fast. When the target crosses quicker than
	# the head can turn, the two directions part company and the lock is lost — not because
	# the target left the cone, but because the seeker could not keep up.
	var lag := sight.angle_to(truth)
	var step := minf(lag, deg_to_rad(slew) * delta)
	var was := sight
	sight = was.slerp(truth, 1.0 if lag < 0.0001 else step / lag)
	turn_rate = 0.0 if delta <= 0.0 else was.angle_to(sight) / delta
	_point()

	off_bore = nose.angle_to(sight)
	if off_bore > deg_to_rad(cone) or lag > deg_to_rad(cone):
		locked = false
		return Vector3.ZERO

	var relative := its_velocity - my_velocity
	closing = -truth.dot(relative)
	_spin = to_target.cross(relative) / to_target.length_squared()

	var want := (_pursue(my_velocity, truth) if law == Law.PURSUIT
			else _proportional(truth))
	demand = want.length() / GRAVITY
	return want


## POINT AT IT. The oldest law and the one everybody writes first: turn until the nose is on
## the target. Against anything that crosses, it spends the whole flight behind and pays for
## it at the end, when the line of sight swings fastest and there is no turn rate left.
func _pursue(my_velocity: Vector3, truth: Vector3) -> Vector3:
	var speed := my_velocity.length()
	if speed < MIN_RANGE:
		return Vector3.ZERO
	var along := my_velocity / speed
	var side := truth - along * truth.dot(along)
	if side.length_squared() < 1e-9:
		return Vector3.ZERO
	return side.normalized() * gain * speed * along.angle_to(truth)


## TURN AS FAST AS THE VIEW TURNS. If the target holds still in the window, the missile is
## already on a collision course and does nothing at all. The law never needs range, speed
## or heading of the target — only how fast the direction to it rotates.
##
## a = N * Vc * (w x u), and one case checks the sign in a minute: the missile runs along +X,
## the target sits at range R and leaves along +Y. Then w = (0, 0, Vt/R) and w x u is
## (0, Vt/R, 0) — the same way the target is going, which is where the lead belongs. The sign
## inverted turns guidance into escape, and it looks exactly like a broken lock.
func _proportional(truth: Vector3) -> Vector3:
	return _spin.cross(truth) * gain * closing


## Turn the node to where the head is looking. The parent's own up is the reference so the
## head does not roll on its own; when the sight runs along it, the parent's side does instead.
func _point() -> void:
	var host := get_parent() as Node3D
	if host == null:
		return
	var up := host.global_basis.y
	if absf(sight.dot(up)) > 0.99:
		up = host.global_basis.x
	look_at(global_position + sight, up)
