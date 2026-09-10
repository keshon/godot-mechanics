class_name VoroSolid
extends RigidBody3D
## ПРЕДМЕТ, КОТОРЫЙ МОЖНО РАСКОЛОТЬ.
##
## По соглашению о сборке предмет не читает ввод и ничего не знает про стрелка: ему сообщают
## воздействие вызовом `hit()`, ровно как мишени в сороковой пробе и элементу в сорок первой.
##
## Разница с сороковой — в том, ВО ЧТО он разваливается. Там куски были случайными коробками
## рядом с предметом; здесь предмет РЕЖЕТСЯ, и куски складываются обратно в него без щелей.
## Отсюда и проверка, которую предмет считает сам: сумма объёмов осколков против своего.
##
## Масса тоже делится по объёму, а не поровну. Мелкая крошка обязана быть лёгкой, иначе куча
## обломков весит как десять предметов и ведёт себя соответственно.

## Осколков за один скол бывают десятки — ровно то, ради чего существуют сцены. Вид и
## физические свойства обломка живут в `shard.tscn`, а не в коде.
const SHARD := preload("res://probes/42_voronoi/shard.tscn")
## Минимальная масса осколка в килограммах: тело легче этого решатель гоняет как пылинку.
const MIN_SHARD_MASS := 0.02

signal shattered(cells: int, kept: float, spent_ms: float)

@export var cells := 24
## Насколько зёрна сбиваются в кучу возле точки удара. Ноль — равномерно по всему предмету.
@export_range(0.0, 1.0) var bias := 0.7
@export var health := 40.0
## Осколки остаются замороженными на своих местах: это показ разреза, а не разрушение.
@export var held := false
## Вид свежего скола. Один ресурс на все осколки предмета, а не свой материал каждому.
@export var shard_look: StandardMaterial3D
@export var scatter_seed := 1

## Размер НЕ ЗАДАЁТСЯ отдельно: он уже описан формой столкновения. Своя копия размера рядом
## с движковой — это второй источник правды, и рано или поздно они разойдутся.
var size := Vector3.ONE
var left := 0.0
var shards: Array[RigidBody3D] = []
var homes := PackedVector3Array()

var _material: StandardMaterial3D
var _base := Color.WHITE
## Тот же урок, что и в сороковой: `queue_free` срабатывает в конце кадра, и до тех пор
## предмет продолжает попадаться под луч. Без флага один предмет колется по нескольку раз.
var _gone := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	left = health
	_rng.seed = scatter_seed
	var collider := get_node("Shape") as CollisionShape3D
	size = (collider.shape as BoxShape3D).size
	var visual := get_node("Mesh") as MeshInstance3D
	_material = visual.material_override as StandardMaterial3D
	if _material != null:
		_base = _material.albedo_color


## Воздействие снаружи. Предмет либо терпит, либо колется — промежуточных состояний нет,
## как и у элемента в сорок первой.
func hit(at: Vector3, direction: Vector3, force: float, hurt: float) -> void:
	if _gone:
		return
	left -= hurt
	# Прочность обязана быть ВИДНА, иначе она неотличима от сломанной ручки: предмет темнеет
	# по мере набора повреждений, и попадания читаются до того, как он расколется.
	if _material != null:
		var wear := 1.0 - clampf(left / maxf(health, 0.001), 0.0, 1.0)
		_material.albedo_color = _base.lerp(Color(0.22, 0.19, 0.17), wear * 0.55)
	if left <= 0.0:
		shatter(at, direction, force)


## СКОЛ. Считает ячейки, ставит на их место тела и уходит.
func shatter(at: Vector3, direction: Vector3, force: float) -> void:
	if _gone:
		return
	_gone = true
	remove_from_group("solid")

	var started := Time.get_ticks_usec()
	var focus := (global_transform.affine_inverse() * at).clamp(size * -0.5, size * 0.5)
	_rng.seed = hash(name)
	var seeds := VoroShatter.scatter_seeds(size, cells, focus, bias, _rng)
	var whole := size.x * size.y * size.z
	var density := mass / whole
	var kept := 0.0

	for index in cells:
		var piece := VoroShatter.cell(size, seeds, index)
		if piece.is_empty() or float(piece["volume"]) < VoroShatter.MIN_VOLUME:
			continue
		kept += float(piece["volume"])
		shards.append(_spawn(piece, density, at, direction, force))
		homes.append(shards[-1].global_position)

	var spent_ms := (Time.get_ticks_usec() - started) / 1000.0
	shattered.emit(shards.size(), kept / whole, spent_ms)
	if not held:
		queue_free()
	else:
		# Показ разреза: сам предмет надо спрятать, но не удалять — риг держит его как
		# хозяина осколков и двигает их наружу.
		var visual := get_node_or_null("Mesh") as MeshInstance3D
		if visual != null:
			visual.visible = false
		collision_layer = 0
		collision_mask = 0


## РАЗВЕСТИ ОСКОЛКИ НАРУЖУ. На нуле они складываются обратно в предмет — это и есть весь
## смысл Вороного, видимый глазом, а не только в числе.
func spread(fraction: float) -> void:
	for index in shards.size():
		var shard := shards[index]
		if not is_instance_valid(shard):
			continue
		var away := homes[index] - global_position
		shard.global_position = homes[index] + away.normalized() * away.length() * fraction


func _spawn(
		piece: Dictionary,
		density: float,
		at: Vector3,
		direction: Vector3,
		force: float) -> RigidBody3D:
	var body := SHARD.instantiate() as RigidBody3D
	body.mass = maxf(float(piece["volume"]) * density, MIN_SHARD_MASS)

	var shape := ConvexPolygonShape3D.new()
	shape.points = piece["points"]
	var collider := body.get_node("Shape") as CollisionShape3D
	collider.shape = shape
	var visual := body.get_node("Mesh") as MeshInstance3D
	visual.mesh = piece["mesh"]
	visual.material_override = shard_look

	# `add_sibling`, а не `get_parent().add_child`: предмет не должен лезть в того, кто его
	# содержит, — ему достаточно знать, что обломок ложится рядом с ним.
	add_sibling(body)
	# Положение — только ПОСЛЕ добавления в дерево: до него у тела нет мировых координат.
	body.global_transform = global_transform.translated_local(piece["centre"])
	if held:
		body.freeze = true
		body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	elif force > 0.0:
		# Разлёт слабеет с удалением от точки попадания: пуля выбивает воронку, а не
		# разбрасывает предмет целиком.
		var away := body.global_position - at
		var apart := away.length()
		var falloff := 1.0 / (1.0 + apart * apart * 4.0)
		body.apply_central_impulse(
				(direction.normalized() * 0.4 + away.normalized() * 0.6) * force * falloff)
	return body
