extends Node3D
class_name CarDrive
## РУКИ, КАМЕРА И РУЧКИ.
##
## Машина ничего не знает про клавиатуру: сюда приходит нажатие, отсюда уходят четыре
## числа — газ, тормоз, руль, ручник. Так же было бы с геймпадом, с автопилотом или с
## записью заезда, и это единственная причина держать ввод отдельно.
##
## Переключатели — на цифрах, потому что WASD занят рулём. Каждый снимает ровно одно
## правило: перенос веса, круг трения, стабилизатор. Гасить их по одному и смотреть, что
## именно ты чувствовал, — вся суть.

const START := Vector3(0.0, 0.9, 20.0)

@export_group("Камера")
@export var distance := 8.2
@export var height := 3.2
@export var follow_lag := 6.0
## Камера идёт за ВЕКТОРОМ СКОРОСТИ, а не за носом машины. Иначе в заносе она едет боком
## вместе с кузовом, и занос перестаёт читаться — видно только, что мир повернулся.
@export_range(0.0, 1.0, 0.05) var velocity_follow := 0.75
@export_range(0.0, 30.0, 1.0) var fov_gain := 14.0

var _car: CarBody
var _cam: Camera3D
var _dir := Vector3.FORWARD
var _bumper := false
var _stiff := 1
var _wet := false

@onready var _hud: RichTextLabel = $Ui/Hud
@onready var _keys: Label = $Ui/Keys


func _ready() -> void:
	_car = $Car
	_cam = $Camera
	_reset()


func _physics_process(_delta: float) -> void:
	_car.throttle = Input.get_action_strength(&"move_forward")
	# Задний ход отдельной кнопкой не нужен: тормоз до остановки, потом та же клавиша
	# толкает назад. Так делает почти всё, во что играют с клавиатуры.
	var back := Input.get_action_strength(&"move_back")
	var v := _car.linear_velocity.dot(-_car.global_basis.z)
	if back > 0.0 and v < 0.6:
		_car.throttle = -back
		_car.brake = 0.0
	else:
		_car.brake = back
	_car.steer_input = Input.get_action_strength(&"move_left") \
		- Input.get_action_strength(&"move_right")
	_car.handbrake = Input.is_action_pressed(&"jump")


func _process(delta: float) -> void:
	_camera(delta)
	_readout()


func _camera(delta: float) -> void:
	if _bumper:
		_cam.global_transform = _car.global_transform
		_cam.global_position += _car.global_basis * Vector3(0.0, 1.45, -2.6)
		_cam.fov = 78.0
		return
	var flat := Vector3(_car.linear_velocity.x, 0.0, _car.linear_velocity.z)
	var want := -_car.global_basis.z
	if flat.length() > 6.0:
		want = want.lerp(flat.normalized(), velocity_follow).normalized()
	_dir = _dir.lerp(want, 1.0 - exp(-4.0 * delta)).normalized()
	var target := _car.global_position - _dir * distance + Vector3.UP * height
	_cam.global_position = _cam.global_position.lerp(target,
		1.0 - exp(-follow_lag * delta))
	_cam.look_at(_car.global_position + Vector3.UP * 0.8)
	# Поле зрения растёт со скоростью. На машине это работает иначе, чем на страйфе: там
	# движение боковое и растяжение врало, здесь мы едем ровно туда, куда смотрим.
	_cam.fov = 70.0 + fov_gain * clampf(_car.linear_velocity.length() / 45.0, 0.0, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			_car.layout = (_car.layout + 1) % 3
			_car.relayout()
		KEY_2: _car.friction_circle = not _car.friction_circle
		KEY_3: _car.weight_transfer = not _car.weight_transfer
		KEY_4: _set_stiff((_stiff + 1) % 3)
		KEY_5: _set_wet(not _wet)
		KEY_6: _car.anti_roll = 0.0 if _car.anti_roll > 0.0 else 9000.0
		KEY_7: _bumper = not _bumper
		KEY_TAB: _reset()


## Мягко / штатно / жёстко. Демпфер едет за пружиной: доля от критического затухания у
## всех трёх одна, иначе мягкая подвеска начинает раскачиваться, а жёсткая — стучать, и
## сравнивать становится нечего.
func _set_stiff(mode: int) -> void:
	_stiff = mode
	var k: float = [24000.0, 44000.0, 78000.0][mode]
	_car.stiffness = k
	_car.damping = 0.55 * 2.0 * sqrt(k * _car.body_mass * 0.25)


func _set_wet(wet: bool) -> void:
	_wet = wet
	_car.grip = 0.62 if wet else 1.10


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
	_car.gear = 1


func _readout() -> void:
	var speed := _car.linear_velocity.dot(-_car.global_basis.z) * 3.6
	var b := _car.global_basis
	var rows := PackedStringArray([
		"[b]%d[/b] км/ч     передача %d     %d об/мин" % [roundi(speed), _car.gear,
			roundi(_car.rpm)],
		"",
		# Полоски израсходованного сцепления рисовать не надо: колесо на пределе краснеет
		# прямо в мире. Цифры остаются для того, чего глазом не увидеть, — сколько именно
		# ньютонов ушло с передней оси на заднюю.
		"нагрузка на колёса, Н   (в покое по %d на каждое)" % roundi(
			_car.body_mass * 9.81 * 0.25),
		"перед  %d  |  %d" % [roundi(_car.wheels[0].load), roundi(_car.wheels[1].load)],
		"зад    %d  |  %d" % [roundi(_car.wheels[2].load), roundi(_car.wheels[3].load)],
		"",
		"крен %+.2f   клевок %+.2f   увод передних %+.2f" % [b.x.y, -b.z.y,
			(_car.wheels[0].slip + _car.wheels[1].slip) * 0.5],
	])
	_hud.text = "\n".join(rows)
	_keys.text = "\n".join(PackedStringArray([
		"WASD руль и газ     SPACE ручник     TAB на старт",
		"",
		"1 привод: %s" % ["передний", "задний", "полный"][_car.layout],
		"2 круг трения: %s" % _on(_car.friction_circle),
		"3 перенос веса: %s" % _on(_car.weight_transfer),
		"4 подвеска: %s" % ["мягкая", "штатная", "жёсткая"][_stiff],
		"5 покрытие: %s" % ("мокрое" if _wet else "сухое"),
		"6 стабилизатор: %s" % _on(_car.anti_roll > 0.0),
		"7 камера: %s" % ("с бампера" if _bumper else "погоня"),
	]))


func _on(v: bool) -> String:
	return "вкл" if v else "выкл"
