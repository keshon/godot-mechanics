class_name MoveCourse
extends Node3D
## ТРАССА И СЕКУНДОМЕР.
##
## Движению нужна причина двигаться. Без неё «пощупать акробатику» превращается в бег по
## пустой комнате, где всё одинаково хорошо. Трасса задаёт задачу, секундомер — число, а
## выключатели слоёв позволяют увидеть, сколько стоит каждый.
##
## Сама трасса лежит в отдельной сцене, а не собирается кодом: расстояния на ней —
## параметры механики (провал 3.5 м потому, что прыжок берёт 4.6; стена 14 м потому, что
## таймер бега 1.7 с при 9.2 м/с даёт 15.6), и числа эти живут в заметке, а геометрия —
## там, где её видно и можно двигать мышью.

## КОНТРОЛЬНЫЕ ТОЧКИ читаются из сцены — маркерами, а не константами. Упал —
## возвращаешься на последнюю пройденную, а не в начало: трасса про механику, а не про
## наказание.
var checks: Array[Vector3] = []

var time := 0.0
var best := -1.0
var running := false
var done := false
var checkpoint := 0

var _spawn := Vector3(0.0, 1.2, 2.0)

@onready var _player: MovePlayer = $Player
@onready var _marks: Node3D = $Course/Checks
@onready var _start: Area3D = $Course/Start
@onready var _finish: Area3D = $Course/Finish
@onready var _label: RichTextLabel = $Ui/Label


func _ready() -> void:
	for mark in _marks.get_children():
		var marker: Node3D = mark
		checks.append(marker.position)
	# Ворота — настоящие Area3D из сцены: срабатывание по объёму даёт и вход сбоку, и
	# вход в прыжке, и не зависит от частоты кадров.
	_start.body_entered.connect(_on_start_body_entered)
	_finish.body_entered.connect(_on_finish_body_entered)
	_reset()


func _process(delta: float) -> void:
	if running:
		time += delta
	var along := _player.global_position.z
	for i in checks.size():
		if along <= checks[i].z + 3.0 and i > checkpoint:
			checkpoint = i
	if _player.global_position.y < -8.0:
		_respawn()
	_draw_hud()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_1:
			_player.air_control = not _player.air_control
		KEY_2:
			_player.coyote = not _player.coyote
		KEY_3:
			_player.buffer = not _player.buffer
		KEY_4:
			_player.variable_jump = not _player.variable_jump
		KEY_5:
			_player.wall_run = not _player.wall_run
		KEY_6:
			_player.dash = not _player.dash
		KEY_7:
			_player.mantle = not _player.mantle
		KEY_8:
			_player.slide = not _player.slide
		KEY_9:
			_player.double_jump = not _player.double_jump
		KEY_0:
			for layer in [
				"air_control", "coyote", "buffer", "variable_jump", "wall_run",
				"dash", "mantle", "slide", "double_jump",
			]:
				_player.set(layer, true)
		KEY_R:
			_reset()


func _respawn() -> void:
	_player.global_position = checks[checkpoint]
	_player.velocity = Vector3.ZERO


func _reset() -> void:
	running = false
	done = false
	checkpoint = 0
	time = 0.0
	_player.global_position = _spawn
	_player.velocity = Vector3.ZERO


func _row(on: bool, key: String, text: String) -> String:
	var tint := "88ff99" if on else "666666"
	return "[color=#%s]%s\t%s[/color]\n" % [tint, key, text]


func _draw_hud() -> void:
	var text := "[font_size=34][b]%.1f[/b][/font_size] м/с   %s\n" % [
		_player.speed, _player.state]
	text += "время [b]%.2f[/b]" % time
	if best >= 0.0:
		text += "   лучшее [color=#ffd479]%.2f[/color]" % best
	if done:
		text += "   [color=#7fe08a]ФИНИШ[/color]"
	text += "\n\n"
	text += _row(
			_player.air_control, "1",
			"воздушное управление (разгон доворотом — Quake)")
	text += _row(_player.coyote, "2", "койот-тайм: %.0f мс после схода с края" % (
			_player.coyote_time * 1000.0))
	text += _row(_player.buffer, "3", "буфер прыжка: %.0f мс до приземления" % (
			_player.buffer_time * 1000.0))
	text += _row(_player.variable_jump, "4", "переменная высота: отпустил рано — ниже")
	text += _row(_player.wall_run, "5", "бег по стене (порог %.1f м/с)" % (
			_player.wall_min_speed))
	text += _row(_player.dash, "6", "рывок [%s]" % (
			"готов" if _player.dash_ready >= 1.0
			else "%.0f%%" % (_player.dash_ready * 100.0)))
	text += _row(_player.mantle, "7", "подтягивание на уступ")
	text += _row(_player.slide, "8", "скольжение")
	text += _row(_player.double_jump, "9", "двойной прыжок [%s]" % (
			"есть" if _player.air_jumps_left > 0 else "потрачен"))
	text += "\nWASD — бег   ПРОБЕЛ — прыжок   SHIFT — рывок   CTRL — скольжение\n"
	text += "1…9 — слои по одному   0 — включить всё   R — заново   ESC — мышь\n"
	if checkpoint >= 5:
		text += "[color=#ffd479]арена: рывок с зажатым боком и доворотом мыши — дуга"
		text += "[/color]\n"
	text += "[color=#66ccff]три верхних слоя невидимы — "
	text += "их замечаешь только когда их нет[/color]"
	_label.text = text


func _on_start_body_entered(body: Node3D) -> void:
	if body != _player or running or done:
		return
	running = true
	time = 0.0


func _on_finish_body_entered(body: Node3D) -> void:
	if body != _player or not running:
		return
	running = false
	done = true
	if best < 0.0 or time < best:
		best = time
