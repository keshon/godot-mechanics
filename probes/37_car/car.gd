class_name CarBody
extends RigidBody3D
## МАШИНА КАК ЧЕТЫРЕ ЛУЧА.
##
## Кузов — обычное твёрдое тело. Ни клевка, ни крена, ни переноса веса здесь не написано:
## всё это ПОСЛЕДСТВИЯ. Из каждого угла вниз идёт луч, находит дорогу, и на найденной
## длине работает пружина с демпфером. Пружина давит вверх в точке колеса — а точки
## разнесены по кузову, поэтому тело само наклоняется вперёд при торможении и валится
## наружу в повороте.
##
## Второе последствие важнее первого: сила пружины — это НАГРУЗКА на колесо, а нагрузка
## задаёт предел сцепления шины. Значит колесо, с которого при торможении сошёл вес, само
## теряет хватку. Вся «жизнь» машины растёт из этой одной связи.
##
## Чего здесь НЕТ и почему это отдельная проба: модель шины по продольному
## проскальзыванию, дифференциал, геометрия подвески с развалом. Это математика Gran
## Turismo; здесь вопрос про ощущение, а не про круг.

const G := 9.81

@export_group("Тело")
@export var body_mass := 2400.0
## ЦЕНТР МАСС — ОТ НАЧАЛА ТЕЛА, А НЕ ОТ ЗЕМЛИ. Начало тела стоит на высоте ступицы, около
## 0.29 м; со смещением −0.25 центр масс оказывается в четырёх сантиметрах над асфальтом,
## и машина едет как утюг: перенос веса при разгоне даёт восемьдесят ньютонов вместо
## восьмисот, потому что рычаг почти нулевой.
##
## Плюс тридцать пять — это около 0.60 м над землёй. Вездеход сидит выше седана, и это
## главная плата за клиренс: порог опрокидывания = половина колеи / высоту центра масс.
## Здесь 1.15 / 0.60 = 1.92 g, и он ОБЯЗАН быть выше сцепления шин, иначе машина
## переворачивается раньше, чем начинает скользить.
@export var com_offset := Vector3(0.0, 0.35, 0.0)

@export_group("Колёса")
@export var wheel_radius := 0.55
@export var wheelbase := 3.2
@export var track_width := 2.30
@export var mount_height := 0.62
@export var wheel_width := 0.45

@export_group("Подвеска")
## Ход подвески у вездехода ВДВОЕ больше, чем у седана, и это главное, что видно глазом:
## рычаг ходит на ладонь, а не на сантиметр.
@export_range(0.1, 0.8, 0.01) var rest_length := 0.50
@export_range(8000.0, 90000.0, 500.0) var stiffness := 44000.0
@export_range(500.0, 12000.0, 100.0) var damping := 5600.0
## СТАБИЛИЗАТОР ПОПЕРЕЧНОЙ УСТОЙЧИВОСТИ. Связывает левое колесо с правым: сжалось одно —
## второму добавляется столько же. Без него мягкая подвеска валит кузов в повороте до
## разгрузки внутреннего колеса, и машина ложится на бок вместо того, чтобы ехать.
@export_range(0.0, 30000.0, 500.0) var anti_roll := 13000.0

@export_group("Шины")
## Сцепление 1.10, а не 1.35. Это не «занижено ради безопасности»: у дорожной шины
## коэффициент как раз около единицы, и именно поэтому седан скользит, а не кувыркается.
@export_range(0.4, 2.5, 0.05) var grip := 1.10
## Крутизна кривой увода: как быстро боковая сила выходит на предел с ростом угла увода.
@export_range(2.0, 30.0, 0.5) var corner_stiffness := 12.0
## КРУГ ТРЕНИЯ. У шины один запас сцепления на всё: чем больше тратишь на торможение, тем
## меньше остаётся на поворот. Выключи — и машина поедет по рельсам.
@export var friction_circle := true
## Перенос веса можно ОТКЛЮЧИТЬ: сцепление считается от статической нагрузки, а подвеска
## продолжает работать и кузов продолжает кренить. Видно, что даёт вес, а что — только вид.
@export var weight_transfer := true

@export_group("Мотор")
@export var max_torque := 540.0
@export var peak_rpm := 4200.0
@export var idle_rpm := 900.0
@export var redline := 6600.0
@export var gears: Array[float] = [3.40, 2.02, 1.40, 1.05, 0.82]
@export var final_drive := 4.10
## 0 передний, 1 задний, 2 полный. Переднему сносит нос, заднему — корму; это одна из тех
## вещей, которые бесполезно читать и мгновенно понятно рулём.
@export_range(0, 2, 1) var layout := 2
@export var brake_force := 24000.0
## Лобовое сопротивление: 0.4·v². На 140 км/ч это уже около 600 Н, и без него максималка
## упирается только в сопротивление качению, то есть уезжает в никуда.
@export var drag := 0.70

var wheels: Array[CarWheel] = []
var gear := 1
var rpm := 0.0
var throttle := 0.0
var brake := 0.0
var steer_input := 0.0
var handbrake := false

var _steer := 0.0

@onready var _wheel_root: Node3D = $Wheels


func _ready() -> void:
	mass = body_mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = com_offset
	can_sleep = false
	# Godot по умолчанию добавляет своё затухание в режиме COMBINE, и оно молча съедает
	# сотни ньютонов на скорости. Сопротивление воздуха считается ниже честно, поэтому
	# здесь замена, а не сложение.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.6
	# Кузов, форма столкновения и колёса лежат в СЦЕНЕ. Плата за это честная: панели
	# кузова не считаются от колеи и базы — раздвинешь колёса, и кузов надо двигать
	# руками. Ровно так это и работает в проекте, где кузов рисует художник.
	for child in _wheel_root.get_children():
		var wheel := child as CarWheel
		if wheel == null:
			continue
		wheel.travel = rest_length
		# Рычаг и пружина лежат РЯДОМ с колесом, а не под ним: колесо крутится рулём, они
		# не должны. Связываются по имени — «FrontLeft» и «FrontLeftArm» стоят вместе.
		wheel.arm = _wheel_root.get_node_or_null(NodePath(wheel.name + "Arm"))
		wheel.spring = _wheel_root.get_node_or_null(NodePath(wheel.name + "Spring"))
		wheels.append(wheel)


func _physics_process(delta: float) -> void:
	var frame := global_transform
	var up := frame.basis.y
	# Перёд машины — минус Z, как у всего в Godot.
	var ahead := -frame.basis.z
	var along := linear_velocity.dot(ahead)

	# РУЛЬ УМЕНЬШАЕТСЯ СО СКОРОСТЬЮ. Не «реализм», а необходимость: угол, нормальный на
	# парковке, на сотне разворачивает машину поперёк за долю секунды.
	var limit := 0.58 * lerpf(1.0, 0.30, clampf(absf(along) / 30.0, 0.0, 1.0))
	_steer = move_toward(_steer, steer_input * limit, 5.0 * delta)

	_transmission(along)
	var pull := 0.0
	if throttle > 0.01:
		pull = (
				_torque_at(rpm) * max_torque * throttle
				* gears[gear - 1] * final_drive / wheel_radius
		)
	var driven_count := 0
	for wheel in wheels:
		if wheel.driven:
			driven_count += 1
	var pull_each := pull / maxf(driven_count, 1)
	var brake_each := brake * brake_force / float(wheels.size())

	_suspension(up)
	_anti_roll()
	for wheel in wheels:
		if wheel.grounded:
			_tire(wheel, frame, up, ahead, pull_each, brake_each, delta)
		else:
			wheel.grip_used = maxf(wheel.grip_used - delta * 3.0, 0.0)
			# В воздухе колесо продолжает крутиться по скорости кузова: своей угловой
			# скорости у него нет, и остановить его нечему.
			wheel.roll = along
		_place(wheel, delta)

	# Сопротивление воздуха — в центр масс, чтобы оно не создавало момента.
	var speed := linear_velocity.length()
	if speed > 0.1:
		apply_central_force(-linear_velocity / speed * drag * speed * speed)


## Пересборка привода после смены раскладки — колёса при этом не трогаются.
func relayout() -> void:
	for wheel in wheels:
		wheel.driven = _driven(wheel.front)


func _driven(front: bool) -> bool:
	if layout == 0:
		return front
	if layout == 1:
		return not front
	return true


## ЛУЧ, ПРУЖИНА, ДЕМПФЕР — на каждое колесо. Всё, что дальше называется «переносом веса»,
## это просто четыре разных значения `wheel_load`.
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
		var squeeze := rest_length - wheel.travel
		# Скорость сжатия берётся В ТОЧКЕ КРЕПЛЕНИЯ, а не в центре масс: у вращающегося
		# тела это разные скорости, и именно разница гасит крен.
		var at_point := linear_velocity + angular_velocity.cross(
				attach - global_position - com_world)
		wheel.wheel_load = maxf(stiffness * squeeze - damping * at_point.dot(up), 0.0)


## Стабилизатор перекидывает часть нагрузки со сжатого колеса на разгруженное по той же
## оси. Считается ПОСЛЕ пружин, потому что ему нужна их разница.
func _anti_roll() -> void:
	if anti_roll <= 0.0:
		return
	for pair in [[0, 1], [2, 3]]:
		var left: CarWheel = wheels[pair[0]]
		var right: CarWheel = wheels[pair[1]]
		# ЗНАК. Стабилизатор давит ВВЕРХ на сжатую сторону и вниз на разгруженную. С
		# обратным знаком это не слабый стабилизатор, а стабилизатор НАОБОРОТ: он
		# добавляет крен вместо того, чтобы его убирать. Ловится только тем, что усиление
		# ручки УХУДШАЕТ картину — крен растёт с 0.25 до 0.30, а внутренние колёса
		# отрываются полностью. Ручка, которая работает в обратную сторону, выглядит как
		# слабая ручка.
		var shift := (left.travel - right.travel) * anti_roll
		if left.grounded:
			left.wheel_load = maxf(left.wheel_load - shift, 0.0)
		if right.grounded:
			right.wheel_load = maxf(right.wheel_load + shift, 0.0)


func _tire(
		wheel: CarWheel,
		frame: Transform3D,
		up: Vector3,
		ahead: Vector3,
		pull_each: float,
		brake_each: float,
		delta: float) -> void:
	var com_world := frame.basis * center_of_mass
	var attach: Vector3 = frame * wheel.attach
	# ТОЧКА В `apply_force` — СМЕЩЕНИЕ ОТ НАЧАЛА ТЕЛА, а не от центра масс и не мировая.
	# Момент Godot считает сам, вычитая центр масс; передашь мировую точку — машину
	# закрутит вокруг начала координат сцены.
	apply_force(up * wheel.wheel_load, attach - global_position)

	var contact := wheel.hit
	var ground := wheel.normal
	var at_point := linear_velocity + angular_velocity.cross(
			contact - global_position - com_world)
	var wheel_ahead := ahead.rotated(up, _steer if wheel.front else 0.0)
	wheel_ahead = (wheel_ahead - ground * wheel_ahead.dot(ground)).normalized()
	var wheel_right := ground.cross(wheel_ahead).normalized()
	var speed_along := at_point.dot(wheel_ahead)
	wheel.roll = speed_along
	var speed_across := at_point.dot(wheel_right)

	# СЦЕПЛЕНИЕ ПРОПОРЦИОНАЛЬНО НАГРУЗКЕ — здесь и происходит перенос веса. Выключатель
	# подменяет нагрузку статической: подвеска и крен остаются, а машина перестаёт «жить».
	var carried := wheel.wheel_load if weight_transfer else body_mass * G * 0.25
	var friction := grip
	if handbrake and not wheel.front:
		friction *= 0.32
	var budget := carried * friction

	# Угол увода в малоугловом приближении. Знаменатель ограничен снизу: на околонуле
	# любое боковое движение даёт бесконечный угол, и машину выстреливает с места.
	var slip := -speed_across / maxf(absf(speed_along), 2.5)
	wheel.slip = slip
	var sideways := clampf(slip * corner_stiffness, -1.0, 1.0) * budget

	var forwards := 0.0
	if wheel.driven:
		forwards += pull_each
	if brake_each > 0.0:
		# Тормоз не должен разворачивать колесо назад за один шаг: ограничиваем импульсом,
		# который останавливает четверть массы ровно к концу тика.
		forwards -= signf(speed_along) * minf(
				brake_each, absf(speed_along) * mass * 0.25 / maxf(delta, 0.001))
	if handbrake and not wheel.front:
		forwards -= signf(speed_along) * budget
	# Сопротивление качению.
	forwards -= signf(speed_along) * carried * 0.015

	var force := Vector2(forwards, sideways)
	if friction_circle:
		# ОДИН ЗАПАС НА ВСЁ. Тормозишь в пол — на поворот не остаётся ничего, и руль
		# перестаёт отвечать. Без этой строки машина едет по рельсам и не умеет ошибаться.
		if force.length() > budget:
			force = force.normalized() * budget
	else:
		force = Vector2(
				clampf(forwards, -budget, budget), clampf(sideways, -budget, budget))
	wheel.grip_used = clampf(force.length() / budget, 0.0, 1.0) if budget > 1.0 else 0.0
	apply_force(
			wheel_ahead * force.x + wheel_right * force.y, contact - global_position)


## Автомат: переключение по оборотам. Не про реализм — про то, чтобы руки были заняты
## рулём, а не передачами, пока щупаешь сцепление.
func _transmission(along: float) -> void:
	rpm = _rpm_at(along)
	if rpm > redline * 0.88 and gear < gears.size():
		gear += 1
	elif rpm < idle_rpm * 2.4 and gear > 1:
		gear -= 1
	rpm = _rpm_at(along)


func _rpm_at(along: float) -> float:
	var turns := absf(along) / (TAU * wheel_radius) * 60.0
	return clampf(turns * gears[gear - 1] * final_drive, idle_rpm, redline)


## Кривая момента — треугольник с вершиной на `peak_rpm`. Настоящая полка сложнее, но
## разница между «тянет везде» и «тянет только вверху» ловится и на треугольнике.
##
## Крутизна 0.55, а не 0.75: на холостых треугольник с 0.75 даёт сорок процентов момента,
## и машина трогается как гружёный автобус. У живого мотора на низах остаётся больше
## половины.
func _torque_at(revs: float) -> float:
	return clampf(1.0 - absf(revs - peak_rpm) / peak_rpm * 0.55, 0.45, 1.0)


func _place(wheel: CarWheel, delta: float) -> void:
	var hub := Vector3(wheel.attach.x, wheel.attach.y - wheel.travel, wheel.attach.z)
	wheel.position = hub
	wheel.rotation.y = _steer if wheel.front else 0.0

	# КАЧЕНИЕ. Угол берётся из скорости в точке контакта: настоящей угловой скорости
	# колеса в этой модели нет, поэтому ни пробуксовку, ни блокировку показать нечем — это
	# уже проскальзывание, математика соседней пробы. Ручник — исключение: там колесо
	# заведомо стоит, и остановленный протектор честнее крутящегося.
	if not (handbrake and not wheel.front):
		wheel.spin.rotation.x = wrapf(
				wheel.spin.rotation.x - wheel.roll / wheel.radius * delta, -PI, PI)

	# РЫЧАГ И ПРУЖИНА — от рамы к ступице. Внутренний шарнир близко к оси машины, верхняя
	# опора пружины над ним; обе точки неподвижны в осях кузова, а ступица ездит. Ровно
	# так это и выглядит на настоящей машине, и ровно поэтому ход подвески видно.
	var side := signf(wheel.attach.x)
	var joint := Vector3(side * 0.26, mount_height - 0.20, wheel.attach.z)
	# Опора пружины вынесена НАРУЖУ от оси машины и ВПЕРЁД (назад у задних) — там, где на
	# настоящей машине стоит амортизатор и где его действительно видно в арке. Икс почти
	# на колее: с опорой ближе к центру пружина уезжает внутрь корпуса и торчит из капота.
	var lean := -0.52 if wheel.front else 0.52
	var top := Vector3(side * 0.95, mount_height + 0.32, wheel.attach.z + lean)
	wheel.place_linkage(joint, hub, top)

	wheel.tint_by_grip()
