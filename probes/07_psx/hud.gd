extends RichTextLabel
## КАКИЕ ОГРАНИЧЕНИЯ СЕЙЧАС ВКЛЮЧЕНЫ и что каждое из них делает.
##
## Читать как список и выключать по одному. Интересный вопрос не «похоже ли это на игру с
## PlayStation», а «на какую именно строку я реагировал» — и ответом обычно оказывается
## первая.

@export var look_path: NodePath = ^"../.."

@onready var look: PsxLook = get_node(look_path)


func _process(_delta: float) -> void:
	var size := look.viewport().size
	text = "\n".join(PackedStringArray([
		"рисуется в [b]%d×%d[/b], дальше растягивается без сглаживания" % [size.x, size.y],
		"",
		"WASD лететь   ПРОБЕЛ вверх   SHIFT быстрее   ESC отпустить мышь",
		"1 привязка вершин: %s   шаг %.2f отрисованного пикселя" % [
			_on_off(look.snap_vertices), look.snap_coarseness],
		"2 аффинные развёртки: %s   (перспективная поправка выключена)" % _on_off(
			look.affine_uv),
		"3 огрубление цвета: %s   %d уровня на канал" % [
			_on_off(look.post_enabled), look.levels],
		"4 растр: %s" % _on_off(look.dither and look.post_enabled),
		"5 разрешение: %s   уменьшение ×%d" % [
			"[b]низкое[/b]" if look.shrink > 1 else "полное", look.shrink],
		"6 сглаживание текстур: %s   (что PS2 делала с диском от PS1)" % _on_off(
			look.smooth_textures),
		"7 строки развёртки: %s   (отдельный проход, уже после растягивания)" % _on_off(
			look.scanlines),
		"8 нарезка пола: %s" % (
			"[b]%d × %d[/b]" % [look.floor_subdivide + 1, look.floor_subdivide + 1]
			if look.floor_subdivide > 0
			else "[color=#ff8a6a]2 треугольника — плывёт во всю силу[/color]"),
		"9 кинескоп: %s   (виньетка, изгиб, растекание цвета)" % _on_off(look.crt),
		"",
		"[color=#66ccff]стиль — это набор ограничений, а не набор ассетов: выключай по"
			+ " одному, и то, чего не хватит сильнее всего, и делает работу[/color]",
	]))


func _on_off(value: bool) -> String:
	return "[color=#7fe08a]вкл[/color]" if value else "выкл"

