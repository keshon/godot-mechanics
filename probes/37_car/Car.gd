extends RigidBody3D
class_name CarBody
## МАШИНА КАК ЧЕТЫРЕ ЛУЧА.
##
## Кузов — обычное твёрдое тело. Ни клевка, ни крена, ни переноса веса здесь не написано:
## всё это ПОСЛЕДСТВИЯ. Из каждого угла вниз идёт луч, находит дорогу, и на найденной длине
## работает пружина с демпфером. Пружина давит вверх в точке колеса — а точки разнесены по
## кузову, поэтому тело само наклоняется вперёд при торможении и валится наружу в повороте.
##
## Второе последствие важнее первого: сила пружины — это НАГРУЗКА на колесо, а нагрузка
## задаёт предел сцепления шины. Значит колесо, с которого при торможении сошёл вес, само
## теряет хватку. Вся «жизнь» машины растёт из этой одной связи.
##
## Чего здесь НЕТ и почему это отдельная проба: модель шины по продольному проскальзыванию,
## дифференциал, геометрия подвески с развалом. Это математика Gran Turismo; здесь вопрос
## про ощущение, а не про круг.

const G := 9.81

@export_group("Тело")
@export var body_mass := 2400.0
## ЦЕНТР МАСС — ОТ НАЧАЛА ТЕЛА, А НЕ ОТ ЗЕМЛИ, и на этом я попался. Начало тела стоит на
## высоте ступицы, около 0.29 м; со смещением −0.25 центр масс оказывался в четырёх
## сантиметрах над асфальтом. Машина ехала как утюг: перенос веса при разгоне давал
## восемьдесят ньютонов вместо восьмисот, потому что рычаг был почти нулевой.
##
## Плюс тридцать пять — это около 0.60 м над землёй. Вездеход сидит выше седана, и это
##
## главная плата за клиренс: порог опрокидывания = половина колеи / высоту центра масс.
## Здесь 1.15 / 0.60 = 1.92 g, и он ОБЯЗАН быть выше сцепления шин, иначе машина
## переворачивается раньше, чем начинает скользить. Широкая колея вездехода даёт
## запас, которого не было у седана с колеёй 1.55 и центром масс на 0.54.
@export var com_offset := Vector3(0.0, 0.35, 0.0)

@export_group("Колёса")
@export var wheel_radius := 0.55
@export var wheelbase := 3.2
@export var track_width := 2.30
@export var mount_height := 0.62
@export var wheel_width := 0.45

@export_group("Подвеска")
## Ход подвески у вездехода ВДВОЕ больше, чем у седана, и это главное, что видно
## глазом: рычаг ходит на ладонь, а не на сантиметр.
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

@onready var _wheel_root: Node3D = $Wheels

var _steer := 0.0


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

	# КУЗОВ И ФОРМА СТОЛКНОВЕНИЯ ЛЕЖАТ В СЦЕНЕ. Раньше собирались здесь, и открытая
	# машина показывала четыре колеса без кузова и предупреждение «у узла нет формы» —
	# то есть половина той же ошибки, что и с колёсами, только этажом ниже.
	#
	# Плата за перенос честная: панели кузова больше НЕ СЧИТАЮТСЯ от колеи и базы.
	# Раздвинешь колёса — кузов останется на месте, и его надо двигать руками. Ровно так
	# это и работает в настоящем проекте, где кузов рисует художник.

	# КОЛЁСА БЕРУТСЯ ИЗ СЦЕНЫ. Раньше здесь стояли четыре вызова с посчитанными
	# координатами, и открытая в редакторе машина выглядела пустым узлом. Теперь колесо —
	# узел: видно, можно подвинуть, можно снять галочку «ведущее».
	for child in _wheel_root.get_children():
		var w := child as CarWheel
		if w == null:
			continue
		w.travel = rest_length
		# Рычаг и пружина лежат РЯДОМ с колесом, а не под ним: колесо крутится рулём, они
		# не должны. Связываются по имени — «ПередЛ» и «ПередЛРычаг» стоят вместе.
		w.arm = _wheel_root.get_node_or_null(NodePath(w.name + "Arm"))
		w.spring = _wheel_root.get_node_or_null(NodePath(w.name + "Spring"))
		wheels.append(w)


func _driven(front: bool) -> bool:
	if layout == 0:
		return front
	if layout == 1:
		return not front
	return true


## Пересборка привода после смены раскладки — колёса при этом не трогаются.
func relayout() -> void:
	for w in wheels:
		w.driven = _driven(w.front)


func _physics_process(delta: float) -> void:
	var xf := global_transform
	var up := xf.basis.y
	var fwd := -xf.basis.z          # перёд машины — минус Z, как у всего в Godot
	var v_fwd := linear_velocity.dot(fwd)

	# РУЛЬ УМЕНЬШАЕТСЯ СО СКОРОСТЬЮ. Не «реализм», а необходимость: угол, нормальный на
	# парковке, на сотне разворачивает машину поперёк за долю секунды.
	var limit := 0.58 * lerpf(1.0, 0.30, clampf(absf(v_fwd) / 30.0, 0.0, 1.0))
	_steer = move_toward(_steer, steer_input * limit, 5.0 * delta)

	_transmission(v_fwd)
	var pull := 0.0
	if throttle > 0.01:
		pull = _torque_at(rpm) * max_torque * throttle \
			* gears[gear - 1] * final_drive / wheel_radius
	var driven_count := 0
	for w in wheels:
		if w.driven:
			driven_count += 1
	var pull_each := pull / maxf(driven_count, 1)
	var brake_each := brake * brake_force / float(wheels.size())

	_suspension(up)
	_anti_roll()
	for w in wheels:
		if w.grounded:
			_tire(w, xf, up, fwd, pull_each, brake_each, delta)
		else:
			w.use = maxf(w.use - delta * 3.0, 0.0)
			# В воздухе колесо продолжает крутиться по скорости кузова: своей угловой
			# скорости у него нет, и остановить его нечему.
			w.roll = v_fwd
		_place(w, delta)

	# Сопротивление воздуха — в центр масс, чтобы оно не создавало момента.
	var speed := linear_velocity.length()
	if speed > 0.1:
		apply_central_force(-linear_velocity / speed * drag * speed * speed)


## ЛУЧ, ПРУЖИНА, ДЕМПФЕР — на каждое колесо. Всё, что дальше называется «переносом веса»,
## это просто четыре разных значения `load`.
func _suspension(up: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var reach := rest_length + wheel_radius
	var com_world := global_transform.basis * center_of_mass
	for w in wheels:
		var attach: Vector3 = global_transform * w.attach
		var q := PhysicsRayQueryParameters3D.create(attach, attach - up * (reach + 0.2))
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		w.grounded = not hit.is_empty()
		if not w.grounded:
			w.travel = rest_length
			w.load = 0.0
			continue
		var contact: Vector3 = hit.position
		w.hit = contact
		w.normal = hit.normal
		w.travel = clampf((attach - contact).length() - wheel_radius, 0.02, rest_length)
		var squeeze: float = rest_length - w.travel
		# Скорость сжатия берётся В ТОЧКЕ КРЕПЛЕНИЯ, а не в центре масс: у вращающегося
		# тела это разные скорости, и именно разница гасит крен.
		var at_point := linear_velocity + angular_velocity.cross(
			attach - global_position - com_world)
		w.load = maxf(stiffness * squeeze - damping * at_point.dot(up), 0.0)


## Стабилизатор перекидывает часть нагрузки со сжатого колеса на разгруженное по той же
## оси. Считается ПОСЛЕ пружин, потому что ему нужна их разница.
func _anti_roll() -> void:
	if anti_roll <= 0.0:
		return
	for pair in [[0, 1], [2, 3]]:
		var a: CarWheel = wheels[pair[0]]
		var b: CarWheel = wheels[pair[1]]
		# ЗНАК. Стабилизатор давит ВВЕРХ на сжатую сторону и вниз на разгруженную. Стояло
		# наоборот, и это был не слабый стабилизатор, а стабилизатор НАОБОРОТ: он добавлял
		# крен вместо того, чтобы его убирать. Поймалось только тем, что усиление ручки
		# УХУДШАЛО картину — крен рос с 0.25 до 0.30, а внутренние колёса отрывались
		# полностью. Ручка, которая работает в обратную сторону, выглядит как слабая ручка.
		var shift: float = (a.travel - b.travel) * anti_roll
		if a.grounded:
			a.load = maxf(a.load - shift, 0.0)
		if b.grounded:
			b.load = maxf(b.load + shift, 0.0)


func _tire(w: CarWheel, xf: Transform3D, up: Vector3, fwd: Vector3,
		pull_each: float, brake_each: float, delta: float) -> void:
	var com_world := xf.basis * center_of_mass
	var attach: Vector3 = xf * w.attach
	# ТОЧКА В `apply_force` — СМЕЩЕНИЕ ОТ НАЧАЛА ТЕЛА, а не от центра масс и не мировая.
	# Момент Godot считает сам, вычитая центр масс; передашь мировую точку — машину
	# закрутит вокруг начала координат сцены.
	apply_force(up * w.load, attach - global_position)

	var contact: Vector3 = w.hit
	var n: Vector3 = w.normal
	var at_point := linear_velocity + angular_velocity.cross(
		contact - global_position - com_world)
	var wf := fwd.rotated(up, _steer if w.front else 0.0)
	wf = (wf - n * wf.dot(n)).normalized()
	var wr := n.cross(wf).normalized()
	var v_long := at_point.dot(wf)
	w.roll = v_long
	var v_lat := at_point.dot(wr)

	# СЦЕПЛЕНИЕ ПРОПОРЦИОНАЛЬНО НАГРУЗКЕ — здесь и происходит перенос веса. Выключатель
	# подменяет нагрузку статической: подвеска и крен остаются, а машина перестаёт «жить».
	var load: float = w.load if weight_transfer else body_mass * G * 0.25
	var mu := grip
	if handbrake and not w.front:
		mu *= 0.32
	var budget := load * mu

	# Угол увода в малоугловом приближении. Знаменатель ограничен снизу: на околонуле любое
	# боковое движение даёт бесконечный угол, и машину выстреливает с места.
	var slip := -v_lat / maxf(absf(v_long), 2.5)
	w.slip = slip
	var lat := clampf(slip * corner_stiffness, -1.0, 1.0) * budget

	var lng := 0.0
	if w.driven:
		lng += pull_each
	if brake_each > 0.0:
		# Тормоз не должен разворачивать колесо назад за один шаг: ограничиваем импульсом,
		# который останавливает четверть массы ровно к концу тика.
		lng -= signf(v_long) * minf(brake_each,
			absf(v_long) * mass * 0.25 / maxf(delta, 0.001))
	if handbrake and not w.front:
		lng -= signf(v_long) * budget
	lng -= signf(v_long) * load * 0.015        # сопротивление качению

	var force := Vector2(lng, lat)
	if friction_circle:
		# ОДИН ЗАПАС НА ВСЁ. Тормозишь в пол — на поворот не остаётся ничего, и руль
		# перестаёт отвечать. Без этой строки машина едет по рельсам и не умеет ошибаться.
		if force.length() > budget:
			force = force.normalized() * budget
	else:
		force = Vector2(clampf(lng, -budget, budget), clampf(lat, -budget, budget))
	w.use = clampf(force.length() / budget, 0.0, 1.0) if budget > 1.0 else 0.0
	apply_force(wf * force.x + wr * force.y, contact - global_position)


## Автомат: переключение по оборотам. Не про реализм — про то, чтобы руки были заняты
## рулём, а не передачами, пока щупаешь сцепление.
func _transmission(v_fwd: float) -> void:
	rpm = _rpm_at(v_fwd)
	if rpm > redline * 0.88 and gear < gears.size():
		gear += 1
	elif rpm < idle_rpm * 2.4 and gear > 1:
		gear -= 1
	rpm = _rpm_at(v_fwd)


func _rpm_at(v_fwd: float) -> float:
	var turns := absf(v_fwd) / (TAU * wheel_radius) * 60.0
	return clampf(turns * gears[gear - 1] * final_drive, idle_rpm, redline)


## Кривая момента — треугольник с вершиной на `peak_rpm`. Настоящая полка сложнее, но
## разница между «тянет везде» и «тянет только вверху» ловится и на треугольнике.
##
## Крутизна 0.55, а не 0.75: на холостых треугольник с 0.75 давал сорок процентов
## момента, и машина трогалась как гружёный автобус. У живого мотора на низах
## остаётся больше половины.
func _torque_at(r: float) -> float:
	return clampf(1.0 - absf(r - peak_rpm) / peak_rpm * 0.55, 0.45, 1.0)


func _place(w: CarWheel, delta: float) -> void:
	var hub := Vector3(w.attach.x, w.attach.y - w.travel, w.attach.z)
	w.position = hub
	w.rotation.y = _steer if w.front else 0.0

	# КАЧЕНИЕ. Угол берётся из скорости в точке контакта: настоящей угловой скорости
	# колеса в этой модели нет, поэтому ни пробуксовку, ни блокировку показать нечем —
	# это уже проскальзывание, математика соседней пробы. Ручник — исключение: там
	# колесо заведомо стоит, и остановленный протектор честнее крутящегося.
	if not (handbrake and not w.front):
		w.spin.rotation.x = wrapf(w.spin.rotation.x - w.roll / w.radius * delta,
			-PI, PI)

	# РЫЧАГ И ПРУЖИНА — от рамы к ступице. Внутренний шарнир близко к оси машины, верхняя
	# опора пружины над ним; обе точки неподвижны в осях кузова, а ступица ездит. Ровно
	# так это и выглядит на настоящей машине, и ровно поэтому ход подвески видно.
	var side := signf(w.attach.x)
	var joint := Vector3(side * 0.26, mount_height - 0.20, w.attach.z)
	# Опора пружины вынесена НАРУЖУ от оси машины и ВПЕРЁД (назад у задних) — там, где
	# на настоящей машине стоит амортизатор и где его действительно видно в арке.
	var lean := -0.52 if w.front else 0.52
	# Икс почти на колее, а не у оси машины: пружина живёт В АРКЕ, между бортом и
	# колесом. С опорой ближе к центру она уезжала внутрь корпуса и торчала из капота.
	var top := Vector3(side * 0.95, mount_height + 0.32, w.attach.z + lean)
	w.place_linkage(joint, hub, top)

	w.tint_by_grip()
