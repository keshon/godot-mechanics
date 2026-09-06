class_name PhysCheck
extends RefCounted

## Three numbers a physics scene will not tell you by looking at it.
##
##   УВОД      how far the top of an untouched tower has wandered. The right answer is
##             exactly zero, so anything else is error, measured in metres.
##   ПРОВИС    how far a chain of joints hangs below its anchors. A solver gets a fixed
##             number of passes over the constraints, and the sag is what it gave up on.
##   ПОВТОР    run the same thing twice from the same state and compare. Rule 4 says
##             tests come back for the deterministic step; this finds out if there is one.

## Physics ticks per replay. A variable, not a constant, because HOW LONG you run before
## comparing is itself the question: a divergence that starts at the last bit and grows to
## metres is chaos amplifying rounding, and one that is already large after a single step
## is something structural. Those are different diagnoses.
var run_ticks := 240

var drift := 0.0
var sag := 0.0
var age := 0.0
var verdict := "не запускался"

var _start: Array[Transform3D] = []
var _a := PackedVector3Array()
var _phase := 0       ## 0 idle, 1 first replay, 2 second replay
var _tick := 0
var _want := false
var _full := true
var _rebuild := Callable()


func reset() -> void:
	_start.clear()
	_a = PackedVector3Array()
	_phase = 0
	_tick = 0
	_want = false
	drift = 0.0
	sag = 0.0
	age = 0.0
	verdict = "не запускался"


## `full` decides WHAT is being asked, and the two questions are not the same one.
##
##   false — put the bodies back and run again. Cheap, but positions and velocities are
##           not the whole state: contact caches, island assignments, sleep timers and the
##           solver's warm-start impulses all survive, so run two starts with run one's
##           leftovers. Divergence here may be the engine or may be my restore.
##   true  — throw everything away and build the scene again from the same seed. No
##           leftovers, and it is also the question a networked game actually asks: two
##           machines build the same world and must get the same result.
func start(full: bool = true, rebuild: Callable = Callable()) -> void:
	_full = full
	_rebuild = rebuild
	_want = true
	verdict = "идёт первый прогон…"


func tick(boxes: Array[RigidBody3D]) -> void:
	if boxes.is_empty():
		return
	if _start.is_empty():
		for b in boxes:
			_start.append(b.global_transform)
	age += 1.0 / 60.0
	var top: RigidBody3D = boxes[boxes.size() - 1]
	drift = Vector2(top.global_position.x - _start[_start.size() - 1].origin.x,
		top.global_position.z - _start[_start.size() - 1].origin.z).length()
	var low := 99.0
	for b in boxes:
		low = minf(low, b.global_position.y)
	sag = maxf(8.0 - low, 0.0)

	if _want:
		_want = false
		_phase = 1
		_tick = 0
		_again(boxes)
		return
	if _phase == 0:
		return
	_tick += 1
	if _tick < run_ticks:
		return
	if _phase == 1:
		_a = _snapshot(boxes)
		_phase = 2
		_tick = 0
		verdict = "идёт второй прогон…"
		_again(boxes)
		return
	var b2 := _snapshot(boxes)
	var worst := 0.0
	for i in b2.size():
		worst = maxf(worst, _a[i].distance_to(b2[i]))
	# 1e-6 m is a micrometre: below that the two runs are the same run.
	#
	# NOT "%.1e": GDScript's string formatting has no scientific notation at all, and says
	# so only at runtime — "unsupported format character", with the raw %.1e left in the
	# text. The supported set is smaller than C's and %e is not in it.
	if worst < 1e-6:
		verdict = "[color=#7fe08a]совпало, расхождение %.9f м[/color]" % worst
	else:
		verdict = "[color=#ff8a6a]разошлось на %.4f м[/color]" % worst
	_phase = 0


func _snapshot(boxes: Array[RigidBody3D]) -> PackedVector3Array:
	var out := PackedVector3Array()
	for b in boxes:
		out.append(b.global_position)
	return out


func _again(boxes: Array[RigidBody3D]) -> void:
	if _full and _rebuild.is_valid():
		var keep := _start.duplicate()
		var a := _a
		var ph := _phase
		var tk := _tick
		var fl := _full
		var rb := _rebuild
		_rebuild.call()          # this calls reset(), so the state has to be carried over
		_start = keep
		_a = a
		_phase = ph
		_tick = tk
		_full = fl
		_rebuild = rb
		verdict = "идёт второй прогон…" if ph == 2 else "идёт первый прогон…"
		return
	_restore(boxes)


## Putting a body back is not assigning to `global_transform`: that fights the server,
## which owns the body's state during the step. The server has to be told directly, and
## the velocities and the sleep flag have to go back too — a body restored to the right
## place while still carrying yesterday's velocity is not the same starting state.
func _restore(boxes: Array[RigidBody3D]) -> void:
	for i in boxes.size():
		var rid := boxes[i].get_rid()
		PhysicsServer3D.body_set_state(rid,
			PhysicsServer3D.BODY_STATE_TRANSFORM, _start[i])
		PhysicsServer3D.body_set_state(rid,
			PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
		PhysicsServer3D.body_set_state(rid,
			PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
		PhysicsServer3D.body_set_state(rid,
			PhysicsServer3D.BODY_STATE_SLEEPING, false)
