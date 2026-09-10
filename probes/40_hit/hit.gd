class_name HitRig
extends Node3D
## РУКИ, КАМЕРА И РУЧКИ.
##
## По соглашению камера и интерфейс принадлежат ригу, а не мишеням. Мишени не знают ни про
## камеру, ни про клавиатуру — им только сообщают, что в них попали.
##
## Стрелять можно двумя вещами, и сравнение — половина пробы:
##
##   ПУЛЯ — луч, мгновенно, импульс 3.6 кг·м/с. Честная пуля почти не двигает ящик.
##   ЗАРЯД — взрыв в точке: импульс по радиусу, от центра, всем сразу.
##
## Второе нужно не ради зрелища, а чтобы стало видно, насколько первое СЛАБОЕ. Пока
## сравнивать не с чем, «пуля не двигает ящик» читается поломкой, а не физикой.

const RANGE := 60.0
const RATE := 0.12
const MAX_MARKS := 120

## Преувеличение импульса. Единица — правда. Играбельно около двадцати, и это признание, а
## не настройка: физика попадания в играх врёт, вопрос только во сколько раз.
@export_range(1.0, 60.0, 1.0) var gain := 20.0
@export var hurt := 12.0
@export var lever := true
@export var ricochets := true
@export_range(0.0, 8.0, 0.1) var blast_radius := 3.5
@export_range(0.0, 400.0, 5.0) var blast_force := 120.0

var shots := 0
var hits := 0
var bounced := 0

var _clock := 0.0
var _next_shot := 0.0
var _yaw := 0.0
var _pitch := -0.12
var _blast := false
var _last_hit := "—"

@onready var _camera: Camera3D = $Camera
@onready var _marks: Node3D = $Marks
@onready var _hud: RichTextLabel = $Ui/Info


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	_clock += delta
	var speed := 7.0 if Input.is_key_pressed(KEY_SHIFT) else 3.5
	var wanted := _camera.global_basis * Vector3(
			Input.get_action_strength(&"move_right")
			- Input.get_action_strength(&"move_left"),
			0.0,
			Input.get_action_strength(&"move_back")
			- Input.get_action_strength(&"move_forward"))
	if Input.is_action_pressed(&"jump"):
		wanted += Vector3.UP
	_camera.global_position += wanted * speed * delta
	_camera.rotation = Vector3(_pitch, _yaw, 0.0)

	if Input.is_action_pressed(&"fire") and _clock >= _next_shot:
		_next_shot = _clock + RATE
		_shoot()
	_readout()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * 0.0032
		_pitch = clampf(_pitch - event.relative.y * 0.0032, -1.5, 1.5)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_blast = not _blast
			KEY_2:
				lever = not lever
			KEY_3:
				ricochets = not ricochets
			KEY_4:
				gain = 1.0 if gain > 1.0 else 20.0
			KEY_TAB:
				get_tree().reload_current_scene()
		return
	if event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _shoot() -> void:
	shots += 1
	var from := _camera.global_position
	var direction := -_camera.global_basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * RANGE)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_last_hit = "мимо"
		return
	if _blast:
		_explode(hit["position"])
		return
	_land(hit, direction, 1.0, 0)


## Одно попадание. Может породить второе — рикошетом, и рекурсия здесь ограничена
## глубиной: иначе пуля, залетевшая в угол, отражается бесконечно.
func _land(hit: Dictionary, direction: Vector3, energy: float, depth: int) -> void:
	var at: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	_mark(at, normal)

	var bounce := {"bounced": false, "dir": direction, "energy": 1.0}
	if ricochets:
		bounce = HitImpact.ricochet(direction, normal, HitImpact.RICOCHET_DEG)
	var left: float = energy * (bounce["energy"] if bounce["bounced"] else 1.0)

	var target := hit["collider"] as HitTarget
	if target != null:
		hits += 1
		# РЫЧАГ МОЖНО ВЫКЛЮЧИТЬ: тогда импульс уходит в центр масс, и предмет только
		# отодвигается, никогда не закручиваясь. Разница видна с первого выстрела.
		var point: Vector3 = at if lever else target.global_position
		target.hit(point, direction, left, gain, hurt)
		_last_hit = "%s, энергия %.2f" % [target.material, left]
	else:
		_last_hit = "фон"

	if not (bounce["bounced"] and depth < 2 and left > 0.15):
		return
	bounced += 1
	_last_hit += " → рикошет"
	var away: Vector3 = bounce["dir"]
	var query := PhysicsRayQueryParameters3D.create(at + away * 0.05, at + away * RANGE)
	var next := get_world_3d().direct_space_state.intersect_ray(query)
	if not next.is_empty():
		_land(next, away, left, depth + 1)


## ЗАРЯД. Импульс по радиусу от точки взрыва — всем мишеням сразу, с падением по
## расстоянию. Точка приложения та же, что у пули: ближайшая к взрыву сторона предмета,
## иначе всё разлетается строго от центра и выглядит одинаково.
func _explode(at: Vector3) -> void:
	_mark(at, Vector3.UP)
	_last_hit = "заряд"
	for node in get_tree().get_nodes_in_group("mishen"):
		var target := node as HitTarget
		if target == null:
			continue
		var away := target.global_position - at
		var range_to := away.length()
		if range_to > blast_radius:
			continue
		var falloff := 1.0 - range_to / blast_radius
		var point := target.global_position
		if lever:
			point = at + away.normalized() * (range_to * 0.5)
		target.hit(
				point,
				away.normalized(),
				falloff * blast_force / HitImpact.BULLET / gain,
				gain,
				hurt * falloff * 3.0)
		hits += 1


## Отметина попадания — простая, без декалей: проба не про следы, а про воздействие.
func _mark(at: Vector3, normal: Vector3) -> void:
	var visual := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	visual.mesh = quad
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.05, 0.05, 0.06)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visual.material_override = material
	_marks.add_child(visual)
	visual.global_position = at + normal * 0.01
	if absf(normal.dot(Vector3.UP)) < 0.99:
		visual.look_at(at + normal, Vector3.UP)
	else:
		visual.look_at(at + normal, Vector3.FORWARD)
	if _marks.get_child_count() > MAX_MARKS:
		_marks.get_child(0).queue_free()


func _on_off(value: bool) -> String:
	return "вкл" if value else "выкл"


func _readout() -> void:
	var alive := get_tree().get_nodes_in_group("mishen").size()
	_hud.text = "\n".join(PackedStringArray([
		"выстрелов [b]%d[/b]   попаданий %d   рикошетов %d   мишеней осталось %d" % [
			shots, hits, bounced, alive],
		"последнее: %s" % _last_hit,
		"",
		"WASD лететь   SHIFT быстрее   ПРОБЕЛ вверх   ЛКМ огонь   TAB заново",
		"",
		"1 чем бить: %s" % ("ЗАРЯД" if _blast else "пуля"),
		"2 импульс в точку попадания: %s   (выкл — в центр масс, без вращения)" % (
				_on_off(lever)),
		"3 рикошеты: %s" % _on_off(ricochets),
		"4 преувеличение импульса: [b]×%d[/b]%s" % [
			roundi(gain),
			"   — честная пуля, 3.6 кг·м/с" if gain <= 1.0 else ""],
		"",
		"[color=#66ccff]честная пуля почти не двигает ящик. всё, что помнится по играм, —"
			+ " преувеличение в десятки раз.[/color]",
	]))
