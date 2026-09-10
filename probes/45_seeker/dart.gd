class_name SeekerDart
extends Node3D
## THE MISSILE, DELIBERATELY STUPID.
##
## A point that flies at a fixed speed and can bend its path by at most so many g. No fins,
## no drag, no fuel — all of that is the forty-fourth probe, and putting it here would mean
## measuring two things at once.
##
## The limit is the one property that had to survive. The whole argument for proportional
## navigation is that it asks for LESS turn; on an airframe with no ceiling both laws hit
## everything and there is nothing to find.

signal finished(miss: float, hit: bool, reason: String)

## Gravity, m/s2. Ceilings are quoted in g and turned into acceleration by this.
const GRAVITY := 9.81
## Beyond this gap, in metres, a range that stopped shrinking means the lock is wandering,
## not that the missile has gone past.
const PASS_GAP := 400.0

@export_range(100.0, 1500.0, 10.0) var speed := 600.0
## Ceiling on lateral acceleration, g. Everything interesting happens against this number.
@export_range(2.0, 80.0, 1.0) var limit := 25.0
## Seconds before the flight is called a timeout.
@export_range(1.0, 60.0, 0.5) var life := 20.0
## Kill radius, metres.
@export_range(1.0, 40.0, 0.5) var kill := 6.0

var flying := false
var clock := 0.0
## Share of the flight spent asking for more g than there is.
var saturated := 0.0
## The load actually pulled this tick, g.
var pulled := 0.0

var _velocity := Vector3.ZERO
var _target: SeekerPrey = null
var _closest := INF
## Where the target was, relative to the missile, at the end of the previous tick. The pass
## is measured on the segment between that sample and this one.
var _last_offset := Vector3.ZERO
var _ticks := 0
var _capped := 0

@onready var head: SeekerHead = $Head


func _physics_process(delta: float) -> void:
	if not flying or _target == null:
		return
	clock += delta
	_ticks += 1

	var want := head.track(
			-global_basis.z,
			global_position,
			_velocity,
			_target.global_position,
			_target.velocity,
			delta)

	# The ceiling. Note what is counted: not how hard it turned, but how often it wanted to
	# turn harder than it could. A law that spends the endgame saturated is a law that misses.
	var asked := want.length() / GRAVITY
	if asked > limit:
		want = want.normalized() * limit * GRAVITY
		_capped += 1
	pulled = want.length() / GRAVITY
	saturated = float(_capped) / float(maxi(_ticks, 1))

	# Speed is held on purpose: only the direction is allowed to change, so every difference
	# between the two laws is a difference in steering and never in energy.
	_velocity = (_velocity + want * delta).normalized() * speed
	global_position += _velocity * delta
	look_at(global_position + _velocity, Vector3.UP)
	_judge()


## Cut loose at the given target. Returns nothing: whether the lock took is reported through
## `finished`, because a shot that never acquired is a result and not an error.
func launch(from: Transform3D, prey: SeekerPrey) -> void:
	global_transform = from
	_velocity = -from.basis.z * speed
	_target = prey
	_closest = INF
	_last_offset = prey.global_position - from.origin
	clock = 0.0
	_ticks = 0
	_capped = 0
	saturated = 0.0
	pulled = 0.0
	flying = head.acquire(-from.basis.z, prey.global_position - from.origin)
	visible = true
	if not flying:
		finished.emit(INF, false, "не захватила на пуске")


## THE PASS IS MEASURED INSIDE THE TICK, not at its edge. The pair closes at up to eight
## hundred metres per second, so one physics step is thirteen metres across while the kill
## radius is six: a gap sampled once a tick steps straight over a hit and calls it a
## seven-metre miss. Relative motion within a step is a straight line, so the answer is the
## nearest point of the segment from the previous sample to this one — five lines, and they
## decide whether a row of the table says "в цель" or does not.
func _judge() -> void:
	var offset := _target.global_position - global_position
	var gap := offset.length()
	var step := offset - _last_offset
	var along := (0.0 if step.length_squared() < 1e-9
			else clampf(-_last_offset.dot(step) / step.length_squared(), 0.0, 1.0))
	var pass_gap := (_last_offset + step * along).length()
	_last_offset = offset
	_closest = minf(_closest, pass_gap)

	if pass_gap < kill:
		_stop(pass_gap, true, "попадание")
	elif gap > _closest and _closest < PASS_GAP:
		# Range stopped shrinking: the missile has gone past, and the smallest gap it ever
		# reached is the answer. Measured at the pass, not at the end of the flight.
		_stop(_closest, false, "промах")
	elif not head.locked:
		_stop(_closest, false, "срыв сопровождения")
	elif clock > life:
		_stop(_closest, false, "вышло время")


func _stop(gap: float, hit: bool, reason: String) -> void:
	flying = false
	visible = false
	finished.emit(gap, hit, reason)
