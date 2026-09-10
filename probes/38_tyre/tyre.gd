class_name TyreRig
extends Node3D
## РУКИ, КАМЕРА, ПЛОЩАДКА И — ГЛАВНОЕ — КРИВАЯ ШИНЫ НА ЭКРАНЕ.
##
## Вся проба про то, что происходит между колесом и землёй, а происходит оно в одной точке
## на одной кривой. Поэтому кривая рисуется живьём, а по ней бегают четыре точки — по одной
## на колесо. Видно сразу три вещи, которые иначе пришлось бы объяснять словами:
##
##   где пик — до него руль отвечает, после него уже нет;
##   насколько кривая ПАДАЕТ после пика — это и есть разница между «поплыла» и «сорвало»;
##   какое колесо ушло за пик первым — с него и начинается занос.
##
## Тот же приём, что краснеющие колёса в 37-й, только теперь показывается не «сколько
## израсходовано», а «в каком месте закона мы находимся».

const START := Vector3(0.0, 0.6, 60.0)
const PLOT := Rect2(36.0, 470.0, 300.0, 150.0)
## Верх шкалы скольжения. При 0.6 интересная часть кривой занимает левую пятую часть
## графика, а остальное — полка. Пик у щёточной модели около 0.17.
const SIGMA_MAX := 0.35
const BARS_FRONT := [11000.0, 26000.0, 4000.0]
const BARS_REAR := [11000.0, 4000.0, 26000.0]
const DIFF_LOCK := [0.0, 45.0, 400.0]
const DIFF_PRELOAD := [0.0, 60.0, 120.0]

@export var distance := 7.0
@export var height := 2.6
@export var follow_lag := 6.0
@export_range(0.0, 1.0, 0.05) var velocity_follow := 0.7

var _facing := Vector3.FORWARD
var _wet := false
var _diff_step := 0
var _bars_step := 0

@onready var _car: TyreChassis = $Chassis
@onready var _camera: Camera3D = $Camera
@onready var _asphalt: MeshInstance3D = $Pad/Asphalt
@onready var _hud: RichTextLabel = $Ui/Hud
@onready var _keys: Label = $Ui/Keys
@onready var _plot: Control = $Ui/Plot
@onready var _curve: Line2D = $Ui/Plot/Curve
@onready var _peak: Line2D = $Ui/Plot/Peak


func _ready() -> void:
	_paint_pad()
	_reset()


func _process(delta: float) -> void:
	_drive_camera(delta)
	_readout()
	_draw_plot()


func _physics_process(_delta: float) -> void:
	_car.throttle = Input.get_action_strength(&"move_forward")
	_car.brake = Input.get_action_strength(&"move_back")
	_car.steer_input = (
			Input.get_action_strength(&"move_left")
			- Input.get_action_strength(&"move_right")
	)
	_car.handbrake = Input.is_action_pressed(&"jump")


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_1:
			_car.model = (_car.model + 1) % 3
		KEY_2:
			_car.load_sensitivity = 0.0 if _car.load_sensitivity > 0.0 else 0.14
		KEY_3:
			_set_diff((_diff_step + 1) % DIFF_LOCK.size())
		KEY_4:
			_car.abs_on = not _car.abs_on
		KEY_5:
			_car.traction_control = not _car.traction_control
		KEY_6:
			_car.layout = (_car.layout + 1) % 3
			_car.relayout()
		KEY_7:
			_set_bars((_bars_step + 1) % BARS_FRONT.size())
		KEY_8:
			_wet = not _wet
			_car.mu = 0.62 if _wet else 1.05
		KEY_9:
			_car.relaxation = 0.0 if _car.relaxation > 0.0 else 0.45
		KEY_TAB:
			_reset()


## Асфальт, его форма столкновения и отметки каждые десять метров лежат в сцене — их по
## одной штуке, у каждой есть положение, и трогать их надо мышью. Здесь остаётся ровно то,
## что сценой не выражается: сетка. Текстура — данные, а не размещение.
func _paint_pad() -> void:
	var material := StandardMaterial3D.new()
	# СЕТКА НУЖНА НЕ ДЛЯ КРАСОТЫ. На ровном сером асфальте скорость не читается вообще:
	# глазу не за что зацепиться, и сорок километров в час неотличимы от ста двадцати.
	var image := Image.create_empty(64, 64, false, Image.FORMAT_RGB8)
	image.fill(Color(0.26, 0.26, 0.27))
	for i in 64:
		image.set_pixel(i, 0, Color(0.34, 0.34, 0.35))
		image.set_pixel(0, i, Color(0.34, 0.34, 0.35))
	material.albedo_texture = ImageTexture.create_from_image(image)
	var plane: PlaneMesh = _asphalt.mesh
	material.uv1_scale = Vector3(plane.size.x * 0.2, plane.size.x * 0.2, 1.0)
	material.roughness = 0.95
	_asphalt.material_override = material


func _drive_camera(delta: float) -> void:
	var flat := Vector3(_car.linear_velocity.x, 0.0, _car.linear_velocity.z)
	var wanted := -_car.global_basis.z
	if flat.length() > 6.0:
		wanted = wanted.lerp(flat.normalized(), velocity_follow).normalized()
	_facing = _facing.lerp(wanted, 1.0 - exp(-4.0 * delta)).normalized()
	var target := _car.global_position - _facing * distance + Vector3.UP * height
	_camera.global_position = _camera.global_position.lerp(
			target, 1.0 - exp(-follow_lag * delta))
	_camera.look_at(_car.global_position + Vector3.UP * 0.7)


## БАЛАНС СТАБИЛИЗАТОРОВ. Жёсткий передний — недостаточная поворачиваемость, жёсткий
## задний — избыточная. Работает это ТОЛЬКО при падающей μ: жёсткая ось сильнее
## перекидывает вес с внутреннего колеса на внешнее, а перекинутый вес теряется. При
## постоянной μ ничего не теряется, и ручка становится пустой.
func _set_bars(step: int) -> void:
	_bars_step = step
	_car.anti_roll_front = BARS_FRONT[step]
	_car.anti_roll_rear = BARS_REAR[step]


func _set_diff(step: int) -> void:
	_diff_step = step
	_car.diff_lock = DIFF_LOCK[step]
	_car.diff_preload = DIFF_PRELOAD[step]


func _reset() -> void:
	# ТВЁРДОЕ ТЕЛО НЕ ТЕЛЕПОРТИРУЮТ ПРИСВАИВАНИЕМ ТРАНСФОРМА. Между кадрами им владеет
	# физический сервер, и запись снаружи он видит как рывок: тело успевает вытолкнуться
	# из проникновения и улететь. Штатный способ — сказать серверу напрямую.
	var body := _car.get_rid()
	PhysicsServer3D.body_set_state(
			body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), START))
	PhysicsServer3D.body_set_state(
			body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(
			body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	for wheel in _car.wheels:
		wheel.omega = 0.0
		wheel.lag = Vector2.ZERO
	_car.train.gear = 1


## КРИВАЯ ШИНЫ ДЛЯ НОМИНАЛЬНОЙ НАГРУЗКИ плюс четыре точки — где сейчас каждое колесо.
func _draw_plot() -> void:
	var load_ref: float = _car.body_mass * 9.81 * 0.25
	var grip: float = _car.mu
	var points := PackedVector2Array()
	for i in 41:
		var sigma := SIGMA_MAX * float(i) / 40.0
		# Кривая строится по чистому продольному скольжению: κ, при котором вектор
		# скольжения равен sigma. Годится как разрез закона — он изотропный.
		var force := TyreLaw.force(
				_car.model, sigma / maxf(1.0 - sigma, 0.2), 0.0, grip, load_ref,
				_car.slip_stiffness * load_ref, _car.pacejka_shape,
				_car.pacejka_curvature)
		points.append(_to_plot(sigma, force.length() / (grip * load_ref)))
	_curve.points = points
	_peak.points = PackedVector2Array([_to_plot(0.0, 1.0), _to_plot(SIGMA_MAX, 1.0)])

	for i in 4:
		# По имени, а не по индексу: порядок детей в сцене — не контракт, и первая же
		# вставленная линия сдвинула бы все точки.
		var dot: ColorRect = _plot.get_node("D%d" % i)
		var wheel := _car.wheels[i]
		var sigma := TyreLaw.slip_vector(wheel.kappa, wheel.alpha).length()
		var mu_now := TyreLaw.mu_at(
				_car.mu, wheel.wheel_load, load_ref, _car.load_sensitivity)
		var used := 0.0
		if wheel.wheel_load > 1.0:
			var force := Vector2(wheel.force_along, wheel.force_across)
			used = force.length() / float(_car.substeps) / (mu_now * wheel.wheel_load)
		dot.position = _to_plot(sigma, used) - dot.size * 0.5
		dot.visible = wheel.grounded


func _to_plot(sigma: float, share: float) -> Vector2:
	return Vector2(
			PLOT.position.x + clampf(sigma / SIGMA_MAX, 0.0, 1.06) * PLOT.size.x,
			PLOT.position.y + PLOT.size.y - clampf(share, 0.0, 1.15) * PLOT.size.y * 0.85)


func _on_off(value: bool) -> String:
	return "вкл" if value else "выкл"


func _readout() -> void:
	var speed := _car.linear_velocity.dot(-_car.global_basis.z) * 3.6
	var wheels := _car.wheels
	var slipping := ""
	if absf(_car.train.clutch_torque) >= _car.train.clutch_capacity - 1.0:
		slipping = "     СЦЕПЛЕНИЕ БУКСУЕТ"
	_hud.text = "\n".join(PackedStringArray([
		"[b]%d[/b] км/ч     передача %d     %d об/мин%s" % [
			roundi(speed), _car.train.gear, roundi(_car.train.rpm()), slipping],
		"",
		"продольное скольжение κ   (+ буксует, −1 заблокировано)",
		"   %+.2f  %+.2f" % [wheels[0].kappa, wheels[1].kappa],
		"   %+.2f  %+.2f" % [wheels[2].kappa, wheels[3].kappa],
		"",
		"угол увода α, град        нагрузка, Н",
		"   %+.1f  %+.1f            %d  %d" % [
			rad_to_deg(wheels[0].alpha), rad_to_deg(wheels[1].alpha),
			roundi(wheels[0].wheel_load), roundi(wheels[1].wheel_load)],
		"   %+.1f  %+.1f            %d  %d" % [
			rad_to_deg(wheels[2].alpha), rad_to_deg(wheels[3].alpha),
			roundi(wheels[2].wheel_load), roundi(wheels[3].wheel_load)],
	]))
	_keys.text = "\n".join(PackedStringArray([
		"WASD руль и газ    SPACE ручник    TAB на старт",
		"",
		"1 модель шины: %s" % ["обрезка (как в 37)", "щёточная", "Пацейка"][_car.model],
		"2 падение μ с нагрузкой: %s" % _on_off(_car.load_sensitivity > 0.0),
		"3 дифференциал: %s" % ["открытый", "самоблок", "заваренный"][_diff_step],
		"4 ABS: %s" % _on_off(_car.abs_on),
		"5 контроль тяги: %s" % _on_off(_car.traction_control),
		"6 привод: %s" % ["передний", "задний", "полный"][_car.layout],
		"7 стабилизаторы: %s" % ["поровну", "жёстче перед", "жёстче зад"][_bars_step],
		"8 покрытие: %s" % ("мокрое" if _wet else "сухое"),
		"9 релаксация: %s" % _on_off(_car.relaxation > 0.0),
	]))
