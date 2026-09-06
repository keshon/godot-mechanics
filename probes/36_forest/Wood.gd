extends Node3D
class_name ForestRig


## 36 — ЛОУ-ПОЛИ ЛЕС
##
## Вопрос пробы: **из чего складывается ощущение леса.** Не «как нарисовать дерево» — дерево
## тут собирается кодом за сорок строк, — а почему тысяча деревьев ощущается лесом или не
## ощущается.
##
## Гипотеза, которую проба проверяет: ощущение чащи создаётся не деревьями, а тремя вещами
## поверх них — **вариативностью силуэта**, **неравномерностью плотности** и **тем, что
## видно недалеко**. Последнее меряется числом: медианной дальностью до первого ствола.
##
##   1  разные деревья       восемь форм против одной
##   2  ветер                раскачка в вершинном шейдере
##   3  порывы               волна по миру поверх общего трепета
##   4  поляны               плотность из шума вместо ровной россыпи
##   5  подлесок             кусты у стволов
##   6  свет сквозь крону    затенение низа кроны и зелёный отскок
##   7  туман                глубина леса вместо плоской стены
##   8  отсечение по дали    дерево дороже травинки в тысячу раз

@export var walk_speed := 5.0
@export var run_mult := 3.0

var vary := true
var wind_on := true
var gusts := true
var clearings := true
var undergrowth := true
var canopy := true
var fog := true
var culling := true
var floor_layer := true
var shafts := true
var grade := true
var debris := true
## Шесть — это уже настоящий лесной ковёр. Дешевле, чем кажется: трава режется на 34 м,
## и платишь только за ближние клетки.
var grass_i := 2
const GRASS_MULT := [1.0, 3.0, 6.0, 12.0]
## Шкала ветра. Именованная, а не число: «0.8» ничего не говорит, «свежий» говорит всё.
var wind_i := 2
const WIND_NAMES := ["штиль", "лёгкий", "свежий", "сильный", "буря"]
const WIND_FORCE := [0.0, 0.35, 0.8, 1.5, 2.6]

var ms_gpu := 0.0
var ms_cpu := 0.0
var sight := -1.0

var world := Vector3(0.0, 0.0, 0.0)
var _yaw := 0.0
var _pitch := -0.03
var _g
var _f
var _mat: ShaderMaterial


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_g = load("res://probes/36_forest/Ground.gd").new()
	# ЗЕМЛЯ — УЗЕЛ ИЗ СЦЕНЫ. Сетка считается кодом из высот (это данные), а держащий её
	# узел единственный и с положением — он лежит в сцене.
	var gm := $Ground as MeshInstance3D
	gm.mesh = _g.mesh
	gm.material_override = _g.material
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://probes/36_forest/tree.gdshader")
	_f = ForestSim.new()
	_f.setup(_g, self, _mat)
	world.y = _g.height(0.0, 0.0) + 1.7
	_push()


func _push() -> void:
	_mat.set_shader_parameter("wind", WIND_FORCE[wind_i] if wind_on else 0.0)
	_mat.set_shader_parameter("gust_on", 1.0 if gusts else 0.0)
	_mat.set_shader_parameter("canopy_shade", 0.75 if canopy else 0.0)
	_mat.set_shader_parameter("tint_spread", 0.55 if vary else 0.0)
	var env: Environment = ($WorldEnvironment as WorldEnvironment).environment
	env.fog_enabled = fog
	_f.cull = 150.0 if culling else 1000.0
	# МУСОР В ВОЗДУХЕ. Сила ветра — это не только наклон, но и то, что ветер НЕСЁТ.
	# Летящие листья появляются с «сильного» и валят стеной в бурю; тихий лес их не
	# показывает вовсе, и именно поэтому их появление читается сменой погоды.
	var p: GPUParticles3D = $Debris
	var force: float = WIND_FORCE[wind_i] if wind_on else 0.0
	p.emitting = debris and force > 1.0
	p.amount_ratio = clampf((force - 1.0) / 1.6, 0.0, 1.0)
	var pm: ParticleProcessMaterial = p.process_material
	pm.direction = Vector3(0.86, -0.12, 0.5)
	# Не быстрее пятнадцати метров в секунду: на сорока лист пересекает кадр за пару
	# кадров и читается не листом, а точкой.
	pm.initial_velocity_min = 3.0 + 2.5 * force
	pm.initial_velocity_max = 6.0 + 4.0 * force
	# ОБЪЁМНЫЙ ТУМАН — родной способ Godot получить лучи сквозь крону. Считается он не
	# по геометрии, а по освещённости объёма, поэтому дырки в пологе дают настоящие
	# столбы света, а не нарисованные полосы.
	env.volumetric_fog_enabled = shafts
	($Sun as DirectionalLight3D).light_color = (Color(1, 0.85, 0.52) if grade
		else Color(1, 0.97, 0.94))
	# ЦВЕТОКОР: тёплый свет против ЧУТЬ более холодной тени.
	#
	# Первая попытка увела тень в синий (0.20, 0.29, 0.38) — и лес стал ночным. Причина в
	# том, что под пологом прямое солнце почти не доходит, и АМБИЕНТ становится главным
	# цветом кадра: чем он окрашен, тем окрашено всё. В открытой сцене синяя тень читается
	# тенью, в лесу — ночью.
	#
	# Работает разница, а не абсолют: тень холоднее света на несколько процентов, и этого
	# уже достаточно, чтобы зелень читалась зеленью, а луч — светом, а не пылью.
	env.ambient_light_color = (Color(0.20, 0.29, 0.44) if grade
		else Color(0.42, 0.44, 0.42))
	env.adjustment_enabled = grade
	env.ambient_light_energy = 2.2 if grade else 1.5
	# ЦВЕТ ДЫМКИ. Голубая дымка уместна на открытом пейзаже, где её красит небо. Под
	# пологом небо не видно вовсе, а рассеянный свет приходит от листвы — и дымка выходит
	# зеленовато-серой. Синий туман здесь и делал из леса ночь: он покрывает всю глубину
	# кадра, и потому решает цвет сильнее, чем тень.
	env.fog_light_color = (Color(0.56, 0.61, 0.55) if grade else Color(0.66, 0.68, 0.66))
	($Sun as DirectionalLight3D).light_volumetric_fog_energy = 2.2 if shafts else 0.0


func _process(delta: float) -> void:
	_walk(delta)
	_f.update(world)
	# Коробка вылета едет за игроком, но не вращается вместе со взглядом: иначе мусор
	# появляется только там, куда смотришь, и это видно при быстром повороте.
	($Debris as GPUParticles3D).global_position = world + Vector3(-9.0, 6.0, -5.0)
	var cam: Camera3D = $Cam
	cam.position = world
	cam.rotation = Vector3(_pitch, _yaw, 0.0)
	var rid := get_viewport().get_viewport_rid()
	ms_gpu = lerpf(ms_gpu, RenderingServer.viewport_get_measured_render_time_gpu(rid), 0.05)
	ms_cpu = lerpf(ms_cpu, RenderingServer.viewport_get_measured_render_time_cpu(rid), 0.05)
	_hud()


func _walk(delta: float) -> void:
	var f := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var r := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var v := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): v += f
	if Input.is_physical_key_pressed(KEY_S): v -= f
	if Input.is_physical_key_pressed(KEY_D): v += r
	if Input.is_physical_key_pressed(KEY_A): v -= r
	if v != Vector3.ZERO:
		var s := walk_speed * (run_mult if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
		world += v.normalized() * s * delta
	world.y = _g.height(world.x, world.z) + 1.7


func _row(on: bool, key: String, text: String) -> String:
	return "[color=#%s]%s\t%s[/color]\n" % ["88ff99" if on else "666666", key, text]


func _hud() -> void:
	var s := "[font_size=26][b]ЛЕС[/b][/font_size]   деревьев %d, кустов %d, травы %d, видно %d\n" % [
		_f.trees, _f.bushes, _f.grass, _f.visible_now]
	s += "отрисовка [b]%.2f мс[/b] GPU + %.2f CPU   треугольников в дереве ~%d\n" % [
		ms_gpu, ms_cpu, _f.tris_per_tree]
	if sight >= 0.0:
		s += "видно до первого ствола: [b]%.1f м[/b] (медиана по 72 лучам)\n" % sight
	else:
		s += "[color=#ffdd66]M[/color] — замерить, насколько далеко видно\n"
	s += "\n"
	s += _row(vary, "1", "восемь форм деревьев против одной")
	s += _row(wind_on, "2", "ветер: раскачка в вершинах")
	s += _row(gusts, "3", "порывы: волна по миру")
	s += _row(clearings, "4", "поляны: плотность из шума")
	s += _row(undergrowth, "5", "подлесок")
	s += _row(canopy, "6", "свет сквозь крону: затенение низа и зелёный отскок")
	s += _row(fog, "7", "туман — глубина вместо плоской стены")
	s += _row(culling, "8", "отсечение дальних клеток (%.0f м)" % _f.cull)
	s += _row(floor_layer, "9", "напочвенный ярус: трава %d, валежник %d" % [
		_f.grass, _f.deadwood])
	s += _row(shafts, "V", "лучи сквозь крону (объёмный туман)")
	s += _row(grade, "C", "цветокор: тёплый свет против холодной тени")
	s += _row(debris, "B", "мусор в воздухе (с «сильного» и выше)")
	s += _row(grass_i > 0, "[ ]", "густота травы: x%.0f" % GRASS_MULT[grass_i])
	s += _row(wind_on, "+/-", "сила ветра: [b]%s[/b]" % WIND_NAMES[wind_i])
	s += "\nWASD — идти   SHIFT — бежать   M — дальность   +/- — ветер   [ ] — трава   C — цветокор\n"
	s += "[color=#66ccff]выключай по одному и смотри, когда лес перестаёт быть лесом[/color]"
	($Ui/Label as RichTextLabel).text = s


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * 0.0022
		_pitch = clampf(_pitch - event.relative.y * 0.0022, -1.4, 1.4)
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return
	var redo := false
	match (event as InputEventKey).physical_keycode:
		KEY_1: vary = not vary; _f.vary = vary; redo = true
		KEY_2: wind_on = not wind_on
		KEY_3: gusts = not gusts
		KEY_4: clearings = not clearings; _f.clearings = clearings; redo = true
		KEY_5: undergrowth = not undergrowth; _f.undergrowth = undergrowth; redo = true
		KEY_6: canopy = not canopy
		KEY_7: fog = not fog
		KEY_8: culling = not culling
		KEY_9: floor_layer = not floor_layer; _f.floor_layer = floor_layer; redo = true
		KEY_V: shafts = not shafts
		KEY_C: grade = not grade
		KEY_B: debris = not debris
		KEY_BRACKETRIGHT:
			grass_i = mini(grass_i + 1, GRASS_MULT.size() - 1)
			_f.grass_density = GRASS_MULT[grass_i]
			redo = true
		KEY_BRACKETLEFT:
			grass_i = maxi(grass_i - 1, 0)
			_f.grass_density = GRASS_MULT[grass_i]
			redo = true
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			wind_i = mini(wind_i + 1, WIND_NAMES.size() - 1)
		KEY_MINUS, KEY_KP_SUBTRACT:
			wind_i = maxi(wind_i - 1, 0)
		KEY_0:
			vary = true; wind_on = true; gusts = true; clearings = true
			undergrowth = true; canopy = true; fog = true; culling = true
			floor_layer = true; shafts = true; wind_i = 2; _f.floor_layer = true
			grade = true; debris = true
			_f.vary = true; _f.clearings = true; _f.undergrowth = true
			redo = true
		KEY_M:
			sight = _f.sight(world)
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if redo:
		_f.rebuild()
	_push()
