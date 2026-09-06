extends Node3D
## МУЛЬТИПРОБА: АКРОБАТИКА ИЗ 32-Й ПЛЮС ОРУЖИЕ ИЗ 30-Й.
##
## Ни одна проба не отвечает на вопрос «а вместе это работает?». Тридцать восемь раз мы
## спрашивали «как ощущается механика ОДНА» — и ни разу «что происходит, когда их две».
##
## Здесь ничего не написано заново. Из проб инстанцируются четыре сцены:
##
##   `32_move/course.tscn`  — трасса: провалы, стена, уступ, потолок, арена
##   `32_move/player.tscn`  — игрок со всей акробатикой, своей камерой и мышью
##   `30_gun/weapon.tscn`   — оружие в собственном подвьюпорте со своим светом
##   `30_gun/fx.tscn`       — искры, гильзы, трассеры, дырки
##
## А этот файл — СВОЙ риг, и по уставу он всегда свой: одна камера (игрока), один интерфейс,
## один владелец стрельбы. Общего рига между мультипробами не будет, иначе получится
## фреймворк, против которого написано правило про ноль общего кода.
##
## ЧТО ЗДЕСЬ ВЫЯСНИЛОСЬ И ЧЕГО НЕ ПОКАЗАЛА НИ ОДНА ПРОБА — в NOTES.md. Коротко: соединять
## пришлось не код, а ВЛАДЕНИЕ. Камера, мышь, ввод и отдача — у каждой пробы был свой
## хозяин, и в паре хозяин может быть только один.

const RATE := 0.095
const RANGE := 60.0
const FLASH_TIME := 0.045

## Поверхности трассы. У 30-й пробы дерево и металл искрят по-разному, и это её лучшая
## находка. На трассе 32-й пород нет — есть плиты, стены и потолки, и они получают свои:
## бетонная плита даёт короткие тусклые искры, деревянная стена — редкие и медленные.
const SURFACES := {
	"Wall": {"count": 9, "speed": 5.0, "life": 0.32, "streak": 0.010,
		"hot": Color(1.0, 0.62, 0.28), "hole": Color(0.34, 0.23, 0.12)},
	"Roof": {"count": 30, "speed": 16.0, "life": 0.8, "streak": 0.034,
		"hot": Color(1.0, 0.98, 0.9), "hole": Color(0.82, 0.83, 0.86)},
	"": {"count": 15, "speed": 9.0, "life": 0.5, "streak": 0.020,
		"hot": Color(1.0, 0.86, 0.6), "hole": Color(0.62, 0.61, 0.58)},
}

@export var tracers := true
@export var sparks := true
@export var decals := true
@export var weapon_kick := true

var shots := 0

var _clock := 0.0
var _next := 0.0
var _kick := 0.0
var _kick_v := 0.0
var _flash_until := -1.0
var _shell_at := -1.0

@onready var _player: CharacterBody3D = $Player
@onready var _cam: Camera3D = $Player/Cam
@onready var _fx: GunFx = $Fx
@onready var _weapon: Node3D = $Hands/Wrap/Sub/Weapon
@onready var _muzzle: Node3D = $Hands/Wrap/Sub/Weapon/Muzzle
@onready var _flash: MeshInstance3D = $Hands/Wrap/Sub/Weapon/Muzzle/Flash
@onready var _lamp: OmniLight3D = $MuzzleLight
@onready var _hud: RichTextLabel = $Ui/Info


func _ready() -> void:
	_flash.visible = false


func _process(delta: float) -> void:
	_clock += delta
	# ПРУЖИНА ОТДАЧИ. Скопирована из 30-й, а не вызвана из неё: риг свой, и по уставу
	# копирование здесь не запах, а цена независимости.
	_kick_v -= _kick * 220.0 * delta
	_kick_v *= exp(-12.0 * delta)
	_kick = maxf(_kick + _kick_v * delta, 0.0)

	if Input.is_action_pressed(&"fire") and _clock >= _next:
		_next = _clock + RATE
		_shoot()

	# ПЛАМЯ РАСТЁТ ПО ВОЗРАСТУ, и это надо гнать каждый кадр. В шейдере стоит
	# `grow = 0.35 + 0.65 * smoothstep(0, 0.25, age)`: без обновления `age` вспышка
	# навсегда застревает на 35% размера. Выглядит не как ошибка, а как «пламя мельче,
	# чем в пробе», и найти это можно только сравнением с оригиналом.
	_flash.visible = _clock < _flash_until
	_lamp.light_energy = 9.0 if _clock < _flash_until else 0.0
	if _flash.visible:
		var fm: ShaderMaterial = _flash.material_override
		var age: float = 1.0 - (_flash_until - _clock) / FLASH_TIME
		fm.set_shader_parameter("age", clampf(age, 0.0, 1.0))
	if _shell_at > 0.0 and _clock >= _shell_at:
		_shell_at = -1.0
		var port: Node3D = $Hands/Wrap/Sub/Weapon/Port
		var world: Vector3 = _cam.global_transform * port.position
		_fx.shell(world, _cam.global_basis.x, _cam.global_basis.y)

	_hold()
	_readout()


## Оружие висит в своём подвьюпорте, и держать его надо руками рига — покачивание при
## ходьбе и отход при выстреле. Скорость берётся у игрока: чем быстрее бежишь, тем размашистее
## качается ствол, и это связь, которой не было ни в одной пробе по отдельности.
func _hold() -> void:
	var swing: float = clampf(_player.speed / 9.0, 0.0, 1.6)
	var bob := sin(_clock * 9.5) * 0.008 * (0.3 + swing)
	var kick: float = _kick if weapon_kick else 0.0
	_weapon.position = Vector3(0.24, -0.24 + bob, -0.62 + kick * 0.07)
	_weapon.rotation = Vector3(kick * 0.16, 0.0, 0.0)


func _shoot() -> void:
	shots += 1
	var from := _cam.global_position
	# Разброс растёт с уже набранной отдачей — держать спуск и щёлкать одиночными должно
	# ощущаться по-разному.
	var cone := 0.006 + _kick * 0.045
	var b := _cam.global_transform.basis
	var dir := (-b.z + b.x * randf_range(-cone, cone)
		+ b.y * randf_range(-cone, cone)).normalized()
	var hit_at := from + dir * RANGE
	var normal := -dir

	var q := PhysicsRayQueryParameters3D.create(from, hit_at)
	q.exclude = [_player.get_rid()]
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		hit_at = r["position"]
		normal = r["normal"]

	# Дуло живёт в мире ПОДВЬЮПОРТА, чья камера стоит в начале координат и смотрит в −Z.
	# Значит его положение там совпадает с положением в осях глаза, и одно умножение на
	# матрицу камеры возвращает его в настоящий мир — туда, где нужны свет и трассер.
	var muzzle_world: Vector3 = _cam.global_transform * _muzzle.position
	_flash_until = _clock + FLASH_TIME
	_lamp.global_position = muzzle_world
	var fm: ShaderMaterial = _flash.material_override
	fm.set_shader_parameter("seed", randf())
	fm.set_shader_parameter("age", 0.0)

	if tracers and shots % 3 == 0:
		_fx.tracer(muzzle_world, hit_at)
	if not r.is_empty():
		var surf: Dictionary = _surface_of(r["collider"])
		if decals:
			_fx.hole(hit_at, normal, dir, surf["hole"])
		if sparks:
			_fx.sparks(hit_at, normal, dir, surf)
	_shell_at = _clock + 0.04
	_kick_v = minf(_kick_v + 4.6, 9.0)
	_kick = minf(_kick, 1.3)


## Порода по имени узла — ровно как в 30-й. Трасса называет свои части `Plate01`, `Wall03`,
## `Roof01`, и этого хватает.
func _surface_of(body: Object) -> Dictionary:
	var n: String = (body as Node).name if body is Node else ""
	for key in SURFACES:
		if key != "" and n.begins_with(key):
			return SURFACES[key]
	return SURFACES[""]


func _readout() -> void:
	_hud.text = "\n".join(PackedStringArray([
		"[b]%.1f[/b] м/с   [color=#aaaaaa]%s[/color]   выстрелов %d" % [
			_player.speed, _player.state, shots],
		"",
		"WASD бег   ПРОБЕЛ прыжок   SHIFT рывок   CTRL скольжение   ЛКМ огонь",
		"",
		"[color=#66ccff]мультипроба: трасса и игрок из 32-й, оружие и эффекты из 30-й.[/color]",
		"[color=#888888]ни строки механики не написано заново — только риг.[/color]",
	]))
