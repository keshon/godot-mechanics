extends Node3D
class_name VoroRig
## РУКИ, КАМЕРА И РУЧКИ.
##
## Камера и интерфейс принадлежат ригу; предметы о них не знают и ввод не читают.
##
## Главная ручка здесь — не сила выстрела, а ЧИСЛО ЯЧЕЕК. Вопрос, ради которого проба и
## затеяна, звучит так: сколько осколков можно себе позволить, чтобы кадр остался живым.
## Ответ на него решает судьбу мультипробы «здание + пушка + скол».

const RANGE := 90.0
const RATE := 0.16
const COUNTS := [8, 16, 32, 64, 128]

@export var bullet_hurt := 18.0
@export var bullet_force := 26.0

var shots := 0

var _clock := 0.0
var _next := 0.0
var _yaw := 0.0
var _pitch := -0.15
var _count := 2
var _bias := true
var _spread := 0.0
var _last_cells := 0
var _last_kept := 0.0
var _last_ms := 0.0
var _peak := 0.0
var _frame_ms := 0.0

@onready var _cam: Camera3D = $Camera
@onready var _hud: RichTextLabel = $Ui/Info
@onready var _show: VoroSolid = $Show

## Показ разреза строит тела, а тела до первого тика стоят в сотни раз дороже.
var _pending := true


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for n in get_tree().get_nodes_in_group("solid"):
		(n as VoroSolid).shattered.connect(_on_shattered)


func _physics_process(_delta: float) -> void:
	if _pending:
		_pending = false
		_show.cells = COUNTS[_count]
		_show.bias = 0.0
		_show.shatter(_show.global_position, Vector3.UP, 0.0)
		_show.spread(_spread)


func _process(delta: float) -> void:
	_clock += delta
	_frame_ms = lerpf(_frame_ms, delta * 1000.0, 0.15)
	_peak = maxf(_peak, delta)
	var speed := 16.0 if Input.is_key_pressed(KEY_SHIFT) else 6.0
	var dir := _cam.global_basis * Vector3(
		Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left"),
		0.0,
		Input.get_action_strength(&"move_back") - Input.get_action_strength(&"move_forward"))
	if Input.is_action_pressed(&"jump"):
		dir += Vector3.UP
	_cam.global_position += dir * speed * delta
	_cam.rotation = Vector3(_pitch, _yaw, 0.0)

	if Input.is_action_pressed(&"fire") and _clock >= _next:
		_next = _clock + RATE
		_shoot()
	_readout()


func _shoot() -> void:
	shots += 1
	var from := _cam.global_position
	var dir := -_cam.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * RANGE)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		return
	var s := r["collider"] as VoroSolid
	if s == null:
		return
	s.cells = COUNTS[_count]
	s.bias = 0.7 if _bias else 0.0
	s.hit(r["position"], dir, bullet_force, bullet_hurt)


func _on_shattered(cells: int, kept: float, ms: float) -> void:
	_last_cells = cells
	_last_kept = kept
	_last_ms = ms


func _unhandled_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= mm.relative.x * 0.0032
		_pitch = clampf(_pitch - mm.relative.y * 0.0032, -1.5, 1.5)
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.keycode:
			KEY_1:
				_count = (_count + 1) % COUNTS.size()
				_reset()
			KEY_2: _bias = not _bias
			KEY_3:
				_spread = 0.0 if _spread > 0.6 else _spread + 0.35
				_show.spread(_spread)
			KEY_4:
				for n in get_tree().get_nodes_in_group("shard"):
					var b := n as RigidBody3D
					if b in _show.shards:
						continue
					b.freeze = not b.freeze
			KEY_TAB: _reset()
	elif event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _reset() -> void:
	shots = 0
	_peak = 0.0
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
			_frame_ms, _peak * 1000.0,
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
