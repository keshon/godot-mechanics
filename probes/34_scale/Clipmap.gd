extends RefCounted
class_name ScaleClipmap


## СХЕМА Б — КЛИПМАП. Не куски мира, а кольца вокруг игрока. Уровень 0 — плотная сетка под
## ногами; каждый следующий вдвое крупнее и охватывает вчетверо большую площадь, но
## треугольников в нём столько же. Пять уровней — и полтора километра видимости при
## постоянном числе вершин.
##
## Главное отличие от чанков — в том, ЧТО меняется при движении. Чанки рождаются и умирают:
## пересёк границу, изволь построить кусок целиком. Кольца никуда не деваются, они просто
## СДВИГАЮТСЯ. И сдвигаются с разной частотой: нулевой уровень при каждом шаге, четвёртый —
## раз в полсотни метров. Дальняя география почти не пересчитывается, и это не оптимизация,
## а следствие устройства.
##
## Обязательное условие — ПРИВЯЗКА К СЕТКЕ УРОВНЯ. Центр кольца округляется к кратному его
## собственному шагу. Без этого вершины непрерывно ползут по рельефу, высота в них меняется
## каждый кадр, и весь мир мелко дрожит — эффект известный как swimming.
##
## Расплата: **геометрии для физики нет**. Кольца перестраиваются, у них нет постоянной
## формы, и вешать на них коллизию бессмысленно. Её приходится строить отдельным куском под
## игроком — ровно то, что в настоящих движках называют «физическое представление рельефа»
## и держат независимо от графического.

var levels := 5
var cells := 32            ## ячеек по стороне на каждом уровне
var cell0 := 3.0           ## шаг нулевого уровня, метры
## Колец за кадр. Кольцо целиком — тысяча вершин с высотой и нормалью; когда несколько
## уровней защёлкиваются одновременно, без бюджета выходит рывок на 34 мс. Замерено.
var budget := 1

var use_lod := true
var use_collision := true

var tris := 0
var pieces := 0
var solid := 0
var rebuilds := 0
var ms_rebuild := 0.0
var queued := 0

var _src: ScaleSource
var _root: Node3D
var _mat: Material
var _rings: Array[MeshInstance3D] = []
var _centres: Array[Vector2] = []
var _body: StaticBody3D
var _cs: CollisionShape3D
var _phys_at := Vector2(1e9, 1e9)
var _origin := Vector3.ZERO


func setup(src: ScaleSource, root: Node3D, mat: Material) -> void:
	_src = src
	_root = root
	_mat = mat


func clear() -> void:
	for r in _rings:
		r.queue_free()
	_rings.clear()
	_centres.clear()
	if _body != null:
		_body.queue_free()
		_body = null
	_phys_at = Vector2(1e9, 1e9)
	tris = 0
	pieces = 0
	solid = 0


func shift(by: Vector3) -> void:
	_origin += by
	for i in _rings.size():
		_rings[i].position = Vector3(_centres[i].x, 0.0, _centres[i].y) - _origin
	if _body != null:
		_body.position -= by


func update(eye_world: Vector3, _delta: float) -> void:
	if _rings.is_empty():
		_build_rings()
	var made := 0
	var t0 := Time.get_ticks_usec()
	queued = 0
	for l in _rings.size():
		var step := cell0 * pow(2.0, l)
		# ПРИВЯЗКА: центр кратен удвоенному шагу уровня. Удвоенному — потому что кольцо
		# состоит из пар ячеек, и сдвиг на одну ячейку переставил бы чётность сетки.
		var snap := step * 2.0
		var c := Vector2(round(eye_world.x / snap) * snap, round(eye_world.z / snap) * snap)
		if c.is_equal_approx(_centres[l]):
			continue
		queued += 1
		# Изнутри наружу: ближнее кольцо обязано быть верным сейчас, дальнее может опоздать
		# на кадр — там шаг вчетверо крупнее, и опоздание физически незаметно.
		if made >= budget:
			continue
		_centres[l] = c
		_mesh_ring(l)
		_rings[l].position = Vector3(c.x, 0.0, c.y) - _origin
		made += 1
	if made > 0:
		ms_rebuild = (Time.get_ticks_usec() - t0) / 1000.0
		rebuilds += made
	_collide(eye_world)
	_count()


func coverage() -> float:
	var n := _rings.size() if not _rings.is_empty() else levels
	return cells * cell0 * pow(2.0, n - 1) * 0.5


func _build_rings() -> void:
	var n := levels if use_lod else 1
	for l in n:
		var mi := MeshInstance3D.new()
		mi.material_override = _mat
		_root.add_child(mi)
		_rings.append(mi)
		_centres.append(Vector2(1e9, 1e9))


## Вершины строятся ОТНОСИТЕЛЬНО ЦЕНТРА КОЛЬЦА, а не в мировых координатах. Числа внутри
## меша остаются маленькими независимо от того, куда игрок ушёл, — большое число живёт
## только в трансформе узла. Точности это не спасает (трансформ тоже 32-битный), но
## по крайней мере не удваивает потерю.
func _mesh_ring(l: int) -> void:
	var step := cell0 * pow(2.0, l)
	var half := cells * step * 0.5
	var c := _centres[l]
	var side := cells + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	# ПРОСАДКА ГРУБЫХ КОЛЕЦ. Перекрытие в клетку закрыло щели, но принесло своё: в полосе
	# нахлёста две сетки рисуют одно место на почти одинаковой глубине, и тест глубины
	# выбирает победителя случайно от кадра к кадру — мерцающие полосы. Опускаю каждое
	# следующее кольцо на десятую долю его собственного шага: мелкое всегда выигрывает,
	# мерцание исчезает, а сама просадка на тех расстояниях, где кольцо видно, незаметна.
	var sink := -0.1 * step * float(mini(l, 1))
	for j in side:
		for i in side:
			var lx := -half + i * step
			var lz := -half + j * step
			verts.append(Vector3(lx, _src.height(c.x + lx, c.y + lz) + sink, lz))
			norms.append(_src.normal(c.x + lx, c.y + lz))
	# ДЫРКА В СЕРЕДИНЕ у всех уровней кроме нулевого: там уже лежит уровень мельче. Без неё
	# каждое кольцо рисовало бы всю площадь, и вместо экономии вышел бы пятикратный
	# перерасход — ровно наоборот замыслу.
	#
	# ПЕРЕКРЫТИЕ В ОДНУ ЯЧЕЙКУ обязательно, и вот почему. Дырка ровно по охвату внутреннего
	# уровня выглядит правильной на бумаге, но центры колец привязаны к РАЗНЫМ сеткам:
	# внутреннее округляется к своему шагу, внешнее к своему, вдвое крупнее. Смещение между
	# ними доходит до шага внешнего уровня — и ровно на эту величину внутреннее кольцо не
	# достаёт до края дырки. В картинке это тонкие светлые прорехи, сквозь которые видно небо.
	#
	# По-взрослому это решают отдельной Г-образной вставкой (в литературе её называют trim),
	# которая съедает полуклеточное смещение. Перекрытие на клетку — её дешёвая замена: та же
	# щель закрыта, ценой полосы, где обе сетки рисуют одно и то же место.
	var q := cells / 4 + 1
	for j in cells:
		for i in cells:
			if l > 0 and i >= q and i < cells - q and j >= q and j < cells - q:
				continue
			var a := j * side + i
			idx.append_array([a, a + 1, a + side, a + 1, a + side + 1, a + side])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_rings[l].mesh = m


## ФИЗИКА ОТДЕЛЬНО. У колец нет постоянной геометрии, поэтому под игроком держится один
## самостоятельный кусок формы высот — он не участвует в отрисовке вообще. Так и устроены
## взрослые движки: графическое представление рельефа и физическое живут порознь.
func _collide(eye: Vector3) -> void:
	solid = 0
	if not use_collision:
		if _body != null:
			_cs.shape = null
		return
	if _body == null:
		_body = StaticBody3D.new()
		_cs = CollisionShape3D.new()
		_body.add_child(_cs)
		_root.add_child(_body)
	var span := 64.0
	var cell := 2.0
	var n := int(span / cell)
	var c := Vector2(round(eye.x / span) * span, round(eye.z / span) * span)
	if not c.is_equal_approx(_phys_at):
		_phys_at = c
		var side := n + 1
		var data := PackedFloat32Array()
		data.resize(side * side)
		for j in side:
			for i in side:
				var wx := c.x - span * 0.5 + i * cell
				var wz := c.y - span * 0.5 + j * cell
				data[j * side + i] = _src.height(wx, wz) / cell
		var s := HeightMapShape3D.new()
		s.map_width = side
		s.map_depth = side
		s.map_data = data
		_cs.shape = s
		_cs.scale = Vector3.ONE * cell
		_body.position = Vector3(c.x, 0.0, c.y) - _origin
	solid = 1


func _count() -> void:
	pieces = _rings.size() + (1 if solid > 0 else 0)
	tris = 0
	for r in _rings:
		var m: ArrayMesh = r.mesh
		if m != null and m.get_surface_count() > 0:
			tris += m.surface_get_array_index_len(0) / 3
