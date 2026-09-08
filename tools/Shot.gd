extends Node

## СЪЁМКА ВИТРИНЫ.
##
## Не проба и не мультипроба: инструмент, как и `launcher/`. Правила устава на него не
## распространяются — он ничего не показывает руками, он готовит картинки для README.
##
## Каждая проба открывается в СВОЁМ `SubViewport` с собственным `World3D`, а не через
## `change_scene_to_file`. Смена сцены убила бы этот узел вместе с очередью; отдельный
## мир заодно даёт изоляцию: свет и окружение одной пробы не протекают в следующую.
##
## Запуск:  run.bat  с подменой сцены  ->  godot --path . res://tools/shot.tscn
## Фильтр:  ... res://tools/shot.tscn -- 30_gun

const PROBES := "res://probes"
const MIXES := "res://mixes"
const OUT := "res://img"

const SIZE := Vector2i(1280, 720)
const QUALITY := 0.86

## Сколько кадров дать сцене до снимка. Секунды мало: физика ещё расставляет тела,
## шейдеры компилируются в первом кадре, а частицы стартуют пустыми.
const SETTLE := 150

## СЦЕНАРИЙ ДЛЯ ТЕХ, У КОГО ПОКОЙ ПУСТ.
##
## Взрыв, эффект и разрушение в состоянии покоя не показывают ничего: снимок выходит
## серым прямоугольником. Такой пробе нажимают то, ради чего она написана, и снимают
## уже последствие. Остальные снимаются как есть — покой у них и есть предмет.
##
## `keys` — кадр и клавиша (одиночное нажатие). `fire` — кадр начала и конца удержания
## огня. `frames` продлевает ожидание: пробе, которая после нажатия что-то СЧИТАЕТ, полутора
## секунд мало. Кадры отсчитываются от появления сцены, снимок берётся на последнем.
const SCRIPTED := {
	"08_boom":    {"keys": [[60, KEY_SPACE]]},
	"09_fx":      {"keys": [[40, KEY_SPACE], [90, KEY_SPACE]]},
	"28_phys":    {"keys": [[30, KEY_X]]},
	"30_gun":     {"fire": [60, 130]},
	"40_hit":     {"fire": [40, 95]},
	"42_voronoi": {"fire": [40, 95]},
	"43_stuff":   {"fire": [40, 100]},
	"01_gunrun":  {"fire": [60, 130]},
	"03_siege":   {"fire": [40, 70]},
	"44_missile": {"fire": [40, 44], "hold": [KEY_D, 150, 999], "frames": 380},
	"45_seeker":  {"keys": [[40, KEY_SPACE]], "hold": [KEY_D, 60, 400], "frames": 500},
	"46_rocket":  {"keys": [[20, KEY_2], [24, KEY_2], [40, KEY_SPACE], [44, KEY_1]], "frames": 8000},
	"47_shoulder": {"keys": [[20, KEY_3], [24, KEY_1]], "fire": [60, 64], "frames": 340},
}


func _ready() -> void:
	var only := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		only = args[0]
	var jobs := _jobs(only)
	print("[shot] scenes: %d" % jobs.size())
	for job in jobs:
		await _take(job["scene"], job["name"], job["out"])
	print("[shot] done")
	get_tree().quit()


func _jobs(only: String) -> Array:
	var out: Array = []
	for pair in [[PROBES, "probes"], [MIXES, "mixes"]]:
		var d := DirAccess.open(pair[0])
		if d == null:
			continue
		var dirs := d.get_directories()
		dirs.sort()
		for name in dirs:
			if only != "" and not name.contains(only):
				continue
			var scene := _scene_in(pair[0], name)
			if scene == "":
				push_warning("no scene in %s/%s" % [pair[0], name])
				continue
			out.append({"scene": scene, "name": name,
				"out": "%s/%s/%s.jpg" % [OUT, pair[1], name]})
	return out


## Входная сцена — та, чьё имя совпадает с хвостом папки: `37_car` -> `car.tscn`.
## То же соглашение, что и в лаунчере, и по той же причине: алфавит выбирать не должен.
func _scene_in(root: String, dir: String) -> String:
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


func _take(scene_path: String, name: String, out_path: String) -> void:
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_warning("load failed: %s" % scene_path)
		return

	var vp := SubViewport.new()
	vp.size = SIZE
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	vp.handle_input_locally = false
	add_child(vp)

	var inst := packed.instantiate()
	vp.add_child(inst)

	var script: Dictionary = SCRIPTED.get(name, {})
	var keys: Array = script.get("keys", [])
	var fire: Array = script.get("fire", [])
	var hold: Array = script.get("hold", [])
	var frames: int = script.get("frames", SETTLE)
	for i in frames:
		for k in keys:
			if k[0] == i:
				_key(vp, k[1], true)
				_key(vp, k[1], false)
		if fire.size() == 2:
			if fire[0] == i:
				_fire(vp, true)
			elif fire[1] == i:
				_fire(vp, false)
		if hold.size() == 3:
			if hold[1] == i:
				_key(vp, hold[0], true)
			elif hold[2] == i:
				_key(vp, hold[0], false)
		await get_tree().process_frame
	# СНИМОК РАНЬШЕ ОТПУСКАНИЯ. Отпустить клавишу перед кадром значит снять пробу в тот
	# момент, когда сценарий уже кончился: у пробы 44 руль успевал вернуться к нулю, и на
	# витрине стояло «руль высоты +0.00» при полной перекладке за кадром.
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if fire.size() == 2:
		_fire(vp, false)
	if hold.size() == 3:
		_key(vp, hold[0], false)
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var err := img.save_jpg(out_path, QUALITY)
	print("[shot] %s  %s" % ["ok " if err == OK else "FAIL", out_path])

	vp.queue_free()
	await get_tree().process_frame


## Ввод идёт двумя путями, потому что пробы читают его двумя способами. Кто слушает
## `_unhandled_input`, получит событие только через свой viewport; кто опрашивает
## `Input.is_action_pressed`, читает глобальное состояние и о viewport не знает.
func _key(vp: SubViewport, code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)
	vp.push_input(e, true)


func _fire(vp: SubViewport, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	e.pressed = down
	e.position = Vector2(SIZE) * 0.5
	e.global_position = e.position
	Input.parse_input_event(e)
	vp.push_input(e, true)
