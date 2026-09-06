@tool
extends Node3D
class_name TyreWheel
## ОДНО КОЛЕСО — УЗЛОМ СЦЕНЫ.
##
## Проба закрыта и по механике заморожена, но правило устава «сцена собирается в редакторе»
## она нарушала: кузов, форма столкновения и четыре колеса собирались в `_ready()`, и машина
## открывалась пустым узлом. Замораживать надо результат, а не ошибку.
##
## Узлов внутри два, и это не прихоть: внешний рулит (вокруг Y), внутренний катится (вокруг
## X). Одним не обойтись — повороты не переставляются местами, и катящееся колесо начало бы
## уводить руль.
##
## Здесь у колеса, в отличие от соседней пробы, есть СВОЯ УГЛОВАЯ СКОРОСТЬ `omega`. Она и
## делает возможными пробуксовку, блокировку и смысл у дифференциала — всё остальное в этой
## пробе следствия одного этого поля.

@export var front := true
## Ведущее ли колесо. Раскладку переключает `Rig.gd`, но исходное состояние — здесь.
@export var driven := false
@export var radius := 0.33:
	set(v):
		radius = v
		_rebuild()
@export var width := 0.22:
	set(v):
		width = v
		_rebuild()

## Точка крепления в осях кузова — берётся из положения узла при запуске.
var attach := Vector3.ZERO
var travel := 0.0
var load := 0.0
var grounded := false
var hit := Vector3.ZERO
var normal := Vector3.UP

## Собственная угловая скорость, рад/с. Ради неё всё и затевалось.
var omega := 0.0
var kappa := 0.0
var alpha := 0.0
var lag := Vector2.ZERO
var fx := 0.0
var fy := 0.0
var use := 0.0
var torque := 0.0

var spin: Node3D

var _rubber: StandardMaterial3D


func _ready() -> void:
	attach = position
	_rebuild()


## Резина и яркая спица. Спица не украшение: гладкое колесо на скорости неотличимо от
## стоящего, а вся проба про то, крутится оно быстрее машины или медленнее.
func _rebuild() -> void:
	if not is_inside_tree():
		return
	if spin != null:
		spin.queue_free()
	spin = Node3D.new()
	add_child(spin)

	_rubber = StandardMaterial3D.new()
	_rubber.albedo_color = Color(0.07, 0.07, 0.08)
	_rubber.roughness = 0.95
	var tyre := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = width
	cyl.radial_segments = 18
	tyre.mesh = cyl
	tyre.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	tyre.material_override = _rubber
	spin.add_child(tyre)

	var mark := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width * 1.1, radius * 1.55, 0.07)
	mark.mesh = bm
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.95, 0.85, 0.20)
	mark.material_override = paint
	spin.add_child(mark)


## Колесо на пределе сцепления краснеет.
func tint_by_grip() -> void:
	if _rubber == null:
		return
	_rubber.albedo_color = Color(0.07, 0.07, 0.08).lerp(Color(0.95, 0.15, 0.05),
		smoothstep(0.7, 1.0, use))
