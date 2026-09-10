class_name SeekerRig
extends Node3D
## HANDS, CAMERA AND KNOBS.
##
## You fly the TARGET. The forty-fourth probe settled that a missile is not a thing a hand
## can usefully pilot; a seeker, on the other hand, is judged exactly the way it is judged
## in life — by trying to get away from it.
##
## `G` runs the same four launches against a target jinking at 0, 3, 6 and 9 g and fills the
## table. Switch the law on `1` and run it again: two tables side by side are the probe.

## Field of view of the seeker inset. Narrow in flight, because the whole point of that
## window is how far off the boresight the target sits.
const EYE_FOV := 22.0
## Wide on the rail, where there is no seeker yet and a twenty-two degree crop of empty sky
## at three kilometres is a white box.
const EYE_REST_FOV := 45.0

const GAINS := [2.0, 3.0, 4.0, 5.0]
const LIMITS := [10.0, 15.0, 25.0, 40.0]
const TEST_G := [0.0, 3.0, 6.0, 9.0]
## Where the target is put back before each measured launch, metres.
const TEST_ALT := 900.0
## Seconds between measured rows: settle before the shot, and read the result after it.
const SETTLE_BEFORE := 0.4
const SETTLE_AFTER := 0.6
## How fast the camera offset catches up, per second.
const TRAIL_RATE := 3.0

@export_range(0.5, 10.0, 0.1) var stick_rate := 2.5
@export_range(0.5, 12.0, 0.1) var stick_return := 4.0
@export_range(10.0, 200.0, 1.0) var chase_back := 40.0

var _pitch := 0.0
var _yaw := 0.0
var _gain := 2
var _limit := 2
var _wide := false
var _last_shot := ""
var _table: Array = []

## Camera offset from what it is watching, smoothed. The POSITION is not smoothed — `_follow`.
var _trail := Vector3.ZERO

## Measurement state, -1 when nobody is measuring.
var _row := -1
var _settle := 0.0

@onready var _camera: Camera3D = $Camera
@onready var _hud: RichTextLabel = $Ui/Info
@onready var _prey: SeekerPrey = $Prey
@onready var _dart: SeekerDart = $Dart
@onready var _rail: Node3D = $Rail
@onready var _threat: SeekerThreat = $Ui/Threat
@onready var _eye: SubViewport = $Ui/Eye/View
@onready var _eye_camera: Camera3D = $Ui/Eye/View/Cam


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_dart.finished.connect(_on_dart_finished)
	_dart.visible = false
	_dart.head.gain = GAINS[_gain]
	_dart.limit = LIMITS[_limit]
	# The inset looks into the SAME world. A SubViewport makes its own `World3D` without being
	# asked, and without this line the window would simply be empty — and not an error.
	_eye.world_3d = get_viewport().world_3d


## Camera and instruments live in the FRAME, not in the physics tick. A rig is the root, so
## its `_physics_process` runs before the bodies it watches, and reading them there gives the
## previous tick — six hundred metres per second is ten metres of it. What used to make the
## frame dangerous, smoothing a position against a body that steps, is gone: positions are
## pinned and only offsets are smoothed.
func _process(delta: float) -> void:
	_follow(delta)
	_eyeball()
	_warn()
	_readout()


func _physics_process(delta: float) -> void:
	if _row >= 0:
		_run(delta)
		return
	_stick(delta)
	_prey.pitch_input = _pitch
	_prey.yaw_input = _yaw


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	_apply_key(key.keycode)


func _apply_key(keycode: Key) -> void:
	match keycode:
		KEY_SPACE:
			if _row < 0 and not _dart.flying:
				_shoot()
		KEY_1:
			_dart.head.law = (SeekerHead.Law.PURSUIT
					if _dart.head.law == SeekerHead.Law.PROPORTIONAL
					else SeekerHead.Law.PROPORTIONAL)
			_table.clear()
		KEY_2:
			_gain = (_gain + 1) % GAINS.size()
			_dart.head.gain = GAINS[_gain]
			_table.clear()
		KEY_3:
			_wide = not _wide
		KEY_4:
			_limit = (_limit + 1) % LIMITS.size()
			_dart.limit = LIMITS[_limit]
			_table.clear()
		KEY_G:
			_table.clear()
			_row = 0
			_start_row()
		KEY_TAB:
			_row = -1
			_reset()


## Aircraft layout, same as the forty-fourth: stick back is nose up.
func _stick(delta: float) -> void:
	var want_pitch := (Input.get_action_strength(&"move_back")
			- Input.get_action_strength(&"move_forward"))
	var want_yaw := (Input.get_action_strength(&"move_right")
			- Input.get_action_strength(&"move_left"))
	_pitch = _toward(_pitch, want_pitch, delta)
	_yaw = _toward(_yaw, want_yaw, delta)


func _toward(now: float, want: float, delta: float) -> float:
	if is_zero_approx(want):
		return move_toward(now, 0.0, stick_return * delta)
	return clampf(now + want * stick_rate * delta, -1.0, 1.0)


## ONE ROW. The target holds a constant break turn at a fixed load, so the only thing that
## differs between rows is how hard it is pulling and the only thing that differs between
## tables is the law.
func _run(delta: float) -> void:
	if not _dart.flying:
		_settle -= delta
		if _settle <= 0.0:
			_row += 1
			if _row < TEST_G.size():
				_start_row()
			else:
				_row = -1
				_reset()
		return
	_prey.pitch_input = 0.0
	_prey.yaw_input = clampf(TEST_G[_row] / maxf(_prey.limit, 0.001), -1.0, 1.0)


func _start_row() -> void:
	_reset_bodies()
	_settle = SETTLE_BEFORE
	_shoot()


func _reset_bodies() -> void:
	_prey.reset(Transform3D(Basis.IDENTITY, Vector3(0.0, TEST_ALT, 0.0)))
	_prey.pitch_input = 0.0
	_prey.yaw_input = 0.0


func _shoot() -> void:
	var at := _rail.global_transform
	at.basis = Basis.looking_at(_prey.global_position - at.origin, Vector3.UP)
	_dart.launch(at, _prey)


func _reset() -> void:
	_reset_bodies()
	_pitch = 0.0
	_yaw = 0.0
	_dart.flying = false
	_dart.visible = false
	_trail = Vector3.ZERO


## Through the missile's eyes, and along its NOSE rather than at the target. The difference
## between the two laws shows in this window without a single number: pursuit holds the target
## in the crosshair by definition, while proportional navigation walks it off to the side and
## aims at the empty place the target is going to be.
##
## The ring the head carries is the second half of the same picture: the crosshair is where
## the missile points, the ring is where the seeker looks, and the gap between them is the
## lead. On the rail the window looks at the target from the launcher, wide, so that "which
## side is it coming from" has an answer before the shot.
func _eyeball() -> void:
	if _dart.flying:
		_eye_camera.fov = EYE_FOV
		_eye_camera.global_position = _dart.global_position
		_eye_camera.look_at(
				_dart.global_position - _dart.global_basis.z * 100.0, Vector3.UP)
	else:
		_eye_camera.fov = EYE_REST_FOV
		_eye_camera.global_position = _rail.global_position
		_eye_camera.look_at(_prey.global_position, Vector3.UP)


## The threat ring: the direction to the missile, put into the target's own axes. From there
## the indicator draws itself, and it needs to know nothing about the missile or the rig.
func _warn() -> void:
	_threat.live = _dart.flying
	if not _dart.flying:
		return
	var offset := _dart.global_position - _prey.global_position
	_threat.bearing = _prey.global_basis.inverse() * offset
	_threat.closing = _dart.head.closing
	_threat.locked = _dart.head.locked


## Behind the target, or wide enough to hold both. The wide view is the honest one for
## judging a law: from behind the target every miss looks like a hit.
##
## The camera is PINNED to what it watches and only the OFFSET is smoothed. Lerping the world
## position instead leaves the camera a fixed distance behind the point it wants, and that
## distance is the target's speed divided by the lerp rate: eighty metres at two hundred and
## fifty metres per second, on a chase meant to sit forty back. The aeroplane ends up three
## times further away than the knob says, and the knob stops meaning anything.
func _follow(delta: float) -> void:
	var anchor := _prey.global_position
	var offset := _prey.global_basis.z * chase_back + Vector3.UP * 8.0
	if _wide and _dart.flying:
		anchor = (_prey.global_position + _dart.global_position) * 0.5
		var span := maxf(
				_prey.global_position.distance_to(_dart.global_position), 120.0)
		offset = Vector3(span * 0.9, span * 0.35, span * 0.9)
	_trail = (offset if _trail == Vector3.ZERO
			else _trail.lerp(offset, clampf(delta * TRAIL_RATE, 0.0, 1.0)))
	_camera.global_position = anchor + _trail
	_camera.look_at(_prey.global_position, Vector3.UP)


## Numbers that belong to a missile in the air. With nothing flying they are the leftovers of
## the last shot, and printing them beside a threat ring that has correctly gone dark is the
## readout contradicting itself on one screen — the exact thing the ring exists to prevent.
func _live(pattern: String, value: float) -> String:
	return (pattern % value) if _dart.flying else "—"


func _readout() -> void:
	var head := _dart.head
	var law := ("погоня" if head.law == SeekerHead.Law.PURSUIT
			else "пропорциональное сближение")
	var lines := PackedStringArray([
		"[b]ГОЛОВКА НАВЕДЕНИЯ[/b]   закон: [b]%s[/b]   N = %.0f   предел ракеты %.0f g" % [
			law, head.gain, _dart.limit],
		"захват: %s   от оси %s   вид крутится %s   сближение %s" % [
			("[color=#7fe08a]есть[/color]" if head.locked else "[color=#ff8866]нет[/color]")
				if _dart.flying else "—",
			_live("%.0f°", rad_to_deg(head.off_bore)),
			_live("%.1f °/с", rad_to_deg(head.turn_rate)),
			_live("%.0f м/с", head.closing)],
		"просит %s   может %s   упиралась в предел %s" % [
			_live("[b]%.1f[/b] g", head.demand), _live("[b]%.1f[/b] g", _dart.pulled),
			_live("%.0f%% полёта", _dart.saturated * 100.0)],
		"дистанция %s   время %s%s" % [
			_live("%.0f м", _prey.global_position.distance_to(_dart.global_position)),
			_live("%.1f с", _dart.clock),
			"   последний пуск: " + _last_shot if _last_shot != "" else ""],
		"",
		"[b]WASD — цель, а не ракета[/b]   S нос вверх   ПРОБЕЛ пустить в себя   TAB заново",
		"1 закон: %s" % law,
		"2 N: %.0f" % head.gain,
		"3 камера: %s" % ("широкая" if _wide else "за целью"),
		"[color=#9fb4c8]круг внизу справа — где ракета относительно вашего носа;"
			+ " окно вверху — её собственный взгляд по курсу[/color]",
		"4 предел ракеты: %.0f g" % _dart.limit,
		"G прогнать четыре пуска по цели с перегрузкой 0 / 3 / 6 / 9",
	])
	if _row >= 0:
		lines.append("")
		lines.append("[color=#66ccff]замер: цель тянет %.0f g[/color]" % TEST_G[_row])
	if not _table.is_empty():
		_append_table(lines, law, head.gain)
	_hud.text = "\n".join(lines)


func _append_table(lines: PackedStringArray, law: String, gain: float) -> void:
	lines.append("")
	lines.append("[b]%s, N = %.0f, предел %.0f g[/b]" % [law, gain, _dart.limit])
	lines.append("[table=4][cell]цель тянет[/cell][cell]промах[/cell]"
		+ "[cell]время[/cell][cell]в пределе[/cell]")
	for row in _table:
		lines.append(
			"[cell]%.0f g[/cell][cell]%s[/cell][cell]%.1f с[/cell][cell]%.0f%%[/cell]"
			% [row["g"], "[color=#7fe08a]в цель[/color]" if row["hit"]
				else ("%.0f м" % row["miss"] if row["miss"] < 9000.0 else row["reason"]),
				row["time"], row["saturated"] * 100.0])
	lines.append("[/table]")


func _on_dart_finished(miss: float, hit: bool, reason: String) -> void:
	_last_shot = "в цель" if hit else "%s, %.0f м" % [reason, miss]
	if _row >= 0:
		_table.append({
			"g": TEST_G[_row],
			"miss": miss,
			"hit": hit,
			"reason": reason,
			"saturated": _dart.saturated,
			"time": _dart.clock,
		})
		_settle = SETTLE_AFTER
