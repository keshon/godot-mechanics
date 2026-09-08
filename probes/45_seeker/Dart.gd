extends Node3D
class_name SeekerDart

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

@export_range(100.0, 1500.0, 10.0) var speed := 600.0
## Ceiling on lateral acceleration. Everything interesting happens against this number.
@export_range(2.0, 80.0, 1.0) var limit := 25.0
@export_range(1.0, 60.0, 0.5) var life := 20.0
@export_range(1.0, 40.0, 0.5) var kill := 6.0

var flying := false
var clock := 0.0
var saturated := 0.0        ## share of the flight spent asking for more g than there is
var pulled := 0.0           ## g actually pulled this tick

var _v := Vector3.ZERO
var _target: SeekerPrey = null
var _closest := INF
## Where the target was, relative to the missile, at the end of the previous tick. The pass
## is measured on the segment between that sample and this one.
var _was_rel := Vector3.ZERO
var _ticks := 0
var _capped := 0

@onready var head: SeekerHead = $Head


func launch(from: Transform3D, prey: SeekerPrey) -> void:
	global_transform = from
	_v = -from.basis.z * speed
	_target = prey
	_closest = INF
	_was_rel = prey.global_position - from.origin
	clock = 0.0
	_ticks = 0
	_capped = 0
	saturated = 0.0
	pulled = 0.0
	flying = head.acquire(-from.basis.z, prey.global_position - from.origin)
	visible = true
	if not flying:
		finished.emit(INF, false, "не захватила на пуске")


func _physics_process(delta: float) -> void:
	if not flying or _target == null:
		return
	clock += delta
	_ticks += 1

	var want := head.track(-global_basis.z, global_position, _v,
		_target.global_position, _target.velocity, delta)

	# The ceiling. Note what is counted: not how hard it turned, but how often it wanted to
	# turn harder than it could. A law that spends the endgame saturated is a law that misses.
	var asked := want.length() / 9.81
	if asked > limit:
		want = want.normalized() * limit * 9.81
		_capped += 1
	pulled = want.length() / 9.81
	saturated = float(_capped) / float(maxi(_ticks, 1))

	# Speed is held on purpose: only the direction is allowed to change, so every difference
	# between the two laws is a difference in steering and never in energy.
	_v = (_v + want * delta).normalized() * speed
	global_position += _v * delta
	look_at(global_position + _v, Vector3.UP)

	# THE PASS IS MEASURED INSIDE THE TICK, not at its edge. The pair closes at up to eight
	# hundred metres per second, so one physics step is thirteen metres across while the kill
	# radius is six: a gap sampled once a tick steps straight over a hit and calls it a
	# seven-metre miss. Relative motion within a step is a straight line, so the answer is the
	# nearest point of the segment from the previous sample to this one — five lines, and they
	# decide whether a row of the table says "в цель" or does not.
	var rel := _target.global_position - global_position
	var gap := rel.length()
	var seg := rel - _was_rel
	var t := 0.0 if seg.length_squared() < 1e-9 else clampf(
		-_was_rel.dot(seg) / seg.length_squared(), 0.0, 1.0)
	var pass_gap := (_was_rel + seg * t).length()
	_was_rel = rel
	_closest = minf(_closest, pass_gap)

	if pass_gap < kill:
		_stop(pass_gap, true, "попадание")
	elif gap > _closest and _closest < 400.0:
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
