class_name VoroRig
extends Node3D
## РУКИ, КАМЕРА И РУЧКИ.
##
## Камера и интерфейс принадлежат ригу; предметы о них не знают и ввод не читают.
##
## Главная ручка здесь — не сила выстрела, а ЧИСЛО ЯЧЕЕК. Вопрос, ради которого проба и
## затеяна, звучит так: сколько осколков можно себе позволить, чтобы кадр остался живым.
## Ответ на него решает судьбу мультипробы «здание + пушка + скол».

## Дальность выстрела в метрах.
const RANGE := 90.0
## Пауза между выстрелами в секундах.
const RATE := 0.16
const COUNTS := [8, 16, 32, 64, 128]
const SPREAD_STEP := 0.35
const FLY_SPEED := 6.0
const FLY_FAST := 16.0
const MOUSE_SENSITIVITY := 0.0032

@export var bullet_hurt := 18.0
@export var bullet_force := 26.0

var shots := 0

## Показ разреза строит тела, а тела до первого тика стоят в сотни раз дороже.
var _pending := true
var _clock := 0.0
var _next_shot := 0.0
var _yaw := 0.0
var _pitch := -0.15
var _count := 2
var _bias := true
var _spread := 0.0
var _last_cells := 0
var _last_kept := 0.0
var _last_ms := 0.0
var _peak_frame := 0.0
var _frame_ms := 0.0

@onready var _camera: Camera3D = $Camera
@onready var _hud: RichTextLabel = $Ui/Info
@onready var _show: VoroSolid = $Show


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for node in get_tree().get_nodes_in_group("solid"):
		(node as VoroSolid).shattered.connect(_on_solid_shattered)


func _physics_process(_delta: float) -> void:
	if not _pending:
		return
	_pending = false
	_show.cells = COUNTS[_count]
	_show.bias = 0.0
	_show.shatter(_show.global_position, Vector3.UP, 0.0)
	_show.spread(_spread)


func _process(delta: float) -> void:
	_clock += delta
	_frame_ms = lerpf(_frame_ms, delta * 1000.0, 0.15)
	_peak_frame = maxf(_peak_frame, delta)
	var speed := FLY_FAST if Input.is_key_pressed(KEY_SHIFT) else FLY_SPEED
	var direction := _camera.global_basis * Vector3(
			Input.get_action_strength(&"move_right")
				- Input.get_action_strength(&"move_left"),
			0.0,
			Input.get_action_strength(&"move_back")
				- Input.get_action_strength(&"move_forward"))
	if Input.is_action_pressed(&"jump"):
		direction += Vector3.UP
	_camera.global_position += direction * speed * delta
	_camera.rotation = Vector3(_pitch, _yaw, 0.0)

	if Input.is_action_pressed(&"fire") and _clock >= _next_shot:
		_next_shot = _clock + RATE
		_shoot()
	_readout()


func _unhandled_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= motion.relative.x * MOUSE_SENSITIVITY
		_pitch = clampf(_pitch - motion.relative.y * MOUSE_SENSITIVITY, -1.5, 1.5)
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		_apply_key(key.keycode)
	elif event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _apply_key(keycode: Key) -> void:
	match keycode:
		KEY_1:
			_count = (_count + 1) % COUNTS.size()
			_reset()
		KEY_2:
			_bias = not _bias
		KEY_3:
			_spread = 0.0 if _spread > 0.6 else _spread + SPREAD_STEP
			_show.spread(_spread)
		KEY_4:
			_freeze_loose_shards()
		KEY_TAB:
			_reset()


func _shoot() -> void:
	shots += 1
	var from := _camera.global_position
	var direction := -_camera.global_basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * RANGE)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var solid := hit["collider"] as VoroSolid
	if solid == null:
		return
	solid.cells = COUNTS[_count]
	solid.bias = 0.7 if _bias else 0.0
	solid.hit(hit["position"], direction, bullet_force, bullet_hurt)


## Осколки показа разреза заморожены навсегда — они и есть показ; трогается только то,
## что осыпалось от выстрела.
func _freeze_loose_shards() -> void:
	for node in get_tree().get_nodes_in_group("shard"):
		var body := node as RigidBody3D
		if body in _show.shards:
			continue
		body.freeze = not body.freeze


func _reset() -> void:
	shots = 0
	_peak_frame = 0.0
	get_tree().reload_current_scene()


func _readout() -> void:
	var shards := get_tree().get_nodes_in_group("shard").size()
	var solids := get_tree().get_nodes_in_group("solid").size()
	_hud.text = "\n".join(PackedStringArray([
		"ячеек на скол [b]%d[/b]   целых предметов %d   осколков %d   выстрелов %d" % [
			COUNTS[_count], solids, shards, shots],
		"последний скол: [b]%d[/b] ячеек за [b]%.1f[/b] мс   объём сохранён на [b]%.2f%%[/b]" % [
			_last_cells, _last_ms, _last_kept * 100.0],
		"кадр %.1f мс   худший %.1f   физика %.1f мс   тел %d, пар %d" % [
			_frame_ms, _peak_frame * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
			int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))],
		"",
		"WASD лететь   SHIFT быстрее   ПРОБЕЛ вверх   ЛКМ огонь   TAB заново",
		"1 ячеек на скол: %d" % COUNTS[_count],
		"2 зёрна: %s" % ("гуще у попадания" if _bias else "равномерно"),
		"3 развести показ: %.0f%%   (на нуле куски складываются в предмет)" % (_spread * 100.0),
		"4 заморозить осколки",
		"",
		"[color=#66ccff]объём сохранён — значит куски получены разрезанием предмета, а не"
			+ " выдуманы рядом с ним.[/color]",
	]))


func _on_solid_shattered(cells: int, kept: float, spent_ms: float) -> void:
	_last_cells = cells
	_last_kept = kept
	_last_ms = spent_ms
