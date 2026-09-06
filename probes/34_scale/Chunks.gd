extends RefCounted
class_name ScaleChunks


## СХЕМА А — ЧАНКИ. Мир нарезан на независимые квадраты. Каждый живёт сам по себе: свой
## меш, своя форма коллизии, свой уровень детализации. Игрок двигается — дальние умирают,
## ближние рождаются.
##
## Сильная сторона: **это настоящая геометрия**. Значит бесплатно есть коллизия, лучи,
## навмеш, всё, что умеет физика. Ставь на неё что угодно.
##
## Слабая: цена платится РЫВКАМИ. Пересёк границу — надо построить новый кусок прямо
## сейчас. Чем быстрее едешь, тем больше кусков в секунду, и на скорости лыжника это уже
## десятки миллисекунд в самый неподходящий момент.

var chunk_size := 48.0
var res := 24
var radius := 6
var budget := 2            ## сколько чанков строим за кадр, чтобы не рвать его целиком
## ПРЕДЕЛ ЧИСЛА КУСКОВ. У чанков площадь растёт как квадрат дальности: удвоил радиус —
## учетверил число узлов, мешей и форм. На четырёх километрах это десятки тысяч узлов, и
## приложение умрёт раньше, чем ты успеешь посмотреть на счётчик кадров. Упёрлись в предел —
## очередь просто перестаёт разбираться, и это видно строкой «в очереди».
var max_pieces := 2600
var skirt_depth := 2.0

var use_lod := true
var use_seams := true
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
var _live := {}            # Vector2i -> {"body","mi","cs","at","lod"}
var _origin := Vector3.ZERO
var _last_here := Vector2i(1 << 30, 1 << 30)
var _last_coll := Vector2i(1 << 30, 1 << 30)
var _dirty := true
var _missing: Array = []
var _relod: Array = []


func setup(src: ScaleSource, root: Node3D, mat: Material) -> void:
	_src = src
	_root = root
	_mat = mat


func clear() -> void:
	for k in _live:
		_live[k]["body"].queue_free()
	_live.clear()
	_missing.clear()
	_relod.clear()
	_last_here = Vector2i(1 << 30, 1 << 30)
	_last_coll = Vector2i(1 << 30, 1 << 30)
	queued = 0
	_dirty = true
	tris = 0
	pieces = 0
	solid = 0


## СДВИГ НАЧАЛА КООРДИНАТ. Узлы едут, мировые координаты чанков не трогаем — высота
## по-прежнему спрашивается в мировых. Именно это разделение и делает плавающее начало
## дешёвым: сдвигается только то, что рисуется.
func shift(by: Vector3) -> void:
	_origin += by
	for k in _live:
		_live[k]["body"].position = _live[k]["at"] - _origin


func update(eye_world: Vector3, _delta: float) -> void:
	var here := Vector2i(int(floor(eye_world.x / chunk_size)), int(floor(eye_world.z / chunk_size)))
	# ПЕРЕСЧЁТ ТОЛЬКО ПРИ ПЕРЕСЕЧЕНИИ ГРАНИЦЫ. Первая версия каждый кадр собирала множество
	# нужных чанков заново — это (2r+1)² операций — и дважды обходила всех живых. При радиусе
	# 34 обслуживание доходило до 20 мс на кадр, и FPS падал с 386 до 44 при том, что GPU всё
	# это время оставался на 0.7 мс.
	#
	# Замер тогда обвинял бы СХЕМУ в том, что виновата была моя бухгалтерия. Внутри своей
	# клетки игрок не может изменить ни набор нужных чанков, ни их уровни: и то и другое
	# считается от центров клеток. Значит и считать это надо на пересечении границы.
	if here != _last_here:
		_last_here = here
		_dirty = true
		_rescan(here, eye_world)
	if queued > 0 or not _relod.is_empty():
		_fill(eye_world)
	_collide(eye_world)
	if _dirty:
		_count()
		_dirty = false


func _rescan(here: Vector2i, eye_world: Vector3) -> void:
	# что должно жить
	var want := {}
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var k := here + Vector2i(dx, dz)
			if Vector2(dx, dz).length() <= radius:
				want[k] = true
	# лишнее — под нож
	for k in _live.keys():
		if not want.has(k):
			_live[k]["body"].queue_free()
			_live.erase(k)
	_missing.clear()
	queued = 0
	for k in want:
		if not _live.has(k):
			queued += 1
			_missing.append(k)
	var ex := eye_world.x
	var ez := eye_world.z
	# ОТ БЛИЖНЕГО К ДАЛЬНЕМУ. Первая версия рождала чанки в порядке обхода сетки. Пока
	# радиус мал, разницы нет — очередь разбирается за пару кадров. На большом радиусе
	# бюджет перестаёт успевать, и мир заполняется ПОЛОСОЙ: под ногами дыра, а сбоку
	# готовая земля.
	_missing.sort_custom(func(p: Vector2i, q: Vector2i) -> bool:
		return (Vector2(p.x * chunk_size - ex, p.y * chunk_size - ez).length_squared()
			< Vector2(q.x * chunk_size - ex, q.y * chunk_size - ez).length_squared()))
	# смена уровня детализации — тоже только здесь
	for k in _live.keys():
		var t: Dictionary = _live[k]
		var lod := _lod_for(t["at"], eye_world)
		if lod != t["lod"]:
			t["lod"] = lod
			_relod.append(k)


## Разбор очереди по бюджету за кадр — единственное, что делается каждый кадр.
func _fill(eye_world: Vector3) -> void:
	var t0 := Time.get_ticks_usec()
	var made := 0
	while made < budget and not _missing.is_empty() and _live.size() < max_pieces:
		_spawn(_missing.pop_front())
		made += 1
		queued -= 1
	while made < budget and not _relod.is_empty():
		var k: Vector2i = _relod.pop_front()
		if _live.has(k):
			_mesh(_live[k])
			made += 1
	if made > 0:
		ms_rebuild = (Time.get_ticks_usec() - t0) / 1000.0
		rebuilds += made
		_dirty = true

func _lod_for(at: Vector3, eye: Vector3) -> int:
	if not use_lod:
		return 0
	var d := Vector2(at.x - eye.x, at.z - eye.z).length()
	if d > chunk_size * 4.0:
		return 2
	if d > chunk_size * 2.0:
		return 1
	return 0


func _spawn(k: Vector2i) -> void:
	var at := Vector3(k.x * chunk_size, 0.0, k.y * chunk_size)
	var body := StaticBody3D.new()
	body.position = at - _origin
	var mi := MeshInstance3D.new()
	mi.material_override = _mat
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	body.add_child(cs)
	_root.add_child(body)
	var t := {"body": body, "mi": mi, "cs": cs, "at": at, "lod": 0}
	_live[k] = t
	t["lod"] = _lod_for(at, Vector3.ZERO) if false else 0
	_mesh(t)


func _mesh(t: Dictionary) -> void:
	var step := 1 << int(t["lod"])
	var n := maxi(res / step, 2)
	var cell := chunk_size / float(n)
	var at: Vector3 = t["at"]
	var side := n + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in side:
		for i in side:
			var lx := i * cell
			var lz := j * cell
			verts.append(Vector3(lx, _src.height(at.x + lx, at.z + lz), lz))
			norms.append(_src.normal(at.x + lx, at.z + lz))
	for j in n:
		for i in n:
			var a := j * side + i
			idx.append_array([a, a + 1, a + side, a + 1, a + side + 1, a + side])
	if use_seams:
		# ЮБКА. Соседи с разным уровнем берут высоту в разных точках, и на общей границе
		# между ними видно небо. Бортик вниз закрывает щель одним рядом треугольников.
		_skirt(verts, norms, idx, side, n, 0, 1, 1, Vector3(0, 0, -1))
		_skirt(verts, norms, idx, side, n, n * side, 1, 0, Vector3(0, 0, 1))
		_skirt(verts, norms, idx, side, n, 0, side, 0, Vector3(-1, 0, 0))
		_skirt(verts, norms, idx, side, n, n, side, 1, Vector3(1, 0, 0))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	t["mi"].mesh = m


## НОРМАЛЬ ЮБКИ — НАРУЖУ И ВНИЗ, а не копия верхней. Копия делает вертикальную стенку
## освещённой как горизонтальная площадка: юбка ловит свет и читается СВЕТЛОЙ ПОЛОСОЙ вдоль
## границы чанка — ровно тот шов, который видит игрок. Правильно освещённая стенка уходит
## в тень и в щель, которую закрывает.
func _skirt(verts: PackedVector3Array, norms: PackedVector3Array, idx: PackedInt32Array,
		side: int, n: int, start: int, stride: int, flip: int, out: Vector3) -> void:
	var first := verts.size()
	var wall := (out + Vector3.DOWN * 0.6).normalized()
	for k in side:
		var v: Vector3 = verts[start + k * stride]
		verts.append(Vector3(v.x, v.y - skirt_depth, v.z))
		norms.append(wall)
	for k in n:
		var a := start + k * stride
		var b := start + (k + 1) * stride
		var la := first + k
		var lb := first + k + 1
		if flip == 0:
			idx.append_array([a, la, b, b, la, lb])
		else:
			idx.append_array([a, b, la, b, lb, la])


## КОЛЛИЗИЯ ТОЛЬКО ВБЛИЗИ И ТОЛЬКО НА НУЛЕВОМ УРОВНЕ. Форма строится по той же функции
## высоты, что и меш, — иначе физика разойдётся с картинкой молча.
func _collide(eye: Vector3) -> void:
	var cell := Vector2i(int(floor(eye.x / 16.0)), int(floor(eye.z / 16.0)))
	if cell == _last_coll:
		return
	_last_coll = cell
	solid = 0
	for k in _live:
		var t: Dictionary = _live[k]
		var at: Vector3 = t["at"]
		var d := Vector2(at.x - eye.x, at.z - eye.z).length()
		var want := use_collision and d < chunk_size * 1.6
		if want and t["cs"].shape == null:
			t["cs"].shape = _shape(at)
			t["cs"].scale = Vector3.ONE * (chunk_size / float(res))
			t["cs"].position = Vector3(chunk_size * 0.5, 0.0, chunk_size * 0.5)
		elif not want and t["cs"].shape != null:
			t["cs"].shape = null
		if t["cs"].shape != null:
			solid += 1


func _shape(at: Vector3) -> HeightMapShape3D:
	var side := res + 1
	var cell := chunk_size / float(res)
	var data := PackedFloat32Array()
	data.resize(side * side)
	for j in side:
		for i in side:
			data[j * side + i] = _src.height(at.x + i * cell, at.z + j * cell) / cell
	var s := HeightMapShape3D.new()
	s.map_width = side
	s.map_depth = side
	s.map_data = data
	return s


## Радиус видимой земли — чтобы сравнение шло при РАВНОМ ОХВАТЕ, а не «у кого меньше
## треугольников». Без этой строки клипмап выигрывал бы просто потому, что видит дальше.
func coverage() -> float:
	return radius * chunk_size


func _count() -> void:
	pieces = _live.size()
	tris = 0
	for k in _live:
		var m: ArrayMesh = _live[k]["mi"].mesh
		if m != null and m.get_surface_count() > 0:
			tris += m.surface_get_array_index_len(0) / 3
