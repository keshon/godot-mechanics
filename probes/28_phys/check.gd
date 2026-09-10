class_name PhysCheck
extends RefCounted
## Three numbers a physics scene will not tell you by looking at it.
##
##   УВОД      how far the top of an untouched tower has wandered. The right answer is
##             exactly zero, so anything else is error, measured in metres.
##   ПРОВИС    how far a chain of joints hangs below its anchors. A solver gets a fixed
##             number of passes over the constraints, and the sag is what it gave up on.
##   ПОВТОР    run the same thing twice from the same state and compare. Rule 4 says
##             tests come back for the deterministic step; this finds out if there is
##             one.

enum Phase {
	IDLE,
	FIRST,
	SECOND,
}

## Physics ticks per replay. A variable, not a constant, because HOW LONG you run before
## comparing is itself the question: a divergence that starts at the last bit and grows
## to metres is chaos amplifying rounding, and one that is already large after a single
## step is something structural. Those are different diagnoses.
var run_ticks := 240

## How far the top of the tower has wandered, metres.
var drift := 0.0
## How far the bridge hangs below its anchors, metres.
var sag := 0.0
## Seconds the current scene has been standing.
var age := 0.0
var verdict := "не запускался"

var _start: Array[Transform3D] = []
var _first_run := PackedVector3Array()
var _phase := Phase.IDLE
var _tick := 0
var _wanted := false
var _full := true
var _rebuild := Callable()


func reset() -> void:
	_start.clear()
	_first_run = PackedVector3Array()
	_phase = Phase.IDLE
	_tick = 0
	_wanted = false
	drift = 0.0
	sag = 0.0
	age = 0.0
	verdict = "не запускался"


## `full` decides WHAT is being asked, and the two questions are not the same one.
##
##   false — put the bodies back and run again. Cheap, but positions and velocities are
##           not the whole state: contact caches, island assignments, sleep timers and
##           the warm-start impulses of the solver all survive, so run two starts with
##           the leftovers of run one. Divergence here may be the engine or the restore.
##   true  — throw everything away and build the scene again from the same seed. No
##           leftovers, and it is also the question a networked game actually asks: two
##           machines build the same world and must get the same result.
func start(full := true, rebuild := Callable()) -> void:
	_full = full
	_rebuild = rebuild
	_wanted = true
	verdict = "идёт первый прогон…"


func tick(boxes: Array[RigidBody3D]) -> void:
	if boxes.is_empty():
		return
	if _start.is_empty():
		for body in boxes:
			_start.append(body.global_transform)
	age += 1.0 / 60.0
	var top: RigidBody3D = boxes[boxes.size() - 1]
	var began := _start[_start.size() - 1].origin
	drift = Vector2(
			top.global_position.x - began.x,
			top.global_position.z - began.z).length()
	var lowest := 99.0
	for body in boxes:
		lowest = minf(lowest, body.global_position.y)
	sag = maxf(8.0 - lowest, 0.0)

	if _wanted:
		_wanted = false
		_phase = Phase.FIRST
		_tick = 0
		_replay(boxes)
		return
	if _phase == Phase.IDLE:
		return
	_tick += 1
	if _tick < run_ticks:
		return
	if _phase == Phase.FIRST:
		_first_run = _snapshot(boxes)
		_phase = Phase.SECOND
		_tick = 0
		verdict = "идёт второй прогон…"
		_replay(boxes)
		return
	var second := _snapshot(boxes)
	var worst := 0.0
	for i in second.size():
		worst = maxf(worst, _first_run[i].distance_to(second[i]))
	# 1e-6 m is a micrometre: below that the two runs are the same run.
	#
	# NOT "%.1e": GDScript string formatting has no scientific notation at all, and says
	# so only at runtime — "unsupported format character", with the raw %.1e left in the
	# text. The supported set is smaller than C and %e is not in it.
	if worst < 1e-6:
		verdict = "[color=#7fe08a]совпало, расхождение %.9f м[/color]" % worst
	else:
		verdict = "[color=#ff8a6a]разошлось на %.4f м[/color]" % worst
	_phase = Phase.IDLE


func _snapshot(boxes: Array[RigidBody3D]) -> PackedVector3Array:
	var found := PackedVector3Array()
	for body in boxes:
		found.append(body.global_position)
	return found


func _replay(boxes: Array[RigidBody3D]) -> void:
	if not (_full and _rebuild.is_valid()):
		_restore(boxes)
		return
	# The rebuild calls reset(), so everything this check is holding has to be carried
	# across it by hand.
	var start := _start.duplicate()
	var first_run := _first_run
	var phase := _phase
	var tick_count := _tick
	var full := _full
	var rebuild := _rebuild
	_rebuild.call()
	_start = start
	_first_run = first_run
	_phase = phase
	_tick = tick_count
	_full = full
	_rebuild = rebuild
	verdict = "идёт второй прогон…" if phase == Phase.SECOND else "идёт первый прогон…"


## Putting a body back is not assigning to `global_transform`: that fights the server,
## which owns the state of the body during the step. The server has to be told directly,
## and the velocities and the sleep flag have to go back too — a body restored to the
## right place while still carrying the velocity of yesterday is not the same start.
func _restore(boxes: Array[RigidBody3D]) -> void:
	for i in boxes.size():
		var body := boxes[i].get_rid()
		PhysicsServer3D.body_set_state(
				body, PhysicsServer3D.BODY_STATE_TRANSFORM, _start[i])
		PhysicsServer3D.body_set_state(
				body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
		PhysicsServer3D.body_set_state(
				body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
		PhysicsServer3D.body_set_state(
				body, PhysicsServer3D.BODY_STATE_SLEEPING, false)
