extends Node
## ВОЗВРАТ В СЕТКУ. Автозагрузка, о которой ни одна проба не знает и знать не должна:
## устав запрещает пробам брать код друг у друга, и добавлять в каждую из тридцати трёх
## по кнопке «назад» значило бы завести общий код через чёрный ход.
##
## Поэтому клавиша ловится узлом-автозагрузкой поверх всей сцены. F1 выбрана потому, что
## функциональные клавиши не занимает ни одна проба: там заняты цифры, WASD, TAB, R, ESC,
## CTRL, SHIFT и +/−.

const LAUNCHER := "res://launcher/launcher.tscn"


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return
	if (event as InputEventKey).keycode != KEY_F1:
		return
	get_viewport().set_input_as_handled()
	var current := get_tree().current_scene
	if current != null and current.scene_file_path == LAUNCHER:
		return
	# Пробы захватывают курсор; вернуть его — часть возврата, иначе в сетке нечем кликать.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(LAUNCHER)
