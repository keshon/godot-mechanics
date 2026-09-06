extends Node3D
class_name DetailRig


## 35 — ДЕТАЛИЗАЦИЯ ПОВЕРХНОСТИ
##
## Тридцать четвёртая проба отвечала на вопрос «как держать мир, который больше экрана».
## Эта отвечает на соседний и совершенно другой: **что происходит между вершинами.**
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

@export var fly_speed := 14.0
@export var fast_mult := 4.0

var ms_gpu := 0.0
var ms_cpu := 0.0
var shimmer := -1.0
var shimmer_off := -1.0

var detail := true
var fade := true
var triplanar := true
var splat := true
var macro := true
## Вид параллакса, а не выключатель. Прежний булев переключатель игрок не мог различить
## на глаз — эффект был слишком слаб, — и было непонятно, включён он или сломан. Явное
## название режима в HUD снимает вопрос по построению.
var pom_mode := 0
const POM_NAMES := ["нет", "классический (1 выборка)", "с ограничением смещения",
	"крутой марш (12 шагов)", "POM: марш + интерполяция", "рельефное: марш + двоичный поиск"]
var props := true
var all_layers := true
var wet := false
var size_i := 0
const SIZES := [128, 512, 1024]

var world := Vector3(0.0, 0.0, 40.0)
var _yaw := 0.0
var _pitch := -0.12
var _g
var _s
var _mat: ShaderMaterial
var _mi: MeshInstance3D
var _busy := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_g = DetailGround.new()
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://probes/35_detail/detail.gdshader")
	_mat.set_shader_parameter("detail_tex", _g.detail_tex)
	_mat.set_shader_parameter("macro_tex", _g.macro_tex)
	_mat.set_shader_parameter("layers_tex", _g.layers_tex)
	# ЗЕМЛЯ — УЗЕЛ ИЗ СЦЕНЫ. Сама сетка считается кодом из высот, и иначе нельзя: это
	# данные. Но узел, который её держит, единственный и с положением — ему место в
	# сцене, иначе проба открывается пустым узлом со скриптом.
	_mi = $Ground
	_mi.mesh = _g.mesh
	_mi.material_override = _mat
	_s = DetailScatter.new()
	_s.setup(_g, self)
	world.y = _g.height(world.x, world.z) + 1.7
	_push()


func _push() -> void:
	_mat.set_shader_parameter("detail_on", 1.0 if detail else 0.0)
	_mat.set_shader_parameter("fade_on", 1.0 if fade else 0.0)
	_mat.set_shader_parameter("triplanar_on", 1.0 if triplanar else 0.0)
	_mat.set_shader_parameter("splat_on", 1.0 if splat else 0.0)
	_mat.set_shader_parameter("macro_on", 1.0 if macro else 0.0)
	_mat.set_shader_parameter("pom_mode", pom_mode)
	_mat.set_shader_parameter("all_layers", 1.0 if all_layers else 0.0)
	_mat.set_shader_parameter("wet", 1.0 if wet else 0.0)
	_s.set_on(props)
	_s.update(world)


func _process(delta: float) -> void:
	_fly(delta)
	_s.update(world)
	var cam: Camera3D = $Cam
	cam.position = world
	cam.rotation = Vector3(_pitch, _yaw, 0.0)
	var rid := get_viewport().get_viewport_rid()
	ms_gpu = lerpf(ms_gpu, RenderingServer.viewport_get_measured_render_time_gpu(rid), 0.05)
	ms_cpu = lerpf(ms_cpu, RenderingServer.viewport_get_measured_render_time_cpu(rid), 0.05)
	_hud()


func _fly(delta: float) -> void:
	var f := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var r := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var v := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): v += f
	if Input.is_physical_key_pressed(KEY_S): v -= f
	if Input.is_physical_key_pressed(KEY_D): v += r
	if Input.is_physical_key_pressed(KEY_A): v -= r
	if Input.is_physical_key_pressed(KEY_E): v += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q): v -= Vector3.UP
	if v != Vector3.ZERO:
		var sp := fly_speed * (fast_mult if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
		world += v.normalized() * sp * delta


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
	var vp := get_viewport()
	for pass_i in 2:
		fade = pass_i == 0
		_push()
		var base := world
		await RenderingServer.frame_post_draw
		var a := vp.get_texture().get_image()
		world = base + Vector3(0.01, 0.0, 0.0)
		($Cam as Camera3D).position = world
		await RenderingServer.frame_post_draw
		var b := vp.get_texture().get_image()
		world = base
		var sum := 0.0
		var n := 0
		# верхняя половина кадра — это даль: камера смотрит почти горизонтально
		for y in range(60, int(a.get_height() * 0.45), 3):
			for x in range(0, a.get_width(), 3):
				var ca := a.get_pixel(x, y)
				var cb := b.get_pixel(x, y)
				sum += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
				n += 1
		var v := sum / maxf(float(n), 1.0) * 1000.0
		if pass_i == 0:
			shimmer = v
		else:
			shimmer_off = v
	fade = was
	_push()
	_busy = false


func _row(on: bool, key: String, text: String) -> String:
	return "[color=#%s]%s\t%s[/color]\n" % ["88ff99" if on else "666666", key, text]


func _hud() -> void:
	var gh: float = _g.height(world.x, world.z)
	var s := "[font_size=26][b]ДЕТАЛИЗАЦИЯ[/b][/font_size]   над землёй %.1f м\n" % (world.y - gh)
	s += "отрисовка [b]%.2f мс[/b] GPU + %.2f CPU   треугольников %d   мелочи %d\n" % [
		ms_gpu, ms_cpu, _g.tris, _s.visible_now]
	if shimmer >= 0.0:
		s += "мерцание вдали: с затуханием [color=#88ff99]%.2f[/color]   без [color=#ff8866]%.2f[/color]   хуже в %.1f раза\n" % [
			shimmer, shimmer_off, shimmer_off / maxf(shimmer, 0.001)]
	else:
		s += "мерцание: [color=#ffdd66]M[/color] — замерить\n"
	s += "\n"
	s += _row(detail, "1", "детальная нормаль (тайл %.1f м)" % (1.0 / 1.0))
	s += _row(fade, "2", "затухание детали с расстоянием (18…70 м)")
	s += _row(triplanar, "3", "триплanar — три выборки вместо одной")
	s += _row(splat, "4", "слои материала по уклону и высоте")
	s += _row(macro, "5", "против повтора тайла: пятно в цвете + второй масштаб нормали")
	s += _row(pom_mode > 0, "6", "параллакс: %s" % POM_NAMES[pom_mode])
	s += _row(props, "7", "мелочь: %d клеток, трава до %.0f м, камни до %.0f м" % [
		_s.cells(), _s.grass_range, _s.rocks_range])
	s += _row(all_layers, "8", "слои: %s" % ("все четыре выборки" if all_layers
		else "только два главных"))
	s += _row(true, "9", "размер текстуры слоя: %d px, %.1f МБ на карту" % [
		_g.layer_size, _g.layer_mb()])
	s += _row(wet, "R", "мокрая земля — блестящая, шероховатость 0.13")
	s += "\nWASD — идти   Q/E — вниз/вверх   SHIFT — быстро   G — к земле   +/− — дальность мелочи\n"
	s += "[color=#66ccff]подойди вплотную и отойди: смотри, что появляется и что кипит[/color]"
	($Ui/Label as RichTextLabel).text = s


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * 0.0022
		_pitch = clampf(_pitch - event.relative.y * 0.0022, -1.5, 1.5)
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return
	match (event as InputEventKey).physical_keycode:
		KEY_1: detail = not detail
		KEY_2: fade = not fade
		KEY_3: triplanar = not triplanar
		KEY_4: splat = not splat
		KEY_5: macro = not macro
		KEY_6: pom_mode = (pom_mode + 1) % POM_NAMES.size()
		KEY_7: props = not props
		KEY_8: all_layers = not all_layers
		KEY_9:
			size_i = (size_i + 1) % SIZES.size()
			_g.set_layer_size(SIZES[size_i])
			_mat.set_shader_parameter("layers_tex", _g.layers_tex)
		KEY_0:
			detail = true; fade = true; triplanar = true
			splat = true; macro = true; pom_mode = 0; props = true; all_layers = true
		KEY_R: wet = not wet
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			_s.grass_range = minf(_s.grass_range * 1.4, 400.0)
			_s.rocks_range = minf(_s.rocks_range * 1.4, 400.0)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_s.grass_range = maxf(_s.grass_range / 1.4, 6.0)
			_s.rocks_range = maxf(_s.rocks_range / 1.4, 6.0)
		KEY_G:
			world.y = _g.height(world.x, world.z) + 1.7
			_pitch = -0.06
		KEY_M:
			_measure_shimmer()
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_push()
