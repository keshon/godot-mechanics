extends Node3D
class_name MissileRig

## HANDS, CAMERA AND KNOBS.
##
## Two ways to use the stand, and they answer different halves of the question.
##
## By hand: fly the thing yourself through the gates. WASD moves FINS, not the missile, and
## the gap between those two sentences is most of what the probe is about.
##
## The stick springs back to centre when let go, which the first version did not do: it
## added mouse movement to an accumulator that nothing ever returned, so any net drift of
## the hand left a fin permanently deflected and the missile permanently turning.
##
## By measurement: `G` runs the same turn four times at four speeds with the motor already
## dead, and fills the table. Run it once with the limiter on and once off — the two tables
## are the answer, and they disagree about whether speed helps you turn.

const SPEEDS := [200.0, 400.0, 600.0, 800.0]
const QUARTER := PI * 0.5
const GIVE_UP := 10.0
## High enough that a failed turn ends in a timeout, not in the ground.
const TEST_ALT := 2500.0

@export var launch_speed := 45.0
## How fast the stick travels while a key is held, and how fast it comes back when it is
## let go. The return is what makes the thing steerable.
@export_range(0.5, 10.0, 0.1) var stick_rate := 3.0
@export_range(0.5, 12.0, 0.1) var stick_return := 5.0
## Distance the camera trails behind the missile.
@export_range(4.0, 40.0, 0.5) var chase_back := 8.0
@export_range(0.0, 10.0, 0.1) var chase_up := 1.8

var _yaw := 0.0
var _pitch := 0.0
var _roll := 0.0
var _chase := true
var _gates := 0
var _peak_g := 0.0
var _flight := 0.0

## Measurement state. `_row` is -1 when nobody is measuring.
var _row := -1
var _t := 0.0
var _from := Vector3.ZERO
var _entry := 0.0
var _sum_g := 0.0
var _ticks := 0
## The LARGEST turn of the run and not the last one: a missile that has run out of speed
## drops its nose, falls back, and the velocity vector returns to where it started.
var _best := 0.0
## Path actually flown during the row. The radius comes from this and not from the speed the
## missile entered with.
var _arc := 0.0
var _table: Array = []

## Camera offset from the missile, smoothed. The POSITION is not smoothed — see `_follow`.
var _trail := Vector3.ZERO
var _gate_total := 0

@onready var _cam: Camera3D = $Camera
@onready var _hud: RichTextLabel = $Ui/Info
@onready var _bird: MissileBody = $Missile
@onready var _rail: Node3D = $Rail


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_bird.struck.connect(_on_struck)
	var gates := get_tree().get_nodes_in_group("gate")
	_gate_total = gates.size()
	for g in gates:
		(g as Area3D).body_entered.connect(func(_b: Node) -> void: _gates += 1)
	_park()


## Back on the rail, motor unlit, nothing moving.
func _park() -> void:
	_bird.flying = false
	_bird.freeze = true
	_bird.global_transform = _rail.global_transform
	_bird.linear_velocity = Vector3.ZERO
	_bird.angular_velocity = Vector3.ZERO
	_bird.pitch_input = 0.0
	_bird.yaw_input = 0.0
	_bird.roll_input = 0.0
	_yaw = 0.0
	_pitch = 0.0
	_roll = 0.0
	_gates = 0
	_peak_g = 0.0
	_flight = 0.0
	_trail = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if _row >= 0:
		_measure(delta)
	else:
		_stick(delta)
		if _bird.flying:
			_flight += delta
			_peak_g = maxf(_peak_g, _bird.lateral_g)
			_bird.pitch_input = _pitch
			_bird.yaw_input = _yaw
			_bird.roll_input = _roll


func _process(delta: float) -> void:
	# The camera stays in the FRAME and not in the physics tick, and that is deliberate. A rig
	# is the root, so its `_physics_process` runs BEFORE the body's: reading the missile there
	# gives last tick's position, and at six hundred metres per second last tick is ten metres
	# away. In the frame the step is already done. What made the frame dangerous — smoothing a
	# position against a body that jumps — is gone: the position is pinned, only the offset is
	# smoothed, and an offset changes slowly.
	_follow(delta)
	_readout()


## THE STICK. Held keys push it, an empty hand lets it come back. Both halves matter: the
## rate decides how quickly full deflection is available, the return decides whether the
## missile can ever fly straight again after a turn.
func _stick(delta: float) -> void:
	# Aircraft layout: stick back is nose up. That is why S gives positive pitch and W gives
	# negative, the way a stick pushed forward does.
	var p := Input.get_action_strength(&"move_back") - Input.get_action_strength(&"move_forward")
	var y := Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left")
	var r := (1.0 if Input.is_key_pressed(KEY_E) else 0.0) 		- (1.0 if Input.is_key_pressed(KEY_Q) else 0.0)
	_pitch = _toward(_pitch, p, delta)
	_yaw = _toward(_yaw, y, delta)
	_roll = _toward(_roll, r, delta)


func _toward(now: float, want: float, delta: float) -> float:
	if is_zero_approx(want):
		return move_toward(now, 0.0, stick_return * delta)
	return clampf(now + want * stick_rate * delta, -1.0, 1.0)


## Chase from behind, or stand still and watch it leave. The second view is the honest one
## for judging a turn: from behind, every turn looks tight.
##
## The camera is PINNED to the missile and only the OFFSET is smoothed. Written the obvious
## way — lerp the world position towards a point behind the missile — the camera settles a
## fixed distance behind that point, and that distance is the missile's speed divided by the
## lerp rate: a hundred metres of extra trail at six hundred metres per second, on a chase
## meant to sit eight metres back. The faster it flies the smaller it gets, which is exactly
## backwards. No earlier probe showed this, because a car does thirty.
func _follow(delta: float) -> void:
	if not _chase:
		_cam.look_at(_bird.global_position, Vector3.UP)
		return
	var back := _bird.global_basis.z * chase_back + Vector3.UP * chase_up
	_trail = back if _trail == Vector3.ZERO else _trail.lerp(
		back, clampf(delta * 6.0, 0.0, 1.0))
	_cam.global_position = _bird.global_position + _trail
	_cam.look_at(_bird.global_position + -_bird.global_basis.z * 30.0, Vector3.UP)


## ONE ROW OF THE TABLE. Launch cold at a chosen speed, hold full pitch, and time how long
## the VELOCITY takes to come round ninety degrees. Not the nose: the nose turns first and
## the missile keeps going the old way for a while, and that lag is the whole story.
func _measure(delta: float) -> void:
	_t += delta
	_bird.pitch_input = 1.0
	_bird.yaw_input = 0.0
	var v := _bird.linear_velocity
	_arc += v.length() * delta
	_peak_g = maxf(_peak_g, _bird.lateral_g)
	# The peak lives for one frame — the one in which the fins slammed to full travel. What
	# actually turns the missile is the settled load, and that is what goes into the table.
	_sum_g += _bird.lateral_g
	_ticks += 1
	var turned := 0.0 if v.length() < 1.0 else _from.angle_to(v.normalized())
	_best = maxf(_best, turned)
	var done := turned >= QUARTER
	if done or _t > GIVE_UP or not _bird.flying:
		_table.append({
			"speed": _entry,
			"time": _t,
			"exit": v.length(),
			# Radius from the PATH FLOWN, not from the entry speed. Written the short way,
			# `v_entry * t / angle` assumes a speed the `exit` column of this same table
			# refutes — the missile leaves at a quarter of what it came in with — and the
			# answer came out as the ratio of entry speeds while looking like a measurement.
			"radius": _arc / maxf(_best, 0.0001),
			"peak": _peak_g,
			"held": _sum_g / maxf(_ticks, 1),
			"turned": rad_to_deg(_best),
			"ok": done,
			"why": "" if done else ("земля" if not _bird.flying else "время"),
		})
		_row += 1
		if _row < SPEEDS.size():
			_start_row()
		else:
			_row = -1
			_park()


func _start_row() -> void:
	var speed: float = SPEEDS[_row]
	var t := _rail.global_transform
	t.origin = Vector3(0.0, TEST_ALT, 0.0)
	_bird.launch(t, -t.basis.z * speed)
	# Motor dead on purpose: this measures the airframe, not the rocket behind it.
	_bird.fuel = 0.0
	_from = (-t.basis.z).normalized()
	_entry = speed
	_t = 0.0
	_peak_g = 0.0
	_sum_g = 0.0
	_ticks = 0
	_best = 0.0
	_arc = 0.0


func _on_struck(_where: Vector3, _speed: float) -> void:
	if _row < 0:
		_bird.pitch_input = 0.0
		_bird.yaw_input = 0.0


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.keycode:
			KEY_1: _bird.limiter = not _bird.limiter
			KEY_2: _bird.sustain_thrust = 0.0 if _bird.sustain_thrust > 0.0 else 1400.0
			KEY_3: _chase = not _chase
			KEY_G:
				_table.clear()
				_row = 0
				_start_row()
			KEY_TAB:
				_row = -1
				_yaw = 0.0
				_pitch = 0.0
				_park()
	elif event is InputEventMouseButton and event.pressed:
		if not _bird.flying and _row < 0:
			_yaw = 0.0
			_pitch = 0.0
			_roll = 0.0
			_bird.launch(_rail.global_transform, -_rail.global_basis.z * launch_speed)


func _readout() -> void:
	var phase := "на рельсе"
	if _bird.flying:
		if _bird.fuel <= 0.0:
			phase = "выбег"
		elif _bird.burn < _bird.boost_time:
			phase = "разгон"
		else:
			phase = "маршевый"
	var lines := PackedStringArray([
		"[b]РАКЕТА[/b]   %s   топливо %.0f%%   ворот пройдено %d из %d" % [
			phase, _bird.fuel * 100.0, _gates, _gate_total],
		"скорость [b]%.0f[/b] м/с   перегрузка [b]%.1f[/b] g   пик %.1f   угол атаки %.1f°" % [
			_bird.speed, _bird.lateral_g, _peak_g, rad_to_deg(_bird.alpha)],
		"крен %.0f °/с   тангаж %.0f °/с   рыскание %.0f °/с" % [
			rad_to_deg(_bird.angular_velocity.dot(-_bird.global_basis.z)),
			rad_to_deg(_bird.angular_velocity.dot(_bird.global_basis.x)),
			rad_to_deg(_bird.angular_velocity.dot(_bird.global_basis.y))],
		"высота %.0f м   пройдено %.0f м   время %.1f с%s" % [
			_bird.global_position.y, _bird.global_position.length(), _flight,
			"   [color=#ffaa66]ограничитель срезал %.0f%%[/color]" % (_bird.throttled * 100.0)
				if _bird.throttled > 0.01 else ""],
		"",
		"ЛКМ пуск   [b]WASD — РУЛИ, а не ракета[/b]   Q E крен   TAB заново",
		"по-самолётному: S нос вверх, W нос вниз, A влево, D вправо",
		"руль высоты [b]%+.2f[/b]   руль направления [b]%+.2f[/b]   элероны %+.2f" % [
			_pitch, _yaw, _roll],
		"1 ограничитель перегрузки: %s (%.0f g)" % [
			"вкл" if _bird.limiter else "[color=#ff8866]выкл[/color]", _bird.structural_g],
		"2 маршевый двигатель: %s" % ("есть" if _bird.sustain_thrust > 0.0 else "нет"),
		"3 камера: %s" % ("погоня" if _chase else "со стороны"),
		"G прогнать замер виража на четырёх скоростях",
	])
	if _row >= 0:
		lines.append("")
		lines.append("[color=#66ccff]замер: %.0f м/с, %.1f с[/color]" % [_entry, _t])
	if not _table.is_empty():
		lines.append("")
		lines.append("[b]вираж на 90° с мёртвым мотором, ограничитель %s[/b]" % (
			"вкл" if _bird.limiter else "выкл"))
		lines.append("[table=5][cell]вход[/cell][cell]время[/cell][cell]радиус[/cell]"
			+ "[cell]выход[/cell][cell]g держит / пик[/cell]")
		for r in _table:
			lines.append("[cell]%.0f м/с[/cell][cell]%s[/cell][cell]%s[/cell]"
				% [r["speed"], "%.2f с" % r["time"] if r["ok"] else "—",
					"%.0f м" % r["radius"] if r["ok"]
					else "дошла до %.0f° (%s)" % [r["turned"], r["why"]]]
				+ "[cell]%.0f м/с[/cell][cell]%.1f / %.1f[/cell]" % [
					r["exit"], r["held"], r["peak"]])
		lines.append("[/table]")
	_hud.text = "\n".join(lines)
