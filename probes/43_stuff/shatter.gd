@abstract
class_name StuffShatter
extends RefCounted
## РЕЗ ПО ЯЧЕЙКАМ ВОРОНОГО — с двумя отличиями от сорок второй пробы.
##
## ПЕРВОЕ: режется произвольная выпуклая форма, заданная списком полупространств, а не
## коробка. Коробка — частный случай, шесть плоскостей. Это и есть условие повторного скола:
## осколок — не коробка, и пока рез умел только коробки, расколоть его было нечем.
##
## ВТОРОЕ: метрика растянута по осям — `grain`. Ячейка Вороного это множество точек, которые
## ближе к своему зерну, чем к чужому; если «ближе» считать по растянутой метрике, ячейки
## вытягиваются вдоль растяжения. Куски по-прежнему замощают предмет без щелей: растянутая
## метрика даёт другую разбивку, а не сломанную.
##
## Отсюда узор ломания одним параметром: (1,1,1) щебень, (5,1,1) щепа, (1,0.2,1) плитняк.

const NEIGHBOURS := 48
## Доля зёрен, садящихся в воронку. Остальные раскладывают материал за её краем.
const IN_CRATER := 0.7
## Допуск в метрах, внутри которого вершина считается лежащей на плоскости грани.
const ON_PLANE := 0.0005


## Коробка как список полупространств.
static func box(size: Vector3) -> Array[Plane]:
	var half := size * 0.5
	return [
		Plane(Vector3.RIGHT, half.x), Plane(Vector3.LEFT, half.x),
		Plane(Vector3.UP, half.y), Plane(Vector3.DOWN, half.y),
		Plane(Vector3.BACK, half.z), Plane(Vector3.FORWARD, half.z),
	] as Array[Plane]


## ЗЁРНА СТАВЯТСЯ ОТ ОЧАГА НАРУЖУ, а не по габариту предмета. Это и есть форма разлома.
##
## Первый заход разбрасывал зёрна равномерно по коробке и потом мягко подтягивал их к точке
## попадания. Получалось «предмет взорвался с уклоном в сторону дырки»: у четырёхметровой
## колонны в тридцати сантиметрах от попадания лежало 3% объёма, а куски улетали на два метра.
##
## Правильнее считать наоборот — от очага: расстояние берётся степенным законом, направление
## равномерно по сфере. Показатель `1/3` даёт равномерную плотность по объёму (это честный
## шар), а чем показатель больше, тем плотнее крошка садится в воронку.
static func spread(
		shape: Array[Plane],
		count: int,
		focus: Vector3,
		crater: float,
		rng: RandomNumberGenerator,
		least := 0.0) -> PackedVector3Array:
	if Geometry3D.compute_convex_mesh_points(shape).size() < 4:
		return PackedVector3Array()
	var out := PackedVector3Array()
	var guard := count * 64
	while out.size() < count and guard > 0:
		guard -= 1
		var away := Vector3(rng.randfn(), rng.randfn(), rng.randfn())
		if away.length_squared() < 1e-9:
			continue
		away = away.normalized()
		# СКОЛЬКО МАТЕРИАЛА В ЭТУ СТОРОНУ — вместо броска наугад с отбраковкой. Отбраковка
		# молча съедала бюджет: заказано 48 ячеек, получено 27. И заодно узор сам ложится по
		# форме предмета: в тонкой панели плоско, в длинной балке вдоль неё.
		var span := _reach(shape, focus, away)
		if span <= 0.0:
			continue
		# ВОРОНКА ЗАДАЁТСЯ КАЛИБРОМ, а не долей предмета. Внутри неё плотность зёрен падает
		# как 1/(1+(r/воронка)²) — крошка у дырки; за краем материал раскладывается ровно и
		# отходит крупными кусками. Безразмерный «уклон к попаданию» давал одинаковую воронку
		# и у пули, и у ракеты.
		var far: float
		if rng.randf() < IN_CRATER:
			far = crater * (pow(maxf(rng.randf(), 1e-6), -1.0 / 3.0) - 1.0)
		else:
			far = span * pow(rng.randf(), 1.0 / 3.0)
		var seed_point := focus + away * minf(far, span)
		# МИНИМАЛЬНЫЙ ШАГ МЕЖДУ ЗЁРНАМИ — по зернистости материала. Без него зёрна сбиваются
		# в кучу у самого очага, ячейки выходят мельче отсечки и ВЫБРАСЫВАЮТСЯ: объём
		# перестаёт сходиться (99.7% вместо 100.00%). Правило то же, что и у повторного скола:
		# мельче своей крошки материал не дробится.
		if least > 0.0 and _crowded(out, seed_point, least):
			continue
		out.append(seed_point)
	return out


## ЗАТОЛКНУТЬ ТОЧКУ ВНУТРЬ ФОРМЫ. Луч возвращает точку попадания РОВНО на поверхности, а
## формально «на грани» — это снаружи: промах в четверть микрона, и очаг скола некуда ставить.
## Двигаем точку от самой нарушенной стены внутрь, пока не окажется под кожей.
static func tuck(shape: Array[Plane], point: Vector3, depth := 0.002) -> Vector3:
	var inside := point
	for _step in 8:
		var worst := -INF
		var guilty := Plane(Vector3.UP, 0.0)
		for wall in shape:
			var outward := wall.distance_to(inside)
			if outward > worst:
				worst = outward
				guilty = wall
		if worst <= -depth:
			return inside
		inside -= guilty.normal * (worst + depth)
	return inside


## Плоскость между двумя зёрнами в растянутой метрике. При `grain = (1,1,1)` это обычный
## серединный перпендикуляр.
static func split(mine: Vector3, other: Vector3, grain: Vector3) -> Plane:
	var squared := grain * grain
	var normal := (other - mine) / squared
	var reach := normal.length()
	if reach < 1e-9:
		return Plane(Vector3.UP, 1e9)
	var offset := (
		(other / grain).length_squared() - (mine / grain).length_squared()) * 0.5 / reach
	return Plane(normal / reach, offset)


## ГОТОВАЯ ЯЧЕЙКА. Кроме вершин, меша и объёма отдаёт СВОИ СТЕНЫ — те плоскости, что дали
## грань. Без них осколок нельзя расколоть ещё раз: он перестал бы быть описанной формой.
static func cell(
		shape: Array[Plane],
		seeds: PackedVector3Array,
		index: int,
		grain := Vector3.ONE,
		neighbours := NEIGHBOURS) -> Dictionary:
	var mine := seeds[index]
	var near: Array[int] = []
	for other_index in seeds.size():
		if other_index != index:
			near.append(other_index)
	if near.size() > neighbours:
		near.sort_custom(
				func(first: int, second: int) -> bool:
					return (((seeds[first] - mine) / grain).length_squared()
						< ((seeds[second] - mine) / grain).length_squared()))
		near.resize(neighbours)

	var planes := shape.duplicate() as Array[Plane]
	for other_index in near:
		planes.append(split(mine, seeds[other_index], grain))

	var points := Geometry3D.compute_convex_mesh_points(planes)
	if points.size() < 4:
		return {}
	var centre := Vector3.ZERO
	for point in points:
		centre += point
	centre /= points.size()

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var walls: Array[Plane] = []
	var seen := {}
	for plane in planes:
		var on_face: Array[int] = []
		for i in points.size():
			if absf(plane.distance_to(points[i])) < ON_PLANE:
				on_face.append(i)
		if on_face.size() < 3:
			continue
		on_face.sort()
		var key := str(on_face)
		if seen.has(key):
			continue
		seen[key] = true
		walls.append(Plane(plane.normal, plane.d - plane.normal.dot(centre)))
		_add_face(vertices, normals, points, on_face, plane, centre)
	if vertices.size() < 3:
		return {}

	var volume := 0.0
	for i in range(0, vertices.size(), 3):
		volume += absf(vertices[i].dot(vertices[i + 1].cross(vertices[i + 2]))) / 6.0

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var local := PackedVector3Array()
	for point in points:
		local.append(point - centre)
	return {
		"centre": centre,
		"points": local,
		"mesh": mesh,
		"volume": volume,
		"walls": walls,
	}


## Докуда от очага в эту сторону есть материал: для выпуклой формы это ближайшее пересечение
## луча с её стенами.
static func _reach(shape: Array[Plane], from: Vector3, away: Vector3) -> float:
	var best := INF
	for wall in shape:
		var facing := wall.normal.dot(away)
		if facing <= 1e-6:
			continue
		var apart := (wall.d - wall.normal.dot(from)) / facing
		if apart >= 0.0:
			best = minf(best, apart)
	return 0.0 if is_inf(best) else best


static func _crowded(placed: PackedVector3Array, point: Vector3, least: float) -> bool:
	for other in placed:
		if other.distance_squared_to(point) < least * least:
			return true
	return false


## Веер треугольников по одной грани, в координатах относительно центра ячейки.
static func _add_face(
		vertices: PackedVector3Array,
		normals: PackedVector3Array,
		points: PackedVector3Array,
		on_face: Array[int],
		plane: Plane,
		centre: Vector3) -> void:
	var middle := Vector3.ZERO
	for i in on_face:
		middle += points[i]
	middle /= on_face.size()
	var axis_x := (points[on_face[0]] - middle).normalized()
	var axis_y := plane.normal.cross(axis_x)
	on_face.sort_custom(
			func(first: int, second: int) -> bool:
				var to_first := points[first] - middle
				var to_second := points[second] - middle
				return (atan2(to_first.dot(axis_y), to_first.dot(axis_x))
					> atan2(to_second.dot(axis_y), to_second.dot(axis_x))))
	for step in range(1, on_face.size() - 1):
		var first := points[on_face[0]] - centre
		var second := points[on_face[step]] - centre
		var third := points[on_face[step + 1]] - centre
		# Намотка закрепляется по нормали грани, а не по порядку сортировки: сортировка
		# срывается примерно на одном треугольнике из семисот, и он выпадает прорехой.
		if (second - first).cross(third - first).dot(plane.normal) > 0.0:
			var swap := second
			second = third
			third = swap
		vertices.append(first)
		vertices.append(second)
		vertices.append(third)
		for _corner in 3:
			normals.append(plane.normal)
