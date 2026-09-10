class_name ScaleChunks
extends ScaleTerrain
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
var resolution := 24
var radius := 6
## Сколько чанков строим за кадр, чтобы не рвать его целиком.
var budget := 2
## ПРЕДЕЛ ЧИСЛА КУСКОВ. У чанков площадь растёт как квадрат дальности: удвоил радиус —
## учетверил число узлов, мешей и форм. На четырёх километрах это десятки тысяч узлов, и
## приложение умрёт раньше, чем ты успеешь посмотреть на счётчик кадров. Упёрлись в
## предел — очередь просто перестаёт разбираться, и это видно строкой «в очереди».
var max_pieces := 2600
var skirt_depth := 2.0
var use_seams := true

var _source: ScaleSource
var _root: Node3D
var _material: Material
## Vector2i -> {body, mesh, collider, at, lod}.
var _live := {}
var _origin := Vector3.ZERO
var _last_here := Vector2i(1 << 30, 1 << 30)
var _last_collide := Vector2i(1 << 30, 1 << 30)
var _dirty := true
var _missing: Array[Vector2i] = []
var _relod: Array[Vector2i] = []


func setup(source: ScaleSource, root: Node3D, material: Material) -> void:
	_source = source
	_root = root
	_material = material


func clear() -> void:
	for key in _live:
		_live[key]["body"].queue_free()
	_live.clear()
	_missing.clear()
	_relod.clear()
	_last_here = Vector2i(1 << 30, 1 << 30)
	_last_collide = Vector2i(1 << 30, 1 << 30)
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
	for key in _live:
		_live[key]["body"].position = _live[key]["at"] - _origin


func update(eye_world: Vector3) -> void:
	var here := Vector2i(
			int(floor(eye_world.x / chunk_size)), int(floor(eye_world.z / chunk_size)))
	# ПЕРЕСЧЁТ ТОЛЬКО ПРИ ПЕРЕСЕЧЕНИИ ГРАНИЦЫ. Первая версия каждый кадр собирала
	# множество нужных чанков заново — это (2r+1)² операций — и дважды обходила всех
	# живых. При радиусе 34 обслуживание доходило до 20 мс на кадр, и FPS падал с 386 до
	# 44 при том, что GPU всё это время оставался на 0.7 мс.
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


func coverage() -> float:
	return radius * chunk_size


func _rescan(here: Vector2i, eye_world: Vector3) -> void:
	var want := {}
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if Vector2(dx, dz).length() <= radius:
				want[here + Vector2i(dx, dz)] = true
	for key in _live.keys():
		if not want.has(key):
			_live[key]["body"].queue_free()
			_live.erase(key)
	_missing.clear()
	queued = 0
	for key in want:
		if not _live.has(key):
			queued += 1
			_missing.append(key)
	var eye_x := eye_world.x
	var eye_z := eye_world.z
	var size := chunk_size
	# ОТ БЛИЖНЕГО К ДАЛЬНЕМУ. Первая версия рождала чанки в порядке обхода сетки. Пока
	# радиус мал, разницы нет — очередь разбирается за пару кадров. На большом радиусе
	# бюджет перестаёт успевать, и мир заполняется ПОЛОСОЙ: под ногами дыра, а сбоку
	# готовая земля.
	_missing.sort_custom(func(first: Vector2i, second: Vector2i) -> bool:
		var to_first := Vector2(first.x * size - eye_x, first.y * size - eye_z)
		var to_second := Vector2(second.x * size - eye_x, second.y * size - eye_z)
		return to_first.length_squared() < to_second.length_squared())
	# Смена уровня детализации — тоже только здесь.
	for key in _live.keys():
		var tile: Dictionary = _live[key]
		var lod := _lod_for(tile["at"], eye_world)
		if lod != tile["lod"]:
			tile["lod"] = lod
			_relod.append(key)


## Разбор очереди по бюджету за кадр — единственное, что делается каждый кадр.
func _fill(eye_world: Vector3) -> void:
	var started := Time.get_ticks_usec()
	var made := 0
	while made < budget and not _missing.is_empty() and _live.size() < max_pieces:
		_spawn(_missing.pop_front(), eye_world)
		made += 1
		queued -= 1
	while made < budget and not _relod.is_empty():
		var key: Vector2i = _relod.pop_front()
		if _live.has(key):
			_mesh(_live[key])
			made += 1
	if made > 0:
		rebuild_ms = (Time.get_ticks_usec() - started) / 1000.0
		rebuilds += made
		_dirty = true


func _lod_for(at: Vector3, eye: Vector3) -> int:
	if not use_lod:
		return 0
	var away := Vector2(at.x - eye.x, at.z - eye.z).length()
	if away > chunk_size * 4.0:
		return 2
	if away > chunk_size * 2.0:
		return 1
	return 0


func _spawn(key: Vector2i, eye_world: Vector3) -> void:
	var at := Vector3(key.x * chunk_size, 0.0, key.y * chunk_size)
	var body := StaticBody3D.new()
	body.position = at - _origin
	var mesh := MeshInstance3D.new()
	mesh.material_override = _material
	body.add_child(mesh)
	var collider := CollisionShape3D.new()
	body.add_child(collider)
	_root.add_child(body)
	# Уровень выбирается СРАЗУ по расстоянию: чанк, рождённый с нулевым уровнем, получит
	# свой только на следующем пересечении границы, то есть иногда никогда.
	var tile := {
		"body": body,
		"mesh": mesh,
		"collider": collider,
		"at": at,
		"lod": _lod_for(at, eye_world),
	}
	_live[key] = tile
	_mesh(tile)


func _mesh(tile: Dictionary) -> void:
	var step := 1 << int(tile["lod"])
	var cells := maxi(resolution / step, 2)
	var cell := chunk_size / float(cells)
	var at: Vector3 = tile["at"]
	var side := cells + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var index := PackedInt32Array()
	for row in side:
		for column in side:
			var local_x := column * cell
			var local_z := row * cell
			verts.append(Vector3(
					local_x, _source.height(at.x + local_x, at.z + local_z), local_z))
			norms.append(_source.normal(at.x + local_x, at.z + local_z))
	for row in cells:
		for column in cells:
			var corner := row * side + column
			index.append_array([
				corner, corner + 1, corner + side,
				corner + 1, corner + side + 1, corner + side,
			])
	if use_seams:
		# ЮБКА. Соседи с разным уровнем берут высоту в разных точках, и на общей границе
		# между ними видно небо. Бортик вниз закрывает щель одним рядом треугольников.
		_skirt(verts, norms, index, side, cells, 0, 1, 1, Vector3(0, 0, -1))
		_skirt(verts, norms, index, side, cells, cells * side, 1, 0, Vector3(0, 0, 1))
		_skirt(verts, norms, index, side, cells, 0, side, 0, Vector3(-1, 0, 0))
		_skirt(verts, norms, index, side, cells, cells, side, 1, Vector3(1, 0, 0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = index
	var built := ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	tile["mesh"].mesh = built


## НОРМАЛЬ ЮБКИ — НАРУЖУ И ВНИЗ, а не копия верхней. Копия делает вертикальную стенку
## освещённой как горизонтальная площадка: юбка ловит свет и читается СВЕТЛОЙ ПОЛОСОЙ
## вдоль границы чанка — ровно тот шов, который видит игрок. Правильно освещённая стенка
## уходит в тень и в щель, которую закрывает.
func _skirt(
		verts: PackedVector3Array,
		norms: PackedVector3Array,
		index: PackedInt32Array,
		side: int,
		cells: int,
		start: int,
		stride: int,
		flip: int,
		outward: Vector3) -> void:
	var first := verts.size()
	var wall := (outward + Vector3.DOWN * 0.6).normalized()
	for k in side:
		var top: Vector3 = verts[start + k * stride]
		verts.append(Vector3(top.x, top.y - skirt_depth, top.z))
		norms.append(wall)
	for k in cells:
		var near_top := start + k * stride
		var far_top := start + (k + 1) * stride
		var near_low := first + k
		var far_low := first + k + 1
		if flip == 0:
			index.append_array([
				near_top, near_low, far_top, far_top, near_low, far_low])
		else:
			index.append_array([
				near_top, far_top, near_low, far_top, far_low, near_low])


## КОЛЛИЗИЯ ТОЛЬКО ВБЛИЗИ И ТОЛЬКО НА НУЛЕВОМ УРОВНЕ. Форма строится по той же функции
## высоты, что и меш, — иначе физика разойдётся с картинкой молча.
func _collide(eye: Vector3) -> void:
	var cell := Vector2i(int(floor(eye.x / 16.0)), int(floor(eye.z / 16.0)))
	if cell == _last_collide:
		return
	_last_collide = cell
	solid = 0
	for key in _live:
		var tile: Dictionary = _live[key]
		var at: Vector3 = tile["at"]
		var collider: CollisionShape3D = tile["collider"]
		var away := Vector2(at.x - eye.x, at.z - eye.z).length()
		var wanted := use_collision and away < chunk_size * 1.6
		if wanted and collider.shape == null:
			collider.shape = _shape(at)
			collider.scale = Vector3.ONE * (chunk_size / float(resolution))
			collider.position = Vector3(chunk_size * 0.5, 0.0, chunk_size * 0.5)
		elif not wanted and collider.shape != null:
			collider.shape = null
		if collider.shape != null:
			solid += 1


func _shape(at: Vector3) -> HeightMapShape3D:
	var side := resolution + 1
	var cell := chunk_size / float(resolution)
	var data := PackedFloat32Array()
	data.resize(side * side)
	for row in side:
		for column in side:
			data[row * side + column] = _source.height(
					at.x + column * cell, at.z + row * cell) / cell
	var shape := HeightMapShape3D.new()
	shape.map_width = side
	shape.map_depth = side
	shape.map_data = data
	return shape


func _count() -> void:
	pieces = _live.size()
	tris = 0
	for key in _live:
		var mesh: MeshInstance3D = _live[key]["mesh"]
		var built: ArrayMesh = mesh.mesh
		if built != null and built.get_surface_count() > 0:
			tris += built.surface_get_array_index_len(0) / 3
