class_name CarTrack
extends Node3D
## ПЛОЩАДКА. Не трасса: трасса — это уже про гонку, а проба про машину.
##
## Четыре вещи, каждая под свой вопрос. Разгонная прямая — про мотор и коробку. Круг
## постоянного радиуса — про то, сколько машина держит вбок и что происходит на пределе.
## Слалом — про перекладку, то есть про крен и про то, успевает ли кузов за рулём.
## Гребёнка — про подвеску: единственное место, где видно, что она вообще есть.
##
## Площадки РАЗВЕДЕНЫ, а не свалены в кучу. На одной оси разгонная прямая идёт ровно по
## линии слалома: машина на девяноста собирает конусы и улетает, а замер разгона меряет не
## мотор, а столкновение.
##
## СЦЕНА ГОВОРИТ ГДЕ, КОД ГОВОРИТ СКОЛЬКО. Асфальт и трамплин — узлы: их одна штука, у них
## есть положение, их хочется двигать мышью. Конусы и валики гребёнки строятся кодом, но
## строятся ВОКРУГ УЗЛА-МЕТКИ, который лежит в сцене: подвинул метку — переехала вся
## группа.

@export var skidpad_radius := 26.0
@export var slalom_count := 9
@export var washboard_count := 14

## Узлы площадки. `@export var x: MeshInstance3D` красивее и переживает переименование, но
## написанный руками `.tscn` Godot так не разрешает: ссылки остаются пустыми. Штатная
## идиома — `@onready` с путём.
@onready var asphalt: MeshInstance3D = $Asphalt
@onready var skidpad: Node3D = $Skidpad
@onready var slalom: Node3D = $Slalom
@onready var washboard: Node3D = $Washboard


func _ready() -> void:
	_ground()
	_skidpad()
	_slalom()
	_washboard()


## Асфальт лежит узлом в сцене — здесь только сетка на него. Текстура рисуется кодом,
## потому что это данные, а не размещение: в файле сцены ей делать нечего.
func _ground() -> void:
	var material := StandardMaterial3D.new()
	# СЕТКА НУЖНА НЕ ДЛЯ КРАСОТЫ. На ровном сером асфальте скорость не читается вообще:
	# глазу не за что зацепиться, и сорок километров в час неотличимы от ста двадцати.
	var image := Image.create_empty(64, 64, false, Image.FORMAT_RGB8)
	image.fill(Color(0.27, 0.27, 0.28))
	for i in 64:
		image.set_pixel(i, 0, Color(0.36, 0.36, 0.37))
		image.set_pixel(0, i, Color(0.36, 0.36, 0.37))
	material.albedo_texture = ImageTexture.create_from_image(image)
	var plane: PlaneMesh = asphalt.mesh
	material.uv1_scale = Vector3(plane.size.x * 0.2, plane.size.x * 0.2, 1.0)
	material.roughness = 0.95
	asphalt.material_override = material


## Круг постоянного радиуса: держишь газ и руль и слушаешь, где машина сдаётся.
func _skidpad() -> void:
	for i in 36:
		var angle := TAU * float(i) / 36.0
		_cone(
				skidpad,
				Vector3(cos(angle), 0.0, sin(angle)) * skidpad_radius,
				Color(0.9, 0.55, 0.1))


## Слалом: перекладка вправо-влево. Шаг растёт, чтобы на скорости он не превращался в
## прямую — на восемнадцати метрах машина ещё успевает, на двадцати восьми уже нет.
func _slalom() -> void:
	for i in slalom_count:
		_cone(
				slalom,
				Vector3(0.0, 0.0, -float(i) * (18.0 + float(i) * 1.2)),
				Color(0.85, 0.85, 0.88))


## Гребёнка — поперечные валики. Единственное место, где подвеска видна глазом, а не
## выведена цифрой: кузов идёт своей волной, отставая от колёс.
func _washboard() -> void:
	for i in washboard_count:
		var visual := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(14.0, 0.16, 0.5)
		visual.mesh = box
		visual.position = Vector3(0.0, 0.0, -float(i) * 3.0)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.34, 0.33, 0.31)
		visual.material_override = material
		var body := StaticBody3D.new()
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box.size
		collider.shape = shape
		body.add_child(collider)
		visual.add_child(body)
		washboard.add_child(visual)


## Конусы — лёгкие твёрдые тела, а не декорация. Сбитый конус это ответ площадки на твою
## ошибку, и он читается лучше любой цифры на экране.
func _cone(at: Node3D, offset: Vector3, tint: Color) -> void:
	var body := RigidBody3D.new()
	body.mass = 1.2
	body.position = offset + Vector3(0.0, 0.3, 0.0)
	var collider := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.22
	shape.height = 0.6
	collider.shape = shape
	body.add_child(collider)
	var visual := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.03
	cone.bottom_radius = 0.26
	cone.height = 0.6
	cone.radial_segments = 10
	visual.mesh = cone
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	visual.material_override = material
	body.add_child(visual)
	at.add_child(body)
