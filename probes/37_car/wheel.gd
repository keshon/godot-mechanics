@tool
class_name CarWheel
extends Node3D
## ОДНО КОЛЕСО — УЗЛОМ СЦЕНЫ.
##
## Положение колеса — ровно то, что хочется таскать мышью: раздвинул колею, отодвинул
## заднюю ось, увидел, как поменялся перенос веса. Признак «ведущее» — галочка в
## инспекторе, а не ветка в коде.
##
## Узлов внутри два, и это не прихоть: внешний рулит (вокруг Y), внутренний катится
## (вокруг X). Одним не обойтись — повороты не переставляются местами, и катящееся колесо
## начало бы уводить руль.

@export var front := true
## Ведущее ли колесо. Раскладку привода переключает `drive.gd`, но исходное состояние —
## здесь, галочкой, и «переднеприводная машина» становится свойством сцены.
@export var driven := false
@export var radius := 0.55:
	set(value):
		radius = value
		_rebuild()
@export var width := 0.45:
	set(value):
		width = value
		_rebuild()

## РЫЧАГ И ПРУЖИНА — УЗЛЫ СЦЕНЫ, а не создание в коде. Лежат рядом с колесом, а не под
## ним: колесо крутится рулём, рычаг вместе с ним поворачиваться не должен. Их положение
## считается каждый кадр из хода подвески — трогать руками нечего, — но САМИ ДЕТАЛИ
## должны быть видны в редакторе, иначе подвеска существует только в запущенной игре.
## Связывает их `car.gd` по имени.
var arm: MeshInstance3D
var spring: MeshInstance3D

## Точка крепления в осях кузова — берётся из положения узла в сцене при запуске. Дальше
## сам узел ездит вниз по ходу подвески, а точка остаётся.
var attach := Vector3.ZERO
## Ход подвески, метры.
var travel := 0.0
## Вертикальная нагрузка на колесо, ньютоны. НЕ `load`: так зовут встроенную функцию.
var wheel_load := 0.0
var slip := 0.0
var grounded := false
var hit := Vector3.ZERO
var normal := Vector3.UP
## Доля израсходованного сцепления, 0…1.
var grip_used := 0.0
## Скорость в точке контакта вдоль колеса, м/с.
var roll := 0.0
var spin: Node3D

var _rubber: Array[StandardMaterial3D] = []


func _ready() -> void:
	attach = position
	_rebuild()


## Колесо на пределе сцепления краснеет. Цифру на экране надо читать, а цвет видно боковым
## зрением, не отрываясь от дороги.
func tint_by_grip() -> void:
	var tint := Color(0.07, 0.07, 0.08).lerp(
			Color(0.95, 0.15, 0.05), smoothstep(0.55, 1.0, grip_used))
	for material in _rubber:
		material.albedo_color = tint


## Натянуть рычаг и пружину между точками. Верхняя опора СМЕЩЕНА вдоль машины, а не стоит
## над осью: иначе пружина оказывается ровно за колесом и её не видно ни сбоку, ни в три
## четверти — то есть деталь, ради которой всё затевалось, невидима. Обе детали единичной
## длины по своей оси, так что вся работа — поворот плюс масштаб; новых мешей не
## создаётся ни одного.
func place_linkage(pivot: Vector3, hub: Vector3, top: Vector3) -> void:
	_span(arm, pivot, hub, true)
	_span(spring, top, pivot.lerp(hub, 0.82), false)


func _make_material(tint: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = rough
	material.metallic = metal
	return material


## Резина, грунтозацепы и диск. Строятся кодом, а не лежат в сцене, и это ровно тот
## случай, который правило разрешает: восемь одинаковых зацепов по кругу — «сколько», а не
## «где».
func _rebuild() -> void:
	if not is_inside_tree():
		return
	if spin != null:
		spin.queue_free()
	_rubber.clear()
	spin = Node3D.new()
	add_child(spin)

	var rubber := _make_material(Color(0.07, 0.07, 0.08))
	_rubber.append(rubber)
	var tyre := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = width
	cylinder.radial_segments = 16
	tyre.mesh = cylinder
	tyre.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	tyre.material_override = rubber
	spin.add_child(tyre)

	var lug := _make_material(Color(0.11, 0.11, 0.12))
	_rubber.append(lug)
	for i in 8:
		var angle := TAU * float(i) / 8.0
		var block := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(width * 1.14, 0.09, radius * 0.5)
		block.mesh = box
		block.position = Vector3(0.0, sin(angle) * radius, cos(angle) * radius)
		block.rotation.x = -angle
		block.material_override = lug
		spin.add_child(block)

	var hub := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius * 0.52
	disc.bottom_radius = radius * 0.52
	disc.height = width * 1.08
	disc.radial_segments = 12
	hub.mesh = disc
	hub.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	hub.material_override = _make_material(Color(0.32, 0.33, 0.29), 0.6, 0.4)
	spin.add_child(hub)


func _span(node: Node3D, from: Vector3, to: Vector3, along_x: bool) -> void:
	var delta := to - from
	var length := maxf(delta.length(), 0.001)
	var along := delta / length
	# Опора для второй оси: любая, лишь бы не сонаправленная с `along`.
	var side := Vector3.UP if absf(along.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var basis: Basis
	var scale: Vector3
	if along_x:
		var out := along.cross(side).normalized()
		basis = Basis(along, out.cross(along).normalized(), out)
		scale = Vector3(length, 1.0, 1.0)
	else:
		var across := side.cross(along).normalized()
		basis = Basis(across, along, across.cross(along).normalized())
		scale = Vector3(1.0, length, 1.0)
	node.transform = Transform3D(basis.scaled_local(scale), (from + to) * 0.5)
