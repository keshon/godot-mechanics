extends Node3D

## 31 — ЗВУК КАК ИНФОРМАЦИЯ
##
## Проба не про «красиво звучит». Она про единственный вопрос: **что игрок узнаёт ухом,
## чего не видит глазом.** Направление. Дистанцию. Стену между вами. Размер помещения.
##
## Поэтому и приёмка тут не «послушал — понравилось», а измеримая: `TAB` гасит экран,
## бот продолжает стрелять, ты поворачиваешься на звук, второй `TAB` показывает ошибку в
## градусах. Если слой несёт информацию — ошибка падает. Если нет — не падает, и никакие
## слова про «атмосферность» этого не изменят.
##
##   1  трёхмерная позиция     иначе всё из центра головы
##   2  затухание с расстоянием
##   3  задержка по скорости звука — 343 м/с
##   4  окклюзия: луч до источника, за преградой — глухая шина
##   5  отражения от стен методом мнимых источников
##   6  реверб комнаты — штатная шина Godot
##   7  вариативность: четыре варианта и разброс высоты
##   8  три слоя выстрела вместо одного склеенного сэмпла

@export var positional := true
@export var attenuate := true
@export var travel := true
@export var occlusion := true
@export var reflections := true
@export var reverb := true
@export var variation := true
@export var layered := true

## Метров в секунду. Настоящее значение; убавь до 60 — и задержка станет очевидной даже
## в комнате, что само по себе объясняет, почему в игре её обычно и не слышно.
@export_range(40.0, 800.0) var sound_speed := 343.0
@export_range(0.3, 4.0) var bot_period := 1.4
@export_range(-24.0, 0.0) var reflect_db := -7.0
@export_range(150.0, 4000.0) var muffle_hz := 520.0
@export_range(0.0, 1.0) var reverb_wet := 0.35

const POOL := 28
const FLAT_POOL := 8
const ROOM_X := 11.0
const ROOM_Z := 11.0

var shots := 0
var voices := 0
var blind := false
var error_deg := -1.0

var _bank: Array = []          # [variant][layer] -> AudioStreamWAV
var _flat: Array = []          # [variant] -> AudioStreamWAV
var _boom: AudioStreamWAV
var _pool: Array[AudioStreamPlayer3D] = []
var _flat_pool: Array[AudioStreamPlayer] = []
var _pi := 0
var _fi := 0
var _pending: Array = []       # [{"t": сек, "at": Vector3, "layer": int, "db": float, "pitch": float}]
var _clock := 0.0
var _next_bot := 0.0
var _next_far := 0.0
var _yaw := 0.785        # взгляд от угла к центру комнаты
var _pitch := -0.02
var _pos := Vector3(4.0, 0.0, 4.0)
var _bot_a := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_make_buses()
	for v in 4:
		_bank.append(SoundBank.shot(v))
		_flat.append(SoundBank.flat(v))
	_boom = SoundBank.boom()
	for i in POOL:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 6.0
		p.max_distance = 400.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_pool.append(p)
	for i in FLAT_POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_flat_pool.append(p)
	_next_bot = 0.7
	_next_far = 2.0


## Две шины и одна разница между ними. Godot не умеет окклюзию сам: перекрытие считается
## лучом, а «глухо» — это лоупасс, и повесить его можно только на ШИНУ, не на источник.
## Отсюда вся конструкция: источник в момент запуска выбирает, в какую шину петь.
func _make_buses() -> void:
	if AudioServer.get_bus_index("Dry") != -1:
		_tune_buses()
		return
	AudioServer.add_bus()
	var dry := AudioServer.bus_count - 1
	AudioServer.set_bus_name(dry, "Dry")
	AudioServer.set_bus_send(dry, "Master")
	AudioServer.add_bus_effect(dry, AudioEffectReverb.new())

	AudioServer.add_bus()
	var wet := AudioServer.bus_count - 1
	AudioServer.set_bus_name(wet, "Muffled")
	AudioServer.set_bus_send(wet, "Master")
	AudioServer.add_bus_effect(wet, AudioEffectLowPassFilter.new())
	AudioServer.add_bus_effect(wet, AudioEffectReverb.new())
	_tune_buses()


func _tune_buses() -> void:
	var dry := AudioServer.get_bus_index("Dry")
	var wet := AudioServer.get_bus_index("Muffled")
	var lp: AudioEffectLowPassFilter = AudioServer.get_bus_effect(wet, 0)
	lp.cutoff_hz = muffle_hz
	for pair in [[dry, 0], [wet, 1]]:
		var rv: AudioEffectReverb = AudioServer.get_bus_effect(pair[0], pair[1])
		rv.room_size = 0.72
		rv.damping = 0.45
		rv.predelay_msec = 18.0
		rv.wet = reverb_wet if reverb else 0.0
		rv.dry = 1.0


func _process(delta: float) -> void:
	_clock += delta
	_walk(delta)
	_aim()
	_move_bot(delta)
	if _clock >= _next_bot:
		_next_bot = _clock + bot_period
		fire(($Bot as Node3D).global_position)
	if _clock >= _next_far:
		_next_far = _clock + 6.0
		_far_shot()
	_service()
	_hud()


## ОДИН ВЫСТРЕЛ. Здесь и живут все слои, кроме реверба: он на шине.
func fire(at: Vector3) -> void:
	shots += 1
	var ear: Vector3 = ($Cam as Camera3D).global_position
	var d := ear.distance_to(at)
	# Слой 3. Звук идёт со своей скоростью, а вспышка приходит мгновенно. В комнате это
	# тридцать миллисекунд и услышать нельзя; на четверти километра — три четверти секунды.
	var lag := (d / sound_speed) if travel else 0.0
	var v := (shots % 4) if variation else 0
	var pitch := randf_range(0.94, 1.07) if variation else 1.0
	_schedule(lag, at, v, 0.0, pitch)

	# Слой 5. МНИМЫЕ ИСТОЧНИКИ. Отражение от плоской стены звучит ровно как копия
	# источника, зеркально отражённая за эту стену: тот же звук, больший путь, меньше
	# громкость. Ни одного дополнительного алгоритма — только геометрия.
	# Отражение ВСЕГДА приходит позже прямого звука: путь длиннее. Эта задержка не зависит
	# от слоя 3 — она и есть суть отражения, без неё это просто второй источник.
	if reflections:
		for m in _mirrors(at):
			_schedule(lag + (ear.distance_to(m) - d) / sound_speed, m, v, reflect_db, pitch)


func _mirrors(at: Vector3) -> Array[Vector3]:
	return [
		Vector3(2.0 * ROOM_X - at.x, at.y, at.z),
		Vector3(-2.0 * ROOM_X - at.x, at.y, at.z),
		Vector3(at.x, at.y, 2.0 * ROOM_Z - at.z),
		Vector3(at.x, at.y, -2.0 * ROOM_Z - at.z),
	]


func _schedule(lag: float, at: Vector3, variant: int, db: float, pitch: float) -> void:
	if lag <= 0.0:
		_play(at, variant, db, pitch)
	else:
		_pending.append({"t": _clock + lag, "at": at, "v": variant, "db": db, "p": pitch})


func _service() -> void:
	var keep := []
	for e in _pending:
		if _clock >= float(e["t"]):
			_play(e["at"], int(e["v"]), float(e["db"]), float(e["p"]))
		else:
			keep.append(e)
	_pending = keep


## Слой 4 решается здесь: луч от уха до источника. Попал во что-то — поём в глухую шину.
func _blocked(at: Vector3) -> bool:
	if not occlusion:
		return false
	var ear: Vector3 = ($Cam as Camera3D).global_position
	var q := PhysicsRayQueryParameters3D.create(ear, at)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _play(at: Vector3, variant: int, db: float, pitch: float) -> void:
	var bus := "Muffled" if _blocked(at) else "Dry"
	# Слой 8. Три потока вместо одного склеенного — три голоса на выстрел вместо одного.
	# Это и есть цена возможности развести слои по дистанции и по преграде.
	var parts: Array = [_boom] if variant < 0 else (_bank[variant] if layered else [_flat[variant]])
	for s in parts:
		if positional:
			var p := _pool[_pi]
			_pi = (_pi + 1) % POOL
			p.stream = s
			p.global_position = at
			p.bus = bus
			p.pitch_scale = pitch
			p.volume_db = db
			# Слой 2. Выключенное затухание — не «тише/громче», а потеря дистанции:
			# все выстрелы приходят одинаковыми, и дальний неотличим от ближнего.
			p.attenuation_model = (AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
				if attenuate else AudioStreamPlayer3D.ATTENUATION_DISABLED)
			p.play()
		else:
			# Слой 1 выключен: обычный AudioStreamPlayer. Ни направления, ни расстояния —
			# звук из середины головы. Ровно так звучит любой звук, забытый в 2D.
			var f := _flat_pool[_fi]
			_fi = (_fi + 1) % FLAT_POOL
			f.stream = s
			f.volume_db = db
			f.pitch_scale = pitch
			f.play()

func _far_shot() -> void:
	var at: Vector3 = ($Far as Node3D).global_position
	var d: float = ($Cam as Camera3D).global_position.distance_to(at)
	var lag := (d / sound_speed) if travel else 0.0
	# Вспышка на горизонте видна СРАЗУ, звук приходит через три четверти секунды. Это
	# единственное место в пробе, где скорость звука слышна без объяснений.
	($Far/Flash as OmniLight3D).visible = true
	get_tree().create_timer(0.06).timeout.connect(
		func() -> void: ($Far/Flash as OmniLight3D).visible = false)
	# +22 дБ: на 256 метрах обратное затухание даёт −32 дБ, и без компенсации выстрел
	# орудия слышно тише, чем шаг рядом. В игре это решают отдельной кривой для «дальних
	# событий» — расстояния боя и расстояния артиллерии не ложатся на одну модель.
	_pending.append({"t": _clock + lag, "at": at, "v": -1, "db": 22.0, "p": 1.0})


func _move_bot(delta: float) -> void:
	_bot_a += delta * 0.42
	var b: Node3D = $Bot
	# Радиус 9, а игрок ближе к центру: на радиусе 7.4 бот проходил в полутора метрах от
	# уха, и «найти на слух» превращалось в «он и так орёт в упор».
	b.position = Vector3(cos(_bot_a) * 9.0, 1.2, sin(_bot_a) * 9.0)


func _walk(delta: float) -> void:
	var f := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var r := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var v := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): v += f
	if Input.is_physical_key_pressed(KEY_S): v -= f
	if Input.is_physical_key_pressed(KEY_D): v += r
	if Input.is_physical_key_pressed(KEY_A): v -= r
	if v != Vector3.ZERO:
		_pos += v.normalized() * 3.6 * delta
		_pos.x = clampf(_pos.x, -ROOM_X + 0.6, ROOM_X - 0.6)
		_pos.z = clampf(_pos.z, -ROOM_Z + 0.6, ROOM_Z - 0.6)
		_push_out()


## Не дать встать ВНУТРЬ перегородки. Не ради физики — ради окклюзии: луч, стартующий
## внутри тела, в Godot не считается попаданием (`hit_from_inside` по умолчанию выключен).
## Я удлинил стену, чтобы она перекрывала бота чаще, и загнал этим камеру внутрь неё —
## замер показал 0 перекрытий из 24 вместо ожидаемых 8. Ошибки при этом никакой: стена
## просто перестала существовать для звука, оставшись на экране.
func _push_out() -> void:
	if absf(_pos.x + 4.0) > 1.5 or absf(_pos.z) > 7.4:
		return
	_pos.x = -2.5 if _pos.x >= -4.0 else -5.5


func _aim() -> void:
	var cam: Camera3D = $Cam
	cam.rotation = Vector3(_pitch, _yaw, 0.0)
	cam.position = _pos + Vector3(0.0, 1.65, 0.0)


## Угол между взглядом и направлением на бота — в горизонтальной плоскости. Это и есть
## оценка: слышно направление или нет.
func _aim_error() -> float:
	var to: Vector3 = ($Bot as Node3D).global_position - ($Cam as Camera3D).global_position
	var look := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	to.y = 0.0
	if to.length() < 0.01:
		return 0.0
	return rad_to_deg(look.angle_to(to.normalized()))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * 0.0025
		_pitch = clampf(_pitch - event.relative.y * 0.0025, -1.3, 1.3)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			fire(($Cam as Camera3D).global_position + Vector3(-sin(_yaw), 0.0, -cos(_yaw)) * 0.6)
	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return
	match (event as InputEventKey).physical_keycode:
		KEY_1: positional = not positional
		KEY_2: attenuate = not attenuate
		KEY_3: travel = not travel
		KEY_4: occlusion = not occlusion
		KEY_5: reflections = not reflections
		KEY_6: reverb = not reverb; _tune_buses()
		KEY_7: variation = not variation
		KEY_8: layered = not layered
		KEY_0:
			positional = true; attenuate = true; travel = true; occlusion = true
			reflections = true; reverb = true; variation = true; layered = true
			_tune_buses()
		KEY_TAB:
			blind = not blind
			($Blind/Rect as ColorRect).visible = blind
			if not blind:
				error_deg = _aim_error()
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _row(on: bool, key: String, text: String) -> String:
	var c := "88ff99" if on else "666666"
	return "[color=#%s]%s\t%s[/color]\n" % [c, key, text]


func _hud() -> void:
	voices = 0
	for p in _pool:
		if p.playing:
			voices += 1
	var d: float = ($Cam as Camera3D).global_position.distance_to(($Bot as Node3D).global_position)
	var s := "[b]ЗВУК[/b]   выстрелов %d   голосов %d\n\n" % [shots, voices]
	s += _row(positional, "1", "трёхмерная позиция")
	s += _row(attenuate, "2", "затухание с расстоянием")
	s += _row(travel, "3", "скорость звука — %.0f м/с (бот в %.1f м, задержка %.0f мс)"
		% [sound_speed, d, d / sound_speed * 1000.0])
	s += _row(occlusion, "4", "окклюзия: %s" % ("СТЕНА между вами"
		if _blocked(($Bot as Node3D).global_position) else "видно напрямую"))
	s += _row(reflections, "5", "отражения от стен (4 мнимых источника)")
	s += _row(reverb, "6", "реверб комнаты")
	s += _row(variation, "7", "вариативность: 4 варианта + разброс высоты")
	s += _row(layered, "8", "три слоя: щелчок / тело / хвост")
	s += "\n[color=#ffdd66]TAB — закрыть глаза и найти бота на слух[/color]"
	if blind:
		s += "   [color=#ff8866]ГЛАЗА ЗАКРЫТЫ[/color]"
	elif error_deg >= 0.0:
		s += "   ошибка: [b]%.0f°[/b]" % error_deg
	s += "\n\nЛКМ — свой выстрел   WASD — ходить   мышь — смотреть\n"
	s += "1…8 — слои по одному   0 — включить всё   ESC — мышь\n"
	s += "[color=#66ccff]выключай по одному и слушай, что перестаёшь ЗНАТЬ[/color]"
	($Ui/Label as RichTextLabel).text = s
