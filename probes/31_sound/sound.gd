class_name SoundBench
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

const POOL := 28
const FLAT_POOL := 8
const ROOM_X := 11.0
const ROOM_Z := 11.0

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

var shots := 0
var voices := 0
var blind := false
## Ошибка последнего поворота на слух, градусы. -1 — ещё не мерили.
var error_degrees := -1.0

## [вариант][слой] -> AudioStreamWAV.
var _bank: Array = []
## [вариант] -> AudioStreamWAV.
var _flat: Array = []
var _boom: AudioStreamWAV
var _pool: Array[AudioStreamPlayer3D] = []
var _flat_pool: Array[AudioStreamPlayer] = []
var _voice_at := 0
var _flat_at := 0
## Звуки, которые ещё летят: {at_time, at, variant, db, pitch}.
var _pending: Array[Dictionary] = []
var _clock := 0.0
var _next_bot := 0.0
var _next_far := 0.0
## Взгляд от угла к центру комнаты.
var _yaw := 0.785
var _pitch := -0.02
var _eye := Vector3(4.0, 0.0, 4.0)
var _bot_angle := 0.0

@onready var _camera: Camera3D = $Camera
@onready var _bot: Node3D = $Bot
@onready var _far: Node3D = $Far
@onready var _far_flash: OmniLight3D = $Far/Flash
@onready var _blind_rect: ColorRect = $Blind/Rect
@onready var _label: RichTextLabel = $Ui/Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_make_buses()
	for variant in 4:
		_bank.append(SoundBank.shot(variant))
		_flat.append(SoundBank.flat(variant))
	_boom = SoundBank.boom()
	for i in POOL:
		var voice := AudioStreamPlayer3D.new()
		voice.unit_size = 6.0
		voice.max_distance = 400.0
		voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(voice)
		_pool.append(voice)
	for i in FLAT_POOL:
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		_flat_pool.append(voice)
	_next_bot = 0.7
	_next_far = 2.0


func _process(delta: float) -> void:
	_clock += delta
	_walk(delta)
	_aim()
	_move_bot(delta)
	if _clock >= _next_bot:
		_next_bot = _clock + bot_period
		fire(_bot.global_position)
	if _clock >= _next_far:
		_next_far = _clock + 6.0
		_far_shot()
	_play_due()
	_draw_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * 0.0025
		_pitch = clampf(_pitch - event.relative.y * 0.0025, -1.3, 1.3)
	if (
			event is InputEventMouseButton
			and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT
	):
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			var ahead := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
			fire(_camera.global_position + ahead * 0.6)
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_1:
			positional = not positional
		KEY_2:
			attenuate = not attenuate
		KEY_3:
			travel = not travel
		KEY_4:
			occlusion = not occlusion
		KEY_5:
			reflections = not reflections
		KEY_6:
			reverb = not reverb
			_tune_buses()
		KEY_7:
			variation = not variation
		KEY_8:
			layered = not layered
		KEY_0:
			positional = true
			attenuate = true
			travel = true
			occlusion = true
			reflections = true
			reverb = true
			variation = true
			layered = true
			_tune_buses()
		KEY_TAB:
			blind = not blind
			_blind_rect.visible = blind
			if not blind:
				error_degrees = _aim_error()
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## ОДИН ВЫСТРЕЛ. Здесь и живут все слои, кроме реверба: он на шине.
func fire(at: Vector3) -> void:
	shots += 1
	var ear := _camera.global_position
	var away := ear.distance_to(at)
	# Слой 3. Звук идёт со своей скоростью, а вспышка приходит мгновенно. В комнате это
	# тридцать миллисекунд и услышать нельзя; на четверти километра — три четверти
	# секунды.
	var lag := (away / sound_speed) if travel else 0.0
	var variant := (shots % 4) if variation else 0
	var pitch := randf_range(0.94, 1.07) if variation else 1.0
	_schedule(lag, at, variant, 0.0, pitch)

	# Слой 5. МНИМЫЕ ИСТОЧНИКИ. Отражение от плоской стены звучит ровно как копия
	# источника, зеркально отражённая за эту стену: тот же звук, больший путь, меньше
	# громкость. Ни одного дополнительного алгоритма — только геометрия.
	#
	# Отражение ВСЕГДА приходит позже прямого звука: путь длиннее. Эта задержка не
	# зависит от слоя 3 — она и есть суть отражения, без неё это просто второй источник.
	if not reflections:
		return
	for mirror in _mirrors(at):
		var extra := (ear.distance_to(mirror) - away) / sound_speed
		_schedule(lag + extra, mirror, variant, reflect_db, pitch)


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
	var muffled := AudioServer.bus_count - 1
	AudioServer.set_bus_name(muffled, "Muffled")
	AudioServer.set_bus_send(muffled, "Master")
	AudioServer.add_bus_effect(muffled, AudioEffectLowPassFilter.new())
	AudioServer.add_bus_effect(muffled, AudioEffectReverb.new())
	_tune_buses()


func _tune_buses() -> void:
	var dry := AudioServer.get_bus_index("Dry")
	var muffled := AudioServer.get_bus_index("Muffled")
	var low_pass: AudioEffectLowPassFilter = AudioServer.get_bus_effect(muffled, 0)
	low_pass.cutoff_hz = muffle_hz
	for bus in [[dry, 0], [muffled, 1]]:
		var effect: AudioEffectReverb = AudioServer.get_bus_effect(bus[0], bus[1])
		effect.room_size = 0.72
		effect.damping = 0.45
		effect.predelay_msec = 18.0
		effect.wet = reverb_wet if reverb else 0.0
		effect.dry = 1.0


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
		return
	_pending.append({
		"at_time": _clock + lag,
		"at": at,
		"variant": variant,
		"db": db,
		"pitch": pitch,
	})


func _play_due() -> void:
	var still_flying: Array[Dictionary] = []
	for sound in _pending:
		if _clock >= float(sound["at_time"]):
			_play(
					sound["at"],
					int(sound["variant"]),
					float(sound["db"]),
					float(sound["pitch"]))
		else:
			still_flying.append(sound)
	_pending = still_flying


## Слой 4 решается здесь: луч от уха до источника. Попал во что-то — поём в глухую шину.
func _is_blocked(at: Vector3) -> bool:
	if not occlusion:
		return false
	var query := PhysicsRayQueryParameters3D.create(_camera.global_position, at)
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _play(at: Vector3, variant: int, db: float, pitch: float) -> void:
	var bus := "Muffled" if _is_blocked(at) else "Dry"
	# Слой 8. Три потока вместо одного склеенного — три голоса на выстрел вместо одного.
	# Это и есть цена возможности развести слои по дистанции и по преграде.
	var parts: Array = [_boom]
	if variant >= 0:
		parts = _bank[variant] if layered else [_flat[variant]]
	for stream in parts:
		if not positional:
			# Слой 1 выключен: обычный AudioStreamPlayer. Ни направления, ни расстояния —
			# звук из середины головы. Ровно так звучит любой звук, забытый в 2D.
			var flat := _flat_pool[_flat_at]
			_flat_at = (_flat_at + 1) % FLAT_POOL
			flat.stream = stream
			flat.volume_db = db
			flat.pitch_scale = pitch
			flat.play()
			continue
		var voice := _pool[_voice_at]
		_voice_at = (_voice_at + 1) % POOL
		voice.stream = stream
		voice.global_position = at
		voice.bus = bus
		voice.pitch_scale = pitch
		voice.volume_db = db
		# Слой 2. Выключенное затухание — не «тише/громче», а потеря дистанции: все
		# выстрелы приходят одинаковыми, и дальний неотличим от ближнего.
		voice.attenuation_model = (
				AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE if attenuate
				else AudioStreamPlayer3D.ATTENUATION_DISABLED)
		voice.play()


func _far_shot() -> void:
	var at := _far.global_position
	var away := _camera.global_position.distance_to(at)
	var lag := (away / sound_speed) if travel else 0.0
	# Вспышка на горизонте видна СРАЗУ, звук приходит через три четверти секунды. Это
	# единственное место в пробе, где скорость звука слышна без объяснений.
	_far_flash.visible = true
	get_tree().create_timer(0.06).timeout.connect(_on_far_flash_timeout)
	# +22 дБ: на 256 метрах обратное затухание даёт −32 дБ, и без компенсации выстрел
	# орудия слышно тише, чем шаг рядом. В игре это решают отдельной кривой для «дальних
	# событий» — расстояния боя и расстояния артиллерии не ложатся на одну модель.
	_pending.append({
		"at_time": _clock + lag,
		"at": at,
		"variant": -1,
		"db": 22.0,
		"pitch": 1.0,
	})


func _move_bot(delta: float) -> void:
	_bot_angle += delta * 0.42
	# Радиус 9, а игрок ближе к центру: на радиусе 7.4 бот проходил в полутора метрах от
	# уха, и «найти на слух» превращалось в «он и так орёт в упор».
	_bot.position = Vector3(cos(_bot_angle) * 9.0, 1.2, sin(_bot_angle) * 9.0)


func _walk(delta: float) -> void:
	var ahead := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var wanted := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		wanted += ahead
	if Input.is_physical_key_pressed(KEY_S):
		wanted -= ahead
	if Input.is_physical_key_pressed(KEY_D):
		wanted += right
	if Input.is_physical_key_pressed(KEY_A):
		wanted -= right
	if wanted == Vector3.ZERO:
		return
	_eye += wanted.normalized() * 3.6 * delta
	_eye.x = clampf(_eye.x, -ROOM_X + 0.6, ROOM_X - 0.6)
	_eye.z = clampf(_eye.z, -ROOM_Z + 0.6, ROOM_Z - 0.6)
	_push_out()


## Не дать встать ВНУТРЬ перегородки. Не ради физики — ради окклюзии: луч, стартующий
## внутри тела, в Godot не считается попаданием (`hit_from_inside` по умолчанию выключен).
## Я удлинил стену, чтобы она перекрывала бота чаще, и загнал этим камеру внутрь неё —
## замер показал 0 перекрытий из 24 вместо ожидаемых 8. Ошибки при этом никакой: стена
## просто перестала существовать для звука, оставшись на экране.
func _push_out() -> void:
	if absf(_eye.x + 4.0) > 1.5 or absf(_eye.z) > 7.4:
		return
	_eye.x = -2.5 if _eye.x >= -4.0 else -5.5


func _aim() -> void:
	_camera.rotation = Vector3(_pitch, _yaw, 0.0)
	_camera.position = _eye + Vector3(0.0, 1.65, 0.0)


## Угол между взглядом и направлением на бота — в горизонтальной плоскости. Это и есть
## оценка: слышно направление или нет.
func _aim_error() -> float:
	var to_bot := _bot.global_position - _camera.global_position
	var look := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	to_bot.y = 0.0
	if to_bot.length() < 0.01:
		return 0.0
	return rad_to_deg(look.angle_to(to_bot.normalized()))


func _row(on: bool, key: String, text: String) -> String:
	var tint := "88ff99" if on else "666666"
	return "[color=#%s]%s\t%s[/color]\n" % [tint, key, text]


func _draw_hud() -> void:
	voices = 0
	for voice in _pool:
		if voice.playing:
			voices += 1
	var away := _camera.global_position.distance_to(_bot.global_position)
	var text := "[b]ЗВУК[/b]   выстрелов %d   голосов %d\n\n" % [shots, voices]
	text += _row(positional, "1", "трёхмерная позиция")
	text += _row(attenuate, "2", "затухание с расстоянием")
	text += _row(travel, "3", "скорость звука — %.0f м/с (бот в %.1f м, задержка %.0f мс)"
			% [sound_speed, away, away / sound_speed * 1000.0])
	text += _row(occlusion, "4", "окклюзия: %s" % (
			"СТЕНА между вами" if _is_blocked(_bot.global_position)
			else "видно напрямую"))
	text += _row(reflections, "5", "отражения от стен (4 мнимых источника)")
	text += _row(reverb, "6", "реверб комнаты")
	text += _row(variation, "7", "вариативность: 4 варианта + разброс высоты")
	text += _row(layered, "8", "три слоя: щелчок / тело / хвост")
	text += "\n[color=#ffdd66]TAB — закрыть глаза и найти бота на слух[/color]"
	if blind:
		text += "   [color=#ff8866]ГЛАЗА ЗАКРЫТЫ[/color]"
	elif error_degrees >= 0.0:
		text += "   ошибка: [b]%.0f°[/b]" % error_degrees
	text += "\n\nЛКМ — свой выстрел   WASD — ходить   мышь — смотреть\n"
	text += "1…8 — слои по одному   0 — включить всё   ESC — мышь\n"
	text += "[color=#66ccff]выключай по одному и слушай, что перестаёшь ЗНАТЬ[/color]"
	_label.text = text


func _on_far_flash_timeout() -> void:
	_far_flash.visible = false
