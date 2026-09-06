extends CharacterBody3D

## ЛЫЖНИК ПО СХЕМЕ TRIBES. Две кнопки, и между ними вся механика.
##
##   ПРОБЕЛ (держать)   ЛЫЖИ. Трения нет, склон разгоняет, перегибы не съедают скорость.
##   SHIFT или ПКМ      ДЖЕТПАК. Тратит энергию, поднимает — меняет скорость на высоту.
##
## Петля, ради которой всё: съехал с горы — разогнался — на дне поддал джетом — улетел по
## дуге — приземлился на следующий спуск — снова разогнался. Высота и скорость здесь одна
## величина в двух видах, а склон и джетпак — два способа переводить одно в другое.
##
## РУЛЬ — ЭТО ПОВОРОТ, А НЕ РАЗГОН. Первая версия добавляла крошечную поперечную
## составляющую и тут же нормировала вектор: управление почти не чувствовалось, направление
## выбирала гравитация, и игрок сказал прямо — «персонаж сам выбирает направление».
## Правильно — поворачивать вектор скорости к тому, куда просят, с сохранением модуля и с
## ограничением по угловой скорости. Тот же приём, что доворот рывка в тридцать второй
## пробе, и та же причина: скорость уже есть, вопрос только куда она.

@export var skiing_on := true
@export var jet_on := true
## Лыжи всё время, без удержания. И режим для игрока, и единственный способ померить
## скольжение со стенда: удержание клавиши подделать нельзя — `Input` каждый кадр
## пересинхронизируется с настоящей клавиатурой, и синтетическое нажатие стирается.
@export var auto_ski := false

@export_group("Земля и воздух")
@export var walk_speed := 9.0
@export var accel := 55.0
@export var friction := 7.0
@export var gravity := 24.0
@export var air_steer := 1.1

@export_group("Лыжи")
## Не ноль: на нуле разгон упирается только в границу карты, а это не механика.
@export var ski_friction := 0.03
## Рад/с доворота на малой скорости. Чем быстрее едешь, тем шире дуга — и это не украшение:
## без такой зависимости скольжение превращается в езду на месте с рулём.
@export var ski_turn := 3.6
@export var turn_falloff := 0.028

@export_group("Джетпак")
@export var jet_thrust := 36.0
@export var jet_push := 7.0
@export var jet_drain := 44.0
@export var jet_regen := 26.0
## Пауза перед восстановлением после отпускания. Без неё щелчками по кнопке можно висеть.
@export var jet_recharge_delay := 0.35
@export var energy_max := 100.0

var speed := 0.0
var skiing := false
var jetting := false
var energy := 100.0
var slope_deg := 0.0

var _yaw := 0.0
var _pitch := -0.05
var _jet_idle := 0.0
var _pre := 0.0
var _post := 0.0

@onready var _cam: Camera3D = $Cam


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	energy = energy_max
	floor_max_angle = deg_to_rad(75.0)
	# `floor_stop_on_slope` мешает персонажу съезжать по склону, и я решил, что дело в нём.
	# Замер потом показал: с ним и без него результат одинаков. Флаг для лыжника всё равно
	# бессмыслен и остаётся выключенным, но виноват был не он.
	floor_stop_on_slope = false
	floor_constant_speed = false


func _physics_process(delta: float) -> void:
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var wish := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): wish += fwd
	if Input.is_physical_key_pressed(KEY_S): wish -= fwd
	if Input.is_physical_key_pressed(KEY_D): wish += right
	if Input.is_physical_key_pressed(KEY_A): wish -= right
	wish = wish.normalized() if wish != Vector3.ZERO else Vector3.ZERO

	skiing = skiing_on and (auto_ski or Input.is_physical_key_pressed(KEY_SPACE))

	# КУРС ЗАДАЁТ ВЗГЛЯД. Без этого руля не было вовсе: если игрок не жал WASD, `wish`
	# оставался пустым, поворот не считался, и курс целиком выбирала гравитация — ровно то,
	# на что игрок и пожаловался. В Tribes рулят мышью, а клавиши лишь смещают курс
	# относительно взгляда.
	if skiing and wish == Vector3.ZERO:
		wish = fwd

	# ДЕРЖИШЬ КНОПКУ — НЕ ВОССТАНАВЛИВАЕШЬСЯ. Здесь был скверный баг: при нулевой энергии
	# `jetting` выключался, а восстановление шло дальше, ПОКА КЛАВИША ЗАЖАТА. Один кадр
	# копил энергию, следующий её тратил — тяга дребезжала, и вместо честного падения
	# выходило парение. Кончилась энергия — падай; так это и в Tribes 2.
	var want_jet := (jet_on and (Input.is_physical_key_pressed(KEY_SHIFT)
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)))
	jetting = want_jet and energy > 0.0
	if jetting:
		_jet(fwd, delta)
		_jet_idle = 0.0
	elif want_jet:
		_jet_idle = 0.0                     # держит впустую — не копим
	else:
		_jet_idle += delta
		if _jet_idle >= jet_recharge_delay:
			energy = minf(energy + jet_regen * delta, energy_max)

	if is_on_floor():
		var n := get_floor_normal()
		slope_deg = rad_to_deg(acos(clampf(n.y, -1.0, 1.0)))
		if skiing:
			_ski(n, wish, delta)
		else:
			_walk(wish, delta)
	else:
		velocity.y -= gravity * delta
		# В воздухе руль тоже поворот, а не разгон: иначе воздух становится вторым мотором.
		_steer(wish, air_steer, delta)

	# ПРИЛИПАНИЕ К ПОЛУ отключается на подъёме. Иначе джетпак работает вхолостую: тяга
	# поднимает, а снап тут же притягивает обратно к склону — кнопка нажата, ничего не
	# происходит, и ошибки при этом нет.
	floor_snap_length = 0.0 if velocity.y > 0.5 else 1.2

	_pre = velocity.length()
	move_and_slide()
	_post = velocity.length()
	# СОХРАНЕНИЕ МОДУЛЯ ЧЕРЕЗ СТОЛКНОВЕНИЕ. `move_and_slide` теряет 0.3% за тик: вектор
	# касателен к СТАРОЙ нормали, а тело тут же въезжает в следующую грань сетки высот. В
	# кадре это не видно; за четырнадцать секунд 0.997^840 ≈ 0.09, то есть 92% энергии.
	# Порог 0.8 отделяет скользящий контакт со склоном (вернуть) от удара в скалу (оставить).
	if skiing and _pre > 0.5 and _post > 0.001 and _post > _pre * 0.8:
		velocity *= _pre / _post
	speed = Vector2(velocity.x, velocity.z).length()


## ПОВОРОТ ВЕКТОРА. Модуль не меняется, меняется только направление, и не быстрее чем
## `rate` радиан в секунду. Это и есть руль во всех режимах, где скорость уже набрана.
func _steer(wish: Vector3, rate: float, delta: float) -> void:
	if wish == Vector3.ZERO or rate <= 0.0:
		return
	var h := Vector3(velocity.x, 0.0, velocity.z)
	var sp := h.length()
	if sp < 0.5:
		return
	var cur := h / sp
	var ang := cur.angle_to(wish)
	if ang < 0.0001:
		return
	var turned := cur.slerp(wish, minf(rate * delta / ang, 1.0)).normalized()
	velocity.x = turned.x * sp
	velocity.z = turned.z * sp


func _walk(wish: Vector3, delta: float) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var sp := flat.length()
	if sp > 0.0:
		flat *= maxf(sp - sp * friction * delta, 0.0) / sp
	velocity.x = flat.x
	velocity.z = flat.z
	if wish != Vector3.ZERO:
		var cur := velocity.dot(wish)
		if cur < walk_speed:
			velocity += wish * minf(accel * delta, walk_speed - cur)
	if velocity.y < 0.0:
		velocity.y = -2.0


## СКОЛЬЖЕНИЕ. Три операции, и все три — школьная механика.
func _ski(n: Vector3, wish: Vector3, delta: float) -> void:
	# 1. Руль. Чем быстрее едешь, тем шире дуга — повернуть на месте нельзя.
	_steer(wish, ski_turn / (1.0 + speed * turn_falloff), delta)
	# 2. Проекция на склон. Модуль сохраняется ТОЛЬКО при скользящем контакте.
	#
	#    Первая версия сохраняла его всегда — и это оказался вечный двигатель: падая на
	#    подъём, лыжник превращал всю вертикальную скорость в горизонтальную без потерь.
	#    В логе видно прямо: за две секунды он поднялся с 17.5 м до 27.5 м И разогнался с
	#    9.8 до 17.1 м/с одновременно. Энергия из ниоткуда, ни ошибки, ни предупреждения.
	#
	#    Различать их надо не по ВЕЛИЧИНЕ потери, а по тому, ВХОДИТ ЛИ вектор в поверхность.
	#    Порог по величине я уже пробовал — и он убил скольжение совсем: после
	#    `move_and_slide` скорость возвращается почти горизонтальной, на склоне в 50° её
	#    проекция теряет cos(50°) = 0.64 каждый тик, и лыжник намертво вставал на 0.4 м/с.
	#
	#    `into` — синус угла входа. Отрицательный или крошечный значит «едем вдоль», и
	#    проекция тут лишь выравнивание, модуль возвращаем. Большой значит «падаем на
	#    склон», и потеря настоящая: удар о землю обязан стоить скорости.
	var sp := velocity.length()
	if sp > 0.01:
		var along := velocity - n * velocity.dot(n)
		if along.length() > 0.001:
			var into := -velocity.dot(n) / sp
			velocity = along.normalized() * sp if into < 0.25 else along
	# 3. Гравитация, разложенная на склон: составляющая вдоль поверхности это g·sin(θ).
	#    Никакого «ускорения скольжения» в коде нет и быть не должно — иначе рельеф
	#    превратится в декорацию при кнопке.
	var g := Vector3.DOWN * gravity
	velocity += (g - n * g.dot(n)) * delta
	velocity *= maxf(1.0 - ski_friction * delta, 0.0)


## ДЖЕТПАК. Тяга вверх плюс небольшая доля вперёд по взгляду — чтобы прыжок через долину
## был решением игрока, а не только высотой. Тратит энергию; без неё это был бы полёт, а
## не размен.
func _jet(fwd: Vector3, delta: float) -> void:
	energy = maxf(energy - jet_drain * delta, 0.0)
	velocity.y += jet_thrust * delta
	velocity += fwd * jet_push * delta


func _process(d: float) -> void:
	_cam.rotation = Vector3(_pitch, 0.0, 0.0)
	rotation.y = _yaw
	# Поле зрения от СКОРОСТИ СБЛИЖЕНИЯ, а не от модуля — урок тридцать второй пробы.
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var closing := Vector3(velocity.x, 0.0, velocity.z).dot(fwd)
	_cam.fov = lerpf(_cam.fov, 75.0 + clampf(closing - walk_speed, 0.0, 45.0) * 0.62,
		1.0 - exp(-6.0 * d))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * 0.0022
		_pitch = clampf(_pitch - event.relative.y * 0.0022, -1.4, 1.4)
	if (event is InputEventMouseButton and event.pressed
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if (event is InputEventKey and event.pressed and not event.is_echo()
			and (event as InputEventKey).physical_keycode == KEY_CTRL):
		auto_ski = not auto_ski
