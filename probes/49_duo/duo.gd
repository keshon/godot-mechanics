class_name DuoRig
extends Node3D
## TWO PEOPLE, TWO DEVICES, TWO VERBS, ONE SCREEN.
##
## The mouse builds: a click raises a platform where the pointer rests. The stick runs and jumps.
## Neither verb is enough alone — the top is out of jumping reach, and nobody on the mouse side
## has a body to put up there — and the knobs switch off the ties between them one by one, so what
## each tie is worth can be read off the readout rather than guessed.
##
## WAITING IS MEASURED, not judged. Every second a player's device is silent past the first one
## counts as waiting, and the readout shows the share per player. Silence is not quite the same as
## having nothing to do — somebody may be thinking — which is why the first second of every
## silence is forgiven.
##
## Devices split by class and need no numbering: the builder is whatever moves the mouse, the
## runner is whatever drives the `run_*` actions, and those carry both a stick and WASD. One
## pad is enough to tell two people apart; a second pad would need device ids, and that is not this
## probe.

enum Life {
	FOREVER,
	LONG,
	SHORT,
}

const LIFE_SECONDS: Array[float] = [0.0, 8.0, 4.0]
const DEADZONES: Array[float] = [0.05, 0.2, 0.4]
## The deadzone the project gives the runner actions, restored on leaving.
const DEFAULT_DEADZONE := 0.2
const RUN_ACTIONS: Array[StringName] = [&"run_left", &"run_right", &"run_forward", &"run_back"]
## Seconds of silence forgiven before a player counts as waiting.
const IDLE_AFTER := 1.0
const MAX_CHARGE := 3
const MAX_PLATFORMS := 3
## Physics layers a platform may stand on: the level and other platforms.
const SURFACES := 1 | 2
## A surface this steep or steeper takes no platform: the normal's vertical part below this.
const FLAT_ENOUGH := 0.7
## Height of the ghost block that shows where a click would build, m. The platform scene carries
## its own height; this is only the preview's.
const GHOST_HEIGHT := 1.2
const VERDICT := ("никто не ждёт, пока глагол одного нужен другому: разорви связь ручкой — и"
		+ " простой выходит в процентах")

@export var platform_scene: PackedScene

var _life := Life.SHORT
var _charge_from_sparks := true
var _build_in_light_only := true
var _deadzone_step := 1
var _charge := 1
var _platforms: Array[DuoPlatform] = []
## Seconds since the first input of the attempt; stops at the top.
var _clock := 0.0
var _started := false
var _finished_at := -1.0
## Per player, builder first: seconds counted as waiting, and the current silence.
var _waited := PackedFloat32Array([0.0, 0.0])
var _silent := PackedFloat32Array([0.0, 0.0])
## Seconds the builder had nothing to build with.
var _dry := 0.0
var _pad := -1
var _pad_news := ""
var _mouse_moved := false
var _running := false
## Where a click would build right now, and why it would not, empty when it would.
var _spot := Vector3.ZERO
var _refusal := ""

@onready var _runner: DuoRunner = $Runner
@onready var _camera: Camera3D = $Camera
@onready var _shelf: Node3D = $Platforms
@onready var _sparks: Node3D = $Level/Sparks
@onready var _ghost: MeshInstance3D = $Ghost
@onready var _ghost_paint: StandardMaterial3D = $Ghost.material_override
@onready var _hud: RichTextLabel = $Ui/Info


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_pick_pad()
	_apply_deadzone()


func _exit_tree() -> void:
	# The deadzone lives in the project's InputMap, not in this scene, and would outlive it.
	for action in RUN_ACTIONS:
		InputMap.action_set_deadzone(action, DEFAULT_DEADZONE)


func _process(delta: float) -> void:
	_steer()
	_aim()
	_account(delta)
	_readout()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_moved = true
		return
	if event is InputEventMouseButton:
		var click: InputEventMouseButton = event
		if click.button_index == MOUSE_BUTTON_LEFT and click.pressed:
			_build()
		return
	if event.is_action_pressed(&"respawn"):
		_restart()
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			_life = ((_life + 1) % Life.size()) as Life
		KEY_2:
			_charge_from_sparks = not _charge_from_sparks
		KEY_3:
			_build_in_light_only = not _build_in_light_only
		KEY_4:
			_deadzone_step = (_deadzone_step + 1) % DEADZONES.size()
			_apply_deadzone()


## "Up on the stick" means away from the camera, so the stick is turned by the camera's heading
## before the runner hears it. The runner itself only knows world directions.
func _steer() -> void:
	var stick := Input.get_vector(&"run_left", &"run_right", &"run_back", &"run_forward")
	var forward := -_camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := Vector3(-forward.z, 0.0, forward.x)
	var world := right * stick.x + forward * stick.y
	_runner.move = Vector2(world.x, -world.z)
	_runner.jumping = Input.is_action_pressed(&"run_jump")
	_running = stick != Vector2.ZERO or _runner.jumping


func _aim() -> void:
	var mouse := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mouse)
	var query := PhysicsRayQueryParameters3D.create(
			from, from + _camera.project_ray_normal(mouse) * 200.0, SURFACES)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	_refusal = ""
	if hit.is_empty():
		_refusal = "под указателем ничего нет"
	else:
		var normal: Vector3 = hit.normal
		_spot = hit.position
		if normal.y < FLAT_ENOUGH:
			_refusal = "на стену не встанет — нужна ровная поверхность"
		elif _build_in_light_only and not _runner.lights(_spot):
			_refusal = "вне света бегущего"
		elif _charge_from_sparks and _charge <= 0:
			_refusal = "нет заряда — нужны искры"

	_ghost.visible = not hit.is_empty()
	_ghost.position = _spot + Vector3.UP * GHOST_HEIGHT * 0.5
	_ghost_paint.albedo_color = (Color(0.5, 0.88, 0.54, 0.35) if _refusal == ""
			else Color(1.0, 0.54, 0.42, 0.35))


func _build() -> void:
	if _refusal != "":
		return
	var platform: DuoPlatform = platform_scene.instantiate()
	platform.plant(_spot, LIFE_SECONDS[_life])
	platform.sank.connect(_on_platform_sank.bind(platform))
	_shelf.add_child(platform)
	_platforms.append(platform)
	if _charge_from_sparks:
		_charge -= 1
	# The oldest goes first once there are too many: the builder chooses which to keep by the
	# order of building, never by a refusal.
	if _platforms.size() > MAX_PLATFORMS:
		var oldest: DuoPlatform = _platforms.pop_front()
		oldest.queue_free()


func _account(delta: float) -> void:
	var building := _mouse_moved or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_mouse_moved = false
	if not _started and (building or _running):
		_started = true
	if not _started or _finished_at >= 0.0:
		return
	_clock += delta
	var active := [building, _running]
	for i in 2:
		if active[i]:
			_silent[i] = 0.0
			continue
		_silent[i] += delta
		if _silent[i] > IDLE_AFTER:
			_waited[i] += delta
	if _charge_from_sparks and _charge <= 0:
		_dry += delta


func _restart() -> void:
	_runner.respawn()
	for platform in _platforms:
		platform.queue_free()
	_platforms.clear()
	for node in _sparks.get_children():
		var spark: DuoSpark = node
		spark.reset()
	_charge = 1
	_clock = 0.0
	_started = false
	_finished_at = -1.0
	_waited = PackedFloat32Array([0.0, 0.0])
	_silent = PackedFloat32Array([0.0, 0.0])
	_dry = 0.0


func _apply_deadzone() -> void:
	for action in RUN_ACTIONS:
		InputMap.action_set_deadzone(action, DEADZONES[_deadzone_step])


func _pick_pad() -> void:
	var pads := Input.get_connected_joypads()
	_pad = pads[0] if not pads.is_empty() else -1


func _readout() -> void:
	var share := func(seconds: float) -> String:
		return "%d%%" % roundi(100.0 * seconds / _clock) if _clock > 0.0 else "—"
	var lines := PackedStringArray([
		"на вершине: %s   время %s   заряд %s   платформ %d из %d" % [
			"[color=#7fe08a]да, за %.1f с[/color]" % _finished_at if _finished_at >= 0.0
				else "нет",
			"%.1f с" % _clock if _started else "—",
			"%d из %d" % [_charge, MAX_CHARGE] if _charge_from_sparks else "без счёта",
			_platforms.size(), MAX_PLATFORMS],
		"строит мышью: простой %s   без заряда %s   сюда: %s" % [
			share.call(_waited[0]), share.call(_dry),
			"можно" if _refusal == "" else "[color=#ff8a6a]%s[/color]" % _refusal],
		"бежит: простой %s   %s" % [share.call(_waited[1]), _pad_line()],
		"",
		"ЛКМ поставить платформу   стик или WASD бежать   A или ПРОБЕЛ прыжок   R заново",
		"1 платформа стоит: %s" % ["вечно", "8 с", "4 с"][_life],
		"2 заряд: %s" % ("от искр, которые собирает бегущий" if _charge_from_sparks
			else "без счёта"),
		"3 строить: %s" % ("только в свете бегущего" if _build_in_light_only else "где угодно"),
		"4 мёртвая зона стика: %.2f" % DEADZONES[_deadzone_step],
		"",
		"[color=#66ccff]%s[/color]" % VERDICT,
	])
	_hud.text = "\n".join(lines)


## The stick's raw deflection is shown next to the deadzone: a resting stick that reads 0.1 is
## drift, and a deadzone below it makes the runner creep with nobody touching anything.
func _pad_line() -> String:
	var news := "   [color=#ff8a6a]%s[/color]" % _pad_news if _pad_news != "" else ""
	if _pad < 0:
		return "[color=#ffd479]геймпада нет — бегут WASD и ПРОБЕЛ[/color]%s" % news
	var raw := Vector2(
			Input.get_joy_axis(_pad, JOY_AXIS_LEFT_X),
			Input.get_joy_axis(_pad, JOY_AXIS_LEFT_Y))
	return "%s, стик отклонён на %.2f%s" % [Input.get_joy_name(_pad), raw.length(), news]


func _on_platform_sank(platform: DuoPlatform) -> void:
	_platforms.erase(platform)


func _on_spark_taken() -> void:
	_charge = mini(_charge + 1, MAX_CHARGE)


func _on_goal_body_entered(body: Node3D) -> void:
	if body.is_in_group(&"duo_runner") and _finished_at < 0.0 and _started:
		_finished_at = _clock


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	_pick_pad()
	_pad_news = "геймпад %s на %.0f с попытки" % [
		"подключился" if connected else "отключился", _clock]
	if not connected and device == _pad:
		_pad = -1
