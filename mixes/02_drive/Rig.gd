extends Node3D
## МУЛЬТИПРОБА: СТРЕЛЬБА С КОЛЁС.
##
## Вопрос, которого не задавала ни одна проба: **что нужно оружию, когда стрелок сам
## движется по инерции, кренится и подпрыгивает?** В 30-й стрелок стоял столбом. В первой
## мультипробе он бегал, но ногами по твёрдому. Здесь под ним подвеска, перенос веса и занос.
##
## Собрано из трёх сцен двух закрытых проб:
##
##   `37_car/track.tscn`    площадка: асфальт, круг, слалом, гребёнка, трамплин
##   `37_car/machine.tscn`  машина: четыре луча, подвеска, круг трения
##   `30_gun/weapon.tscn`   оружие в своём подвьюпорте со своим светом
##   `30_gun/fx.tscn`       искры, гильзы, трассеры, дырки
##
## Своего — только риг: он ведёт машину, целится мышью и стреляет.
##
## РАЗНИЦА С ПЕРВОЙ МУЛЬТИПРОБОЙ, и она важная. Игрока из 32-й приходилось глушить снаружи:
## он читает клавиши внутри себя. Машина не читает НИЧЕГО — у неё четыре поля наружу
## (`throttle`, `brake`, `steer_input`, `handbrake`), и риг просто их заполняет. Одна и та же
## мастерская, два соседних месяца, а собирается только вторая.

const RATE := 0.095
const RANGE := 90.0
const FLASH_TIME := 0.045
const START := Vector3(0.0, 0.9, 20.0)

## Породы площадки. Асфальт даёт тусклую пыль, металл трамплина — злые белые искры.
const SURFACES := {
	"Ramp": {"count": 30, "speed": 16.0, "life": 0.8, "streak": 0.034,
		"hot": Color(1.0, 0.98, 0.9), "hole": Color(0.82, 0.83, 0.86)},
	"": {"count": 15, "speed": 9.0, "life": 0.5, "streak": 0.020,
		"hot": Color(1.0, 0.86, 0.6), "hole": Color(0.62, 0.61, 0.58)},
}

@export var sensitivity := 0.0026
@export var chase := 8.5
@export var chase_height := 3.2
## Насколько оружие ОТСТАЁТ от кузова. Ноль — ствол приварен к раме и трясётся вместе с ней;
## это и есть самая заметная разница между стрельбой стоя и стрельбой с колёс.
@export_range(0.0, 3.0, 0.05) var sway := 1.0
## ГЛАЗ СТРЕЛКА ИЛИ ПОГОНЯ. Оружие из 30-й — это ВИММОДЕЛЬ: она рисуется в своём
## подвьюпорте так, будто камера и есть глаз держащего. Поставь камеру позади машины —
## и ствол повиснет перед экраном, не принадлежа никому. Значит либо камера на месте
## стрелка, либо виммодель прячется. Третьего у этого приёма нет, и это находка про сам
## приём, а не про пробы.
@export var gunner := true

var shots := 0

var _clock := 0.0
var _next := 0.0
var _kick := 0.0
var _kick_v := 0.0
var _flash_until := -1.0
var _shell_at := -1.0
var _yaw := 0.0
var _pitch := -0.06
var _sway := Vector2.ZERO
var _drop := 0.0
var _last_up := 0.0

@onready var _car: CarBody = $Car
@onready var _cam: Camera3D = $Camera
@onready var _fx: GunFx = $Fx
@onready var _weapon: Node3D = $Hands/Wrap/Sub/Weapon
@onready var _muzzle: Node3D = $Hands/Wrap/Sub/Weapon/Muzzle
@onready var _flash: MeshInstance3D = $Hands/Wrap/Sub/Weapon/Muzzle/Flash
@onready var _lamp: OmniLight3D = $MuzzleLight
@onready var _hud: RichTextLabel = $Ui/Info


func _ready() -> void:
	_flash.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## МАШИНА НЕ ЧИТАЕТ ВВОД — риг заполняет её четыре поля. Ровно поэтому её и удалось взять
## как есть: между «управлять» и «быть управляемым» проходит вся разница.
func _physics_process(_delta: float) -> void:
	var back := Input.get_action_strength(&"move_back")
	var v := _car.linear_velocity.dot(-_car.global_basis.z)
	_car.throttle = Input.get_action_strength(&"move_forward")
	if back > 0.0 and v < 0.6:
		_car.throttle = -back
		_car.brake = 0.0
	else:
		_car.brake = back
	_car.steer_input = Input.get_action_strength(&"move_left") \
		- Input.get_action_strength(&"move_right")
	_car.handbrake = Input.is_action_pressed(&"jump")


func _process(delta: float) -> void:
	_clock += delta
	_kick_v -= _kick * 220.0 * delta
	_kick_v *= exp(-12.0 * delta)
	_kick = maxf(_kick + _kick_v * delta, 0.0)

	if Input.is_action_pressed(&"fire") and _clock >= _next:
		_next = _clock + RATE
		_shoot()

	_flash.visible = _clock < _flash_until
	_lamp.light_energy = 9.0 if _clock < _flash_until else 0.0
	if _flash.visible:
		var fm: ShaderMaterial = _flash.material_override
		var age: float = 1.0 - (_flash_until - _clock) / FLASH_TIME
		fm.set_shader_parameter("age", clampf(age, 0.0, 1.0))
	if _shell_at > 0.0 and _clock >= _shell_at:
		_shell_at = -1.0
		var b := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
		_fx.shell(_turret_muzzle(b) - b * Vector3(0.0, 0.0, -0.45), b.x, b.y)

	_camera()
	_hold(delta)
	_readout()


## ПРИЦЕЛ ЖИВЁТ В МИРОВЫХ ОСЯХ, а не в осях машины, и это не мелочь: только так можно
## держать ствол на цели, пока машину разворачивает в заносе. Приваришь прицел к кузову —
## и вся стрельба с колёс превращается в «целься корпусом».
func _camera() -> void:
	var b := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	var pivot: Vector3 = _car.global_position + Vector3.UP * 1.1
	if gunner:
		# Глаз стрелка стоит В ТУРЕЛИ: над задней частью и ВЫШЕ кузова. Первый заход посадил
		# его на 1.55 — и при взгляде вбок весь экран занимал собственный борт. Стрелок в
		# кузове обязан видеть поверх своей машины, иначе стрелять можно только вперёд.
		_cam.global_transform = Transform3D(b, _car.global_transform
			* Vector3(0.0, 2.05, 1.15))
	else:
		_cam.global_transform = Transform3D(b, pivot + b * Vector3(0.0, chase_height, chase))
	$Hands.visible = gunner


## Оружие в подвьюпорте держится ригом. Здесь к покачиванию добавляются две вещи, которых
## не было ни в одной пробе: ОТСТАВАНИЕ от поворота кузова и ПРОСАДКА на неровности.
func _hold(delta: float) -> void:
	# Угловая скорость машины в её собственных осях: крен и тангаж, которые ствол обязан
	# догонять с запозданием, иначе он приварен к раме.
	var local: Vector3 = _car.global_basis.inverse() * _car.angular_velocity
	_sway = _sway.lerp(Vector2(local.x, local.y), 1.0 - exp(-7.0 * delta))
	# Вертикальный толчок от подвески: разница вертикальной скорости за кадр — это и есть
	# то, что подбрасывает руки на гребёнке.
	var up_now: float = _car.linear_velocity.y
	_drop = lerpf(_drop, clampf((up_now - _last_up) * 0.06, -0.05, 0.05),
		1.0 - exp(-14.0 * delta))
	_last_up = up_now

	# ВЕЛИЧИНА ОТСТАВАНИЯ ВЫМЕРЕНА, а не подобрана на глаз. Пик угловой скорости машины в
	# повороте с ручником — 1.39 рад/с; при прежнем коэффициенте 0.09 это давало 7° на пике
	# и около двух в обычном повороте, то есть выключатель не менял ничего видимого.
	# Теперь 0.19 — это 15° на пике, плюс боковой сдвиг: у виммодели смещение читается
	# лучше поворота, потому что она висит в ладони от глаза.
	var bob := sin(_clock * 6.0) * 0.004
	var lag := _sway.y * sway
	_weapon.position = Vector3(0.24 + lag * 0.045, -0.24 + bob + _drop,
		-0.62 + _kick * 0.07)
	_weapon.rotation = Vector3(_kick * 0.16 - _sway.x * sway * 0.19,
		-lag * 0.19, lag * 0.11)


func _shoot() -> void:
	shots += 1
	var from := _cam.global_position
	var cone := 0.006 + _kick * 0.045
	var b := _cam.global_transform.basis
	var dir := (-b.z + b.x * randf_range(-cone, cone)
		+ b.y * randf_range(-cone, cone)).normalized()
	var hit_at := from + dir * RANGE
	var normal := -dir

	var q := PhysicsRayQueryParameters3D.create(from, hit_at)
	# Своя машина в прицел не попадает — иначе каждый выстрел бьёт в собственный капот.
	q.exclude = [_car.get_rid()]
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		hit_at = r["position"]
		normal = r["normal"]

	# ДУЛО ЖИВЁТ НА МАШИНЕ, а не перед камерой. Раньше оно считалось от камеры — в первом
	# лице это верно (камера и есть глаз держащего), а в погоне камера висит в восьми
	# метрах позади и выше, и трассеры вылетали из пустоты над машиной.
	#
	# Это цена виммодели: точка выстрела у неё определена только в первом лице. На
	# платформе дуло обязано быть точкой ТУРЕЛИ, и тогда оба вида честны.
	var muzzle_world := _turret_muzzle(b)
	_flash_until = _clock + FLASH_TIME
	_lamp.global_position = muzzle_world
	var fm: ShaderMaterial = _flash.material_override
	fm.set_shader_parameter("seed", randf())
	fm.set_shader_parameter("age", 0.0)

	if shots % 3 == 0:
		_fx.tracer(muzzle_world, hit_at)
	if not r.is_empty():
		var surf: Dictionary = _surface_of(r["collider"])
		_fx.hole(hit_at, normal, dir, surf["hole"])
		_fx.sparks(hit_at, normal, dir, surf)
	_shell_at = _clock + 0.04
	_kick_v = minf(_kick_v + 4.6, 9.0)
	_kick = minf(_kick, 1.3)


## Точка ствола турели в осях мира: плечо стрелка плюс полметра вдоль прицела.
func _turret_muzzle(aim: Basis) -> Vector3:
	var eye: Vector3 = _car.global_transform * Vector3(0.0, 2.05, 1.15)
	return eye + aim * Vector3(0.22, -0.08, -0.7)


func _surface_of(body: Object) -> Dictionary:
	var n: String = (body as Node).name if body is Node else ""
	for key in SURFACES:
		if key != "" and n.begins_with(key):
			return SURFACES[key]
	return SURFACES[""]


func _unhandled_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= mm.relative.x * sensitivity
		_pitch = clampf(_pitch - mm.relative.y * sensitivity,
			-deg_to_rad(60.0), deg_to_rad(35.0))
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.keycode:
			KEY_1: sway = 0.0 if sway > 0.0 else 1.0
			KEY_2: gunner = not gunner
			KEY_TAB: _reset()
	elif event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _reset() -> void:
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
	# Угол между тем, куда смотрит ствол, и тем, куда едет машина. Ради этого числа
	# мультипроба и собиралась: стоя оно всегда ноль.
	var aim := -_cam.global_basis.z
	var nose := -_car.global_basis.z
	var apart := rad_to_deg(Vector2(aim.x, aim.z).angle_to(Vector2(nose.x, nose.z)))
	_hud.text = "\n".join(PackedStringArray([
		"[b]%d[/b] км/ч   передача %d   %d об/мин   выстрелов %d" % [roundi(speed),
			_car.gear, roundi(_car.rpm), shots],
		"",
		"ствол в стороне от носа на [b]%+d°[/b]   крен %+.2f" % [roundi(apart),
			_car.global_basis.x.y],
		"",
		"WASD руль и газ   SPACE ручник   МЫШЬ прицел   ЛКМ огонь   TAB на старт",
		"1 отставание ствола от кузова: %s" % ("вкл" if sway > 0.0 else "выкл"),
		"2 камера: %s" % ("глаз стрелка" if gunner else "погоня (ствол убран)"),
		"",
		"[color=#66ccff]мультипроба: машина и площадка из 37-й, оружие и эффекты из 30-й.[/color]",
	]))
