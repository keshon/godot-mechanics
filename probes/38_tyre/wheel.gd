@tool
class_name TyreWheel
extends Node3D
## ОДНО КОЛЕСО — УЗЛОМ СЦЕНЫ.
##
## Узлов внутри два, и это не прихоть: внешний рулит (вокруг Y), внутренний катится
## (вокруг X). Одним не обойтись — повороты не переставляются местами, и катящееся колесо
## начало бы уводить руль.
##
## Здесь у колеса, в отличие от 37-й, есть СВОЯ УГЛОВАЯ СКОРОСТЬ `omega`. Она и делает
## возможными пробуксовку, блокировку и смысл у дифференциала — всё остальное в этой пробе
## следствия одного этого поля.

@export var front := true
## Ведущее ли колесо. Раскладку переключает `tyre.gd`, но исходное состояние — здесь.
@export var driven := false
@export var radius := 0.33:
	set(value):
		radius = value
		_rebuild()
@export var width := 0.22:
	set(value):
		width = value
		_rebuild()

## Точка крепления в осях кузова — берётся из положения узла при запуске.
var attach := Vector3.ZERO
var travel := 0.0
## Вертикальная нагрузка, ньютоны. НЕ `load`: так зовут встроенную функцию.
var wheel_load := 0.0
var grounded := false
var hit := Vector3.ZERO
var normal := Vector3.UP

## Собственная угловая скорость, рад/с. Ради неё всё и затевалось.
var omega := 0.0
var kappa := 0.0
var alpha := 0.0
## Скольжение, доехавшее до своего значения через релаксацию.
var lag := Vector2.ZERO
var force_along := 0.0
var force_across := 0.0
## Доля израсходованного сцепления, 0…1.
var grip_used := 0.0
var torque := 0.0
var spin: Node3D

var _rubber: StandardMaterial3D


func _ready() -> void:
	attach = position
	_rebuild()


## Колесо на пределе сцепления краснеет.
func tint_by_grip() -> void:
	if _rubber == null:
		return
	_rubber.albedo_color = Color(0.07, 0.07, 0.08).lerp(
			Color(0.95, 0.15, 0.05), smoothstep(0.7, 1.0, grip_used))


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
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = width
	cylinder.radial_segments = 18
	tyre.mesh = cylinder
	tyre.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	tyre.material_override = _rubber
	spin.add_child(tyre)

	var mark := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width * 1.1, radius * 1.55, 0.07)
	mark.mesh = box
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.95, 0.85, 0.20)
	mark.material_override = paint
	spin.add_child(mark)
