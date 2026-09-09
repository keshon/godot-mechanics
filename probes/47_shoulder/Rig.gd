extends Node3D
class_name ShoulderRig

## HANDS, EYE AND KNOBS.
##
## You are the shooter, and that is the whole difference from the two probes before this one.
## The forty-fourth had nobody holding the missile; the forty-fifth put the hand on the target
## and let the seeker do its own work. Here the hand IS the guidance, and what it costs is the
## measured quantity.
##
## `G` fires four rounds at four ranges with the sight held perfectly by the rig, once for each
## kind of round. Two tables side by side are what the probe is for: one says how far a thrown
## thing drifts, the other says what a steady hand buys.

## TWO ROUNDS, TWO ENVELOPES, AND THEY BARELY OVERLAP. This is a finding and not a setting. A
## thrown round is a three-hundred-metre weapon because that is how far it stays flat enough to
## aim; a ridden one is not worth its wire until past the range where the thrown one has already
## stopped working. Measuring both over one set of ranges hid that behind a column of misses.
const THROWN := [80.0, 160.0, 240.0, 320.0]
const RIDDEN := [300.0, 600.0, 900.0, 1200.0]
## How steady the machine's hand is during a measured shot, degrees of wobble. Zero would be a
## hand nobody has; this is roughly a trained one on a rest.
const STEADY := 0.25

@export_range(0.05, 1.0, 0.01) var look_speed := 0.22
@export_range(1.0, 9.0, 0.1) var walk := 3.4
## How wide the sight is. A narrow sight is easier to hold on the target and harder to find it
## with, and that trade is the one thing the shooter actually chooses.
@export_range(8.0, 70.0, 1.0) var zoom_fov := 18.0
@export_range(40.0, 100.0, 1.0) var open_fov := 70.0

var _kind := ShoulderRound.Kind.BEAM
var _yaw := 0.0
var _pitch := 0.0
var _zoom := false
## Watching from the side, which is the only way to JUDGE a shot. From the shoulder the round
## leaves as a dot over the ground and every flight looks the same; the difference between a
## thrown thing and a beam rider is a SHAPE, and a shape needs to be seen from off to one side.
var _side := false
## Where the round has been. Kept after the shot, so the last path can be compared with the
## line that was being held while it flew.
var _path := PackedVector3Array()
var _shot: ShoulderRound = null
var _last := ""
var _table: Array = []

## Measurement state, -1 when nobody is measuring.
var _row := -1
var _settle := 0.0
var _hold := 0.0        ## seconds the sight was on the target during the shot
var _flight := 0.0

@onready var _eye: Camera3D = $Body/Eye
@onready var _off: Camera3D = $Side
@onready var _trace: MeshInstance3D = $Trace
@onready var _body: CharacterBody3D = $Body
@onready var _tube: ShoulderLauncher = $Body/Eye/Tube
@onready var _mark: ShoulderTarget = $Target
@onready var _hud: RichTextLabel = $Ui/Info
@onready var _shots: Node3D = $Shots

## Where the shooter stands and what height the target sits at. The shooter is on a RISE, so
## neither of these is the origin any more and neither can be reset to it.
var _stand := Vector3.ZERO
var _floor := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_stand = _body.position
	_floor = _mark.position.y
	_tube.refused.connect(func(why: String) -> void: _last = why)
	_set_range(_ranges()[1])


func _unhandled_input(event: InputEvent) -> void:
	var move := event as InputEventMouseMotion
	if move != null:
		_yaw -= move.relative.x * look_speed * 0.01
		_pitch = clampf(_pitch - move.relative.y * look_speed * 0.01, -0.6, 0.9)
		return
	var button := event as InputEventMouseButton
	if button != null and button.pressed:
		if button.button_index == MOUSE_BUTTON_LEFT and _row < 0:
			_pull()
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			_zoom = not _zoom
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			var r: PackedScene = _tube.round_scene
			if r != null:
				_kind_flip()
		KEY_2: _mark.speed = 0.0 if _mark.speed > 0.0 else 11.0
		KEY_3: _side = not _side
		KEY_4:
			var marks := _ranges()
			var i: int = marks.find(_tube.sight_range)
			_set_range(marks[(i + 1) % marks.size()])
		KEY_G:
			_table.clear()
			_row = 0
			_start_row()
		KEY_TAB: _reset()
		KEY_ESCAPE:
			Input.mouse_mode = (Input.MOUSE_MODE_VISIBLE
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED)


func _ranges() -> Array:
	return THROWN if _kind == ShoulderRound.Kind.DUMB else RIDDEN


## The round kind lives on the ROUND, not on the tube, so switching it means switching what
## comes out — and the tube neither knows nor cares which one it just handed over. What the tube
## DOES have to be told is the range, because a sight is cut for one round and one speed.
func _kind_flip() -> void:
	_kind = (ShoulderRound.Kind.DUMB if _kind == ShoulderRound.Kind.BEAM
		else ShoulderRound.Kind.BEAM)
	_table.clear()
	_set_range(_ranges()[1])


## The dial moves the SIGHT AND THE TARGET together. Dialling a range with nothing standing at it
## measures nothing, and the two kinds are only comparable when each is asked for the distance it
## was built for.
func _set_range(d: float) -> void:
	_tube.sight_range = d
	_mark.place(Vector3(0.0, _floor, _stand.z - d))
	if _tube.round_scene == null:
		return
	# CUT AGAINST THE ROUND ITSELF, with a throwaway copy rather than a table of its numbers: a
	# sight has to be asking the thing it will actually fire.
	var sample := _tube.round_scene.instantiate() as ShoulderRound
	sample.kind = _kind
	_tube.cut(sample, _mark.centre().y - _tube.muzzle().origin.y)
	sample.free()


func _pull() -> void:
	var shot := _tube.fire()
	if shot == null:
		return
	shot.kind = _kind
	_shots.add_child(shot)
	shot.launch(_tube.muzzle(), _mark)
	shot.finished.connect(_on_finished)
	_shot = shot
	_flight = 0.0
	_hold = 0.0
	_path = PackedVector3Array([_tube.muzzle().origin])


func _physics_process(delta: float) -> void:
	if _row >= 0:
		_aim_for_measurement(delta)
	else:
		_walk(delta)
		_look()
	_feed(delta)
	if _row >= 0 and _shot == null:
		_settle -= delta
		if _settle <= 0.0:
			_row += 1
			if _row < _ranges().size():
				_start_row()
			else:
				_row = -1
				_reset()


func _look() -> void:
	_body.rotation.y = _yaw
	_eye.rotation.x = _pitch
	_eye.fov = lerpf(_eye.fov, zoom_fov if _zoom else open_fov, 0.25)
	_eye.current = not _side
	_off.current = _side


## The side view stands off the line between shooter and target, high enough to put the whole
## flight against the ground. The sight is still the EYE, so the round is still being guided by
## the hand while this camera watches it — flying and judging want different places to stand.
func _watch() -> void:
	var from := _body.global_position
	var mid := (from + _mark.global_position) * 0.5
	var flat := _mark.global_position - from
	flat.y = 0.0
	var span := maxf(flat.length(), 40.0)
	var side := Vector3(-flat.z, 0.0, flat.x).normalized() if flat.length() > 1.0 		else Vector3.RIGHT
	# A vertical fov of 55 spans roughly 43 degrees each way on a wide viewport, so 0.78 of the
	# baseline holds both ends with room for the round to overshoot the far one.
	_off.global_position = mid + side * span * 0.78 + Vector3.UP * span * 0.14
	# Aimed at the middle of the baseline and not at the round: the whole flight has to stay in
	# frame, and a camera that follows the round swings the ground out from under it.
	_off.look_at(mid, Vector3.UP)


func _walk(delta: float) -> void:
	var f := Input.get_action_strength(&"move_back") - Input.get_action_strength(&"move_forward")
	var s := Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left")
	var step := (_body.global_basis.z * f + _body.global_basis.x * s)
	var flat := step.normalized() * walk if step.length() > 0.01 else Vector3.ZERO
	# Gravity, which the flat range never needed: the shooter now stands on something with
	# an edge, and walking off it has to cost something.
	var fall := 0.0 if _body.is_on_floor() else _body.velocity.y - 9.81 * delta
	_body.velocity = Vector3(flat.x, fall, flat.z)
	_body.move_and_slide()


## THE SIGHT IS FED TO THE ROUND EVERY TICK, and that is the mechanic. A beam rider has no
## memory of where the sight was at launch; it goes wherever the line is NOW. Look away and
## the round follows the look.
func _feed(delta: float) -> void:
	# The TUBE is held above the line of sight; the BEAM stays on the sight, so a round leaves
	# high and settles down onto the line, and that settling is what the side view was added to
	# show. How high depends on WHICH round: a thrown one needs the whole ballistic elevation the
	# scale gives, a ridden one only the token degree a real launcher uses — asked to gather five
	# degrees it spends its first three hundred metres doing nothing else.
	_point()
	if _shot == null:
		return
	_flight += delta
	_shot.beam_from = _tube.muzzle().origin
	_shot.beam_dir = -_eye.global_basis.z
	if _path.is_empty() or _path[-1].distance_to(_shot.global_position) > 1.5:
		_path.append(_shot.global_position)
	# How much of the flight the sight actually spent on the target. This is the price of
	# guidance, expressed in the only currency the shooter has.
	var to_mark := _mark.centre() - _eye.global_position
	if to_mark.length_squared() > 1.0 and (-_eye.global_basis.z).angle_to(
			to_mark.normalized()) < deg_to_rad(1.5):
		_hold += delta


## ONE ROW. The machine holds the sight on the target with a small tremor, so the two kinds
## are compared with the same hand. What differs is only the round.
## HOW HIGH THE TUBE IS HELD, and the one place that decides it, because the readout has to say
## what the hand is actually doing. The whole cut scale for a thrown round; for a ridden one the
## token degree a real launcher leaves on — asked to gather five degrees it would spend its first
## three hundred metres doing nothing else.
## POINT THE TUBE, its own step because it has to happen after the eye has moved and before the
## trigger, and those are not always the same moment.
##
## The tube is a CHILD of the eye, so `look_at` pins its LOCAL basis: turn the eye afterwards and
## the tube comes along still carrying the old elevation. In the measured run that mattered — the
## `physics_frame` signal fires BEFORE `_physics_process`, so an `await` on it resumes a tick
## early: the eye had been swung onto the new range and the tube was still holding the previous
## row's elevation. Two metres low at three hundred metres, which the ground turned into nine
## metres short. Same family as the rig-before-children ordering in the forty-fourth.
func _point() -> void:
	_tube.aim((-_eye.global_basis.z).rotated(_eye.global_basis.x, _lift()), Vector3.UP)


func _lift() -> float:
	return _tube.lift if _kind == ShoulderRound.Kind.DUMB else deg_to_rad(1.0)


func _aim_for_measurement(delta: float) -> void:
	var to_mark := _mark.centre() - _eye.global_position
	if to_mark.length_squared() < 1.0:
		return
	var want := to_mark.normalized()
	var wobble := sin(_flight * 7.0) * deg_to_rad(STEADY)
	want = want.rotated(Vector3.UP, wobble)
	_yaw = atan2(-want.x, -want.z)
	_pitch = asin(clampf(want.y, -1.0, 1.0))
	_look()


func _start_row() -> void:
	_set_range(_ranges()[_row])
	_body.position = _stand
	_tube.reset()
	_settle = 0.8
	_flight = 0.0
	_hold = 0.0
	await get_tree().physics_frame
	_aim_for_measurement(0.0)
	_point()
	_pull()


func _on_finished(miss: float, hit: bool, reason: String) -> void:
	_last = "в цель" if hit else "%s, %.1f м" % [reason, miss]
	if hit:
		_mark.wreck()
	if _row >= 0:
		_table.append({
			"range": _ranges()[_row],
			"miss": miss,
			"hit": hit,
			"reason": reason,
			"time": _flight,
			"hold": _hold / maxf(_flight, 0.001),
		})
		_settle = 0.7
	if _shot != null:
		_shot.queue_free()
	_shot = null


func _reset() -> void:
	_row = -1
	for c in _shots.get_children():
		c.queue_free()
	_shot = null
	_mark.reset()
	_tube.reset()
	_body.position = _stand
	_flight = 0.0
	_hold = 0.0


func _process(_delta: float) -> void:
	_watch()
	_draw()
	_readout()


## THE PATH AND THE LINE IN ONE PICTURE. The round's track is drawn where it went, the sight
## line where it is being held, and the whole mechanic is the distance between them: a beam
## rider closes it, a thrown round never had one to close.
func _draw() -> void:
	var mesh := _trace.mesh as ImmediateMesh
	if mesh == null:
		return
	mesh.clear_surfaces()
	if _path.size() > 1:
		mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for point in _path:
			mesh.surface_set_color(Color(1.0, 0.62, 0.24, 0.95))
			mesh.surface_add_vertex(point)
		mesh.surface_end()
	if not _side:
		return
	var from := _tube.muzzle().origin
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_set_color(Color(0.45, 0.85, 1.0, 0.5))
	mesh.surface_add_vertex(from)
	mesh.surface_set_color(Color(0.45, 0.85, 1.0, 0.0))
	mesh.surface_add_vertex(from - _eye.global_basis.z * _tube.sight_range * 1.2)
	mesh.surface_end()
	# WHERE THE TARGET IS, drawn rather than looked for. From half a kilometre off to one side a
	# two-metre box is four pixels, and a trace is only readable next to something that says
	# where it was supposed to end.
	var at := _mark.centre()
	var tint := Color(1.0, 0.3, 0.25, 0.9) if _mark.hit else Color(0.5, 1.0, 0.6, 0.75)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for axis in [Vector3.UP, Vector3.RIGHT, Vector3.BACK]:
		mesh.surface_set_color(tint)
		mesh.surface_add_vertex(at - axis * 9.0)
		mesh.surface_set_color(tint)
		mesh.surface_add_vertex(at + axis * 9.0)
	mesh.surface_end()


func _live(fmt: String, value: float) -> String:
	return (fmt % value) if _shot != null else "—"


func _readout() -> void:
	var kind := "по лучу" if _kind == ShoulderRound.Kind.BEAM else "неуправляемая"
	var to_mark := _mark.centre().distance_to(_eye.global_position)
	var lines := PackedStringArray([
		"[b]ПУСК С ПЛЕЧА[/b]   ракета: [b]%s[/b]   в трубе %d   %s" % [
			kind, _tube.left,
			"[color=#ff8866]%s[/color]" % _tube.last if _tube.last != "" else
			("[color=#ffcc66]перезарядка %.1f с[/color]" % _tube.ready_in
				if _tube.ready_in > 0.0 else "готова")],
		"до цели [b]%.0f[/b] м   прицел набран на [b]%.0f[/b] м (+%.1f°)   цель идёт %.0f м/с" % [
			to_mark, _tube.sight_range, rad_to_deg(_lift()),
			_mark.velocity.length()],
		"полёт %s   от луча %s   тянет %s   прицел на цели %s" % [
			_live("%.1f с", _flight), _live("%.1f м", _shot.off_beam if _shot else 0.0),
			_live("%.1f g", _shot.pulled if _shot else 0.0),
			_live("%.0f%%", 100.0 * _hold / maxf(_flight, 0.001))],
		"последний пуск: %s" % (_last if _last != "" else "—"),
		"",
		"[b]ЛКМ пуск[/b]   ПКМ прицел   WASD ходить   ESC отпустить мышь",
		"1 ракета: %s" % kind,
		"2 цель: %s" % ("идёт" if _mark.speed > 0.0 else "стоит"),
		"3 взгляд: %s" % ("со стороны — видно траекторию и луч" if _side else "с плеча"),
		"4 дальность (двигает и прицел, и цель): %.0f м" % _tube.sight_range,
		"G прогнать четыре пуска: %s м" % " / ".join(PackedStringArray(
			_ranges().map(func(d: float) -> String: return "%.0f" % d))),
		"[color=#9fb4c8]за спиной у трубы струя: у стены выстрел не пройдёт[/color]",
	])
	if _row >= 0:
		lines.append("")
		lines.append("[color=#66ccff]замер: %.0f м[/color]" % _ranges()[_row])
	if not _table.is_empty():
		lines.append("")
		lines.append("[b]%s, цель %s[/b]" % [kind, "идёт" if _mark.speed > 0.0 else "стоит"])
		lines.append("[table=4][cell]дальность[/cell][cell]подлёт[/cell]"
			+ "[cell]промах[/cell][cell]прицел держал[/cell]")
		for r in _table:
			lines.append("[cell]%.0f м[/cell][cell]%.1f с[/cell][cell]%s[/cell][cell]%.0f%%[/cell]"
				% [r["range"], r["time"],
					"[color=#7fe08a]в цель[/color]" if r["hit"]
						else ("%.1f м" % r["miss"] if r["miss"] < 900.0 else r["reason"]),
					r["hold"] * 100.0])
		lines.append("[/table]")
	_hud.text = "\n".join(lines)
