class_name StuffRig
extends Node3D
## РУКИ, КАМЕРА И РУЧКИ.
##
## Камера и интерфейс принадлежат ригу; предметы о них не знают и ввод не читают.
##
## Ручки здесь — про закон, а не про удобство. Главная пара: СНАРЯД и МАТЕРИАЛ. У снаряда
## своя пара, независимая: энергия решает, на сколько кусков, импульс — как далеко они
## улетят. Винтовочная пуля колет и не толкает, ракета выносит стену — и это не «сильнее», а
## другое соотношение двух величин.

## Дальность выстрела в метрах.
const RANGE := 90.0
## Пауза между выстрелами в секундах.
const RATE := 0.18
## Во сколько раз вязкость отличается от паспортной.
const TOUGH := [0.5, 1.0, 2.0]
const MAX_DEPTH := 3
const FLY_SPEED := 6.0
const FLY_FAST := 16.0
const MOUSE_SENSITIVITY := 0.0032

## Чем стрелять. Ставится в сцене, как материалы на предметах: снаряд — такой же ресурс.
@export var rounds: Array[StuffRound] = []

var shots := 0

var _clock := 0.0
var _next_shot := 0.0
var _yaw := 0.0
var _pitch := -0.07
var _round := 0
var _tough := 1
var _grain_flat := false
var _depth := MAX_DEPTH
var _say := "—"
var _frame_ms := 0.0
var _peak_frame := 0.0

@onready var _camera: Camera3D = $Camera
@onready var _hud: RichTextLabel = $Ui/Info


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_apply()


func _process(delta: float) -> void:
	_clock += delta
	_frame_ms = lerpf(_frame_ms, delta * 1000.0, 0.15)
	# Первый кадр сцены всегда стоит сотню миллисекунд, и худший, включающий загрузку,
	# не сообщает ничего. Считаем с секунды.
	if _clock > 1.0:
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
		_apply()
	elif event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _apply_key(keycode: Key) -> void:
	match keycode:
		KEY_1:
			_round = (_round + 1) % maxi(rounds.size(), 1)
		KEY_2:
			_tough = (_tough + 1) % TOUGH.size()
		KEY_3:
			_grain_flat = not _grain_flat
		KEY_4:
			_depth = 0 if _depth > 0 else MAX_DEPTH
		KEY_TAB:
			get_tree().reload_current_scene()


## Ручки доходят до предметов ЧЕРЕЗ ГРУППУ, а не через имена узлов: осколки рождаются на
## ходу, и знать их поимённо нельзя в принципе.
func _apply() -> void:
	for node in get_tree().get_nodes_in_group("solid"):
		var solid := node as StuffSolid
		if solid == null:
			continue
		_tune(solid)


func _tune(solid: StuffSolid) -> void:
	solid.toughness_scale = TOUGH[_tough]
	solid.grain_flat = _grain_flat
	solid.max_depth = _depth


func _shoot() -> void:
	shots += 1
	var from := _camera.global_position
	var direction := -_camera.global_basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * RANGE)
	var found := get_world_3d().direct_space_state.intersect_ray(query)
	if found.is_empty():
		return
	var solid := found["collider"] as StuffSolid
	if solid == null or rounds.is_empty():
		return
	_tune(solid)
	if not solid.shattered.is_connected(_on_solid_shattered):
		solid.shattered.connect(_on_solid_shattered)
	var threshold := solid.limit()
	var kind: String = solid.stuff.title if solid.stuff != null else "?"
	var shot: StuffRound = rounds[_round]
	solid.hit(found["position"], direction, shot)
	if is_instance_valid(solid):
		_say = "[b]%s[/b] (глубина %d, %.2f м³): накоплено %.0f из %.0f Дж — держится" % [
			kind, solid.depth, solid.volume, solid.soaked, threshold]


func _readout() -> void:
	if rounds.is_empty():
		return
	var shot: StuffRound = rounds[_round]
	var bodies := get_tree().get_nodes_in_group("solid").size()
	_hud.text = "\n".join(PackedStringArray([
		_say,
		"тел %d   выстрелов %d   кадр %.1f мс   худший %.1f   физика %.1f мс   пар %d" % [
			bodies, shots, _frame_ms, _peak_frame * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))],
		"",
		"WASD лететь   SHIFT быстрее   ПРОБЕЛ вверх   ЛКМ огонь   TAB заново",
		"1 снаряд: [b]%s[/b]   калибр %.0f мм   энергия %.0f Дж   импульс %.0f кг·м/с" % [
			shot.title, shot.calibre * 1000.0, shot.energy, shot.momentum],
		"2 вязкость: ×%.1f от паспортной" % TOUGH[_tough],
		"3 узор: %s" % ("ПРИНУДИТЕЛЬНО щебень" if _grain_flat else "как у материала"),
		"4 повторный скол: %s" % ("до 3 раз" if _depth > 0 else "выключен"),
		"",
		"[color=#66ccff]у материала: прочность решает, сломается ли, вязкость — на сколько"
			+ " кусков. у снаряда: энергия — на сколько кусков, импульс — как далеко они"
			+ " улетят, калибр — размер воронки.[/color]",
	]))


func _on_solid_shattered(
		what: StuffSolid,
		born: Array,
		kept: float,
		spent_ms: float) -> void:
	var kind: String = what.stuff.title if what.stuff != null else "?"
	var want := what.stuff.pieces(what.soaked / TOUGH[_tough], what.volume, 1 << 20)
	_say = ("[b]%s[/b] (глубина %d, %.2f м³): %.0f Дж при пороге %.0f — [b]%d[/b] кусков"
		+ "   закон обещал %d, потолок %d   объём %.2f%%   %.1f мс") % [
		kind, what.depth, what.volume, what.soaked, what.limit(), born.size(),
		want, what.most, kept * 100.0, spent_ms]
