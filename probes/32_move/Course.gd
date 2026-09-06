extends Node3D

## ТРАССА И СЕКУНДОМЕР.
##
## Движению нужна причина двигаться. Без неё «пощупать акробатику» превращается в бег по
## пустой комнате, где всё одинаково хорошо. Трасса задаёт задачу, секундомер — число, а
## выключатели слоёв позволяют увидеть, сколько стоит каждый.
##
## Трасса собрана НЕ руками в сцене, а из таблицы: расстояния тут — параметры механики
## (дальность прыжка, дальность рывка, длина стены под таймер бега), и держать их в виде
## чисел рядом друг с другом важнее, чем в виде узлов.

## КОНТРОЛЬНЫЕ ТОЧКИ читаются из сцены — маркерами, а не константами. Упал —
## возвращаешься на последнюю пройденную, а не в начало: трасса про механику, а не про
## наказание.
var checks: Array[Vector3] = []

var time := 0.0
var best := -1.0
var running := false
var done := false
var check := 0

var _p: CharacterBody3D
var _spawn := Vector3(0.0, 1.2, 2.0)


func _ready() -> void:
	_p = $Player
	# ТРАССА — ОТДЕЛЬНАЯ СЦЕНА. Раньше она собиралась здесь из таблицы, и это было
	# аргументировано: расстояния тут параметры механики (провал 3.5 м потому, что прыжок
	# берёт 4.6; стена 14 м потому, что таймер бега 1.7 с при 9.2 м/с даёт 15.6). Довод
	# верный, но не крайняя мера: числа прекрасно живут в заметке, а трасса — в сцене,
	# где её видно и где её можно двигать мышью.
	for m in ($Course/Checks as Node3D).get_children():
		checks.append((m as Node3D).position)
	# Ворота — настоящие Area3D из сцены: срабатывание по объёму даёт и вход сбоку, и
	# вход в прыжке, и не зависит от частоты кадров.
	($Course/Start as Area3D).body_entered.connect(
		func(b: Node3D) -> void: _gate_hit("Start", b))
	($Course/Finish as Area3D).body_entered.connect(
		func(b: Node3D) -> void: _gate_hit("Finish", b))
	_reset()


func _gate_hit(name_: String, b: Node3D) -> void:
	if b != _p:
		return
	if name_ == "Start" and not running and not done:
		running = true
		time = 0.0
	elif name_ == "Finish" and running:
		running = false
		done = true
		if best < 0.0 or time < best:
			best = time


func _process(delta: float) -> void:
	if running:
		time += delta
	var z := _p.global_position.z
	for i in checks.size():
		if z <= checks[i].z + 3.0 and i > check:
			check = i
	if _p.global_position.y < -8.0:
		_respawn()
	_hud()


func _respawn() -> void:
	_p.global_position = checks[check]
	_p.velocity = Vector3.ZERO


func _reset() -> void:
	running = false
	done = false
	check = 0
	time = 0.0
	_p.global_position = _spawn
	_p.velocity = Vector3.ZERO


func _row(on: bool, key: String, text: String) -> String:
	var c := "88ff99" if on else "666666"
	return "[color=#%s]%s\t%s[/color]\n" % [c, key, text]


func _hud() -> void:
	var s := "[font_size=34][b]%.1f[/b][/font_size] м/с   [color=#aaaaaa]%s[/color]\n" % [
		_p.speed, _p.state]
	s += "время [b]%.2f[/b]" % time
	if best >= 0.0:
		s += "   лучшее [color=#ffdd66]%.2f[/color]" % best
	if done:
		s += "   [color=#88ff99]ФИНИШ[/color]"
	s += "\n\n"
	s += _row(_p.air_control, "1", "воздушное управление (разгон доворотом — Quake)")
	s += _row(_p.coyote, "2", "койот-тайм: %.0f мс после схода с края" % (_p.coyote_time * 1000.0))
	s += _row(_p.buffer, "3", "буфер прыжка: %.0f мс до приземления" % (_p.buffer_time * 1000.0))
	s += _row(_p.variable_jump, "4", "переменная высота: отпустил рано — ниже")
	s += _row(_p.wall_run, "5", "бег по стене (порог %.1f м/с)" % _p.wall_min_speed)
	s += _row(_p.dash, "6", "рывок [%s]" % ("готов" if _p.dash_ready >= 1.0
		else "%.0f%%" % (_p.dash_ready * 100.0)))
	s += _row(_p.mantle, "7", "подтягивание на уступ")
	s += _row(_p.slide, "8", "скольжение")
	s += _row(_p.double_jump, "9", "двойной прыжок [%s]" % ("есть" if _p._air_left > 0
		else "потрачен"))
	s += "\nWASD — бег   ПРОБЕЛ — прыжок   SHIFT — рывок   CTRL — скольжение\n"
	s += "1…9 — слои по одному   0 — включить всё   R — заново   ESC — мышь\n"
	if check >= 5:
		s += "[color=#ffdd66]арена: рывок с зажатым боком и доворотом мыши — дуга[/color]
"
	s += "[color=#66ccff]три верхних слоя невидимы — их замечаешь только когда их нет[/color]"
	($Ui/Label as RichTextLabel).text = s


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return
	match (event as InputEventKey).physical_keycode:
		KEY_1: _p.air_control = not _p.air_control
		KEY_2: _p.coyote = not _p.coyote
		KEY_3: _p.buffer = not _p.buffer
		KEY_4: _p.variable_jump = not _p.variable_jump
		KEY_5: _p.wall_run = not _p.wall_run
		KEY_6: _p.dash = not _p.dash
		KEY_7: _p.mantle = not _p.mantle
		KEY_8: _p.slide = not _p.slide
		KEY_9: _p.double_jump = not _p.double_jump
		KEY_0:
			for f in ["air_control", "coyote", "buffer", "variable_jump",
					"wall_run", "dash", "mantle", "slide", "double_jump"]:
				_p.set(f, true)
		KEY_R: _reset()
