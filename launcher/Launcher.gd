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

var _rows: Array = []       # [{"dir","title","ref","done","scene"}]


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rows = _collect()
	($V/Filter as LineEdit).text_changed.connect(func(_t: String) -> void: _fill())
	($V/Filter as LineEdit).grab_focus()
	_fill()


## Разбор таблицы устава. Строка выглядит так:
##   | механика | эталон | `30_gun` ✓ |
## Незакрытые — без галочки, ненаписанные — с прочерком вместо имени.
func _collect() -> Array:
	var out: Array = []
	var seen := {}
	if FileAccess.file_exists(PURPOSE):
		for line in FileAccess.get_file_as_string(PURPOSE).split("\n"):
			var l := line.strip_edges()
			if not l.begins_with("|") or l.begins_with("|---") or l.find("`") == -1:
				continue
			var cells: PackedStringArray = l.split("|")
			if cells.size() < 5:
				continue
			var title := cells[1].strip_edges()
			var ref := cells[2].strip_edges()
			var last := cells[3].strip_edges()
			var a := last.find("`")
			var b := last.rfind("`")
			if a == -1 or b <= a:
				continue
			var dir := last.substr(a + 1, b - a - 1)
			if seen.has(dir):
				continue
			seen[dir] = true
			out.append({"dir": dir, "title": title, "ref": ref, "mix": false,
				"done": last.contains("✓"), "scene": _scene_in(dir)})
	# Пробы, которых в уставе нет, но которые лежат на диске, — тоже показать. Забыть
	# строчку легче, чем забыть каталог.
	var d := DirAccess.open(PROBES)
	if d != null:
		for name in d.get_directories():
			if not seen.has(name):
				out.append({"dir": name, "title": "(нет строки в PURPOSE.md)", "ref": "—",
					"done": false, "scene": _scene_in(name), "mix": false})
	out.sort_custom(func(x, y) -> bool: return x["dir"] < y["dir"])
	# МУЛЬТИПРОБЫ — отдельным хвостом и с пометкой. В список механик они не входят
	# (там одиночные механики), но запускать их надо откуда-то, и это единственное место.
	var m := DirAccess.open(MIXES)
	if m != null:
		var mixes: Array = []
		for name in m.get_directories():
			var scene := _scene_in_dir(MIXES, name)
			mixes.append({"dir": name, "title": "мультипроба", "ref": _uses(scene),
				"done": false, "scene": scene, "mix": true})
		mixes.sort_custom(func(x, y) -> bool: return x["dir"] < y["dir"])
		out.append_array(mixes)
	return out


## ВХОДНАЯ СЦЕНА ПРОБЫ — та, чьё имя совпадает с хвостом папки: `37_car` → `car.tscn`.
##
## Раньше брался первый попавшийся `.tscn`, и это работало ровно до тех пор, пока в пробе
## был один файл. Как только машина и площадка разъехались по своим сценам, выбор стал
## зависеть от алфавита: повезло, что `car` идёт раньше `machine` и `track`. Соглашение это
## уже существовало во всех тридцати восьми пробах — оставалось его записать.
func _scene_in(dir: String) -> String:
	return _scene_in_dir(PROBES, dir)


func _scene_in_dir(root: String, dir: String) -> String:
	var path := "%s/%s" % [root, dir]
	var d := DirAccess.open(path)
	if d == null:
		return ""
	var want := dir.substr(dir.find("_") + 1) + ".tscn"
	var files := d.get_files()
	if files.has(want):
		return "%s/%s" % [path, want]
	for f in files:
		if f.ends_with(".tscn"):
			return "%s/%s" % [path, f]
	return ""

## ОТ ЧЕГО ЗАВИСИТ МУЛЬТИПРОБА — читается из самой сцены, а не пишется руками. В `.tscn`
## лежат пути внешних ресурсов; те, что смотрят в `res://probes/`, и есть её опора.
## Соврать такой список не может: он и есть то, что движок реально грузит.
func _uses(scene: String) -> String:
	if scene == "":
		return "—"
	var f := FileAccess.open(scene, FileAccess.READ)
	if f == null:
		return "—"
	var seen := {}
	var text := f.get_as_text()
	for line in text.split("
"):
		var i := line.find("res://probes/")
		if i == -1:
			continue
		var tail := line.substr(i + 13)
		var j := tail.find("/")
		if j > 0:
			seen[tail.substr(0, j)] = true
	var names := seen.keys()
	names.sort()
	return "из " + " + ".join(names) if not names.is_empty() else "—"


func _fill() -> void:
	var grid: GridContainer = $V/Scroll/Grid
	for c in grid.get_children():
		c.queue_free()
	var q := ($V/Filter as LineEdit).text.strip_edges().to_lower()
	var shown := 0
	var mixes := 0
	# Сначала пробы, потом мультипробы — с разделителем во всю строку. Список механик и
	# список сборок это разные списки, и мешать их в одну ленту значит терять и то и другое.
	for pass_mix in [false, true]:
		var first := true
		for r in _rows:
			if bool(r.get("mix", false)) != pass_mix:
				continue
			if q != "" and not ("%s %s %s" % [r["dir"], r["title"], r["ref"]]).to_lower().contains(q):
				continue
			if pass_mix and first:
				first = false
				grid.add_child(_divider())
			grid.add_child(_card(r))
			shown += 1
			if pass_mix:
				mixes += 1
	($V/Head as RichTextLabel).text = ("[b]ПРОБЫ[/b]   всего %d, закрыто %d   [color=#88ccff]мультипроб %d[/color]%s"
		% [_rows.size() - mixes, _rows.filter(func(r): return r["done"]).size(), mixes,
			"" if q == "" else "   показано %d" % shown])


## Полоса во всю ширину сетки: дальше идут не пробы, а сборки из них.
func _divider() -> Control:
	var l := Label.new()
	l.text = "———  МУЛЬТИПРОБЫ  —  собраны из проб, в список механик не входят  ———"
	l.custom_minimum_size = Vector2(486, 44)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", Color(0.53, 0.8, 1.0))
	var grid: GridContainer = $V/Scroll/Grid
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _card(r: Dictionary) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(486, 76)
	b.clip_text = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = r["scene"] == ""
	var mark := "✓" if r["done"] else " "
	b.text = "%s  %s\n%s\n%s" % [mark, r["dir"],
		_cut(r["title"], 62), "" if r["ref"] == "—" else r["ref"]]
	b.tooltip_text = r["scene"] if r["scene"] != "" else "сцена не найдена"
	if r["scene"] != "":
		b.pressed.connect(func() -> void: get_tree().change_scene_to_file(r["scene"]))
	return b


func _cut(s: String, n: int) -> String:
	return s if s.length() <= n else s.substr(0, n - 1) + "…"


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
