extends Node3D
class_name StuffRig
## РУКИ, КАМЕРА И РУЧКИ.
##
## Камера и интерфейс принадлежат ригу; предметы о них не знают и ввод не читают.
##
## Ручки здесь — про закон, а не про удобство. Главная пара: СНАРЯД и МАТЕРИАЛ. У снаряда
## своя пара, независимая: энергия решает, на сколько кусков, импульс — как далеко они
## улетят. Винтовочная пуля колет и не толкает, ракета выносит стену — и это не «сильнее», а
## другое соотношение двух величин.

const RANGE := 90.0
const RATE := 0.18
const TOUGH := [0.5, 1.0, 2.0]

## Чем стрелять. Ставится в сцене, как материалы на предметах: снаряд — такой же ресурс.
@export var rounds: Array[StuffRound] = []

var shots := 0

var _clock := 0.0
var _next := 0.0
var _yaw := 0.0
var _pitch := -0.07
var _r := 0
var _t := 1
var _flat := false
var _deep := 3
var _say := "—"
var _frame_ms := 0.0
var _peak := 0.0

@onready var _cam: Camera3D = $Camera
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


## Ручки доходят до предметов ЧЕРЕЗ ГРУППУ, а не через имена узлов: осколки рождаются на
## ходу, и знать их поимённо нельзя в принципе.
func _apply() -> void:
	for n in get_tree().get_nodes_in_group("solid"):
		var s := n as StuffSolid
		if s == null:
			continue
		s.toughness_scale = TOUGH[_t]
		s.grain_flat = _flat
		s.max_depth = _deep


func _shoot() -> void:
	shots += 1
	var from := _cam.global_position
	var dir := -_cam.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * RANGE)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		return
	var s := r["collider"] as StuffSolid
	if s == null or rounds.is_empty():
		return
	s.toughness_scale = TOUGH[_t]
	s.grain_flat = _flat
	s.max_depth = _deep
	if not s.shattered.is_connected(_on_shattered):
		s.shattered.connect(_on_shattered)
	var lim := s.limit()
	var kind: String = s.stuff.title if s.stuff != null else "?"
	var shot: StuffRound = rounds[_r]
	s.hit(r["position"], dir, shot)
	if is_instance_valid(s):
		_say = "[b]%s[/b] (глубина %d, %.2f м³): накоплено %.0f из %.0f Дж — держится" % [
			kind, s.depth, s.volume, s.soaked, lim]


func _on_shattered(what: StuffSolid, born: Array, kept: float, ms: float) -> void:
	var kind: String = what.stuff.title if what.stuff != null else "?"
	var want := what.stuff.pieces(what.soaked / TOUGH[_t], what.volume, 1 << 20)
	_say = ("[b]%s[/b] (глубина %d, %.2f м³): %.0f Дж при пороге %.0f — [b]%d[/b] кусков"
		+ "   закон обещал %d, потолок %d   объём %.2f%%   %.1f мс") % [
		kind, what.depth, what.volume, what.soaked, what.limit(), born.size(),
		want, what.most, kept * 100.0, ms]


func _unhandled_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= mm.relative.x * 0.0032
		_pitch = clampf(_pitch - mm.relative.y * 0.0032, -1.5, 1.5)
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.keycode:
			KEY_1: _r = (_r + 1) % maxi(rounds.size(), 1)
			KEY_2: _t = (_t + 1) % TOUGH.size()
			KEY_3: _flat = not _flat
			KEY_4: _deep = 0 if _deep > 0 else 3
			KEY_TAB: get_tree().reload_current_scene()
		_apply()
	elif event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _readout() -> void:
	if rounds.is_empty():
		return
	var shot: StuffRound = rounds[_r]
	var bodies := get_tree().get_nodes_in_group("solid").size()
	_hud.text = "\n".join(PackedStringArray([
		_say,
		"тел %d   выстрелов %d   кадр %.1f мс   худший %.1f   физика %.1f мс   пар %d" % [
			bodies, shots, _frame_ms, _peak * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))],
		"",
		"WASD лететь   SHIFT быстрее   ПРОБЕЛ вверх   ЛКМ огонь   TAB заново",
		"1 снаряд: [b]%s[/b]   калибр %.0f мм   энергия %.0f Дж   импульс %.0f кг·м/с" % [
			shot.title, shot.calibre * 1000.0, shot.energy, shot.momentum],
		"2 вязкость: ×%.1f от паспортной" % TOUGH[_t],
		"3 узор: %s" % ("ПРИНУДИТЕЛЬНО щебень" if _flat else "как у материала"),
		"4 повторный скол: %s" % ("до 3 раз" if _deep > 0 else "выключен"),
		"",
		"[color=#66ccff]у материала: прочность решает, сломается ли, вязкость — на сколько"
			+ " кусков. у снаряда: энергия — на сколько кусков, импульс — как далеко они"
			+ " улетят, калибр — размер воронки.[/color]",
	]))
