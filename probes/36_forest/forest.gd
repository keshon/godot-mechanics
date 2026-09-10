class_name ForestRig
extends Node3D
## 36 — ЛОУ-ПОЛИ ЛЕС
##
## Вопрос пробы: **из чего складывается ощущение леса.** Не «как нарисовать дерево» —
## дерево тут собирается кодом за сорок строк, — а почему тысяча деревьев ощущается лесом
## или не ощущается.
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

const GRASS_MULT := [1.0, 3.0, 6.0, 12.0]
## Шкала ветра. Именованная, а не число: «0.8» ничего не говорит, «свежий» говорит всё.
const WIND_NAMES := ["штиль", "лёгкий", "свежий", "сильный", "буря"]
const WIND_FORCE := [0.0, 0.35, 0.8, 1.5, 2.6]

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
## Шесть — это уже настоящий лесной ковёр. Дешевле, чем кажется: трава режется на 34 м, и
## платишь только за ближние клетки.
var grass_step := 2
var wind_step := 2

var gpu_ms := 0.0
var cpu_ms := 0.0
## Медианная дальность до первого ствола, метры. -1 — ещё не мерили.
var sight := -1.0
var world := Vector3.ZERO

var _ground: ForestGround
var _sim: ForestSim
var _material: ShaderMaterial
var _yaw := 0.0
var _pitch := -0.03

@onready var _camera: Camera3D = $Camera
@onready var _ground_mesh: MeshInstance3D = $Ground
@onready var _sun: DirectionalLight3D = $Sun
@onready var _world_env: WorldEnvironment = $WorldEnvironment
@onready var _debris: GPUParticles3D = $Debris
@onready var _label: RichTextLabel = $Ui/Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	RenderingServer.viewport_set_measure_render_time(
			get_viewport().get_viewport_rid(), true)
	_ground = ForestGround.new()
	# ЗЕМЛЯ — УЗЕЛ ИЗ СЦЕНЫ. Сетка считается кодом из высот (это данные), а держащий её
	# узел единственный и с положением — он лежит в сцене.
	_ground_mesh.mesh = _ground.mesh
	_ground_mesh.material_override = _ground.material
	_material = ShaderMaterial.new()
	_material.shader = load("res://probes/36_forest/tree.gdshader")
	_sim = ForestSim.new()
	_sim.setup(_ground, self, _material)
	world.y = _ground.height(0.0, 0.0) + 1.7
	_push_flags()


func _process(delta: float) -> void:
	_walk(delta)
	_sim.update(world)
	# Коробка вылета едет за игроком, но не вращается вместе со взглядом: иначе мусор
	# появляется только там, куда смотришь, и это видно при быстром повороте.
	_debris.global_position = world + Vector3(-9.0, 6.0, -5.0)
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
		_pitch = clampf(_pitch - event.relative.y * 0.0022, -1.4, 1.4)
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var redo := false
	match event.physical_keycode:
		KEY_1:
			vary = not vary
			_sim.vary = vary
			redo = true
		KEY_2:
			wind_on = not wind_on
		KEY_3:
			gusts = not gusts
		KEY_4:
			clearings = not clearings
			_sim.clearings = clearings
			redo = true
		KEY_5:
			undergrowth = not undergrowth
			_sim.undergrowth = undergrowth
			redo = true
		KEY_6:
			canopy = not canopy
		KEY_7:
			fog = not fog
		KEY_8:
			culling = not culling
		KEY_9:
			floor_layer = not floor_layer
			_sim.floor_layer = floor_layer
			redo = true
		KEY_V:
			shafts = not shafts
		KEY_C:
			grade = not grade
		KEY_B:
			debris = not debris
		KEY_BRACKETRIGHT:
			grass_step = mini(grass_step + 1, GRASS_MULT.size() - 1)
			_sim.grass_density = GRASS_MULT[grass_step]
			redo = true
		KEY_BRACKETLEFT:
			grass_step = maxi(grass_step - 1, 0)
			_sim.grass_density = GRASS_MULT[grass_step]
			redo = true
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			wind_step = mini(wind_step + 1, WIND_NAMES.size() - 1)
		KEY_MINUS, KEY_KP_SUBTRACT:
			wind_step = maxi(wind_step - 1, 0)
		KEY_0:
			vary = true
			wind_on = true
			gusts = true
			clearings = true
			undergrowth = true
			canopy = true
			fog = true
			culling = true
			floor_layer = true
			shafts = true
			grade = true
			debris = true
			wind_step = 2
			_sim.vary = true
			_sim.clearings = true
			_sim.undergrowth = true
			_sim.floor_layer = true
			redo = true
		KEY_M:
			sight = _sim.sight(world)
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if redo:
		_sim.rebuild()
	_push_flags()


func _push_flags() -> void:
	var force: float = WIND_FORCE[wind_step] if wind_on else 0.0
	_material.set_shader_parameter("wind", force)
	_material.set_shader_parameter("gust_on", 1.0 if gusts else 0.0)
	_material.set_shader_parameter("canopy_shade", 0.75 if canopy else 0.0)
	_material.set_shader_parameter("tint_spread", 0.55 if vary else 0.0)
	_sim.cull = 150.0 if culling else 1000.0
	# МУСОР В ВОЗДУХЕ. Сила ветра — это не только наклон, но и то, что ветер НЕСЁТ.
	# Летящие листья появляются с «сильного» и валят стеной в бурю; тихий лес их не
	# показывает вовсе, и именно поэтому их появление читается сменой погоды.
	_debris.emitting = debris and force > 1.0
	_debris.amount_ratio = clampf((force - 1.0) / 1.6, 0.0, 1.0)
	var process: ParticleProcessMaterial = _debris.process_material
	process.direction = Vector3(0.86, -0.12, 0.5)
	# Не быстрее пятнадцати метров в секунду: на сорока лист пересекает кадр за пару кадров
	# и читается не листом, а точкой.
	process.initial_velocity_min = 3.0 + 2.5 * force
	process.initial_velocity_max = 6.0 + 4.0 * force

	var environment: Environment = _world_env.environment
	environment.fog_enabled = fog
	# ОБЪЁМНЫЙ ТУМАН — родной способ Godot получить лучи сквозь крону. Считается он не по
	# геометрии, а по освещённости объёма, поэтому дырки в пологе дают настоящие столбы
	# света, а не нарисованные полосы.
	environment.volumetric_fog_enabled = shafts
	_sun.light_volumetric_fog_energy = 2.2 if shafts else 0.0
	_sun.light_color = Color(1, 0.85, 0.52) if grade else Color(1, 0.97, 0.94)
	# ЦВЕТОКОР: тёплый свет против ЧУТЬ более холодной тени.
	#
	# Тень, уведённая в синий (0.20, 0.29, 0.38), делает лес НОЧНЫМ. Причина в том, что под
	# пологом прямое солнце почти не доходит, и АМБИЕНТ становится главным цветом кадра:
	# чем он окрашен, тем окрашено всё. В открытой сцене синяя тень читается тенью, в лесу
	# — ночью.
	#
	# Работает разница, а не абсолют: тень холоднее света на несколько процентов, и этого
	# уже достаточно, чтобы зелень читалась зеленью, а луч — светом, а не пылью.
	environment.ambient_light_color = (
			Color(0.20, 0.29, 0.44) if grade else Color(0.42, 0.44, 0.42))
	environment.ambient_light_energy = 2.2 if grade else 1.5
	environment.adjustment_enabled = grade
	# ЦВЕТ ДЫМКИ. Голубая дымка уместна на открытом пейзаже, где её красит небо. Под пологом
	# небо не видно вовсе, а рассеянный свет приходит от листвы — и дымка выходит
	# зеленовато-серой. Синий туман здесь и делает из леса ночь: он покрывает всю глубину
	# кадра, и потому решает цвет сильнее, чем тень.
	environment.fog_light_color = (
			Color(0.56, 0.61, 0.55) if grade else Color(0.66, 0.68, 0.66))


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
	if wanted != Vector3.ZERO:
		var fast := run_mult if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
		world += wanted.normalized() * walk_speed * fast * delta
	world.y = _ground.height(world.x, world.z) + 1.7


func _row(on: bool, key: String, text: String) -> String:
	return "[color=#%s]%s\t%s[/color]\n" % ["88ff99" if on else "666666", key, text]


func _draw_hud() -> void:
	var text := "[font_size=26][b]ЛЕС[/b][/font_size]   "
	text += "деревьев %d, кустов %d, травы %d, видно %d\n" % [
		_sim.trees, _sim.bushes, _sim.grass, _sim.visible_now]
	text += "отрисовка [b]%.2f мс[/b] GPU + %.2f CPU   треугольников в дереве ~%d\n" % [
		gpu_ms, cpu_ms, _sim.tris_per_tree]
	if sight >= 0.0:
		text += "видно до первого ствола: [b]%.1f м[/b] (медиана по 72 лучам)\n" % sight
	else:
		text += "[color=#ffd479]M[/color] — замерить, насколько далеко видно\n"
	text += "\n"
	text += _row(vary, "1", "восемь форм деревьев против одной")
	text += _row(wind_on, "2", "ветер: раскачка в вершинах")
	text += _row(gusts, "3", "порывы: волна по миру")
	text += _row(clearings, "4", "поляны: плотность из шума")
	text += _row(undergrowth, "5", "подлесок")
	text += _row(canopy, "6", "свет сквозь крону: затенение низа и зелёный отскок")
	text += _row(fog, "7", "туман — глубина вместо плоской стены")
	text += _row(culling, "8", "отсечение дальних клеток (%.0f м)" % _sim.cull)
	text += _row(floor_layer, "9", "напочвенный ярус: трава %d, валежник %d" % [
		_sim.grass, _sim.deadwood])
	text += _row(shafts, "V", "лучи сквозь крону (объёмный туман)")
	text += _row(grade, "C", "цветокор: тёплый свет против холодной тени")
	text += _row(debris, "B", "мусор в воздухе (с «сильного» и выше)")
	text += _row(grass_step > 0, "[ ]", "густота травы: x%.0f" % GRASS_MULT[grass_step])
	text += _row(wind_on, "+/-", "сила ветра: [b]%s[/b]" % WIND_NAMES[wind_step])
	text += "\nWASD — идти   SHIFT — бежать   M — дальность   +/- — ветер   "
	text += "[ ] — трава   C — цветокор\n"
	text += "[color=#66ccff]выключай по одному и смотри, "
	text += "когда лес перестаёт быть лесом[/color]"
	_label.text = text
