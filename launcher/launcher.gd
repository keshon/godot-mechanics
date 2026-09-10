extends Control
## ПУСКОВАЯ СЕТКА.
##
## Это не проба. Проб уже за тридцать, и единственным способом запустить нужную была
## правка `run/main_scene` в `project.godot` — то есть чтобы поиграть, надо было открыть
## конфиг движка. Сетка чинит ровно это и больше ничего.
##
## Она НЕ трогает ни одну пробу и ничего у них не берёт: только читает `PURPOSE.md`,
## находит рядом сцену и вызывает `change_scene_to_file`. Устав цел — код проб остаётся
## изолированным, а возврат живёт в автозагрузке, о которой пробы не знают.
##
## Источник правды — `PURPOSE.md`. Название, эталон и галочка «закрыта» берутся из той же
## таблицы, которую я и так веду; заводить второй список значило бы завести второй список,
## который разойдётся с первым через неделю.

const PURPOSE := "res://PURPOSE.md"
const PROBES := "res://probes"
const MIXES := "res://mixes"
## Размер карточки пробы в сетке, точки.
const CARD := Vector2(486, 76)
## Сколько символов названия влезает в карточку.
const TITLE_CUT := 62

## Строки сетки: `{"dir", "title", "ref", "done", "scene", "mix"}`.
var _rows: Array = []

@onready var _head: RichTextLabel = $Column/Head
@onready var _filter: LineEdit = $Column/Filter
@onready var _grid: GridContainer = $Column/Scroll/Grid


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rows = _collect()
	_filter.text_changed.connect(_on_filter_text_changed)
	_filter.grab_focus()
	_fill()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()


## Разбор таблицы устава. Строка выглядит так:
##   | механика | эталон | `30_gun` ✓ |
## Незакрытые — без галочки, ненаписанные — с прочерком вместо имени.
func _collect() -> Array:
	var out: Array = []
	var seen := {}
	if FileAccess.file_exists(PURPOSE):
		for line in FileAccess.get_file_as_string(PURPOSE).split("\n"):
			var row := _row_of(line.strip_edges(), seen)
			if not row.is_empty():
				seen[row["dir"]] = true
				out.append(row)
	# Пробы, которых в уставе нет, но которые лежат на диске, — тоже показать. Забыть
	# строчку легче, чем забыть каталог.
	var probes := DirAccess.open(PROBES)
	if probes != null:
		for name in probes.get_directories():
			if not seen.has(name):
				out.append({
					"dir": name, "title": "(нет строки в PURPOSE.md)", "ref": "—",
					"done": false, "scene": _scene_in(name), "mix": false,
				})
	out.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
			return first["dir"] < second["dir"])
	out.append_array(_mix_rows())
	return out


func _row_of(line: String, seen: Dictionary) -> Dictionary:
	if not line.begins_with("|") or line.begins_with("|---") or line.find("`") == -1:
		return {}
	var cells: PackedStringArray = line.split("|")
	if cells.size() < 5:
		return {}
	var last := cells[3].strip_edges()
	var open_tick := last.find("`")
	var close_tick := last.rfind("`")
	if open_tick == -1 or close_tick <= open_tick:
		return {}
	var dir := last.substr(open_tick + 1, close_tick - open_tick - 1)
	if seen.has(dir):
		return {}
	return {
		"dir": dir,
		"title": cells[1].strip_edges(),
		"ref": cells[2].strip_edges(),
		"done": last.contains("✓"),
		"scene": _scene_in(dir),
		"mix": false,
	}


## МУЛЬТИПРОБЫ — отдельным хвостом и с пометкой. В список механик они не входят (там
## одиночные механики), но запускать их надо откуда-то, и это единственное место.
func _mix_rows() -> Array:
	var dir := DirAccess.open(MIXES)
	if dir == null:
		return []
	var out: Array = []
	for name in dir.get_directories():
		var scene := _scene_in_dir(MIXES, name)
		out.append({
			"dir": name, "title": "мультипроба", "ref": _uses(scene),
			"done": false, "scene": scene, "mix": true,
		})
	out.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
			return first["dir"] < second["dir"])
	return out


## ВХОДНАЯ СЦЕНА ПРОБЫ — та, чьё имя совпадает с хвостом папки: `37_car` → `car.tscn`.
##
## Первый попавшийся `.tscn` работает ровно до тех пор, пока в пробе один файл. Как только
## машина и площадка разъезжаются по своим сценам, выбор начинает зависеть от алфавита —
## повезло, что `car` идёт раньше `machine` и `track`. Соглашение это уже существовало во
## всех тридцати восьми пробах; оставалось его записать.
func _scene_in(dir: String) -> String:
	return _scene_in_dir(PROBES, dir)


func _scene_in_dir(root: String, dir: String) -> String:
	var path := "%s/%s" % [root, dir]
	var at := DirAccess.open(path)
	if at == null:
		return ""
	var want := dir.substr(dir.find("_") + 1) + ".tscn"
	var files := at.get_files()
	if files.has(want):
		return "%s/%s" % [path, want]
	for file in files:
		if file.ends_with(".tscn"):
			return "%s/%s" % [path, file]
	return ""


## ОТ ЧЕГО ЗАВИСИТ МУЛЬТИПРОБА — читается из самой сцены, а не пишется руками. В `.tscn`
## лежат пути внешних ресурсов; те, что смотрят в `res://probes/`, и есть её опора.
## Соврать такой список не может: он и есть то, что движок реально грузит.
func _uses(scene: String) -> String:
	if scene == "":
		return "—"
	var file := FileAccess.open(scene, FileAccess.READ)
	if file == null:
		return "—"
	var seen := {}
	const MARK := "res://probes/"
	for line in file.get_as_text().split("\n"):
		var at := line.find(MARK)
		if at == -1:
			continue
		var tail := line.substr(at + MARK.length())
		var slash := tail.find("/")
		if slash > 0:
			seen[tail.substr(0, slash)] = true
	var names := seen.keys()
	names.sort()
	return "из " + " + ".join(names) if not names.is_empty() else "—"


func _fill() -> void:
	for child in _grid.get_children():
		child.queue_free()
	var query := _filter.text.strip_edges().to_lower()
	var shown := 0
	var mixes := 0
	# Сначала пробы, потом мультипробы — с разделителем во всю строку. Список механик и
	# список сборок это разные списки, и мешать их в одну ленту значит терять и то и другое.
	for want_mix in [false, true]:
		var first := true
		for row in _rows:
			if bool(row.get("mix", false)) != want_mix:
				continue
			if not _matches(row, query):
				continue
			if want_mix and first:
				first = false
				_grid.add_child(_divider())
			_grid.add_child(_card(row))
			shown += 1
			if want_mix:
				mixes += 1
	var done := _rows.filter(func(row: Dictionary) -> bool: return row["done"]).size()
	_head.text = (
			"[b]ПРОБЫ[/b]   всего %d, закрыто %d   [color=#88ccff]мультипроб %d[/color]%s"
			% [_rows.size() - mixes, done, mixes,
				"" if query == "" else "   показано %d" % shown])


func _matches(row: Dictionary, query: String) -> bool:
	if query == "":
		return true
	var haystack := "%s %s %s" % [row["dir"], row["title"], row["ref"]]
	return haystack.to_lower().contains(query)


## Полоса во всю ширину сетки: дальше идут не пробы, а сборки из них.
func _divider() -> Control:
	var label := Label.new()
	label.text = "———  МУЛЬТИПРОБЫ  —  собраны из проб, в список механик не входят  ———"
	label.custom_minimum_size = Vector2(CARD.x, 44)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.53, 0.8, 1.0))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _card(row: Dictionary) -> Button:
	var button := Button.new()
	button.custom_minimum_size = CARD
	button.clip_text = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var scene: String = row["scene"]
	button.disabled = scene == ""
	var mark := "✓" if row["done"] else " "
	button.text = "%s  %s\n%s\n%s" % [
		mark, row["dir"], _cut(row["title"], TITLE_CUT),
		"" if row["ref"] == "—" else row["ref"]]
	button.tooltip_text = scene if scene != "" else "сцена не найдена"
	if scene != "":
		button.pressed.connect(
				func() -> void: get_tree().change_scene_to_file(scene))
	return button


func _cut(text: String, most: int) -> String:
	return text if text.length() <= most else text.substr(0, most - 1) + "…"


func _on_filter_text_changed(_text: String) -> void:
	_fill()
