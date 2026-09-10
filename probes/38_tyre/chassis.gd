class_name TyreChassis
extends RigidBody3D
## КУЗОВ, ПОДВЕСКА И ЧЕТЫРЕ КОЛЕСА СО СВОЕЙ УГЛОВОЙ СКОРОСТЬЮ.
##
## Подвеска здесь такая же, как в 37-й, и намеренно: луч, пружина, демпфер, нагрузка.
## Копия, а не общий код — менять её тут не собираемся, она фон. Предмет пробы начинается
## там, где у колеса появляется ω.
##
## ЦЕПОЧКА ПОЛУЧАЕТСЯ ЗАМКНУТОЙ, и в этом вся разница с обрезкой из 37-й:
##
##   момент на колесо → ω растёт → κ растёт → сила растёт → сила ТОРМОЗИТ колесо → ω падает
##
## Колесо само находит равновесие, и это равновесие и есть та точка на кривой шины, в
## которой машина сейчас едет. Пробуксовка — не отдельный режим и не флаг: это просто
## равновесие, ушедшее за пик.
##
## Замкнутая петля жёсткая: инерция колеса мала, а наклон кривой велик, поэтому на
## шестидесяти герцах она разваливается. Отсюда подшаги — единственное место, где эта проба
## стоит дороже соседней по процессору.

const G := 9.81

@export_group("Тело")
@export var body_mass := 1400.0
@export var body_size := Vector3(1.82, 1.0, 4.5)
@export var com_offset := Vector3(0.0, 0.22, 0.0)

@export_group("Колёса")
@export var wheel_radius := 0.33
@export var wheelbase := 2.70
@export var track_width := 1.60
@export var mount_height := 0.32
## Момент инерции колеса, кг·м². Занизишь — колесо срывается от чиха и дребезжит;
## завысишь — пробуксовка становится вялой и ленивой.
@export var wheel_inertia := 1.2

@export_group("Подвеска")
@export var rest_length := 0.34
@export var stiffness := 40000.0
@export var damping := 4200.0
## СТАБИЛИЗАТОРЫ ПО ОСЯМ ОТДЕЛЬНО. В 37-й баланс осей не значил ничего, и это было
## измерено: со стабилизатором и без него скорость в повороте совпадала. Здесь у них
## появляется смысл — но только вместе с падающей μ, и это и есть главный опыт пробы.
@export var anti_roll_front := 11000.0
@export var anti_roll_rear := 11000.0

@export_group("Шина")
@export var model: TyreLaw.Model = TyreLaw.Model.BRUSH
@export_range(0.4, 2.0, 0.05) var mu := 1.05
## Наклон кривой у нуля, в долях нагрузки. Одно число на оба скольжения — упрощение: у
## настоящей шины продольная жёсткость примерно вдвое выше боковой.
@export_range(4.0, 40.0, 0.5) var slip_stiffness := 18.0
## Форма и кривизна для Пацейки. `shape` задаёт, насколько кривая ПАДАЕТ после пика: 1.0 —
## не падает вовсе, 1.35 — отдаёт около пятнадцати процентов, как дорожная шина.
@export var pacejka_shape := 1.35
@export var pacejka_curvature := 0.95
## Падение сцепления с ростом нагрузки. Ноль — поведение 37-й, где перенос веса не
## отнимает ничего.
@export_range(0.0, 0.5, 0.01) var load_sensitivity := 0.14
## Длина релаксации, м. Шина набирает силу не мгновенно, а прокатившись: боковая сила
## отстаёт от руля на эту дистанцию. Она же гасит жёсткость петли на малой скорости.
@export_range(0.0, 2.0, 0.05) var relaxation := 0.45

@export_group("Тормоза и помощь")
@export var brake_torque := 2000.0
@export var brake_bias := 0.62
@export var abs_on := true
@export var traction_control := false

@export_group("Привод")
## 0 передний, 1 задний, 2 полный.
@export_range(0, 2, 1) var layout := 1
## Блокировка дифференциала: 0 открытый, 40 самоблок, 400 заваренный.
@export_range(0.0, 400.0, 5.0) var diff_lock := 0.0
@export_range(0.0, 200.0, 5.0) var diff_preload := 0.0
## Сколько раз за физический тик пересчитывается петля «колесо — шина».
@export_range(1, 16, 1) var substeps := 8

var wheels: Array[TyreWheel] = []
var train := TyreTrain.new()
var throttle := 0.0
var brake := 0.0
var steer_input := 0.0
var handbrake := false

var _steer := 0.0
## Номинальная нагрузка на колесо, ньютоны.
var _load_ref := 1.0
## Демпфирование, которое трансмиссия навязывает колесу: сцепление тянет его к оборотам
## мотора тем сильнее, чем выше передача, и в первой это очень жёстко.
var _train_damping := 0.0

@onready var _wheel_root: Node3D = $Wheels


func _ready() -> void:
	mass = body_mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = com_offset
	can_sleep = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.5
	_load_ref = body_mass * G * 0.25
	for child in _wheel_root.get_children():
		var wheel := child as TyreWheel
		if wheel == null:
			continue
		wheel.travel = rest_length
		wheel.driven = _driven(wheel.front)
		wheels.append(wheel)


func _physics_process(delta: float) -> void:
	var frame := global_transform
	var up := frame.basis.y
	var ahead := -frame.basis.z
	var along := linear_velocity.dot(ahead)

	var limit := 0.55 * lerpf(1.0, 0.32, clampf(absf(along) / 30.0, 0.0, 1.0))
	_steer = move_toward(_steer, steer_input * limit, 5.0 * delta)

	_suspension(up)
	_anti_roll()

	# ПРОТИВОБУКСОВОЧНАЯ И АНТИБЛОКИРОВОЧНАЯ — по одной строке каждая, и обе стали
	# возможны только сейчас: обе смотрят на κ, которого в 37-й не существовало.
	var gas := throttle
	if traction_control:
		for wheel in wheels:
			if wheel.driven and wheel.kappa > 0.14:
				gas = minf(gas, 0.18)

	var driven_omega := 0.0
	var driven_count := 0
	for wheel in wheels:
		if wheel.driven:
			driven_omega += wheel.omega
			driven_count += 1
	if driven_count > 0:
		driven_omega /= float(driven_count)
	_distribute(train.step(delta, gas, driven_omega))
	# Наклон момента сцепления по скорости колеса: k·r², делённое на число ведущих.
	var geared := train.ratio()
	_train_damping = -train.clutch_stiffness * geared * geared / maxf(driven_count, 1)

	var step := delta / float(substeps)
	for wheel in wheels:
		wheel.force_along = 0.0
		wheel.force_across = 0.0
	for _pass in substeps:
		for wheel in wheels:
			_wheel_step(wheel, frame, up, ahead, step)
	for wheel in wheels:
		_apply(wheel, frame, up)
		_place(wheel, delta)

	var speed := linear_velocity.length()
	if speed > 0.1:
		apply_central_force(-linear_velocity / speed * 0.42 * speed * speed)


func relayout() -> void:
	for wheel in wheels:
		wheel.driven = _driven(wheel.front)


func _driven(front: bool) -> bool:
	if layout == 0:
		return front
	if layout == 1:
		return not front
	return true


## Момент со вторичного вала — по осям и дальше через дифференциал по колёсам.
func _distribute(shaft: float) -> void:
	var live: Array = []
	for pair in [[0, 1], [2, 3]]:
		if wheels[pair[0]].driven:
			live.append(pair)
	for wheel in wheels:
		wheel.torque = 0.0
	if live.is_empty():
		return
	var per_axle := shaft / float(live.size())
	for pair in live:
		var left: TyreWheel = wheels[pair[0]]
		var right: TyreWheel = wheels[pair[1]]
		var split := TyreTrain.split(
				per_axle, left.omega, right.omega, diff_lock, diff_preload)
		left.torque = split.x
		right.torque = split.y


func _suspension(up: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var reach := rest_length + wheel_radius
	var com_world := global_transform.basis * center_of_mass
	for wheel in wheels:
		var attach: Vector3 = global_transform * wheel.attach
		var query := PhysicsRayQueryParameters3D.create(
				attach, attach - up * (reach + 0.2))
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		wheel.grounded = not hit.is_empty()
		if not wheel.grounded:
			wheel.travel = rest_length
			wheel.wheel_load = 0.0
			continue
		var contact: Vector3 = hit["position"]
		wheel.hit = contact
		wheel.normal = hit["normal"]
		wheel.travel = clampf(
				(attach - contact).length() - wheel_radius, 0.02, rest_length)
		var at_point := linear_velocity + angular_velocity.cross(
				attach - global_position - com_world)
		wheel.wheel_load = maxf(
				stiffness * (rest_length - wheel.travel) - damping * at_point.dot(up),
				0.0)


func _anti_roll() -> void:
	for pair in [[0, 1, anti_roll_front], [2, 3, anti_roll_rear]]:
		var left: TyreWheel = wheels[pair[0]]
		var right: TyreWheel = wheels[pair[1]]
		var shift: float = (left.travel - right.travel) * pair[2]
		if left.grounded:
			left.wheel_load = maxf(left.wheel_load - shift, 0.0)
		if right.grounded:
			right.wheel_load = maxf(right.wheel_load + shift, 0.0)


## ОДИН ПОДШАГ ПЕТЛИ. Скорость кузова внутри подшагов держится постоянной — её Godot
## обновит один раз за тик; меняется только ω колеса, и именно она требует мелкого шага.
func _wheel_step(
		wheel: TyreWheel,
		frame: Transform3D,
		up: Vector3,
		ahead: Vector3,
		step: float) -> void:
	if not wheel.grounded:
		# В воздухе колесо только раскручивается моментом и ничем не тормозится.
		wheel.omega += wheel.torque / wheel_inertia * step
		wheel.kappa = 0.0
		wheel.alpha = 0.0
		return

	var com_world := frame.basis * center_of_mass
	var at_point := linear_velocity + angular_velocity.cross(
			wheel.hit - global_position - com_world)
	var ground := wheel.normal
	var wheel_ahead := ahead.rotated(up, _steer if wheel.front else 0.0)
	wheel_ahead = (wheel_ahead - ground * wheel_ahead.dot(ground)).normalized()
	var wheel_right := ground.cross(wheel_ahead).normalized()
	var speed_along := at_point.dot(wheel_ahead)
	var speed_across := at_point.dot(wheel_right)

	var slips := TyreLaw.slips(wheel.omega, wheel_radius, speed_along, speed_across)
	# РЕЛАКСАЦИЯ: скольжение доезжает до своего значения не мгновенно, а прокатившись на
	# длину релаксации. Физически это гибкость каркаса; численно — то, что спасает петлю
	# на малой скорости, где мгновенное κ скачет между плюс и минус бесконечностью.
	if relaxation > 0.0:
		# ЗНАМЕНАТЕЛЬ С ПОЛОМ, иначе фильтр умирает на месте. Скорость набегания равна
		# пути, делённому на длину релаксации; на стоящей машине путь нулевой, фильтр
		# застывает, κ навсегда остаётся нулём — и шина не выдаёт силы вообще. Колёса
		# крутятся, машина стоит: буксует ВСЁ и никогда не трогается.
		var rate := (absf(speed_along) + TyreLaw.V_EPS) / relaxation
		wheel.lag = wheel.lag.lerp(slips, clampf(rate * step, 0.0, 1.0))
	else:
		wheel.lag = slips
	wheel.kappa = wheel.lag.x
	wheel.alpha = wheel.lag.y

	var grip := TyreLaw.mu_at(mu, wheel.wheel_load, _load_ref, load_sensitivity)
	if handbrake and not wheel.front:
		grip *= 0.45
	var force := TyreLaw.force(
			model, wheel.kappa, wheel.alpha, grip, wheel.wheel_load,
			slip_stiffness * wheel.wheel_load, pacejka_shape, pacejka_curvature)
	wheel.force_along += force.x
	wheel.force_across += force.y
	wheel.grip_used = clampf(force.length() / maxf(grip * wheel.wheel_load, 1.0), 0.0, 1.0)

	# Колесо: приложенный момент, реакция от продольной силы, потом тормоз отдельно — так,
	# чтобы он мог остановить колесо ровно в ноль, но не провернуть его назад.
	var spin_torque := wheel.torque + TyreLaw.reaction_torque(force.x, wheel_radius)
	spin_torque -= signf(wheel.omega) * wheel.wheel_load * 0.012 * wheel_radius
	# НЕЯВНЫЙ ШАГ. Явное интегрирование колеса неустойчиво в принципе, а не при «слишком
	# крупном шаге»: постоянная времени петли равна инерции колеса, делённой на наклон
	# кривой шины, а наклон растёт при ПАДЕНИИ скорости — на семи метрах в секунду это
	# около 1.3 мс, на двух уже 0.4 мс. Никакое разумное число подшагов не спасает.
	#
	# Спасает поправка на собственный наклон. Наклон берётся численно: считаем силу ещё
	# раз при чуть большей ω и смотрим, насколько изменился момент. Плюс наклон от
	# сцепления, которое тянет колесо к оборотам мотора и тоже жёсткое.
	var probe := 0.5
	var nudged := TyreLaw.slips(
			wheel.omega + probe, wheel_radius, speed_along, speed_across)
	var nudged_force := TyreLaw.force(
			model, nudged.x, wheel.alpha, grip, wheel.wheel_load,
			slip_stiffness * wheel.wheel_load, pacejka_shape, pacejka_curvature)
	var slope := minf((nudged_force.x - force.x) * -wheel_radius / probe, 0.0)
	if wheel.driven:
		slope += _train_damping
	var next := (
			wheel.omega + spin_torque / wheel_inertia * step
			/ (1.0 - slope * step / wheel_inertia)
	)
	var stop := _brake_torque(wheel) / wheel_inertia * step
	wheel.omega = 0.0 if absf(next) <= stop else next - signf(next) * stop


func _brake_torque(wheel: TyreWheel) -> float:
	var share := brake_bias if wheel.front else 1.0 - brake_bias
	var torque := brake * brake_torque * share * 2.0
	if handbrake and not wheel.front:
		torque = maxf(torque, brake_torque * 0.9)
	# АНТИБЛОКИРОВОЧНАЯ. Заблокированное колесо (κ = −1) теряет боковое сцепление целиком,
	# и машина едет прямо, как ни выворачивай руль. Система просто отпускает тормоз, когда
	# проскальзывание уходит глубже порога, — весь принцип в одной строке.
	if abs_on and not handbrake and wheel.kappa < -0.22:
		torque *= 0.15
	return torque


func _apply(wheel: TyreWheel, frame: Transform3D, up: Vector3) -> void:
	var attach: Vector3 = frame * wheel.attach
	apply_force(up * wheel.wheel_load, attach - global_position)
	if not wheel.grounded:
		return
	var ground := wheel.normal
	var wheel_ahead := (-frame.basis.z).rotated(up, _steer if wheel.front else 0.0)
	wheel_ahead = (wheel_ahead - ground * wheel_ahead.dot(ground)).normalized()
	var wheel_right := ground.cross(wheel_ahead).normalized()
	# Силы копились по подшагам — прикладывается среднее за тик.
	var share := 1.0 / float(substeps)
	apply_force(
			wheel_ahead * (wheel.force_along * share)
			+ wheel_right * (wheel.force_across * share),
			wheel.hit - global_position)


func _place(wheel: TyreWheel, delta: float) -> void:
	wheel.position = Vector3(
			wheel.attach.x, wheel.attach.y - wheel.travel, wheel.attach.z)
	wheel.rotation.y = _steer if wheel.front else 0.0
	# Колесо крутится по СВОЕЙ ω, а не по скорости машины. В этом и разница: буксующее
	# колесо видно, потому что метка на диске обгоняет землю.
	wheel.spin.rotation.x = wrapf(
			wheel.spin.rotation.x - wheel.omega * delta, -PI, PI)
	wheel.tint_by_grip()
