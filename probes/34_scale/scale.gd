class_name ScaleRig
extends Node3D
## 34 — МАСШТАБ: КАК ДЕРЖАТЬ МИР, КОТОРЫЙ БОЛЬШЕ ЭКРАНА
##
## Проба сравнительная. Одна и та же земля собирается двумя разными способами, и вопрос
## только один: **чем платишь за каждый.**
##
##   ЧАНКИ     независимые куски, рождаются и умирают по расстоянию.
##             Настоящая геометрия — коллизия достаётся даром. Цена платится рывками.
##   КЛИПМАП   кольца вокруг игрока, шаг удваивается наружу, кольца сдвигаются.
##             Постоянное число вершин, дальнее почти не пересчитывается.
##             Физики нет вовсе — её надо строить отдельно.
##
## Вторая ось — ОТКУДА ВЫСОТА: функция в точке (бесконечно, дорого), запечённая карта в
## 16 бит (быстро, повторяется), она же в 8 бит (ровно то, что скачаешь из интернета, и
## ровно та ловушка, которую никто не объясняет).
##
## Третья — КООРДИНАТЫ. `Vector3` в Godot тридцатидвухбитный: на ста километрах от нуля
## шаг сетки уже 6.6 мм, на тысяче — пять сантиметров. Плавающее начало возвращает игрока
## к нулю, и мир становится по-настоящему безграничным. Клавиша 9 отправляет на сто
## километров, чтобы это можно было увидеть глазами, а не только прочитать.

## ЛЕСТНИЦА ДАЛЬНОСТИ. Одна цель в метрах на обе схемы — каждая пересчитывает её в свои
## параметры. Иначе сравнение сползает в «у кого шаг настройки удачнее»: у чанков радиус
## растёт по одному куску, у клипмапа уровень сразу удваивает охват.
const LADDER := [
	192.0, 288.0, 384.0, 512.0, 768.0, 1024.0, 1536.0, 2048.0, 3072.0, 4096.0,
]

@export var fly_speed := 26.0
@export var fast_mult := 5.0
@export var rebase_at := 800.0
@export var autopilot_speed := 90.0
@export var use_paint := true
@export var floating_origin := true

## 0 — чанки, 1 — клипмап.
var scheme := 0
var coverage_step := 3
var fog := true
var autopilot := false
var far_away := false

## ИСТИННОЕ ПОЛОЖЕНИЕ В МИРЕ — в обычных `float`, а они в GDScript ДВОЙНОЙ точности.
## Именно поэтому плавающее начало вообще возможно: авторитетная координата остаётся
## точной, а тридцатидвухбитным остаётся только то, что уходит в отрисовку.
var world := Vector3(0.0, 60.0, 0.0)
var origin := Vector3.ZERO

var gpu_ms := 0.0
var cpu_ms := 0.0
var frame_ms := 0.0
var rebuilds_per_second := 0.0
var rebases := 0
## Худший кадр за последние полсекунды, миллисекунды.
var worst_ms := 0.0
## Сколько стоит само обслуживание схемы, миллисекунды.
var update_ms := 0.0

var _source: ScaleSource
var _chunks: ScaleChunks
var _clipmap: ScaleClipmap
var _material: ShaderMaterial
var _yaw := 0.0
var _pitch := -0.25
var _window := 0.0
var _window_rebuilds := 0
var _last_rebuilds := 0
var _worst := 0.0

@onready var _camera: Camera3D = $Camera
@onready var _chunk_root: Node3D = $Chunks
@onready var _clip_root: Node3D = $Clipmap
@onready var _world_env: WorldEnvironment = $WorldEnvironment
@onready var _label: RichTextLabel = $Ui/Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	RenderingServer.viewport_set_measure_render_time(
			get_viewport().get_viewport_rid(), true)
	_material = ShaderMaterial.new()
	_material.shader = load("res://probes/34_scale/scale.gdshader")
	_source = ScaleSource.new()
	_chunks = ScaleChunks.new()
	_chunks.setup(_source, _chunk_root, _material)
	_clipmap = ScaleClipmap.new()
	_clipmap.setup(_source, _clip_root, _material)
	world.y = _source.height(0.0, 0.0) + 70.0
	_apply_coverage()


func _process(delta: float) -> void:
	_fly(delta)
	# СКОЛЬКО СТОИТ САМО ОБСЛУЖИВАНИЕ СХЕМЫ. Отдельно от отрисовки: у чанков это обход
	# сотен живых кусков каждый кадр, у клипмапа — пять сравнений. Разница тут крупнее,
	# чем в треугольниках, и без этого счётчика её не видно вовсе.
	var started := Time.get_ticks_usec()
	_active().update(world)
	update_ms = lerpf(update_ms, (Time.get_ticks_usec() - started) / 1000.0, 0.06)
	if floating_origin:
		_rebase()
	_camera.position = world - origin
	_camera.rotation = Vector3(_pitch, _yaw, 0.0)

	var viewport := get_viewport().get_viewport_rid()
	gpu_ms = lerpf(
			gpu_ms, RenderingServer.viewport_get_measured_render_time_gpu(viewport), 0.06)
	cpu_ms = lerpf(
			cpu_ms, RenderingServer.viewport_get_measured_render_time_cpu(viewport), 0.06)
	frame_ms = lerpf(frame_ms, delta * 1000.0, 0.06)
	# ХУДШИЙ КАДР МЕРЯЕТСЯ БЕЗ СГЛАЖИВАНИЯ. Сглаженное среднее рывок как раз и прячет, а
	# вся разница между схемами именно в рывках, не в среднем.
	_worst = maxf(_worst, delta * 1000.0)
	_window += delta
	_window_rebuilds += _active().rebuilds - _last_rebuilds
	_last_rebuilds = _active().rebuilds
	if _window >= 0.5:
		rebuilds_per_second = _window_rebuilds / _window
		worst_ms = _worst
		_window = 0.0
		_window_rebuilds = 0
		_worst = 0.0
	_material.set_shader_parameter("paint", 1.0 if use_paint else 0.0)
	_material.set_shader_parameter("amplitude", _source.amplitude)
	_material.set_shader_parameter("origin_y", 0.0)
	_draw_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * 0.0022
		_pitch = clampf(_pitch - event.relative.y * 0.0022, -1.5, 1.5)
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_1:
			_active().clear()
			scheme = 1 - scheme
			_chunk_root.visible = scheme == 0
			_clip_root.visible = scheme == 1
			# Счётчик перестроений принадлежит СХЕМЕ. Без этой строки разность бралась
			# между двумя разными счётчиками и уходила в минус — в замере так и вышло,
			# «−88 в секунду».
			_last_rebuilds = _active().rebuilds
		KEY_2:
			var last := ScaleSource.Mode.DISK if _source.has_disk() \
					else ScaleSource.Mode.BITS8
			_source.mode = 0 if _source.mode >= last else _source.mode + 1
			_chunks.clear()
			_clipmap.clear()
		KEY_3:
			_chunks.use_lod = not _chunks.use_lod
			_clipmap.use_lod = _chunks.use_lod
			_chunks.clear()
			_clipmap.clear()
		KEY_4:
			_chunks.use_seams = not _chunks.use_seams
			_chunks.clear()
		KEY_5:
			_chunks.use_collision = not _chunks.use_collision
			_clipmap.use_collision = _chunks.use_collision
		KEY_6:
			floating_origin = not floating_origin
		KEY_7:
			use_paint = not use_paint
		KEY_8:
			autopilot = not autopilot
		KEY_9:
			far_away = not far_away
			# Прыжок делается по ИСТИННОЙ координате. При выключенном плавающем начале
			# отрисовочная уедет туда же, и сетка float32 станет видна глазом.
			world.x = 100000.0 if far_away else 0.0
			world.y = _source.height(world.x, world.z) + 70.0
			_chunks.clear()
			_clipmap.clear()
		KEY_0:
			_chunks.use_lod = true
			_clipmap.use_lod = true
			_chunks.use_seams = true
			_chunks.use_collision = true
			_clipmap.use_collision = true
			floating_origin = true
			use_paint = true
			autopilot = false
		KEY_R:
			world = Vector3(0.0, _source.height(0.0, 0.0) + 70.0, 0.0)
			far_away = false
			origin = Vector3.ZERO
			rebases = 0
			_chunks.clear()
			_clipmap.clear()
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			coverage_step = mini(coverage_step + 1, LADDER.size() - 1)
			_apply_coverage()
		KEY_MINUS, KEY_KP_SUBTRACT:
			coverage_step = maxi(coverage_step - 1, 0)
			_apply_coverage()
		KEY_T:
			fog = not fog
			_apply_coverage()
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _active() -> ScaleTerrain:
	return _chunks if scheme == 0 else _clipmap


## Цель в метрах превращается в параметры схем. У чанков площадь растёт как КВАДРАТ
## дальности, у клипмапа число уровней — как ЛОГАРИФМ. Вся разница масштабируемости этих
## двух семейств сидит в этих двух строчках.
func _apply_coverage() -> void:
	var target: float = LADDER[coverage_step]
	_chunks.radius = clampi(int(ceil(target / _chunks.chunk_size)), 2, 34)
	var ring_span := _clipmap.cells * _clipmap.cell0
	_clipmap.levels = clampi(
			int(ceil(log(target * 2.0 / ring_span) / log(2.0))) + 1, 2, 9)
	_chunks.clear()
	_clipmap.clear()
	_camera.far = target * 2.2 + 400.0
	# ТУМАН ПРИВЯЗАН К ДАЛЬНОСТИ. Край мира видно ровно потому, что за ним ничего нет;
	# единственный честный способ его спрятать — не рисовать дальше, чем видно. Плотность
	# подобрана так, чтобы у самой границы оставалось около трети видимости.
	var environment: Environment = _world_env.environment
	environment.fog_enabled = fog
	environment.fog_density = 1.1 / target


## ПЛАВАЮЩЕЕ НАЧАЛО. Когда отрисовочная координата отходит слишком далеко, весь мир едет
## обратно к нулю. Истинное положение при этом не меняется — меняется только то, из чего
## вычитается. Ровно это и делают взрослые движки под именем origin rebasing.
func _rebase() -> void:
	var render := world - origin
	if Vector2(render.x, render.z).length() < rebase_at:
		return
	var by := Vector3(render.x, 0.0, render.z)
	origin += by
	_chunks.shift(by)
	_clipmap.shift(by)
	rebases += 1


func _fly(delta: float) -> void:
	var ahead := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	if autopilot:
		world += ahead * autopilot_speed * delta
		world.y = _source.height(world.x, world.z) + 45.0
		return
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
	if Input.is_physical_key_pressed(KEY_E):
		wanted += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q):
		wanted -= Vector3.UP
	if wanted == Vector3.ZERO:
		return
	var fast := fast_mult if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
	world += wanted.normalized() * fly_speed * fast * delta


## Наименьшая величина, которую ещё различает `Vector3` на текущем удалении. Это и есть
## «насколько сломаны координаты», выраженное числом, а не ощущением.
func _grid_step(at: float) -> float:
	var here := Vector3(absf(at), 0.0, 0.0)
	var step := 1.0e-7
	while (here + Vector3(step, 0.0, 0.0)).x == here.x and step < 100.0:
		step *= 2.0
	return step


func _row(on: bool, key: String, text: String) -> String:
	return "[color=#%s]%s\t%s[/color]\n" % ["88ff99" if on else "666666", key, text]


func _draw_hud() -> void:
	var active := _active()
	var render := world - origin
	var far := Vector2(world.x, world.z).length()
	var text := "[font_size=28][b]%s[/b][/font_size]   %s\n" % [
		"ЧАНКИ" if scheme == 0 else "КЛИПМАП", _source.label()]
	text += "треугольников [b]%d[/b]   кусков %d   форм коллизии %d\n" % [
		active.tris, active.pieces, active.solid]
	text += "перестроений %.1f/с   последнее %.2f мс   в очереди %d   охват %.0f м\n" % [
		rebuilds_per_second, active.rebuild_ms, active.queued, active.coverage()]
	text += "худший кадр за полсекунды [b]%.2f мс[/b]   кадров в секунду %.0f   " % [
		worst_ms, Engine.get_frames_per_second()]
	text += "обслуживание %.2f мс\n" % update_ms
	text += "отрисовка %.2f мс GPU + %.2f CPU   кадр %.2f мс (с ожиданием vsync)\n" % [
		gpu_ms, cpu_ms, frame_ms]
	text += "от начала координат [b]%.0f м[/b]   для отрисовки %.0f м   сдвигов %d\n" % [
		far, Vector2(render.x, render.z).length(), rebases]
	text += "шаг сетки float32 здесь: [color=#%s]%.4f м[/color]\n\n" % [
		"ff8866" if _grid_step(far) > 0.01 else "88ff99", _grid_step(far)]

	text += _row(scheme == 1, "1", "схема: %s" % (
			"клипмап — кольца" if scheme == 1 else "чанки — независимые куски"))
	text += _row(true, "2", "высота: %s (%s)" % [_source.label(), _source.levels()])
	text += _row(active.use_lod, "3", "уровни детализации")
	if scheme == 0:
		text += _row(_chunks.use_seams, "4", "юбки на швах")
	else:
		text += _row(false, "4", "юбки — у клипмапа швов нет, кольца вложены")
	text += _row(active.use_collision, "5", "коллизия%s" % (
			"" if scheme == 0 else " — отдельным куском, из колец её не получить"))
	text += _row(floating_origin, "6", "плавающее начало (сдвиг за %.0f м)" % rebase_at)
	text += _row(use_paint, "7", "раскраска по уклону и высоте")
	text += _row(true, "+/−", "дальность: цель %.0f м, чанки %.0f м, клипмап %.0f м\n" % [
		LADDER[coverage_step], _chunks.coverage(), _clipmap.coverage()])
	text += _row(fog, "T", "туман по дальности — выключи, чтобы увидеть край мира")
	text += _row(autopilot, "8", "автопилот: лететь прямо на %.0f м/с" % autopilot_speed)
	text += _row(far_away, "9", "прыжок на 100 км от нуля")
	text += "\nWASD — лететь   Q/E — вниз/вверх   SHIFT — быстро   R — в ноль   ESC — мышь\n"
	text += "[color=#66ccff]сравнивай не картинку, а строку «перестроений в секунду»[/color]"
	_label.text = text
