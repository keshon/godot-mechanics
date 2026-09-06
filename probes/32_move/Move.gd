extends CharacterBody3D

## 32 — АКРОБАТИКА ОТ ПЕРВОГО ЛИЦА
##
## Эталон: Titanfall 2, Mirror's Edge. Движение здесь — не «перемещение персонажа», а
## самостоятельная механика со своим удовольствием: разгон, сохранение импульса, риск
## потерять скорость.
##
## Восемь слоёв на цифрах. Три из них НЕВИДИМЫ и при этом решают почти всё: воздушное
## управление, койот-тайм и буфер прыжка. Их нельзя увидеть на экране — можно только
## почувствовать их отсутствие, и в этом весь смысл выключателей.
##
##   1  воздушное управление   разгон в воздухе доворотом мыши — механика из Quake
##   2  койот-тайм             прыжок засчитывается ещё 0.12 с после схода с края
##   3  буфер прыжка           нажатие за 0.15 с ДО приземления не пропадает
##   4  переменная высота      отпустил рано — прыгнул ниже
##   5  бег по стене
##   6  рывок
##   7  подтягивание на уступ
##   8  скольжение
##   9  двойной прыжок

@export var air_control := true
@export var coyote := true
@export var buffer := true
@export var variable_jump := true
@export var wall_run := true
@export var dash := true
@export var mantle := true
@export var slide := true
@export var double_jump := true

@export_group("Земля")
@export var ground_speed := 8.0
@export var ground_accel := 70.0
@export var ground_friction := 10.0

@export_group("Воздух")
## Классическая формула Quake: в воздухе можно добавлять скорость только В ТУ СТОРОНУ,
## куда ты ещё не летишь. Отсюда strafe-jumping: доворачивая мышь и держа бок, игрок
## бесконечно добавляет по чуть-чуть перпендикулярно движению — и разгоняется.
@export var air_accel := 45.0
## Тот самый маленький потолок, без которого разгона не будет. Это НЕ скорость полёта,
## а предел проекции скорости на желаемое направление.
@export var air_wish_speed := 1.2
## ГРАВИТАЦИЯ РАЗНАЯ НА ПОДЪЁМЕ И НА ПАДЕНИИ. Одинаковая читается как «тяжело»: прыжок
## одновременно низкий и долгий, и добавлять высоту приходится задиранием импульса, отчего
## он становится ещё дольше. Разведённые — подъём лёгкий, падение быстрое — дают высокий
## И резкий прыжок сразу. Приём из платформеров, в шутерах он тот же.
@export var gravity := 18.0
@export var gravity_fall := 32.0
@export var jump_speed := 7.2

@export_group("Прощение")
## Две форточки, которые есть в каждом платформере и которых не видит никто.
@export var coyote_time := 0.12
@export var buffer_time := 0.15
@export_range(0.1, 1.0) var jump_cut := 0.45

@export_group("Стена")
@export var wall_run_time := 1.7
@export var wall_gravity := 4.5
@export var wall_min_speed := 4.5
@export var wall_jump_out := 7.0
@export var wall_jump_up := 6.2
@export var wall_roll := 0.22

@export_group("Рывок")
@export var dash_speed := 30.0
@export var dash_time := 0.13
@export var dash_cooldown := 1.1
## Скорость, до которой рывок гасится НА ВЫХОДЕ. Без гашения 26 м/с остаются навсегда, и
## рывок перестаёт быть рывком: он становится сменой режима полёта. «Длинный и воздушный» —
## это ровно оно.
@export var dash_exit_speed := 14.0
## Рад/с доворота рывка. Воздушное управление во время рывка формально работает, но толку
## не даёт: прибавка ограничена 1.2 м/с, а скорость тридцать — проекция всегда выше потолка,
## и `add` уходит в минус. Значит рывок надо ПОВОРАЧИВАТЬ, сохраняя модуль, а не разгонять.
## Ноль — рывок строго по прямой, как было.
@export_range(0.0, 14.0) var dash_steer := 6.0
@export_range(0, 3) var air_jumps := 1

@export_group("Уступ и скольжение")
@export var mantle_time := 0.26
@export var slide_boost := 3.2
@export var slide_friction := 1.4
@export var slide_min_speed := 2.6

var speed := 0.0
var state := "земля"
var dash_ready := 1.0

var _yaw := 0.0
var _pitch := 0.0
var _since_ground := 99.0
var _jump_at := -99.0
var _jump_used := true
var _wall_n := Vector3.ZERO
var _wall_left := 0.0
var _dash_left := 0.0
var _dash_cd := 0.0
var _sliding := false
var _mantle_left := 0.0
var _mantle_from := Vector3.ZERO
var _mantle_to := Vector3.ZERO
var _air_left := 1
var _roll := 0.0
var _clock := 0.0

@onready var _cam: Camera3D = $Cam
@onready var _col: CollisionShape3D = $Col
@onready var _stand_h: float = (_col.shape as CapsuleShape3D).height


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# своя копия формы: менять высоту общего ресурса — значит менять её всем сразу
	_col.shape = _col.shape.duplicate()
	_stand_h = (_col.shape as CapsuleShape3D).height


func _physics_process(delta: float) -> void:
	_clock += delta
	_dash_cd = maxf(_dash_cd - delta, 0.0)
	dash_ready = 1.0 - _dash_cd / dash_cooldown

	if _mantle_left > 0.0:
		_do_mantle(delta)
		return

	var wish := _wish_dir()
	if is_on_floor():
		_since_ground = 0.0
	else:
		_since_ground += delta

	if _wall_left > 0.0:
		_run_wall(wish, delta)
	elif is_on_floor():
		_on_ground(wish, delta)
	else:
		_in_air(wish, delta)

	if _dash_left > 0.0:
		_dash_left -= delta
		if _dash_left <= 0.0:
			_end_dash()

	move_and_slide()
	_try_wall(wish)
	_camera(delta)
	speed = Vector2(velocity.x, velocity.z).length()


## Куда игрок ПРОСИТ двигаться, в мировых осях. Отдельная функция, потому что это
## направление нужно всем режимам, а считается оно от поворота головы.
func _wish_dir() -> Vector3:
	var f := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var r := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var v := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): v += f
	if Input.is_physical_key_pressed(KEY_S): v -= f
	if Input.is_physical_key_pressed(KEY_D): v += r
	if Input.is_physical_key_pressed(KEY_A): v -= r
	return v.normalized() if v != Vector3.ZERO else Vector3.ZERO


## ФОРМУЛА QUAKE. Скорость добавляется только в ту сторону, куда игрок ещё НЕ летит:
## `add` — это разница между потолком и текущей проекцией. Летишь строго вперёд — проекция
## равна потолку, добавить нечего. Летишь боком, а просишь вперёд — проекция около нуля, и
## тебе дают полную порцию. Из этих трёх строк выросли strafe-jumping и bunny hop.
func _accelerate(dir: Vector3, wish_speed: float, accel: float, delta: float) -> void:
	if dir == Vector3.ZERO:
		return
	var current := velocity.dot(dir)
	var add := wish_speed - current
	if add <= 0.0:
		return
	velocity += dir * minf(accel * wish_speed * delta, add)


func _on_ground(wish: Vector3, delta: float) -> void:
	state = "скольжение" if _sliding else "земля"
	if _sliding and not (slide and Input.is_physical_key_pressed(KEY_CTRL)):
		_stop_slide()
	if _dash_left > 0.0:
		# Рывок по земле не должен съедаться трением: 30 м/с при трении 10 гаснут за пару
		# тиков, и рывок с земли просто не случался. На время рывка земля «скользкая».
		state = "рывок"
		_steer_dash(wish, delta)
		velocity.y = -2.0
		return
	var fr := slide_friction if _sliding else ground_friction
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var sp := flat.length()
	if sp > 0.0:
		# ТРЕНИЕ ОТДЕЛЬНО ОТ РАЗГОНА. Слитые в один `move_toward` они дают ватное
		# управление: отпустил клавишу — и едешь по инерции ровно так же, как разгоняешься.
		var drop := sp * fr * delta
		flat *= maxf(sp - drop, 0.0) / sp
		velocity.x = flat.x
		velocity.z = flat.z
	if not _sliding:
		_accelerate(wish, ground_speed, ground_accel, delta)
	_air_left = air_jumps
	velocity.y = -2.0
	if _wants_jump():
		_jump()


func _in_air(wish: Vector3, delta: float) -> void:
	state = "рывок" if _dash_left > 0.0 else "воздух"
	if _dash_left > 0.0:
		_steer_dash(wish, delta)
	else:
		velocity.y -= (gravity if velocity.y > 0.0 else gravity_fall) * delta
	if air_control:
		_accelerate(wish, air_wish_speed, air_accel, delta)
	else:
		# «выключено» — это не «нельзя рулить», а обычное управление с потолком по
		# скорости бега. Разгоняться в воздухе становится нечем, и это ровно та разница.
		_accelerate(wish, ground_speed, 12.0, delta)
	if _wants_jump():
		if coyote and _since_ground < coyote_time:
			_jump()
		elif double_jump and _air_left > 0:
			_air_jump()


## Прыжок засчитывается, если нажатие ещё «живо». Вся разница между включённым и
## выключенным буфером — ширина этого окна: 150 мс против одного тика физики (17 мс).
##
## Первая версия проверяла «клавиша ЗАЖАТА», и получался автопрыжок: держи пробел и скачи
## вечно. Приём законный — Titanfall так и делает, — но он ПОДМЕНЯЛ собой буфер: зажатая
## клавиша срабатывает всегда, и выключатель переставал что-либо менять. Слой, который
## нельзя выключить, ничего и не доказывает.
func _wants_jump() -> bool:
	if _jump_used:
		return false
	return _clock - _jump_at <= (buffer_time if buffer else 1.0 / 60.0)


func _jump() -> void:
	velocity.y = jump_speed
	_jump_used = true
	_since_ground = 99.0
	if _sliding:
		_stop_slide()


## ВТОРОЙ ПРЫЖОК. Две вещи делают его не «ещё одним прыжком», а инструментом.
##
## Первая: вертикальная скорость СБРАСЫВАЕТСЯ, а не складывается. Падая на десяти метрах в
## секунду, ты иначе получишь почти ничего — и решишь, что кнопка не сработала.
##
## Вторая: горизонтальный импульс ДОВОРАЧИВАЕТСЯ к тому, куда ты просишь. Наполовину, не
## полностью: полный доворот убивает наказание за плохой заход, отсутствие доворота делает
## второй прыжок бесполезным при промахе. Половина — это «исправить, но не переиграть».
func _air_jump() -> void:
	_air_left -= 1
	_jump_used = true
	velocity.y = jump_speed * 0.95
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var sp := flat.length()
	var d := _wish_dir()
	if d == Vector3.ZERO:
		return
	if sp < 0.5:
		velocity.x = d.x * ground_speed * 0.6
		velocity.z = d.z * ground_speed * 0.6
		return
	var turned := flat.normalized().lerp(d, 0.5).normalized() * sp
	velocity.x = turned.x
	velocity.z = turned.z


## ДОВОРОТ РЫВКА. Вектор поворачивается к тому, куда просит игрок, не более чем на
## `dash_steer` радиан за секунду, и МОДУЛЬ при этом не меняется. Отсюда стрейф рывком:
## зажал бок, повёл мышью — и тридцать метров в секунду уезжают по дуге, а не по прямой.
## Разгонять здесь нечем и не нужно: скорость уже задана, интересно только направление.
func _steer_dash(wish: Vector3, delta: float) -> void:
	if wish == Vector3.ZERO or dash_steer <= 0.0:
		return
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var sp := flat.length()
	if sp < 0.01:
		return
	var cur := flat / sp
	var ang := cur.angle_to(wish)
	if ang < 0.0001:
		return
	var turned := cur.slerp(wish, minf(dash_steer * delta / ang, 1.0)).normalized()
	velocity.x = turned.x * sp
	velocity.z = turned.z * sp


## Гашение на выходе из рывка. Рывок — это всплеск, а не новая крейсерская скорость.
func _end_dash() -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var sp := flat.length()
	if sp > dash_exit_speed:
		flat = flat / sp * dash_exit_speed
		velocity.x = flat.x
		velocity.z = flat.z


## БЕГ ПО СТЕНЕ. Условие входа — три вещи сразу: ты в воздухе, рядом стена, и ты уже
## быстрый. Последнее важнее всего: без порога скорости стена превращается в лифт, на
## который можно залезть стоя, и вся акробатика обесценивается.
func _try_wall(wish: Vector3) -> void:
	if not wall_run or is_on_floor() or _wall_left > 0.0 or _dash_left > 0.0:
		return
	if Vector2(velocity.x, velocity.z).length() < wall_min_speed:
		return
	if not is_on_wall():
		return
	var n := get_wall_normal()
	if absf(n.y) > 0.3:
		return
	if wish.dot(n) > -0.1:
		return
	_wall_n = n
	_wall_left = wall_run_time
	# стена перезаряжает второй прыжок — иначе связка «стена, отскок, доворот» невозможна
	_air_left = air_jumps


func _run_wall(wish: Vector3, delta: float) -> void:
	state = "стена"
	_wall_left -= delta
	if is_on_floor() or _wall_left <= 0.0 or not is_on_wall():
		_wall_left = 0.0
		return
	velocity.y -= wall_gravity * delta
	# Скорость ПРОЕЦИРУЕТСЯ на стену, а не гасится: смысл бега по стене в том, что импульс
	# сохраняется. Гасить его — значит сделать красивую анимацию, которая мешает бежать.
	var along := (velocity - _wall_n * velocity.dot(_wall_n))
	velocity.x = along.x
	velocity.z = along.z
	var fwd := along
	fwd.y = 0.0
	if fwd.length() > 0.1:
		_accelerate(fwd.normalized(), ground_speed * 1.15, ground_accel * 0.5, delta)
	if _wants_jump():
		# Отскок ОТ стены плюс вверх. Только вверх — и стена становится лестницей;
		# только от стены — и с неё невозможно уйти вперёд.
		velocity += _wall_n * wall_jump_out
		velocity.y = wall_jump_up
		_wall_left = 0.0
		_jump_used = true


func _do_dash() -> void:
	if not dash or _dash_cd > 0.0:
		return
	var d := _wish_dir()
	if d == Vector3.ZERO:
		d = Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	# Рывок ЗАДАЁТ скорость, а не добавляет её. Прибавка складывалась бы с разгоном, и
	# цепочка рывков выкидывала бы игрока за карту; заданная скорость — это ещё и обещание
	# «рывок всегда одинаковый», на которое можно опереться в прыжке через пропасть.
	velocity.x = d.x * dash_speed
	velocity.z = d.z * dash_speed
	# НЕ обнуляем падение целиком: полный сброс вертикали и есть та «воздушность», из-за
	# которой рывок читается как зависание. Гасим наполовину.
	velocity.y = velocity.y * 0.5 if velocity.y < 0.0 else velocity.y
	_dash_left = dash_time
	_dash_cd = dash_cooldown
	_wall_left = 0.0


## ПОДТЯГИВАНИЕ. Три луча, и все три обязательны: на уровне пояса — стена есть, на уровне
## головы — стены нет, сверху вниз — есть на что встать. Без второго игрок «подтягивается»
## на глухую стену; без третьего — в воздух.
func _try_mantle() -> bool:
	if not mantle or _mantle_left > 0.0:
		return false
	var f := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var ss := get_world_3d().direct_space_state
	var waist := global_position + Vector3.UP * 0.7
	var hit := ss.intersect_ray(PhysicsRayQueryParameters3D.create(waist, waist + f * 1.0,
		1, [get_rid()]))
	if hit.is_empty():
		return false
	var head := global_position + Vector3.UP * 1.85
	if not ss.intersect_ray(PhysicsRayQueryParameters3D.create(head, head + f * 1.0,
		1, [get_rid()])).is_empty():
		return false
	var probe: Vector3 = hit["position"] + f * 0.35 + Vector3.UP * 1.6
	var top := ss.intersect_ray(PhysicsRayQueryParameters3D.create(probe,
		probe - Vector3.UP * 1.9, 1, [get_rid()]))
	if top.is_empty():
		return false
	var h: float = top["position"].y - global_position.y
	if h < 0.35 or h > 1.7:
		return false
	_mantle_from = global_position
	_mantle_to = top["position"] + f * 0.35 + Vector3.UP * 0.05
	_mantle_left = mantle_time
	return true


func _do_mantle(delta: float) -> void:
	state = "уступ"
	_mantle_left -= delta
	var k := clampf(1.0 - _mantle_left / mantle_time, 0.0, 1.0)
	# Подъём раньше, доводка вперёд позже: иначе игрок въезжает в угол уступа и застревает.
	global_position = Vector3(
		lerpf(_mantle_from.x, _mantle_to.x, k * k),
		lerpf(_mantle_from.y, _mantle_to.y, sqrt(k)),
		lerpf(_mantle_from.z, _mantle_to.z, k * k))
	velocity = Vector3.ZERO
	if _mantle_left <= 0.0:
		_since_ground = 0.0


func _start_slide() -> void:
	if not slide or _sliding or not is_on_floor():
		return
	if Vector2(velocity.x, velocity.z).length() < slide_min_speed:
		return
	_sliding = true
	var flat := Vector3(velocity.x, 0.0, velocity.z).normalized()
	velocity += flat * slide_boost
	(_col.shape as CapsuleShape3D).height = _stand_h * 0.5
	_col.position.y = -_stand_h * 0.25


## Из скольжения нельзя встать под потолком. Без проверки капсула вырастает внутрь
## перекрытия, и игрока либо выталкивает наверх, либо заклинивает — классическая беда
## всех приседаний, и стоит она четыре строки.
func _ceiling_free() -> bool:
	var ss := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 0.1
	return ss.intersect_ray(PhysicsRayQueryParameters3D.create(
		from, from + Vector3.UP * (_stand_h * 0.5 + 0.15), 1, [get_rid()])).is_empty()


func _stop_slide() -> void:
	if not _ceiling_free():
		return
	_sliding = false
	(_col.shape as CapsuleShape3D).height = _stand_h
	_col.position.y = 0.0


func _camera(delta: float) -> void:
	# ОБРАТНАЯ СВЯЗЬ ПО СКОРОСТИ. Поле зрения расширяется с разгоном, камера кренится на
	# стене. Ни то, ни другое не меняет ни одного числа в физике — и при этом именно они
	# сообщают, что ты быстрый. Выключи их, и то же самое движение станет вялым.
	#
	# Поле зрения слушает НЕ модуль скорости, а её проекцию на взгляд. Расширение FOV
	# имитирует оптический поток — то, как мир проносится навстречу; боковое движение
	# такого потока не даёт, и рывок стрейфом раздувал картинку без всякой причины.
	# Заодно бесплатно решается движение спиной вперёд: проекция отрицательна, кика нет.
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var closing := Vector3(velocity.x, 0.0, velocity.z).dot(fwd)
	var target_fov := 78.0 + clampf(closing - ground_speed, 0.0, 16.0) * 1.5
	_cam.fov = lerpf(_cam.fov, target_fov, 1.0 - exp(-8.0 * delta))
	var want_roll := 0.0
	if _wall_left > 0.0:
		var side := _wall_n.cross(Vector3.UP).dot(Vector3(-sin(_yaw), 0.0, -cos(_yaw)))
		want_roll = wall_roll * signf(side)
	_roll = lerpf(_roll, want_roll, 1.0 - exp(-9.0 * delta))
	_cam.rotation = Vector3(_pitch, 0.0, _roll)
	rotation.y = _yaw
	var duck := -0.45 if _sliding else 0.0
	_cam.position.y = lerpf(_cam.position.y, 0.65 + duck, 1.0 - exp(-14.0 * delta))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * 0.0022
		_pitch = clampf(_pitch - event.relative.y * 0.0022, -1.4, 1.4)
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if k.pressed and not k.is_echo():
		match k.physical_keycode:
			KEY_SPACE:
				_jump_at = _clock
				_jump_used = false
				_try_mantle()
			KEY_SHIFT:
				_do_dash()
			KEY_CTRL:
				_start_slide()
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not k.pressed and k.physical_keycode == KEY_SPACE:
		# ПЕРЕМЕННАЯ ВЫСОТА. Отпустил рано — подъём срезается. Это единственный способ
		# дать один прыжок с двумя разными высотами, не заводя вторую кнопку.
		if variable_jump and velocity.y > 0.0:
			velocity.y *= jump_cut
