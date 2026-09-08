extends Node3D
class_name RocketRig

## HANDS, CAMERAS AND A FLOATING ORIGIN.
##
## The rig decides WHERE the nose should point and hands that to the stack as `want_dir`.
## How the stack gets there is its own business — the loop that does it lives in the vehicle,
## because "hold the attitude you were given" is a sentence about a rocket and not about a
## test stand.
##
## The floating origin arrived here already measured, from the thirty-fourth probe: a
## `Vector3` is thirty-two bits, so the world drives back to zero instead of the numbers
## growing. The accumulated shift is kept as three plain `float`s, which are double.
##
## `G` runs four ascents with different turn speeds and fills the table.

## Where the cameras stand off to. Chosen ACROSS the plane the gravity turn happens in: the
## kick lays the rocket over towards world -Z, so a camera on that axis would watch the whole
## manoeuvre edge-on and see nothing.
const SIDE := Vector3(1.0, 0.0, 0.0)

const SHIFT_AT := 1500.0
## Seconds a measured ascent is given before it counts as a failure. Without it a profile
## that neither reaches orbit nor falls over runs forever and the row never returns.
const GIVE_UP := 330.0
## Speed at which the turn starts, and a SPEED rather than an altitude: gravity lays the
## vector over at g/v, so an altitude says nothing about how fast that will go. Early and
## deliberately, while there is no dynamic pressure to punish the angle the lean costs.
const TURN_AT := 50.0
## How far to lean at the start of the turn — the measured quantity. Both ends of this range
## lose: too little and gravity never gets the vector down, so the vehicle throws its whole
## budget straight up; too much and it noses over into the ground or reaches orbital speed
## before it has any altitude. The answer is in the middle and the middle is narrow.
const KICKS := [5.0, 9.0, 13.0, 20.0]
## How far the command may ever sit off the velocity vector, which is the whole of load
## relief. A lean of thirteen degrees asked for in one tick IS thirteen degrees of angle of
## attack, and at max q the airframe out-moments the engines at that angle. Walked in, the
## same lean costs nothing. Real launchers carry the same limit for the same reason.
const MAX_ALPHA := 4.0

## How long the vehicle is. Every camera distance is a multiple of it, so reframing a
## different stack means changing this one number and nothing else.
@export_range(5.0, 200.0, 1.0) var vehicle_length := 48.0
## How fast the hand moves the AIM, degrees per second. This is not the rate the rocket
## turns: it catches up as fast as its engines let it.
@export_range(2.0, 60.0, 1.0) var aim_rate := 14.0
## How far to lean the rocket at the moment the turn starts. Nothing else needs setting:
## after that it flies along its velocity vector, and gravity does the laying over.
@export_range(1.0, 25.0, 0.5) var kick := 9.0
## How far above the horizon to hold the nose once the velocity vector has dropped below it.
@export_range(0.0, 45.0, 0.5) var floor_angle := 6.0
## The rocket, as a separate scene. A measurement run rebuilds it rather than reloading the
## probe: reloading would take the rig down with it, and the table with the rig.
@export var stack_scene: PackedScene
## What a separated block becomes. A scene, so the Korolev cross is made of the blocks that
## were flying a second ago and not of grey boxes that stand in for them.
@export var spent_scene: PackedScene

## Which camera is live. The first two are bolted to the ground and are dragged into place in
## the editor; only the third one is driven from here.
enum Eye { PAD, SCOPE, TRAIL }
const EYES := ["у башни", "телеобъектив", "рядом с бортом"]

var _eye := Eye.PAD
## Where the side camera stands, in the rocket's own sky. Turned with the left button held,
## pulled in and out with the wheel: a fixed offset shows the vehicle and nothing about where
## it is going, and "where it is going" is the whole question of an ascent.
var _orbit_yaw := 0.0
var _orbit_pitch := 0.06
var _orbit_far := 1.45
var _dragging := false
var _want_dir := Vector3.ZERO
var _look := Vector3.ZERO
var _auto := false
var _kick := 13.0
var _peak_q := 0.0
var _row := -1
var _table: Array = []
var _flight := 0.0
var _done := false
var _wreck := ""

## Accumulated shift of the world. Three numbers rather than a `Vector3`, exactly for the
## double precision.
var _sx := 0.0
var _sy := 0.0
var _sz := 0.0

@onready var _hud: RichTextLabel = $Ui/Info
@onready var _planet: RocketPlanet = $Planet
@onready var _stack: RocketStack = $Stack
@onready var _junk: Node3D = $Junk
@onready var _cams: Array[Camera3D] = [$Cams/Pad, $Cams/Scope, $Cams/Trail]

var _pad := Transform3D.IDENTITY
var _home := Vector3.ZERO


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_pad = _stack.global_transform
	_home = _planet.global_position
	_cams[_eye].make_current()
	_hold_down()


func _physics_process(delta: float) -> void:
	_flight += delta
	_stack.want_dir = _program() if (_row >= 0 or _auto) else _steer(delta)
	_peak_q = maxf(_peak_q, _stack.dynamic)
	_autostage()
	_rebase()
	if _row >= 0 and (not _stack.flying or _orbited() or _flight > GIVE_UP):
		_finish_row()


## The cameras are computed in the FRAME, not in the physics tick. A rig is the root, so its
## `_physics_process` runs before the body it is watching: reading the stack there gives last
## tick's position. In the frame the step is already done.
func _process(delta: float) -> void:
	_follow(delta)
	_readout()


## BY HAND, and the hand moves the AIM rather than the engines. Steering the gimbal directly
## is meaningless here: the airframe is aerodynamically unstable, the static margin is
## negative, and without a loop it turns over in seconds. Real launchers are flown the same
## way — the hand says where to look and the automation holds it.
##
## Aircraft layout, as in the forty-fourth and forty-fifth: stick back is nose up.
func _steer(delta: float) -> Vector3:
	if _want_dir.length_squared() < 0.5:
		_want_dir = -_stack.global_basis.z
	var p := Input.get_action_strength(&"move_back") - Input.get_action_strength(&"move_forward")
	var y := Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left")
	var step := deg_to_rad(aim_rate) * delta
	_want_dir = _want_dir.rotated(_stack.global_basis.x, p * step)
	_want_dir = _want_dir.rotated(_stack.global_basis.y, -y * step).normalized()
	return _want_dir


## THE GRAVITY TURN, and it is not a pitch program. An angle commanded against altitude
## fights the velocity vector: twenty degrees of attack, paid for in dynamic pressure, and no
## horizontal speed to show for it.
##
## The real turn is vertical until `TURN_AT`, one short lean, and after that the nose held ON
## THE VELOCITY VECTOR and never touched again. Gravity does the turning, the angle of attack
## stays near zero, and the turn costs nothing.
func _program() -> Vector3:
	var up := -_planet.down(_stack.global_position)
	var v := _stack.linear_velocity
	if v.length() < TURN_AT:
		return up
	# Never ask for more than `MAX_ALPHA` away from where the vehicle is actually going.
	var prograde := v.normalized()
	var want := _aimed(up, v)
	var off := prograde.angle_to(want)
	var cap := deg_to_rad(MAX_ALPHA)
	return want if off <= cap or off < 1e-6 else prograde.slerp(want, cap / off)


func _aimed(up: Vector3, v: Vector3) -> Vector3:
	var prograde := v.normalized()
	var lean := up.angle_to(prograde)
	var tilt: float = _kick if _row >= 0 else kick
	if lean < deg_to_rad(tilt):
		# The kick. Once, and small: from here on it is gravity that works, not the engines.
		var side := up.cross(Vector3.FORWARD)
		if side.length_squared() < 1e-6:
			side = up.cross(Vector3.RIGHT)
		var flat := side.cross(up).normalized()
		return up.slerp(flat, deg_to_rad(tilt) / (PI * 0.5))
	# Holding the velocity vector only works while it still points up. The moment the vertical
	# speed goes negative, "along the vector" means "nose into the ground" and the thrust
	# starts driving the rocket into the planet. The nose does not go below the horizon.
	var flat_dir := prograde - up * prograde.dot(up)
	if flat_dir.length_squared() < 1e-6:
		return up
	flat_dir = flat_dir.normalized()
	var rise := asin(clampf(prograde.dot(up), -1.0, 1.0))
	var least := deg_to_rad(floor_angle)
	return prograde if rise > least else flat_dir * cos(least) + up * sin(least)


## Only a measurement run separates by itself. By hand the stages are dropped by hand, and
## that is half of what people watch a rocket for.
func _autostage() -> void:
	if _row < 0 or not _stack.flying or _stack.stages.is_empty():
		return
	for st in _stack.stages:
		if st.group == _stack.group and not st.spent:
			return
	_stack.drop()


## THE FLOATING ORIGIN. The rocket stays at zero and everything else drives towards zero. The
## true position does not change — what changes is the thing it is measured from.
func _rebase() -> void:
	var off := _stack.global_position
	if off.length() < SHIFT_AT:
		return
	for c in get_children():
		var n := c as Node3D
		if n != null and n != _junk:
			n.global_position -= off
	# The debris are moved one by one and their parent is left alone. Shifting the parent as
	# well would move every piece twice, and a rigid body has to be told where it went in any
	# case — dragging it by its parent is not telling it.
	for c in _junk.get_children():
		(c as Node3D).global_position -= off
	_planet.centre -= off
	_sx += off.x
	_sy += off.y
	_sz += off.z


## A separated block goes on flying with its own physics, as the block it was. The Korolev
## cross is authored nowhere: it comes out of four blocks leaving a common axis at once.
func _on_separated(at: Transform3D, away: Vector3, dry: float) -> void:
	if spent_scene == null:
		return
	var body := spent_scene.instantiate() as RigidBody3D
	body.mass = maxf(dry, 1.0)
	_junk.add_child(body)
	# The scale rides in with the transform, and a physics body will not take it. It goes to
	# the shell instead, which carries both the mesh and the collision shape.
	var size: float = at.basis.get_scale().x
	body.global_transform = Transform3D(at.basis.orthonormalized(), at.origin)
	(body.get_node("Shell") as Node3D).scale = Vector3.ONE * size
	body.linear_velocity = away
	body.angular_velocity = Vector3(randf_range(-0.7, 0.7), randf_range(-0.7, 0.7), 0.0)
	get_tree().create_timer(25.0).timeout.connect(body.queue_free)


## Hook up a fresh rocket and hold it on the table. Until the launch key it stands and spends
## nothing: lift-off is an event, and an event is only visible if something was still first.
func _hold_down() -> void:
	_stack.planet = _planet
	if not _stack.separated.is_connected(_on_separated):
		_stack.separated.connect(_on_separated)
		_stack.staged_out.connect(func() -> void: _done = true)
		_stack.struck.connect(_on_struck)
	_stack.freeze = true
	_stack.flying = false


func _on_struck(_where: Vector3, at_speed: float) -> void:
	_wreck = "[color=#ff8866]разбилась на %.0f м/с[/color]" % at_speed


func _lift() -> void:
	_stack.freeze = false
	_stack.ignite()


## Rebuilt, not reloaded, and the world goes back to zero with it: the accumulated shift is
## rig state, and keeping it would start the next ascent in orbit.
func _rebuild() -> void:
	if stack_scene == null:
		return
	for c in _junk.get_children():
		c.queue_free()
	_stack.queue_free()
	_stack = stack_scene.instantiate()
	_stack.name = "Stack"
	add_child(_stack)
	_planet.global_position = _home
	_planet.centre = _home
	_stack.global_transform = _pad
	_look = Vector3.ZERO
	_sx = 0.0
	_sy = 0.0
	_sz = 0.0
	_peak_q = 0.0
	_flight = 0.0
	_done = false
	_wreck = ""
	_want_dir = Vector3.ZERO
	_hold_down()


## A run ends when the periapsis clears the air, not when the tanks do. Burning every stage
## to the last drop takes nine minutes of ascent and answers a different question; the one
## being asked is which profile gets there at all, and at what price in dynamic pressure.
func _orbited() -> bool:
	return _stack.orbit()["peri"] > _planet.edge


func _start_row() -> void:
	_kick = KICKS[_row]
	_rebuild()
	_lift()


func _finish_row() -> void:
	var o := _stack.orbit()
	_table.append({
		"kick": _kick,
		"apo": o["apo"],
		"peri": o["peri"],
		"speed": _stack.speed,
		"q": _peak_q,
		"time": _flight,
		"ok": _orbited(),
	})
	_row += 1
	if _row < KICKS.size():
		_start_row()
	else:
		_row = -1
		_rebuild()


## THREE VIEWPOINTS. Two of them stand where the editor put them, and one of those is not
## touched by this code at all.
##
## `у башни` is bolted down: it neither moves nor turns, and the rocket leaves the frame
## upwards by itself. Its position AND its aim are what somebody dragged them to, which is
## the whole point — a shot that cannot be composed with a mouse is not a shot, it is a
## constant.
##
## `телеобъектив` stands off and tracks through an eight degree lens: perspective squashed,
## the vehicle hanging in the frame and crawling. That is the whole trick that makes a rocket
## look huge and slow, and it belongs to the lens rather than to the model.
##
## `рядом с бортом` rides alongside and is turned by hand. Without ground in shot neither the
## climb nor the drift downrange can be read at all.
func _follow(delta: float) -> void:
	var pos := _stack.global_position
	var up := -_planet.down(pos)
	var side := SIDE - up * SIDE.dot(up)
	side = side.normalized() if side.length_squared() > 1e-6 else Vector3.RIGHT
	var cam := _cams[_eye]
	if _eye == Eye.PAD:
		return
	if _eye == Eye.TRAIL:
		var away := (side * cos(_orbit_pitch) + up * sin(_orbit_pitch)).rotated(up, _orbit_yaw)
		cam.global_position = pos + away * vehicle_length * _orbit_far
		# The stack's origin sits at the middle of the vehicle, so the aim needs no offset.
		_aim(cam, pos, up, side)
		return
	# A mounted long lens is turned by a hand, and a hand is late. That lag is why the rocket
	# gets away from it rather than being held in the middle of the frame forever.
	_look = pos if _look == Vector3.ZERO else _look.lerp(pos, clampf(delta * 2.0, 0.0, 1.0))
	_aim(cam, _look, up, side)


## Godot complains when "up" lines up with the direction of view, and the camera loses its
## roll at that moment. It happens constantly here: a ground camera looking at a rocket almost
## overhead is exactly that case. Substitute the sideways vector when the main one degenerates.
func _aim(cam: Camera3D, at: Vector3, up: Vector3, side: Vector3) -> void:
	var view := at - cam.global_position
	if view.length_squared() < 1e-6:
		return
	var v := view.normalized()
	cam.look_at(at, up if absf(v.dot(up)) < 0.98 else side)


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null:
		if button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit_far = maxf(_orbit_far - 0.15, 0.45)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit_far = minf(_orbit_far + 0.15, 8.0)
		return
	var drag := event as InputEventMouseMotion
	if drag != null:
		if _dragging:
			_orbit_yaw -= drag.relative.x * 0.006
			_orbit_pitch = clampf(_orbit_pitch + drag.relative.y * 0.006, -1.3, 1.3)
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_SPACE:
			if _stack.flying:
				_stack.drop()
			else:
				_lift()
		KEY_1: _auto = not _auto
		KEY_2:
			_eye = ((_eye + 1) % EYES.size()) as Eye
			_look = Vector3.ZERO
			_cams[_eye].make_current()
		KEY_SHIFT: _stack.throttle = minf(_stack.throttle + 0.25, 1.0)
		KEY_CTRL: _stack.throttle = maxf(_stack.throttle - 0.25, 0.0)
		KEY_G:
			_table.clear()
			_row = 0
			_start_row()
		KEY_TAB: _rebuild()


## Four states, and time passes between them: on the table, on the clamps with the engines
## running, in flight, and down. Thrust-to-weight is on the readout at all times: a stage
## whose ratio has quietly fallen below one does not announce itself, it just stops climbing.
func _state() -> String:
	if _wreck != "":
		return _wreck
	if not _stack.flying:
		return "выведено" if _done else "на столе"
	if _stack.clamped:
		return "[color=#ffcc66]удержание, тяга к весу %.2f[/color]" % _stack.lift_ratio
	return "полёт"


## A periapsis below the surface is not a number anyone reads, it is a word: the trajectory
## comes back down. Printing "-120.0 км" says the low point of the ellipse is at the centre of
## the planet, which is true and useless.
func _peri(value: float) -> String:
	return "%.1f км" % (value * 0.001) if value > 0.0 else "суборбита"


## WHERE THE SPEED IS GOING, and it is what the readout was missing. Flown straight up a
## rocket spends everything on altitude and reaches orbital SPEED without being in orbit at
## all: only what goes ACROSS the local vertical ever becomes an orbit. Without these three
## figures that mistake reads as "the engines are too weak".
func _readout() -> void:
	var up := -_planet.down(_stack.global_position)
	var climb := _stack.linear_velocity.dot(up)
	var across := (_stack.linear_velocity - up * climb).length()
	var slope := rad_to_deg(atan2(climb, maxf(across, 0.001)))
	var h := _planet.altitude(_stack.global_position)
	var o := _stack.orbit()
	var fuel := 0.0
	var count := 0
	for st in _stack.stages:
		if st.group == _stack.group:
			fuel += st.fuel
			count += 1
	var lines := PackedStringArray([
		"[b]РАКЕТА-НОСИТЕЛЬ[/b]   %s   ступень %d   блоков в ней %d   топливо %.0f%%" % [
			_state(), _stack.group + 1, count, 100.0 * fuel / maxf(count, 1)],
		"высота [b]%.1f[/b] км   скорость [b]%.0f[/b] м/с   круговая %.0f   уход %.0f м/с" % [
			h * 0.001, _stack.speed, _planet.orbital_speed(h),
			_planet.orbital_speed(h) * sqrt(2.0)],
		"вверх %.0f   вбок [b]%.0f[/b] м/с   к горизонту [b]%.0f[/b]°   %s" % [
			climb, across, slope, "[color=#9fb4c8]в орбиту идёт только «вбок»[/color]"],
		"апоцентр [b]%.1f[/b] км   перицентр %s   масса %.1f т   тяга %.0f кН = [b]%.2f[/b] веса" % [
			o["apo"] * 0.001, _peri(o["peri"]), _stack.mass * 0.001, _stack.push * 0.001,
			_stack.lift_ratio],
		"качание камер %+.1f° / %+.1f°   вращение %.1f °/с" % [
			_stack.swing_pitch, _stack.swing_yaw, rad_to_deg(_stack.angular_velocity.length())],
		"напор %.1f кПа   пик %.1f   угол атаки %.1f°   запас устойчивости %.2f м" % [
			_stack.dynamic * 0.001, _peak_q * 0.001, rad_to_deg(_stack.alpha), _stack.margin],
		"мир съехал на %.1f км   (плавающее начало, взято из 34-й пробы)" % (
			sqrt(_sx * _sx + _sy * _sy + _sz * _sz) * 0.001),
		"",
		"[b]WASD — куда смотреть[/b] (когда автопилот выключен)   S вверх   TAB заново",
		"[b]ПРОБЕЛ — %s[/b]" % ("отделить ступень" if _stack.flying else "ПУСК"),
		"1 автопилот по программе тангажа: %s" % ("вкл" if _auto else "выкл"),
		"2 камера: %s%s" % [EYES[_eye],
			"   (ЛКМ вращать вокруг, колесо ближе/дальше)" if _eye == Eye.TRAIL else ""],
		"SHIFT / CTRL тяга: %.0f%%" % (_stack.throttle * 100.0),
		"G прогнать четыре подъёма с наклоном 5 / 9 / 13 / 20°",
	])
	if _row >= 0:
		lines.append("")
		lines.append("[color=#66ccff]замер: наклон %.0f°[/color]" % _kick)
	if not _table.is_empty():
		lines.append("")
		lines.append("[b]подъём: насколько класть на развороте (с %.0f м/с)[/b]" % TURN_AT)
		lines.append("[table=6][cell]наклон[/cell][cell]апоцентр[/cell][cell]перицентр[/cell]"
			+ "[cell]скорость[/cell][cell]пик напора[/cell][cell]время[/cell]")
		for r in _table:
			lines.append("[cell]%.0f°[/cell][cell]%.1f км[/cell][cell]%s[/cell]"
				% [r["kick"], r["apo"] * 0.001,
					_peri(r["peri"]) if r["ok"] else "[color=#ff8866]не вышла[/color]"]
				+ "[cell]%.0f м/с[/cell][cell]%.1f кПа[/cell][cell]%.0f с[/cell]" % [
					r["speed"], r["q"] * 0.001, r["time"]])
		lines.append("[/table]")
	_hud.text = "\n".join(lines)
