extends RefCounted
class_name TyreTrain
## ТРАНСМИССИЯ: мотор, сцепление, коробка, дифференциал.
##
## В соседней пробе всего этого не было и не могло быть: там тяга сразу превращалась в силу
## на колесе. Здесь мотор — отдельное тело со своей инерцией, и оно может крутиться БЫСТРЕЕ
## колёс. Без этого пробуксовка невозможна в принципе: буксующее колесо это и есть колесо,
## обогнавшее машину, а мотор, обогнавший колёса.
##
## Сцепление — не выключатель, а пружина по скорости: момент пропорционален разнице оборотов
## и ограничен сверху. Отсюда бесплатно берётся и трогание с места, и провал оборотов под
## нагрузкой, и то, что мотор на нейтрали свободно раскручивается.

const IDLE := 850.0
const REDLINE := 6800.0

# --- мотор ---
var peak_torque := 300.0
var peak_rpm := 4300.0
## Момент инерции всего, что крутится в моторе, кг·м². Маленькая цифра с большими
## последствиями: лёгкий маховик даёт злой отклик на газ и лёгкий срыв в пробуксовку.
var engine_inertia := 0.28

# --- трансмиссия ---
var gears: Array[float] = [3.55, 2.05, 1.42, 1.05, 0.82]
var final_drive := 3.90
## Предельный момент, который сцепление вообще способно передать, Н·м. Ниже момента мотора —
## и оно будет буксовать вместо колёс.
var clutch_capacity := 480.0
var clutch_stiffness := 3.2

var omega := IDLE * TAU / 60.0     ## угловая скорость мотора, рад/с
var gear := 1
var clutch_torque := 0.0


func rpm() -> float:
	return omega * 60.0 / TAU


## Кривая момента — треугольник с вершиной на `peak_rpm`, срез после отсечки. Настоящая
## полка сложнее, но разница между «тянет внизу» и «тянет только вверху» ловится и здесь.
func torque_at(r: float, throttle: float) -> float:
	if r > REDLINE:
		return 0.0
	var shape := clampf(1.0 - absf(r - peak_rpm) / peak_rpm * 0.55, 0.45, 1.0)
	var drive := peak_torque * shape * throttle
	# Холостой ход: пока газ отпущен, регулятор не даёт мотору заглохнуть. Плюс насосные
	# потери, из-за которых отпущенный газ ТОРМОЗИТ машину — без них накат неотличим от
	# нейтрали, а торможение двигателем не существует.
	var idle_hold := maxf(IDLE - r, 0.0) * 0.06
	var pumping := -0.014 * r * (1.0 - throttle)
	return drive + idle_hold + pumping


func ratio() -> float:
	return gears[gear - 1] * final_drive


## Один шаг трансмиссии. На входе — газ и средняя угловая скорость ведущих колёс; на выходе
## момент, приходящий НА КОЛЁСА (уже умноженный на передаточное число).
func step(delta: float, throttle: float, wheel_omega: float) -> float:
	_shift(wheel_omega)
	var r := ratio()
	# Сцепление как пружина по скорости: чем сильнее мотор обгоняет вход коробки, тем
	# больше момент, но не выше того, что диски способны удержать.
	var mismatch := omega - wheel_omega * r
	clutch_torque = clampf(mismatch * clutch_stiffness, -clutch_capacity, clutch_capacity)
	var engine := torque_at(rpm(), throttle)
	omega = maxf(omega + (engine - clutch_torque) / engine_inertia * delta, 0.0)
	return clutch_torque * r


## Автомат по оборотам. Не про реализм: руки должны быть заняты рулём и газом, пока щупаешь
## шину, а не передачами.
func _shift(wheel_omega: float) -> void:
	var r := rpm()
	if r > REDLINE * 0.87 and gear < gears.size():
		gear += 1
		omega = wheel_omega * ratio()
	elif r < IDLE * 2.3 and gear > 1:
		gear -= 1
		omega = maxf(wheel_omega * ratio(), IDLE * TAU / 60.0)


## ДИФФЕРЕНЦИАЛ. Возвращает моменты на левое и правое колесо оси.
##
## Открытый делит момент строго пополам — и потому передаёт ровно вдвое больше того, что
## держит ХУДШЕЕ колесо: одно вывесил, и вся ось встала. Это не поломка, это определение
## открытого дифференциала.
##
## Блокировка добавляет момент, стягивающий скорости: он снимается с быстрого колеса и
## отдаётся медленному. Преднатяг работает даже при нулевой разнице — так ведёт себя
## дисковый самоблок. Полная блокировка это просто очень большой `lock`.
## Параметр называется `bias_preload`, а не `preload`: `preload` — ключевое слово
## GDScript, и имя параметра ломает разбор ВСЕГО файла, причём сообщение об ошибке
## приходит из тех файлов, которые его подключают, а не из этого.
static func split(total: float, omega_l: float, omega_r: float, lock: float,
		bias_preload: float) -> Vector2:
	var half := total * 0.5
	if lock <= 0.0 and bias_preload <= 0.0:
		return Vector2(half, half)
	var diff := omega_l - omega_r
	var cap := absf(total) * 0.5 + bias_preload
	var bias := clampf(diff * lock, -cap, cap)
	bias += signf(diff) * bias_preload
	return Vector2(half - bias, half + bias)
