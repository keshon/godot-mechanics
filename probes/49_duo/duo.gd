class_name DuoRig
extends Node3D
## THE NAIL AND THE SWING: two people, two devices, and verbs that meet in the same second.
##
## The keyboard walks the thrower and the mouse aims: a click drives a nail into wood, the right
## button calls every nail back. The stick walks the swinger, who catches a nail and swings from it.
## A pit is crossed by the swinger on the thrower's nails, then the swinger pulls a lever on the far
## side that lays a bridge for the thrower. Three nails in hand means the one behind has to be
## called back while the swinger is still hanging from the one in front.
##
## Edge occupancy and the lack of a currently reachable, stuck anchor are separate counters.
## Neither measures boredom: a player standing still may be aiming or planning a jump.
##
## Devices split by class. The mouse is always the thrower's; WASD and space belong to the thrower,
## the stick and its buttons to the swinger. With no pad, TAB hands the keyboard to the swinger, so
## one person can still play both sides in turn.

## Speeds a thrown nail flies at, m/s. Zero is a nail that arrives the moment it leaves.
const THROW_SPEEDS: Array[float] = [25.0, 60.0, 0.0]
const PUMPS: Array[float] = [2.0, 4.0, 8.0]
const DEADZONES: Array[float] = [0.05, 0.2, 0.4]
## The deadzone the project gives the stick actions, restored on leaving.
const DEFAULT_DEADZONE := 0.2
const STICK_ACTIONS: Array[StringName] = [&"run_left", &"run_right"]
const NAILS_IN_HAND := 3
## How far the aim is traced, m. The same as a nail's own flight range in `nail.tscn`.
const AIM_RANGE := 30.0
const SOLIDS := 1 | 2
## Camera distance from the course plane, m: close when the two stand together, pulled back as
## they spread out, so both always stay on the one screen.
const CAMERA_NEAR := 13.0
const CAMERA_FAR := 30.0
const CAMERA_SPREAD := 0.8
const CAMERA_RISE := 3.0
## How far ahead of the feet the edge test looks, m, and how deep, m.
const EDGE_AHEAD := 1.0
const EDGE_DEPTH := 4.0
const VERDICT := ("гипотеза: гвоздь, нужный в полёте, делает сотрудничество интереснее;"
		+ " нужна игра вдвоём")

@export var nail_scene: PackedScene
## The material that takes a nail; the aim uses it to say in advance whether a throw will hold.
@export var wood: PhysicsMaterial

var _throw_step := 0
var _nails_counted := true
var _pump_step := 1
var _deadzone_step := 1
var _keyboard_on_swinger := false
var _nails: Array[DuoNail] = []
var _held: DuoNail = null
var _grab_requested := false
var _aim_point := Vector3.ZERO
var _aim_note := ""
var _throw_note := "—"
var _swing_note := "—"
## When the swinger last let go of a nail, on `_clock`; negative once the feet touch ground.
var _released_at := -1.0
var _clock := 0.0
var _started := false
var _finished_at := -1.0
## Seconds each player waited at a pit, thrower first.
var _waited := PackedFloat32Array([0.0, 0.0])
var _without_anchor := 0.0
var _handoffs := 0
var _missed_grabs := 0
var _failed_handoffs := 0
var _pad := -1
var _pad_news := ""

@onready var _thrower: DuoBody = $Thrower
@onready var _swinger: DuoBody = $Swinger
@onready var _camera: Camera3D = $Camera
@onready var _shelf: Node3D = $Nails
@onready var _aim_line: MeshInstance3D = $AimLine
@onready var _aim_mark: MeshInstance3D = $AimMark
@onready var _aim_paint: StandardMaterial3D = $AimMark.material_override
@onready var _levers: Node3D = $Level/Levers
@onready var _bridges: Node3D = $Level/Bridges
@onready var _goal: Area3D = $Level/Goal
@onready var _hud: RichTextLabel = $Ui/Info


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_pick_pad()
	_swinger.respawned.connect(_on_swinger_respawned)
	_apply_knobs()
	_camera.global_position = Vector3(_thrower.global_position.x, CAMERA_RISE, CAMERA_NEAR)


func _exit_tree() -> void:
	# The deadzone lives in the project's InputMap, not in this scene, and would outlive it.
	for action in STICK_ACTIONS:
		InputMap.action_set_deadzone(action, DEFAULT_DEADZONE)


func _process(delta: float) -> void:
	_steer()
	_aim()
	_follow(delta)
	_account(delta)
	_readout()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click: InputEventMouseButton = event
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			_throw()
		elif click.pressed and click.button_index == MOUSE_BUTTON_RIGHT:
			_recall()
		return
	if event.is_action_pressed(&"respawn"):
		_restart()
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_E:
			_grab_requested = true
		KEY_TAB:
			_keyboard_on_swinger = not _keyboard_on_swinger
		KEY_1:
			_throw_step = (_throw_step + 1) % THROW_SPEEDS.size()
		KEY_2:
			_nails_counted = not _nails_counted
		KEY_3:
			_pump_step = (_pump_step + 1) % PUMPS.size()
		KEY_4:
			_deadzone_step = (_deadzone_step + 1) % DEADZONES.size()
	_apply_knobs()


func _steer() -> void:
	var keys := Input.get_axis(&"move_left", &"move_right")
	var keys_jump := Input.is_action_pressed(&"jump")
	var stick := Input.get_axis(&"run_left", &"run_right")
	var stick_jump := Input.is_action_pressed(&"run_jump")
	var keyboard_used := keys != 0.0 or keys_jump
	if _keyboard_on_swinger:
		_thrower.move = 0.0
		_thrower.jumping = false
		_swinger.move = clampf(stick + keys, -1.0, 1.0)
		_swinger.jumping = stick_jump or keys_jump
	else:
		_thrower.move = keys
		_thrower.jumping = keys_jump
		_swinger.move = stick
		_swinger.jumping = stick_jump
	if Input.is_action_just_pressed(&"run_grab") or _grab_requested:
		_grab_requested = false
		_toggle_grab()
	if keyboard_used or stick != 0.0 or stick_jump:
		_started = true


## Traces where a nail thrown now would go, and says in advance whether it would hold.
func _aim() -> void:
	var mouse := get_viewport().get_mouse_position()
	var origin := _camera.project_ray_origin(mouse)
	var normal := _camera.project_ray_normal(mouse)
	if absf(normal.z) < 0.001:
		return
	# The course is the plane z = 0: the pointer aims at where its ray crosses it.
	_aim_point = origin + normal * (-origin.z / normal.z)
	var from := _thrower.hand()
	var direction := (_aim_point - from).normalized()
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * AIM_RANGE, SOLIDS)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var mark := from + direction * AIM_RANGE
	if hit.is_empty():
		_aim_note = "дальше %d м нет ничего" % roundi(AIM_RANGE)
	else:
		mark = hit.position
		var body: CollisionObject3D = hit.collider
		var surface: PhysicsMaterial = body.get("physics_material_override")
		_aim_note = "" if surface == wood else "не дерево — гвоздь не воткнётся"
	if _nails_counted and _in_hand() <= 0:
		_aim_note = "гвоздей в руке нет — ПКМ вернуть"

	_aim_mark.global_position = mark
	_aim_paint.albedo_color = (Color(0.5, 0.88, 0.54) if _aim_note == ""
			else Color(1.0, 0.54, 0.42))
	var span := mark - from
	_aim_line.global_position = from + span * 0.5
	_aim_line.global_basis = Basis(
			span.normalized().cross(Vector3.BACK),
			span,
			Vector3.BACK)


func _throw() -> void:
	if _nails_counted and _in_hand() <= 0:
		_throw_note = "[color=#ff8a6a]в руке пусто — ПКМ вернуть[/color]"
		return
	var nail: DuoNail = nail_scene.instantiate()
	_shelf.add_child(nail)
	nail.launch(_thrower.hand(), _aim_point - _thrower.hand(), THROW_SPEEDS[_throw_step])
	nail.stuck.connect(_on_nail_stuck)
	nail.missed.connect(_on_nail_missed)
	nail.gone.connect(_on_nail_gone.bind(nail))
	_nails.append(nail)


func _recall() -> void:
	for nail in _nails:
		nail.recall(_thrower)
	# A nail pulled out of the wood drops whoever hangs from it at once, not when it is back.
	if _held != null:
		_swinger.release()


func _toggle_grab() -> void:
	if _swinger.hanging:
		_swinger.release()
		return
	var best: DuoNail = null
	var best_distance := _swinger.reach
	for nail in _nails:
		var distance := nail.tip().distance_to(_swinger.hand())
		if nail.state == DuoNail.State.STUCK and distance <= best_distance:
			best = nail
			best_distance = distance
	if best == null:
		_missed_grabs += 1
		_swing_note = "[color=#ff8a6a]не за что схватиться: гвоздя ближе %.1f м нет[/color]" % (
			_swinger.reach)
		return
	_swinger.grab(best.tip())
	_held = best
	if _released_at >= 0.0:
		_handoffs += 1
		_swing_note = "от гвоздя до гвоздя %.2f с" % (_clock - _released_at)
	_released_at = -1.0


func _follow(delta: float) -> void:
	var a := _thrower.global_position
	var b := _swinger.global_position
	var middle := (a + b) * 0.5
	var distance := clampf(
			CAMERA_NEAR + absf(a.x - b.x) * CAMERA_SPREAD, CAMERA_NEAR, CAMERA_FAR)
	var goal := Vector3(middle.x, maxf(middle.y, 0.0) + CAMERA_RISE, distance)
	_camera.global_position = _camera.global_position.lerp(goal, 1.0 - exp(-4.0 * delta))
	_camera.look_at(
			Vector3(_camera.global_position.x, _camera.global_position.y - CAMERA_RISE * 0.7, 0.0),
			Vector3.UP)


func _account(delta: float) -> void:
	if _held != null and not _swinger.hanging:
		_held = null
		_released_at = _clock
	if _swinger.is_on_floor():
		_finish_handoff()
		_released_at = -1.0
	if not _started or _finished_at >= 0.0:
		return
	_clock += delta
	if _at_pit(_thrower):
		_waited[0] += delta
	if _at_pit(_swinger):
		_waited[1] += delta
		if not _nail_ahead():
			_without_anchor += delta
	var inside := _goal.get_overlapping_bodies()
	if inside.has(_thrower) and inside.has(_swinger):
		_finished_at = _clock


## Standing on ground with nothing under the next step forward.
func _at_pit(body: DuoBody) -> bool:
	if not body.is_on_floor():
		return false
	var probe := body.global_position + Vector3(EDGE_AHEAD, 0.5, 0.0)
	var query := PhysicsRayQueryParameters3D.create(
			probe, probe + Vector3.DOWN * EDGE_DEPTH, SOLIDS)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _nail_ahead() -> bool:
	var ahead := false
	for nail in _nails:
		var gap := nail.tip().x - _swinger.global_position.x
		if (nail.state == DuoNail.State.STUCK and gap > 0.0
				and nail.tip().distance_to(_swinger.hand()) <= _swinger.reach):
			ahead = true
	return ahead


## A release followed by landing or respawn did not become an airborne handoff.
## This includes deliberate landings; the counter measures outcomes, not player intent.
func _finish_handoff() -> void:
	if _released_at >= 0.0:
		_failed_handoffs += 1
	_released_at = -1.0


func _in_hand() -> int:
	return NAILS_IN_HAND - _nails.size()


func _restart() -> void:
	_thrower.restart()
	_swinger.restart()
	for nail in _nails:
		nail.queue_free()
	_nails.clear()
	_held = null
	for node in _levers.get_children():
		var lever: DuoLever = node
		lever.reset()
	for node in _bridges.get_children():
		var bridge: DuoBridge = node
		bridge.fold()
	_clock = 0.0
	_started = false
	_finished_at = -1.0
	_released_at = -1.0
	_waited = PackedFloat32Array([0.0, 0.0])
	_without_anchor = 0.0
	_handoffs = 0
	_missed_grabs = 0
	_failed_handoffs = 0
	_throw_note = "—"
	_swing_note = "—"


func _apply_knobs() -> void:
	_swinger.pump = PUMPS[_pump_step]
	for action in STICK_ACTIONS:
		InputMap.action_set_deadzone(action, DEADZONES[_deadzone_step])


func _pick_pad() -> void:
	var pads := Input.get_connected_joypads()
	_pad = pads[0] if not pads.is_empty() else -1


func _readout() -> void:
	var share := func(seconds: float) -> String:
		return "%d%%" % roundi(100.0 * seconds / _clock) if _clock > 0.0 else "—"
	var laid := 0
	for node in _bridges.get_children():
		var bridge: DuoBridge = node
		if bridge.laid:
			laid += 1
	var lines := PackedStringArray([
		"метатель: ждёт у пропасти %s   в руке %s   бросок: %s" % [
			share.call(_waited[0]),
			"%d из %d" % [_in_hand(), NAILS_IN_HAND] if _nails_counted else "без счёта",
			_throw_note],
		"качается: у края %s, без доступного гвоздя %s   %s" % [
			share.call(_waited[1]), share.call(_without_anchor), _swing_note],
		"перехватов %d, отпусканий без перехвата %d, пустых хватов %d" % [
			_handoffs, _failed_handoffs, _missed_grabs],
		"мостов опущено %d из %d   дошли оба: %s   %s" % [
			laid, _bridges.get_child_count(),
			"[color=#7fe08a]да, за %.1f с[/color]" % _finished_at if _finished_at >= 0.0
				else "нет",
			_pad_line()],
		"прицел: %s" % ("в дерево" if _aim_note == "" else "[color=#ff8a6a]%s[/color]" % _aim_note),
		"",
		"WASD ПРОБЕЛ идти   ЛКМ гвоздь   ПКМ вернуть все   стик, A прыжок, X схватиться   R заново",
		"1 гвоздь: %s" % ["летит 25 м/с", "летит 60 м/с", "долетает мгновенно"][_throw_step],
		"2 гвоздей в руке: %s" % ("три" if _nails_counted else "без счёта"),
		"3 раскачка стиком: %s" % ["слабая, 2 м/с²", "средняя, 4 м/с²", "сильная, 8 м/с²"][
			_pump_step],
		"4 мёртвая зона стика: %.2f" % DEADZONES[_deadzone_step],
		"TAB клавиатура: %s" % ("у качающегося — WASD, ПРОБЕЛ, E схватиться"
			if _keyboard_on_swinger else "у метателя"),
		"",
		"[color=#66ccff]%s[/color]" % VERDICT,
	])
	_hud.text = "\n".join(lines)


func _pad_line() -> String:
	var news := "   [color=#ff8a6a]%s[/color]" % _pad_news if _pad_news != "" else ""
	if _pad < 0:
		return "[color=#ffd479]геймпада нет — TAB отдаст клавиатуру качающемуся[/color]%s" % news
	return "%s%s" % [Input.get_joy_name(_pad), news]


func _on_nail_stuck(flight: float) -> void:
	_throw_note = "воткнулся, летел %.2f с" % flight


func _on_nail_missed(why: String) -> void:
	_throw_note = "[color=#ff8a6a]%s[/color]" % why


func _on_nail_gone(nail: DuoNail) -> void:
	_nails.erase(nail)
	if nail == _held:
		_swinger.release()
		_held = null


func _on_joy_connection_changed(_device: int, connected: bool) -> void:
	_pick_pad()
	_pad_news = "геймпад %s на %.0f с попытки" % [
		"подключился" if connected else "отключился", _clock]


func _on_swinger_respawned() -> void:
	# Respawn may precede the rig's next frame, while it still remembers the held nail.
	if _held != null:
		_released_at = _clock
		_held = null
	_finish_handoff()
