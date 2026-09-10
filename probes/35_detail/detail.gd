class_name DetailRig
extends Node3D
## 35 — ДЕТАЛИЗАЦИЯ ПОВЕРХНОСТИ
##
## 34-я проба отвечала на вопрос «как держать мир, который больше экрана». Эта отвечает на
## соседний и совершенно другой: **что происходит между вершинами.**
##
## Главное, из чего всё растёт: геометрия обязана совпадать с физикой, а затенение — нет.
## Поэтому мелкий рельеф здесь не двигает ни одной вершины; он живёт в нормали, и физика о
## нём не знает. Единственный слой, который добавляет настоящую геометрию, — разбросанная
## мелочь, и она же дороже всех остальных вместе.
##
##   1  детальная нормаль      неровность в пределах текселя
##   2  затухание с далью      без него дальние пиксели кипят
##   3  триплanar              текстура не растягивается на обрывах
##   4  слои материала         трава / камень / песок по уклону и высоте
##   5  макро-вариация         ломает видимый повтор тайла
##   6  параллакс              глубина без вершин
##   7  разбросанная мелочь    камни и трава: единственная настоящая геометрия
##
## Проверять надо не «красиво ли», а две вещи: **цену каждого слоя в миллисекундах** и
## **мерцание вдали**. Второе меряется числом — клавиша `M`.

## Вид параллакса, а не выключатель. Булев переключатель игрок не мог различить на глаз —
## эффект слишком слаб, — и было непонятно, включён он или сломан. Явное название режима
## в табло снимает вопрос по построению.
const POM_NAMES := [
	"нет",
	"классический (1 выборка)",
	"с ограничением смещения",
	"крутой марш (12 шагов)",
	"POM: марш + интерполяция",
	"рельефное: марш + двоичный поиск",
]
const SIZES := [128, 512, 1024]

@export var fly_speed := 14.0
@export var fast_mult := 4.0

var gpu_ms := 0.0
var cpu_ms := 0.0
## Кипение дальней половины кадра, условные единицы. -1 — ещё не мерили.
var shimmer := -1.0
var shimmer_off := -1.0

var detail := true
var fade := true
var triplanar := true
var splat := true
var macro := true
var pom_mode := 0
var props := true
var all_layers := true
var wet := false
var size_step := 0

var world := Vector3(0.0, 0.0, 40.0)

var _ground: DetailGround
var _scatter: DetailScatter
var _material: ShaderMaterial
var _yaw := 0.0
var _pitch := -0.12
var _busy := false

@onready var _camera: Camera3D = $Camera
@onready var _ground_mesh: MeshInstance3D = $Ground
@onready var _label: RichTextLabel = $Ui/Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	RenderingServer.viewport_set_measure_render_time(
			get_viewport().get_viewport_rid(), true)
	_ground = DetailGround.new()
	_material = ShaderMaterial.new()
	_material.shader = load("res://probes/35_detail/detail.gdshader")
	_material.set_shader_parameter("detail_tex", _ground.detail_tex)
	_material.set_shader_parameter("macro_tex", _ground.macro_tex)
	_material.set_shader_parameter("layers_tex", _ground.layers_tex)
	# ЗЕМЛЯ — УЗЕЛ ИЗ СЦЕНЫ. Сама сетка считается кодом из высот, и иначе нельзя: это
	# данные. Но узел, который её держит, единственный и с положением — ему место в сцене,
	# иначе проба открывается пустым узлом со скриптом.
	_ground_mesh.mesh = _ground.mesh
	_ground_mesh.material_override = _material
	_scatter = DetailScatter.new()
	_scatter.setup(_ground, self)
	world.y = _ground.height(world.x, world.z) + 1.7
	_push_flags()


func _process(delta: float) -> void:
	_fly(delta)
	_scatter.update(world)
	_camera.position = world
	_camera.rotation = Vector3(_pitch, _yaw, 0.0)
	var viewport := get_viewport().get_viewport_rid()
	gpu_ms = lerpf(
			gpu_ms, RenderingServer.viewport_get_measured_render_time_gpu(viewport), 0.05)
	cpu_ms = lerpf(
			cpu_ms, RenderingServer.viewport_get_measured_render_time_cpu(viewport), 0.05)
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
			detail = not detail
		KEY_2:
			fade = not fade
		KEY_3:
			triplanar = not triplanar
		KEY_4:
			splat = not splat
		KEY_5:
			macro = not macro
		KEY_6:
			pom_mode = (pom_mode + 1) % POM_NAMES.size()
		KEY_7:
			props = not props
		KEY_8:
			all_layers = not all_layers
		KEY_9:
			size_step = (size_step + 1) % SIZES.size()
			_ground.set_layer_size(SIZES[size_step])
			_material.set_shader_parameter("layers_tex", _ground.layers_tex)
		KEY_0:
			detail = true
			fade = true
			triplanar = true
			splat = true
			macro = true
			pom_mode = 0
			props = true
			all_layers = true
		KEY_R:
			wet = not wet
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			_scatter.grass_range = minf(_scatter.grass_range * 1.4, 400.0)
			_scatter.rocks_range = minf(_scatter.rocks_range * 1.4, 400.0)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_scatter.grass_range = maxf(_scatter.grass_range / 1.4, 6.0)
			_scatter.rocks_range = maxf(_scatter.rocks_range / 1.4, 6.0)
		KEY_G:
			world.y = _ground.height(world.x, world.z) + 1.7
			_pitch = -0.06
		KEY_M:
			_measure_shimmer()
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_push_flags()


func _push_flags() -> void:
	_material.set_shader_parameter("detail_on", 1.0 if detail else 0.0)
	_material.set_shader_parameter("fade_on", 1.0 if fade else 0.0)
	_material.set_shader_parameter("triplanar_on", 1.0 if triplanar else 0.0)
	_material.set_shader_parameter("splat_on", 1.0 if splat else 0.0)
	_material.set_shader_parameter("macro_on", 1.0 if macro else 0.0)
	_material.set_shader_parameter("pom_mode", pom_mode)
	_material.set_shader_parameter("all_layers", 1.0 if all_layers else 0.0)
	_material.set_shader_parameter("wet", 1.0 if wet else 0.0)
	_scatter.showing = props
	_scatter.update(world)


func _fly(delta: float) -> void:
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
	if Input.is_physical_key_pressed(KEY_E):
		wanted += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q):
		wanted -= Vector3.UP
	if wanted == Vector3.ZERO:
		return
	var fast := fast_mult if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
	world += wanted.normalized() * fly_speed * fast * delta


## МЕРЦАНИЕ, ИЗМЕРЕННОЕ ЧИСЛОМ.
##
## Снимаем кадр, сдвигаем камеру на сотую долю метра, снимаем второй и считаем среднюю
## разницу пикселей в ДАЛЬНЕЙ половине экрана. Сдвиг настолько мал, что честная картинка
## обязана почти не измениться; всё, что изменилось, — это выборка текстуры, попавшая в
## другие тексели. Это и есть кипение.
##
## Меряется дважды — с затуханием детали и без, — чтобы число можно было с чем-то сравнить.
func _measure_shimmer() -> void:
	if _busy:
		return
	_busy = true
	var was := fade
	var viewport := get_viewport()
	for run in 2:
		fade = run == 0
		_push_flags()
		var base := world
		await RenderingServer.frame_post_draw
		var before := viewport.get_texture().get_image()
		world = base + Vector3(0.01, 0.0, 0.0)
		_camera.position = world
		await RenderingServer.frame_post_draw
		var after := viewport.get_texture().get_image()
		world = base
		var total := 0.0
		var samples := 0
		# Верхняя половина кадра — это даль: камера смотрит почти горизонтально.
		for y in range(60, int(before.get_height() * 0.45), 3):
			for x in range(0, before.get_width(), 3):
				var was_pixel := before.get_pixel(x, y)
				var now_pixel := after.get_pixel(x, y)
				total += (
						absf(was_pixel.r - now_pixel.r)
						+ absf(was_pixel.g - now_pixel.g)
						+ absf(was_pixel.b - now_pixel.b)
				)
				samples += 1
		var value := total / maxf(float(samples), 1.0) * 1000.0
		if run == 0:
			shimmer = value
		else:
			shimmer_off = value
	fade = was
	_push_flags()
	_busy = false


func _row(on: bool, key: String, text: String) -> String:
	return "[color=#%s]%s\t%s[/color]\n" % ["88ff99" if on else "666666", key, text]


func _draw_hud() -> void:
	var ground_y := _ground.height(world.x, world.z)
	var text := "[font_size=26][b]ДЕТАЛИЗАЦИЯ[/b][/font_size]   над землёй %.1f м\n" % (
			world.y - ground_y)
	text += "отрисовка [b]%.2f мс[/b] GPU + %.2f CPU   треугольников %d   мелочи %d\n" % [
		gpu_ms, cpu_ms, _ground.tris, _scatter.visible_now]
	if shimmer >= 0.0:
		text += "мерцание вдали: с затуханием [color=#7fe08a]%.2f[/color]   " % shimmer
		text += "без [color=#ff8a6a]%.2f[/color]   хуже в %.1f раза\n" % [
			shimmer_off, shimmer_off / maxf(shimmer, 0.001)]
	else:
		text += "мерцание: [color=#ffd479]M[/color] — замерить\n"
	text += "\n"
	text += _row(detail, "1", "детальная нормаль (тайл 1.0 м)")
	text += _row(fade, "2", "затухание детали с расстоянием (18…70 м)")
	text += _row(triplanar, "3", "триплanar — три выборки вместо одной")
	text += _row(splat, "4", "слои материала по уклону и высоте")
	text += _row(
			macro, "5",
			"против повтора тайла: пятно в цвете + второй масштаб нормали")
	text += _row(pom_mode > 0, "6", "параллакс: %s" % POM_NAMES[pom_mode])
	text += _row(props, "7", "мелочь: %d клеток, трава до %.0f м, камни до %.0f м" % [
		_scatter.cells(), _scatter.grass_range, _scatter.rocks_range])
	text += _row(all_layers, "8", "слои: %s" % (
			"все четыре выборки" if all_layers else "только два главных"))
	text += _row(true, "9", "размер текстуры слоя: %d px, %.1f МБ на карту" % [
		_ground.layer_size, _ground.layer_mb()])
	text += _row(wet, "R", "мокрая земля — блестящая, шероховатость 0.13")
	text += "\nWASD — идти   Q/E — вниз/вверх   SHIFT — быстро   G — к земле   "
	text += "+/− — дальность мелочи\n"
	text += "[color=#66ccff]подойди вплотную и отойди: "
	text += "смотри, что появляется и что кипит[/color]"
	_label.text = text
