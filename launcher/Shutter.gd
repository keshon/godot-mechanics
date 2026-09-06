extends Node

## ЗАТВОР. Вторая автозагрузка, по той же причине, что и `Back.gd`: снимок нужен в каждой
## пробе, а класть в каждую по кнопке значило бы завести общий код через чёрный ход.
##
## Витрину в README можно снять и programmatically — `tools/Shot.gd` так и делает, открывая
## каждую сцену на пару секунд. Но покой у половины проб пуст: взрыв не взорван, дом не
## разрушен, толпа стоит. Такой кадр ставится руками, как и всё остальное в этом проекте.
##
## F2 — снять текущую пробу. Путь берётся из пути сцены, поэтому промахнуться папкой
## нельзя: `res://probes/30_gun/gun.tscn` -> `img/probes/30_gun.jpg`.

const OUT := "res://img"
const SIZE := Vector2i(1280, 720)
const QUALITY := 0.86


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return
	if (event as InputEventKey).keycode != KEY_F2:
		return
	get_viewport().set_input_as_handled()
	var out := _path_for(get_tree().current_scene)
	if out == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var err := img.save_jpg(out, QUALITY)
	print("[shot] %s %s" % ["ok" if err == OK else "FAIL", out])
	_flash(out if err == OK else "не сохранилось")


func _path_for(scene: Node) -> String:
	if scene == null:
		return ""
	var parts := scene.scene_file_path.trim_prefix("res://").split("/")
	if parts.size() < 3 or not (parts[0] == "probes" or parts[0] == "mixes"):
		return ""
	return "%s/%s/%s.jpg" % [OUT, parts[0], parts[1]]


## Консоль во время игры не видно, а знать, что кадр лёг, надо сразу.
func _flash(text: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 128
	var label := Label.new()
	label.text = "СНЯТО   " + text
	label.position = Vector2(24, 24)
	label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 6)
	layer.add_child(label)
	add_child(layer)
	await get_tree().create_timer(1.5).timeout
	layer.queue_free()
