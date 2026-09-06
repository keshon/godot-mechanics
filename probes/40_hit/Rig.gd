extends Node3D
class_name HitRig
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

## Преувеличение импульса. Единица — правда. Играбельно около двадцати, и это признание,
## а не настройка: физика попадания в играх врёт, вопрос только во сколько раз.
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
var _next := 0.0
var _yaw := 0.0
var _pitch := -0.12
var _blast := false
var _last := "—"

@onready var _cam: Camera3D = $Camera
@onready var _marks: Node3D = $Marks
@onready var _hud: RichTextLabel = $Ui/Info


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	_clock += delta
	var speed := 7.0 if Input.is_key_pressed(KEY_SHIFT) else 3.5
	var dir := _cam.global_basis * Vector3(
		Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left"),
		0.0,
		Input.get_action_strength(&"move_back") - Input.get_action_strength(&"move_forward"))
	if Input.is_action_pressed(&"jump"):
		dir += Vector3.UP
	_cam.global_position += dir * speed * delta
	_cam.rotation = Vector3(_pitch, _yaw, 0.0)

	if Input.is_action_pressed(&"fire") and _clock >= _next:
		_next = _clock + RATE
		_shoot()
	_readout()


func _shoot() -> void:
	shots += 1
	var from := _cam.global_position
	var dir := -_cam.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * RANGE)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		_last = "мимо"
		return
	if _blast:
		_explode(r["position"])
		return
	_land(r, dir, 1.0, 0)


## Одно попадание. Может породить второе — рикошетом, и рекурсия здесь ограничена глубиной:
## иначе пуля, залетевшая в угол, отражается бесконечно.
func _land(r: Dictionary, dir: Vector3, energy: float, depth: int) -> void:
	var at: Vector3 = r["position"]
	var normal: Vector3 = r["normal"]
	_mark(at, normal)

	var ric := HitImpact.ricochet(dir, normal, HitImpact.RICOCHET_DEG) \
		if ricochets else {"bounced": false, "dir": dir, "energy": 1.0}
	var left: float = energy * (ric["energy"] if ric["bounced"] else 1.0)

	var t := r["collider"] as HitTarget
	if t != null:
		hits += 1
		# ЛЕВЕР МОЖНО ВЫКЛЮЧИТЬ: тогда импульс уходит в центр масс, и предмет только
		# отодвигается, никогда не закручиваясь. Разница видна с первого выстрела.
		var point: Vector3 = at if lever else t.global_position
		t.hit(point, dir, left, gain, hurt)
		_last = "%s, энергия %.2f" % [t.material, left]
	else:
		_last = "фон"

	if ric["bounced"] and depth < 2 and left > 0.15:
		bounced += 1
		_last += " → рикошет"
		var q := PhysicsRayQueryParameters3D.create(at + ric["dir"] * 0.05,
			at + ric["dir"] * RANGE)
		var r2 := get_world_3d().direct_space_state.intersect_ray(q)
		if not r2.is_empty():
			_land(r2, ric["dir"], left, depth + 1)


## ЗАРЯД. Импульс по радиусу от точки взрыва — всем мишеням сразу, с падением по расстоянию.
## Точка приложения та же, что у пули: ближайшая к взрыву сторона предмета, иначе всё
## разлетается строго от центра и выглядит одинаково.
func _explode(at: Vector3) -> void:
	_mark(at, Vector3.UP)
	_last = "заряд"
	for n in get_tree().get_nodes_in_group("mishen"):
		var t := n as HitTarget
		if t == null:
			continue
		var away := t.global_position - at
		var d := away.length()
		if d > blast_radius:
			continue
		var falloff := 1.0 - d / blast_radius
		var point: Vector3 = at + away.normalized() * (d * 0.5) if lever else t.global_position
		t.hit(point, away.normalized(), falloff * blast_force / HitImpact.BULLET / gain,
			gain, hurt * falloff * 3.0)
		hits += 1


## Отметина попадания — простая, без декалей: проба не про следы, а про воздействие.
func _mark(at: Vector3, normal: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.05, 0.06)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	_marks.add_child(mi)
	mi.global_position = at + normal * 0.01
	if absf(normal.dot(Vector3.UP)) < 0.99:
		mi.look_at(at + normal, Vector3.UP)
	else:
		mi.look_at(at + normal, Vector3.FORWARD)
	if _marks.get_child_count() > 120:
		_marks.get_child(0).queue_free()


func _unhandled_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= mm.relative.x * 0.0032
		_pitch = clampf(_pitch - mm.relative.y * 0.0032, -1.5, 1.5)
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.keycode:
			KEY_1: _blast = not _blast
			KEY_2: lever = not lever
			KEY_3: ricochets = not ricochets
			KEY_4: gain = 1.0 if gain > 1.0 else 20.0
			KEY_TAB: get_tree().reload_current_scene()
	elif event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _readout() -> void:
	var alive := get_tree().get_nodes_in_group("mishen").size()
	_hud.text = "\n".join(PackedStringArray([
		"выстрелов [b]%d[/b]   попаданий %d   рикошетов %d   мишеней осталось %d" % [
			shots, hits, bounced, alive],
		"последнее: %s" % _last,
		"",
		"WASD лететь   SHIFT быстрее   ПРОБЕЛ вверх   ЛКМ огонь   TAB заново",
		"",
		"1 чем бить: %s" % ("ЗАРЯД" if _blast else "пуля"),
		"2 импульс в точку попадания: %s   (выкл — в центр масс, без вращения)" % _on(lever),
		"3 рикошеты: %s" % _on(ricochets),
		"4 преувеличение импульса: [b]×%d[/b]%s" % [roundi(gain),
			"   — честная пуля, 3.6 кг·м/с" if gain <= 1.0 else ""],
		"",
		"[color=#66ccff]честная пуля почти не двигает ящик. всё, что помнится по играм, —"
			+ " преувеличение в десятки раз.[/color]",
	]))


func _on(v: bool) -> String:
	return "вкл" if v else "выкл"
