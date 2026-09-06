@tool
extends Node3D
class_name CarWheel
## ОДНО КОЛЕСО — УЗЛОМ СЦЕНЫ.
##
## Так и должно было быть с самого начала. Проба закрыта и по механике заморожена, но правило
## устава «сцена собирается в редакторе» она нарушала прямо: машина открывалась пустым узлом,
## а четыре колеса, кузов и вся площадка строились в `_ready()`. Замораживать надо результат,
## а не ошибку, поэтому это правится.
##
## Что даёт перенос. Положение колеса — ровно то, что хочется таскать мышью: раздвинул колею,
## отодвинул заднюю ось, увидел, как поменялся перенос веса. Признак «ведущее» стал галочкой
## в инспекторе, а не веткой в коде. И главное: открыв сцену, ты ВИДИШЬ машину, а не догадка,
## что она где-то соберётся.
##
## Узлов внутри два, и это не прихоть: внешний рулит (вокруг Y), внутренний катится (вокруг
## X). Одним не обойтись — повороты не переставляются местами, и катящееся колесо начало бы
## уводить руль.

@export var front := true
## Ведущее ли колесо. Раскладку привода переключает `Drive.gd`, но исходное состояние —
## здесь, галочкой, и «переднеприводная машина» становится свойством сцены.
@export var driven := false
@export var radius := 0.55:
	set(v):
		radius = v
		_rebuild()
@export var width := 0.45:
	set(v):
		width = v
		_rebuild()

## РЫЧАГ И ПРУЖИНА — УЗЛЫ СЦЕНЫ, а не создание в коде. Лежат рядом с колесом, а не под
## ним: колесо крутится рулём, рычаг вместе с ним поворачиваться не должен. Их положение
## считается каждый кадр из хода подвески — трогать руками нечего, — но САМИ ДЕТАЛИ
## должны быть видны в редакторе, иначе подвеска существует только в запущенной игре.
## Связывает их `Car.gd` по имени.
var arm: MeshInstance3D
var spring: MeshInstance3D

## Точка крепления в осях кузова — берётся из положения узла в сцене при запуске. Дальше сам
## узел ездит вниз по ходу подвески, а точка остаётся.
var attach := Vector3.ZERO
var travel := 0.0
var load := 0.0
var slip := 0.0
var grounded := false
var hit := Vector3.ZERO
var normal := Vector3.UP
var use := 0.0
var roll := 0.0

var spin: Node3D

var _rubber: Array[StandardMaterial3D] = []


func _ready() -> void:
	attach = position
	_rebuild()


func _mat(tint: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.roughness = rough
	m.metallic = metal
	return m


## Резина, грунтозацепы и диск. Строятся кодом, а не лежат в сцене, и это ровно тот случай,
## который правило разрешает: восемь одинаковых зацепов по кругу — «сколько», а не «где».
func _rebuild() -> void:
	if not is_inside_tree():
		return
	if spin != null:
		spin.queue_free()
	_rubber.clear()
	spin = Node3D.new()
	add_child(spin)

	var rubber := _mat(Color(0.07, 0.07, 0.08))
	_rubber.append(rubber)
	var tyre := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = width
	cyl.radial_segments = 16
	tyre.mesh = cyl
	tyre.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	tyre.material_override = rubber
	spin.add_child(tyre)

	var lug := _mat(Color(0.11, 0.11, 0.12))
	_rubber.append(lug)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var block := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(width * 1.14, 0.09, radius * 0.5)
		block.mesh = bm
		block.position = Vector3(0.0, sin(a) * radius, cos(a) * radius)
		block.rotation.x = -a
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
	hub.material_override = _mat(Color(0.32, 0.33, 0.29), 0.6, 0.4)
	spin.add_child(hub)


## Колесо на пределе сцепления краснеет. Цифру на экране надо читать, а цвет видно боковым
## зрением, не отрываясь от дороги.
func tint_by_grip() -> void:
	var c := Color(0.07, 0.07, 0.08).lerp(Color(0.95, 0.15, 0.05),
		smoothstep(0.55, 1.0, use))
	for m in _rubber:
		m.albedo_color = c


## Натянуть рычаг и пружину между точками. Верхняя опора СМЕЩЕНА вдоль машины, а не
## стоит над осью: иначе пружина оказывается ровно за колесом и её не видно ни сбоку, ни
## в три четверти — то есть деталь, ради которой всё затевалось, невидима. Обе детали единичной длины по своей оси, так что
## вся работа — поворот плюс масштаб; новых мешей не создаётся ни одного.
func place_linkage(pivot: Vector3, hub: Vector3, top: Vector3) -> void:
	_span(arm, pivot, hub, true)
	_span(spring, top, pivot.lerp(hub, 0.82), false)


func _span(node: Node3D, from: Vector3, to: Vector3, along_x: bool) -> void:
	var delta := to - from
	var length := maxf(delta.length(), 0.001)
	var dir := delta / length
	# Опора для второй оси: любая, лишь бы не сонаправленная с `dir`.
	var side := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var b: Basis
	var scale: Vector3
	if along_x:
		var z := dir.cross(side).normalized()
		b = Basis(dir, z.cross(dir).normalized(), z)
		scale = Vector3(length, 1.0, 1.0)
	else:
		var x := side.cross(dir).normalized()
		b = Basis(x, dir, x.cross(dir).normalized())
		scale = Vector3(1.0, length, 1.0)
	node.transform = Transform3D(b.scaled_local(scale), (from + to) * 0.5)
