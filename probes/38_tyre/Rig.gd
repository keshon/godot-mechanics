extends Node3D
class_name TyreRig
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
## Тот же приём, что краснеющие колёса в соседней пробе, только теперь показывается не
## «сколько израсходовано», а «в каком месте закона мы находимся».

const START := Vector3(0.0, 0.6, 60.0)
const PLOT := Rect2(36.0, 470.0, 300.0, 150.0)
## Верх шкалы скольжения. Ставил 0.6 — интересная часть кривой занимала левую пятую
## часть графика, а остальное было полкой. Пик у щёточной модели около 0.17.
const SIGMA_MAX := 0.35

@export var distance := 7.0
@export var height := 2.6
@export var follow_lag := 6.0
@export_range(0.0, 1.0, 0.05) var velocity_follow := 0.7

var _car: TyreChassis
var _cam: Camera3D
var _dir := Vector3.FORWARD
var _wet := false
var _diff := 0
var _bars := 0

@onready var _hud: RichTextLabel = $Ui/Hud
@onready var _keys: Label = $Ui/Keys
@onready var _curve: Line2D = $Ui/Plot/Curve
@onready var _peak: Line2D = $Ui/Plot/Peak


func _ready() -> void:
	_car = $Chassis
	_cam = $Camera
	_reset()


func _physics_process(_delta: float) -> void:
	_car.throttle = Input.get_action_strength(&"move_forward")
	_car.brake = Input.get_action_strength(&"move_back")
	_car.steer_input = Input.get_action_strength(&"move_left") \
		- Input.get_action_strength(&"move_right")
	_car.handbrake = Input.is_action_pressed(&"jump")


func _process(delta: float) -> void:
	_camera(delta)
	_readout()
	_plot()


func _camera(delta: float) -> void:
	var flat := Vector3(_car.linear_velocity.x, 0.0, _car.linear_velocity.z)
	var want := -_car.global_basis.z
	if flat.length() > 6.0:
		want = want.lerp(flat.normalized(), velocity_follow).normalized()
	_dir = _dir.lerp(want, 1.0 - exp(-4.0 * delta)).normalized()
	var target := _car.global_position - _dir * distance + Vector3.UP * height
	_cam.global_position = _cam.global_position.lerp(target, 1.0 - exp(-follow_lag * delta))
	_cam.look_at(_car.global_position + Vector3.UP * 0.7)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1: _car.model = (_car.model + 1) % 3
		KEY_2: _car.load_sensitivity = 0.0 if _car.load_sensitivity > 0.0 else 0.14
		KEY_3: _set_diff((_diff + 1) % 3)
		KEY_4: _car.abs_on = not _car.abs_on
		KEY_5: _car.traction_control = not _car.traction_control
		KEY_6:
			_car.layout = (_car.layout + 1) % 3
			_car.relayout()
		KEY_7: _set_bars((_bars + 1) % 3)
		KEY_9: _car.relaxation = 0.0 if _car.relaxation > 0.0 else 0.45
		KEY_8: _car.mu = 0.62 if not _wet else 1.05; _wet = not _wet
		KEY_TAB: _reset()


## БАЛАНС СТАБИЛИЗАТОРОВ. Жёсткий передний — недостаточная поворачиваемость, жёсткий
## задний — избыточная. Работает это ТОЛЬКО при падающей μ: жёсткая ось сильнее
## перекидывает вес с внутреннего колеса на внешнее, а перекинутый вес теряется. При
## постоянной μ ничего не теряется, и ручка становится пустой.
func _set_bars(mode: int) -> void:
	_bars = mode
	_car.anti_roll_front = [11000.0, 26000.0, 4000.0][mode]
	_car.anti_roll_rear = [11000.0, 4000.0, 26000.0][mode]


func _set_diff(mode: int) -> void:
	_diff = mode
	_car.diff_lock = [0.0, 45.0, 400.0][mode]
	_car.diff_preload = [0.0, 60.0, 120.0][mode]


func _reset() -> void:
	# ТВЁРДОЕ ТЕЛО НЕ ТЕЛЕПОРТИРУЮТ ПРИСВАИВАНИЕМ ТРАНСФОРМА. Между кадрами им владеет
	# физический сервер, и запись снаружи он видит как рывок: тело успевает вытолкнуться
	# из проникновения и улететь. Штатный способ — сказать серверу напрямую.
	var rid := _car.get_rid()
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM,
		Transform3D(Basis(), START))
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY,
		Vector3.ZERO)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY,
		Vector3.ZERO)
	for w in _car.wheels:
		w.omega = 0.0
		w.lag = Vector2.ZERO
	_car.train.gear = 1


## КРИВАЯ ШИНЫ ДЛЯ НОМИНАЛЬНОЙ НАГРУЗКИ плюс четыре точки — где сейчас каждое колесо.
func _plot() -> void:
	var fz: float = _car.body_mass * 9.81 * 0.25
	var grip: float = _car.mu
	var pts := PackedVector2Array()
	for i in 41:
		var sigma := SIGMA_MAX * float(i) / 40.0
		# Кривая строится по чистому продольному скольжению: κ, при котором вектор
		# скольжения равен sigma. Годится как разрез закона — он изотропный.
		var f: Vector2 = TyreLaw.force(_car.model, sigma / maxf(1.0 - sigma, 0.2), 0.0, grip,
			fz, _car.slip_stiffness * fz, _car.pacejka_shape, _car.pacejka_curvature)
		pts.append(_to_plot(sigma, f.length() / (grip * fz)))
	_curve.points = pts
	_peak.points = PackedVector2Array([_to_plot(0.0, 1.0), _to_plot(SIGMA_MAX, 1.0)])

	for i in 4:
		# По имени, а не по индексу: порядок детей в сцене — не контракт, и первая же
		# вставленная линия сдвинула бы все точки.
		var dot: ColorRect = $Ui/Plot.get_node("D%d" % i)
		var w = _car.wheels[i]
		var s := TyreLaw.slip_vector(w.kappa, w.alpha).length()
		var mu_now: float = TyreLaw.mu_at(_car.mu, w.load, _car.body_mass * 9.81 * 0.25,
			_car.load_sensitivity)
		var used := 0.0
		if w.load > 1.0:
			used = Vector2(w.fx, w.fy).length() / float(_car.substeps) / (mu_now * w.load)
		dot.position = _to_plot(s, used) - dot.size * 0.5
		dot.visible = w.grounded


func _to_plot(sigma: float, share: float) -> Vector2:
	return Vector2(PLOT.position.x + clampf(sigma / SIGMA_MAX, 0.0, 1.06) * PLOT.size.x,
		PLOT.position.y + PLOT.size.y - clampf(share, 0.0, 1.15) * PLOT.size.y * 0.85)


func _readout() -> void:
	var speed := _car.linear_velocity.dot(-_car.global_basis.z) * 3.6
	var w := _car.wheels
	_hud.text = "\n".join(PackedStringArray([
		"[b]%d[/b] км/ч     передача %d     %d об/мин%s" % [roundi(speed),
			_car.train.gear, roundi(_car.train.rpm()),
			"     СЦЕПЛЕНИЕ БУКСУЕТ" if absf(_car.train.clutch_torque) >= \
				_car.train.clutch_capacity - 1.0 else ""],
		"",
		"продольное скольжение κ   (+ буксует, −1 заблокировано)",
		"   %+.2f  %+.2f" % [w[0].kappa, w[1].kappa],
		"   %+.2f  %+.2f" % [w[2].kappa, w[3].kappa],
		"",
		"угол увода α, град        нагрузка, Н",
		"   %+.1f  %+.1f            %d  %d" % [rad_to_deg(w[0].alpha),
			rad_to_deg(w[1].alpha), roundi(w[0].load), roundi(w[1].load)],
		"   %+.1f  %+.1f            %d  %d" % [rad_to_deg(w[2].alpha),
			rad_to_deg(w[3].alpha), roundi(w[2].load), roundi(w[3].load)],
	]))
	_keys.text = "\n".join(PackedStringArray([
		"WASD руль и газ    SPACE ручник    TAB на старт",
		"",
		"1 модель шины: %s" % ["обрезка (как в 37)", "щёточная", "Пацейка"][_car.model],
		"2 падение μ с нагрузкой: %s" % _on(_car.load_sensitivity > 0.0),
		"3 дифференциал: %s" % ["открытый", "самоблок", "заваренный"][_diff],
		"4 ABS: %s" % _on(_car.abs_on),
		"5 контроль тяги: %s" % _on(_car.traction_control),
		"6 привод: %s" % ["передний", "задний", "полный"][_car.layout],
		"7 стабилизаторы: %s" % ["поровну", "жёстче перед", "жёстче зад"][_bars],
		"8 покрытие: %s" % ("мокрое" if _wet else "сухое"),
		"9 релаксация: %s" % _on(_car.relaxation > 0.0),
	]))


func _on(v: bool) -> String:
	return "вкл" if v else "выкл"
