extends RigidBody3D
class_name TyreChassis
## КУЗОВ, ПОДВЕСКА И ЧЕТЫРЕ КОЛЕСА СО СВОЕЙ УГЛОВОЙ СКОРОСТЬЮ.
##
## Подвеска здесь такая же, как в соседней пробе, и намеренно: луч, пружина, демпфер,
## нагрузка. Копия, а не общий код — менять её тут не собираемся, она фон. Предмет пробы
## начинается там, где у колеса появляется ω.
##
## ЦЕПОЧКА ПОЛУЧАЕТСЯ ЗАМКНУТОЙ, и в этом вся разница с обрезкой из 37-й:
##
##   момент на колесо → ω растёт → κ растёт → сила растёт → сила ТОРМОЗИТ колесо → ω падает
##
## Колесо само находит равновесие, и это равновесие и есть та точка на кривой шины, в
## которой машина сейчас едет. Пробуксовка — не отдельный режим и не флаг: это просто
## равновесие, ушедшее за пик.
##
## Замкнутая петля жёсткая: инерция колеса мала, а наклон кривой велик, поэтому на шестидесяти
## герцах она разваливается. Отсюда подшаги — единственное место, где эта проба стоит дороже
## соседней по процессору.

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
## СТАБИЛИЗАТОРЫ ПО ОСЯМ ОТДЕЛЬНО. В соседней пробе баланс осей не значил ничего, и это
## было измерено: со стабилизатором и без него скорость в повороте совпадала. Здесь у
## них появляется смысл — но только вместе с падающей μ, и это и есть главный опыт пробы.
@export var anti_roll_front := 11000.0
@export var anti_roll_rear := 11000.0

@export_group("Шина")
@export var model: TyreLaw.Model = TyreLaw.Model.BRUSH
@export_range(0.4, 2.0, 0.05) var mu := 1.05
## Наклон кривой у нуля, в долях нагрузки. Одно число на оба скольжения — упрощение:
## у настоящей шины продольная жёсткость примерно вдвое выше боковой.
@export_range(4.0, 40.0, 0.5) var slip_stiffness := 18.0
## Форма и кривизна для Пацейки. `shape` задаёт, насколько кривая ПАДАЕТ после пика:
## 1.0 — не падает вовсе, 1.35 — отдаёт около пятнадцати процентов, как дорожная шина.
@export var pacejka_shape := 1.35
@export var pacejka_curvature := 0.95
## Падение сцепления с ростом нагрузки. Ноль — поведение соседней пробы, где перенос веса
## не отнимает ничего.
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

@onready var _wheel_root: Node3D = $Wheels

var _steer := 0.0
var _fz_ref := 1.0
## Демпфирование, которое трансмиссия навязывает колесу: сцепление тянет его к оборотам
## мотора тем сильнее, чем выше передача, и в первой это очень жёстко.
var _train_damping := 0.0


func _ready() -> void:
	mass = body_mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = com_offset
	can_sleep = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.5
	_fz_ref = body_mass * G * 0.25

	# КУЗОВ, ФОРМА СТОЛКНОВЕНИЯ И КОЛЁСА ЛЕЖАТ В СЦЕНЕ. Раньше собирались здесь, и
	# машина открывалась пустым узлом с предупреждением «у узла нет формы».
	for child in _wheel_root.get_children():
		var w := child as TyreWheel
		if w == null:
			continue
		w.travel = rest_length
		w.driven = _driven(w.front)
		wheels.append(w)

func _driven(front: bool) -> bool:
	if layout == 0:
		return front
	if layout == 1:
		return not front
	return true


func relayout() -> void:
	for w in wheels:
		w.driven = _driven(w.front)


func _physics_process(delta: float) -> void:
	var xf := global_transform
	var up := xf.basis.y
	var fwd := -xf.basis.z
	var v_fwd := linear_velocity.dot(fwd)

	var limit := 0.55 * lerpf(1.0, 0.32, clampf(absf(v_fwd) / 30.0, 0.0, 1.0))
	_steer = move_toward(_steer, steer_input * limit, 5.0 * delta)

	_suspension(up)
	_anti_roll()

	# ПРОТИВОБУКСОВОЧНАЯ И АНТИБЛОКИРОВОЧНАЯ — по одной строке каждая, и обе стали возможны
	# только сейчас: обе смотрят на κ, которого в предыдущей пробе не существовало.
	var gas := throttle
	if traction_control:
		for w in wheels:
			if w.driven and w.kappa > 0.14:
				gas = minf(gas, 0.18)

	var driven_omega := 0.0
	var driven_count := 0
	for w in wheels:
		if w.driven:
			driven_omega += w.omega
			driven_count += 1
	if driven_count > 0:
		driven_omega /= float(driven_count)
	var shaft := train.step(delta, gas, driven_omega)
	_distribute(shaft)
	# Наклон момента сцепления по скорости колеса: k·r², делённое на число ведущих.
	var ratio := train.ratio()
	_train_damping = -train.clutch_stiffness * ratio * ratio / maxf(driven_count, 1)

	var h := delta / float(substeps)
	for w in wheels:
		w.fx = 0.0
		w.fy = 0.0
	for _s in substeps:
		for w in wheels:
			_wheel_step(w, xf, up, fwd, h)
	for w in wheels:
		_apply(w, xf, up, h * float(substeps))
		_place(w, delta)

	var speed := linear_velocity.length()
	if speed > 0.1:
		apply_central_force(-linear_velocity / speed * 0.42 * speed * speed)


## Момент со вторичного вала — по осям и дальше через дифференциал по колёсам.
func _distribute(shaft: float) -> void:
	var axles := [[0, 1], [2, 3]]
	var live: Array = []
	for pair in axles:
		if wheels[pair[0]].driven:
			live.append(pair)
	for w in wheels:
		w.torque = 0.0
	if live.is_empty():
		return
	var per_axle := shaft / float(live.size())
	for pair in live:
		var l: TyreWheel = wheels[pair[0]]
		var r: TyreWheel = wheels[pair[1]]
		var t := TyreTrain.split(per_axle, l.omega, r.omega, diff_lock, diff_preload)
		l.torque = t.x
		r.torque = t.y


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
		var at_point := linear_velocity + angular_velocity.cross(
			attach - global_position - com_world)
		w.load = maxf(stiffness * (rest_length - w.travel) - damping * at_point.dot(up), 0.0)


func _anti_roll() -> void:
	for pair in [[0, 1, anti_roll_front], [2, 3, anti_roll_rear]]:
		var a: TyreWheel = wheels[pair[0]]
		var b: TyreWheel = wheels[pair[1]]
		var shift: float = (a.travel - b.travel) * pair[2]
		if a.grounded:
			a.load = maxf(a.load - shift, 0.0)
		if b.grounded:
			b.load = maxf(b.load + shift, 0.0)


## ОДИН ПОДШАГ ПЕТЛИ. Скорость кузова внутри подшагов держится постоянной — её Godot
## обновит один раз за тик; меняется только ω колеса, и именно она требует мелкого шага.
func _wheel_step(w: TyreWheel, xf: Transform3D, up: Vector3, fwd: Vector3,
		h: float) -> void:
	if not w.grounded:
		# В воздухе колесо только раскручивается моментом и ничем не тормозится.
		w.omega += w.torque / wheel_inertia * h
		w.kappa = 0.0
		w.alpha = 0.0
		return

	var com_world := xf.basis * center_of_mass
	var at_point := linear_velocity + angular_velocity.cross(
		w.hit - global_position - com_world)
	var n: Vector3 = w.normal
	var wf := fwd.rotated(up, _steer if w.front else 0.0)
	wf = (wf - n * wf.dot(n)).normalized()
	var wr := n.cross(wf).normalized()
	var v_long := at_point.dot(wf)
	var v_lat := at_point.dot(wr)

	var s := TyreLaw.slips(w.omega, wheel_radius, v_long, v_lat)
	# РЕЛАКСАЦИЯ: скольжение доезжает до своего значения не мгновенно, а прокатившись на
	# длину релаксации. Физически это гибкость каркаса; численно — то, что спасает петлю на
	# малой скорости, где мгновенное κ скачет между плюс и минус бесконечностью.
	if relaxation > 0.0:
		# ЗНАМЕНАТЕЛЬ С ПОЛОМ, иначе фильтр умирает на месте. Скорость набегания равна
		# пути, делённому на длину релаксации; на стоящей машине путь нулевой, фильтр
		# застывает, κ навсегда остаётся нулём — и шина не выдаёт силы вообще. Колёса
		# крутились, машина стояла: буксовало ВСЁ, и никогда не трогалось.
		var rate := (absf(v_long) + TyreLaw.V_EPS) / relaxation
		w.lag = w.lag.lerp(s, clampf(rate * h, 0.0, 1.0))
	else:
		w.lag = s
	w.kappa = w.lag.x
	w.alpha = w.lag.y

	var grip := TyreLaw.mu_at(mu, w.load, _fz_ref, load_sensitivity)
	if handbrake and not w.front:
		grip *= 0.45
	var f := TyreLaw.force(model, w.kappa, w.alpha, grip, w.load,
		slip_stiffness * w.load, pacejka_shape, pacejka_curvature)
	w.fx += f.x
	w.fy += f.y
	w.use = clampf(f.length() / maxf(grip * w.load, 1.0), 0.0, 1.0)

	# Колесо: приложенный момент, реакция от продольной силы, потом тормоз отдельно —
	# так, чтобы он мог остановить колесо ровно в ноль, но не провернуть его назад.
	var spin_torque: float = w.torque + TyreLaw.reaction_torque(f.x, wheel_radius)
	spin_torque -= signf(w.omega) * w.load * 0.012 * wheel_radius
	# НЕЯВНЫЙ ШАГ. Явное интегрирование колеса неустойчиво в принципе, а не при «слишком
	# крупном шаге»: постоянная времени петли равна инерции колеса, делённой на наклон
	# кривой шины, а наклон растёт при ПАДЕНИИ скорости — на семи метрах в секунду это
	# около 1.3 мс, на двух уже 0.4 мс. Никакое разумное число подшагов не спасает.
	#
	# Спасает поправка на собственный наклон. Наклон берётся численно: считаем силу ещё
	# раз при чуть большей ω и смотрим, насколько изменился момент. Плюс наклон от
	# сцепления, которое тянет колесо к оборотам мотора и тоже жёсткое.
	var probe := 0.5
	var s2 := TyreLaw.slips(w.omega + probe, wheel_radius, v_long, v_lat)
	var f2 := TyreLaw.force(model, s2.x, w.alpha, grip, w.load,
		slip_stiffness * w.load, pacejka_shape, pacejka_curvature)
	var slope := minf((f2.x - f.x) * -wheel_radius / probe, 0.0)
	if w.driven:
		slope += _train_damping
	var next: float = w.omega + spin_torque / wheel_inertia * h \
		/ (1.0 - slope * h / wheel_inertia)
	var stop := _brake_torque(w) / wheel_inertia * h
	w.omega = 0.0 if absf(next) <= stop else next - signf(next) * stop


func _brake_torque(w: TyreWheel) -> float:
	var share: float = brake_bias if w.front else 1.0 - brake_bias
	var t := brake * brake_torque * share * 2.0
	if handbrake and not w.front:
		t = maxf(t, brake_torque * 0.9)
	# АНТИБЛОКИРОВОЧНАЯ. Заблокированное колесо (κ = −1) теряет боковое сцепление целиком,
	# и машина едет прямо, как ни выворачивай руль. Система просто отпускает тормоз, когда
	# проскальзывание уходит глубже порога, — весь принцип в одной строке.
	if abs_on and not handbrake and w.kappa < -0.22:
		t *= 0.15
	return t


func _apply(w: TyreWheel, xf: Transform3D, up: Vector3, _dt: float) -> void:
	var attach: Vector3 = xf * w.attach
	apply_force(up * w.load, attach - global_position)
	if not w.grounded:
		return
	var n: Vector3 = w.normal
	var wf := (-xf.basis.z).rotated(up, _steer if w.front else 0.0)
	wf = (wf - n * wf.dot(n)).normalized()
	var wr := n.cross(wf).normalized()
	# Силы копились по подшагам — прикладывается среднее за тик.
	var k := 1.0 / float(substeps)
	apply_force(wf * (w.fx * k) + wr * (w.fy * k), w.hit - global_position)


func _place(w: TyreWheel, delta: float) -> void:
	w.position = Vector3(w.attach.x, w.attach.y - w.travel, w.attach.z)
	w.rotation.y = _steer if w.front else 0.0
	# Колесо крутится по СВОЕЙ ω, а не по скорости машины. В этом и разница: буксующее
	# колесо видно, потому что метка на диске обгоняет землю.
	w.spin.rotation.x = wrapf(w.spin.rotation.x - w.omega * delta, -PI, PI)
	w.tint_by_grip()
