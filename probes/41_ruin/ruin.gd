class_name RuinRig
extends Node3D
## РУКИ, КАМЕРА И РУЧКИ.
##
## По соглашению камера и интерфейс принадлежат ригу; элементы здания о них не знают и ввод
## не читают — им сообщают воздействие вызовом `hit()`.
##
## Главная ручка — не сила и не порог, а СХЕМА. Суставы против графа опоры: два ответа на
## один вопрос, и переключатель между ними и есть проба.

## Дальность выстрела в метрах.
const RANGE := 90.0
## Пауза между выстрелами в секундах.
const RATE := 0.15
const SCHEMES := ["граф опоры", "суставы", "граф с нагрузкой"]
const SAFETY_STEPS := [1.2, 1.5, 2.0, 3.0]
const FLY_SPEED := 6.0
const FLY_FAST := 14.0
const MOUSE_SENSITIVITY := 0.0032

@export var blast_radius := 4.0
@export var blast_force := 900.0
@export var bullet_hurt := 14.0
@export var bullet_force := 90.0

var shots := 0

## СТРОИТЬ НАДО НЕ В `_ready`, А НА ПЕРВОМ ТИКЕ. Пока физический сервер ещё не крутится,
## создание каждого тела и каждого сустава упирается в синхронизацию: семь элементов
## строились 574 мс, двадцать один сустав — шесть секунд. На живом сервере ровно то же
## самое занимает 1.6 и 1.3 мс. Разница в сотни раз, и никакого предупреждения.
var _pending := true
var _clock := 0.0
var _next_shot := 0.0
var _yaw := 0.0
var _pitch := -0.12
var _blast := true
var _show_graph := false
## 0 — граф опоры, 1 — суставы, 2 — граф с нагрузкой.
var _scheme := 0
var _peak_frame := 0.0
var _frame_ms := 0.0

@onready var _frame: RuinFrame = $Frame
@onready var _camera: Camera3D = $Camera
@onready var _hud: RichTextLabel = $Ui/Info


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(_delta: float) -> void:
	if _pending:
		_pending = false
		_frame.build(_scheme)
		return
	_frame.snap_joints()
	# В схеме суставов связность считается только чтобы ПОКАЗАТЬ, кто повис: ронять там
	# должна физика, иначе сравнение схем теряет смысл.
	if _show_graph:
		_frame.mark_supported(true)
	elif _scheme != 1:
		_frame.drop_unsupported()
		# Нагрузка считается ПОСЛЕ связности: сперва падает то, у чего нет опоры вовсе,
		# и лишь потом смотрим, кому из оставшихся стало слишком тяжело.
		_frame.stress()


func _process(delta: float) -> void:
	_clock += delta
	# Сглаженный кадр плюс худший с последней перестройки: пик обрушения проскакивает
	# за один кадр, и без запоминания его просто не увидеть.
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
			_scheme = (_scheme + 1) % SCHEMES.size()
			_rebuild()
		KEY_2:
			_blast = not _blast
		KEY_3:
			_show_graph = not _show_graph
			if not _show_graph:
				_frame.mark_supported(false)
		KEY_4:
			_frame.snap = 0.35 if _frame.snap < 0.2 else 0.12
		KEY_5:
			var step := SAFETY_STEPS.find(snappedf(_frame.safety, 0.1))
			_frame.safety = (
					SAFETY_STEPS[(step + 1) % SAFETY_STEPS.size()] if step >= 0 else 1.5)
			_rebuild()
		KEY_TAB:
			_rebuild()


func _shoot() -> void:
	shots += 1
	var from := _camera.global_position
	var direction := -_camera.global_basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * RANGE)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var at: Vector3 = hit["position"]
	if _blast:
		_explode(at)
		return
	var piece := hit["collider"] as RuinPiece
	if piece != null:
		piece.hit(at, direction, bullet_force, bullet_hurt)


## ЗАРЯД. Бьёт по всем элементам в радиусе — и по стоящим, и по уже падающим. Именно он
## показывает разницу схем: выбитая колонна в графе роняет всё, что над ней, мгновенно, а на
## суставах здание сначала оседает и только потом решает, падать ему или нет.
func _explode(at: Vector3) -> void:
	var tree := get_tree()
	for node in tree.get_nodes_in_group("piece") + tree.get_nodes_in_group("debris"):
		var piece := node as RuinPiece
		if piece == null or not is_instance_valid(piece):
			continue
		var away := piece.global_position - at
		var apart := away.length()
		if apart > blast_radius:
			continue
		var falloff := 1.0 - apart / blast_radius
		piece.hit(
				at + away.normalized() * apart * 0.5,
				away.normalized(),
				blast_force * falloff,
				60.0 * falloff)


func _rebuild() -> void:
	shots = 0
	_peak_frame = 0.0
	_pending = true


func _readout() -> void:
	var standing := _frame.standing_count()
	var debris := get_tree().get_nodes_in_group("debris").size()
	_hud.text = "\n".join(PackedStringArray([
		"схема: [b]%s[/b]   стоит %d из %d   упало %d   выстрелов %d" % [
			SCHEMES[_scheme].to_upper(), standing, _frame.pieces.size(), debris, shots],
		"кадр [b]%.1f[/b] мс   худший %.1f   физика %.1f мс   тел %d, пар %d   суставов %d" % [
			_frame_ms, _peak_frame * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
			int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)),
			_frame.joints.size()],
		"",
		"WASD лететь   SHIFT быстрее   ПРОБЕЛ вверх   ЛКМ огонь   TAB перестроить",
		"1 схема: %s" % SCHEMES[_scheme],
		"2 чем бить: %s" % ("заряд" if _blast else "пуля"),
		"3 показать опору: %s   (зелёный — путь до земли есть, красный — нет)" % (
			"вкл" if _show_graph else "выкл"),
		"4 порог разрыва сустава: %.2f м" % _frame.snap,
		"5 запас прочности: ×%.1f   (во сколько раз держит больше, чем несёт)" %
			_frame.safety,
		"",
		"[color=#66ccff]суставы спрашивают «растянулось ли». граф опоры — «есть ли путь"
			+ " до земли». нагрузка — «сколько на мне лежит».[/color]",
	]))
