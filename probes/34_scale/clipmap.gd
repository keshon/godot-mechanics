class_name ScaleClipmap
extends ScaleTerrain
## СХЕМА Б — КЛИПМАП. Не куски мира, а кольца вокруг игрока. Уровень 0 — плотная сетка
## под ногами; каждый следующий вдвое крупнее и охватывает вчетверо большую площадь, но
## треугольников в нём столько же. Пять уровней — и полтора километра видимости при
## постоянном числе вершин.
##
## Главное отличие от чанков — в том, ЧТО меняется при движении. Чанки рождаются и
## умирают: пересёк границу, изволь построить кусок целиком. Кольца никуда не деваются,
## они просто СДВИГАЮТСЯ. И сдвигаются с разной частотой: нулевой уровень при каждом
## шаге, четвёртый — раз в полсотни метров. Дальняя география почти не пересчитывается, и
## это не оптимизация, а следствие устройства.
##
## Обязательное условие — ПРИВЯЗКА К СЕТКЕ УРОВНЯ. Центр кольца округляется к кратному
## его собственному шагу. Без этого вершины непрерывно ползут по рельефу, высота в них
## меняется каждый кадр, и весь мир мелко дрожит — эффект известный как swimming.
##
## Расплата: **геометрии для физики нет**. Кольца перестраиваются, у них нет постоянной
## формы, и вешать на них коллизию бессмысленно. Её приходится строить отдельным куском
## под игроком — ровно то, что в настоящих движках называют «физическое представление
## рельефа» и держат независимо от графического.

var levels := 5
## Ячеек по стороне на каждом уровне.
var cells := 32
## Шаг нулевого уровня, метры.
var cell0 := 3.0
## Колец за кадр. Кольцо целиком — тысяча вершин с высотой и нормалью; когда несколько
## уровней защёлкиваются одновременно, без бюджета выходит рывок на 34 мс. Замерено.
var budget := 1

var _source: ScaleSource
var _root: Node3D
var _material: Material
var _rings: Array[MeshInstance3D] = []
var _centres: Array[Vector2] = []
var _body: StaticBody3D
var _collider: CollisionShape3D
var _physics_at := Vector2(1e9, 1e9)
var _origin := Vector3.ZERO


func setup(source: ScaleSource, root: Node3D, material: Material) -> void:
	_source = source
	_root = root
	_material = material


func clear() -> void:
	for ring in _rings:
		ring.queue_free()
	_rings.clear()
	_centres.clear()
	if _body != null:
		_body.queue_free()
		_body = null
	_physics_at = Vector2(1e9, 1e9)
	tris = 0
	pieces = 0
	solid = 0


func shift(by: Vector3) -> void:
	_origin += by
	for i in _rings.size():
		_rings[i].position = Vector3(_centres[i].x, 0.0, _centres[i].y) - _origin
	if _body != null:
		_body.position -= by


func update(eye_world: Vector3) -> void:
	if _rings.is_empty():
		_build_rings()
	var made := 0
	var started := Time.get_ticks_usec()
	queued = 0
	for level in _rings.size():
		var step := cell0 * pow(2.0, level)
		# ПРИВЯЗКА: центр кратен удвоенному шагу уровня. Удвоенному — потому что кольцо
		# состоит из пар ячеек, и сдвиг на одну ячейку переставил бы чётность сетки.
		var snap := step * 2.0
		var centre := Vector2(
				round(eye_world.x / snap) * snap, round(eye_world.z / snap) * snap)
		if centre.is_equal_approx(_centres[level]):
			continue
		queued += 1
		# Изнутри наружу: ближнее кольцо обязано быть верным сейчас, дальнее может
		# опоздать на кадр — там шаг вчетверо крупнее, и опоздание физически незаметно.
		if made >= budget:
			continue
		_centres[level] = centre
		_mesh_ring(level)
		_rings[level].position = Vector3(centre.x, 0.0, centre.y) - _origin
		made += 1
	if made > 0:
		rebuild_ms = (Time.get_ticks_usec() - started) / 1000.0
		rebuilds += made
	_collide(eye_world)
	_count()


func coverage() -> float:
	var count := _rings.size() if not _rings.is_empty() else levels
	return cells * cell0 * pow(2.0, count - 1) * 0.5


func _build_rings() -> void:
	for level in (levels if use_lod else 1):
		var ring := MeshInstance3D.new()
		ring.material_override = _material
		_root.add_child(ring)
		_rings.append(ring)
		_centres.append(Vector2(1e9, 1e9))


## Вершины строятся ОТНОСИТЕЛЬНО ЦЕНТРА КОЛЬЦА, а не в мировых координатах. Числа внутри
## меша остаются маленькими независимо от того, куда игрок ушёл, — большое число живёт
## только в трансформе узла. Точности это не спасает (трансформ тоже 32-битный), но
## по крайней мере не удваивает потерю.
func _mesh_ring(level: int) -> void:
	var step := cell0 * pow(2.0, level)
	var half := cells * step * 0.5
	var centre := _centres[level]
	var side := cells + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var index := PackedInt32Array()
	# ПРОСАДКА ГРУБЫХ КОЛЕЦ. Перекрытие в клетку закрыло щели, но принесло своё: в полосе
	# нахлёста две сетки рисуют одно место на почти одинаковой глубине, и тест глубины
	# выбирает победителя случайно от кадра к кадру — мерцающие полосы. Опускаю каждое
	# следующее кольцо на десятую долю его собственного шага: мелкое всегда выигрывает,
	# мерцание исчезает, а сама просадка на тех расстояниях, где кольцо видно, незаметна.
	var sink := -0.1 * step * float(mini(level, 1))
	for row in side:
		for column in side:
			var local_x := -half + column * step
			var local_z := -half + row * step
			verts.append(Vector3(
					local_x,
					_source.height(centre.x + local_x, centre.y + local_z) + sink,
					local_z))
			norms.append(_source.normal(centre.x + local_x, centre.y + local_z))
	# ДЫРКА В СЕРЕДИНЕ у всех уровней кроме нулевого: там уже лежит уровень мельче. Без
	# неё каждое кольцо рисовало бы всю площадь, и вместо экономии вышел бы пятикратный
	# перерасход — ровно наоборот замыслу.
	#
	# ПЕРЕКРЫТИЕ В ОДНУ ЯЧЕЙКУ обязательно, и вот почему. Дырка ровно по охвату
	# внутреннего уровня выглядит правильной на бумаге, но центры колец привязаны к РАЗНЫМ
	# сеткам: внутреннее округляется к своему шагу, внешнее к своему, вдвое крупнее.
	# Смещение между ними доходит до шага внешнего уровня — и ровно на эту величину
	# внутреннее кольцо не достаёт до края дырки. В картинке это тонкие светлые прорехи,
	# сквозь которые видно небо.
	#
	# По-взрослому это решают отдельной Г-образной вставкой (в литературе её называют
	# trim), которая съедает полуклеточное смещение. Перекрытие на клетку — её дешёвая
	# замена: та же щель закрыта, ценой полосы, где обе сетки рисуют одно и то же место.
	var quarter := cells / 4 + 1
	for row in cells:
		for column in cells:
			if (
					level > 0
					and column >= quarter and column < cells - quarter
					and row >= quarter and row < cells - quarter
			):
				continue
			var corner := row * side + column
			index.append_array([
				corner, corner + 1, corner + side,
				corner + 1, corner + side + 1, corner + side,
			])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = index
	var built := ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_rings[level].mesh = built


## ФИЗИКА ОТДЕЛЬНО. У колец нет постоянной геометрии, поэтому под игроком держится один
## самостоятельный кусок формы высот — он не участвует в отрисовке вообще. Так и устроены
## взрослые движки: графическое представление рельефа и физическое живут порознь.
func _collide(eye: Vector3) -> void:
	solid = 0
	if not use_collision:
		if _body != null:
			_collider.shape = null
		return
	if _body == null:
		_body = StaticBody3D.new()
		_collider = CollisionShape3D.new()
		_body.add_child(_collider)
		_root.add_child(_body)
	var span := 64.0
	var cell := 2.0
	var side := int(span / cell) + 1
	var centre := Vector2(round(eye.x / span) * span, round(eye.z / span) * span)
	if not centre.is_equal_approx(_physics_at):
		_physics_at = centre
		var data := PackedFloat32Array()
		data.resize(side * side)
		for row in side:
			for column in side:
				var world_x := centre.x - span * 0.5 + column * cell
				var world_z := centre.y - span * 0.5 + row * cell
				data[row * side + column] = _source.height(world_x, world_z) / cell
		var shape := HeightMapShape3D.new()
		shape.map_width = side
		shape.map_depth = side
		shape.map_data = data
		_collider.shape = shape
		_collider.scale = Vector3.ONE * cell
		_body.position = Vector3(centre.x, 0.0, centre.y) - _origin
	solid = 1


func _count() -> void:
	pieces = _rings.size() + (1 if solid > 0 else 0)
	tris = 0
	for ring in _rings:
		var built: ArrayMesh = ring.mesh
		if built != null and built.get_surface_count() > 0:
			tris += built.surface_get_array_index_len(0) / 3
