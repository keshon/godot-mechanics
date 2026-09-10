@abstract
class_name VoroShatter
extends RefCounted
## СКОЛ ПО ЯЧЕЙКАМ ВОРОНОГО.
##
## Сороковая проба била предметы на случайные коробки, и это её главный записанный изъян:
## куски НЕ СКЛАДЫВАЮТСЯ обратно в предмет. Стеклянной панели повезло — тонкие пластины
## похожи на то, чем она была; бочке бы не повезло совсем.
##
## Ячейка Вороного — это множество точек, которые ближе к своему зерну, чем к любому другому.
## Отсюда её главное свойство и весь смысл приёма: **ячейки замощают исходный объём без
## щелей и без нахлёста.** Куски получены разрезанием предмета, а не выдуманы рядом с ним.
##
## Считается это неожиданно просто, и никакой библиотеки не нужно:
##
##   ячейка = исходная выпуклая форма ∩ полупространства между своим зерном и каждым чужим
##
## Плоскость между двумя зёрнами — перпендикуляр к отрезку через его середину. Пересечение
## полупространств всегда выпукло, а выпуклую форму Godot умеет и рисовать, и сталкивать
## бесплатно: `Geometry3D.compute_convex_mesh_points` отдаёт вершины, `ConvexPolygonShape3D`
## принимает их как есть.
##
## Приёмка у пробы числовая и жёсткая: **сумма объёмов ячеек обязана равняться объёму
## оригинала.** Если не сходится — куски либо потеряли материал, либо налезли друг на друга.
##
## Класс помечен `@abstract`: это набор правил, а не вещь. Создавать его нечего и незачем.

## Ячейки тоньше этого, в кубометрах, не имеют смысла: их не видно, а тело они занимают
## полноценное.
const MIN_VOLUME := 0.0004
## ТОЛЬКО БЛИЖАЙШИЕ СОСЕДИ. Резать каждую ячейку плоскостями от всех зёрен — честно, но
## квадратично: 128 ячеек считались 1.37 с. Ячейку Вороного ограничивают только соседи
## поблизости, далёкое зерно даёт плоскость, которая её и не касается. Отбор ближайших —
## приближение, и проба обязана проверить его тем же объёмом: недорезанная ячейка вылезет
## за оригинал и сумма перевалит за сто процентов.
const NEIGHBOURS := 48
## Допуск в метрах, внутри которого вершина считается лежащей на плоскости грани.
const ON_PLANE := 0.0005


## Зёрна внутри коробки. `focus` — точка удара; чем больше `bias`, тем гуще зёрна возле неё.
##
## СГУЩЕНИЕ ВОЗЛЕ УДАРА — не украшение, а способ уложиться в бюджет тел. Мелкие осколки нужны
## там, куда попали; остальной предмет может расколоться на две-три крупные части. Так делают
## все, кто дробит в реальном времени.
static func scatter_seeds(
		size: Vector3,
		count: int,
		focus: Vector3,
		bias: float,
		rng: RandomNumberGenerator) -> PackedVector3Array:
	var out := PackedVector3Array()
	for _index in count:
		var seed_point := Vector3(
				rng.randf() - 0.5, rng.randf() - 0.5, rng.randf() - 0.5) * size
		if bias > 0.0:
			# Тянем зерно к точке удара тем сильнее, чем ближе оно к ней оказалось.
			var pull: float = pow(rng.randf(), 1.0 + bias * 3.0)
			seed_point = seed_point.lerp(focus, pull * clampf(bias, 0.0, 1.0))
		out.append(seed_point)
	return out


## Одна ячейка: полупространства между своим зерном и чужими, плюс грани самой коробки.
static func cell_planes(
		size: Vector3,
		seeds: PackedVector3Array,
		index: int,
		neighbours := NEIGHBOURS) -> Array[Plane]:
	var half := size * 0.5
	var planes: Array[Plane] = [
		Plane(Vector3.RIGHT, half.x),
		Plane(Vector3.LEFT, half.x),
		Plane(Vector3.UP, half.y),
		Plane(Vector3.DOWN, half.y),
		Plane(Vector3.BACK, half.z),
		Plane(Vector3.FORWARD, half.z),
	]
	var mine := seeds[index]

	var near: Array[int] = []
	for other_index in seeds.size():
		if other_index != index:
			near.append(other_index)
	if near.size() > neighbours:
		near.sort_custom(
				func(first: int, second: int) -> bool:
					return (mine.distance_squared_to(seeds[first])
						< mine.distance_squared_to(seeds[second])))
		near.resize(neighbours)

	for other_index in near:
		var other := seeds[other_index]
		var towards := other - mine
		var apart := towards.length()
		if apart < 0.0001:
			continue
		towards /= apart
		# Серединный перпендикуляр: всё, что ближе к «моему» зерну, остаётся внутри.
		planes.append(Plane(towards, (mine + other).dot(towards) * 0.5))
	return planes


## Вершины ячейки. Пусто — значит зерно оказалось накрыто соседями и ячейки нет вовсе.
static func cell_points(planes: Array[Plane]) -> PackedVector3Array:
	return Geometry3D.compute_convex_mesh_points(planes)


## ГОТОВАЯ ЯЧЕЙКА: вершины, меш и объём, всё в системе координат самой ячейки.
##
## Плоскости граней НЕ НАДО ИСКАТЬ — они уже есть, это тот же список, из которого получены
## вершины. Первый заход искал их перебором троек точек: `O(n^3)`, и вдобавок неверно —
## одна и та же грань попадала в список дважды и объём выходил вдвое-втрое больше исходного.
## Куски, которые «больше» предмета, — ровно то, что проба обязана поймать числом.
##
## Пусто — значит зерно накрыто соседями и ячейки нет вовсе.
static func cell(
		size: Vector3,
		seeds: PackedVector3Array,
		index: int,
		neighbours := NEIGHBOURS) -> Dictionary:
	var planes := cell_planes(size, seeds, index, neighbours)
	var points := Geometry3D.compute_convex_mesh_points(planes)
	if points.size() < 4:
		return {}

	var centre := Vector3.ZERO
	for point in points:
		centre += point
	centre /= points.size()

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var seen := {}
	for plane in planes:
		var on_face: Array[int] = []
		for i in points.size():
			if absf(plane.distance_to(points[i])) < ON_PLANE:
				on_face.append(i)
		if on_face.size() < 3:
			# Плоскость лишняя: соседнее зерно слишком далеко, чтобы срезать эту ячейку.
			continue
		# Две почти совпавшие плоскости дали бы одну грань дважды. Ключ — сам набор точек.
		on_face.sort()
		var key := str(on_face)
		if seen.has(key):
			continue
		seen[key] = true
		_add_face(vertices, normals, points, on_face, plane, centre)
	if vertices.size() < 3:
		return {}

	# Объём — сумма тетраэдров «центр + грань». Он же приёмка: сумма по ячейкам обязана
	# сойтись с объёмом исходной коробки.
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
	return {"centre": centre, "points": local, "mesh": mesh, "volume": volume}


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
	# По часовой стрелке, если смотреть снаружи: у Godot это лицевая сторона.
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
		# Намотку закрепляем ПО НОРМАЛИ, а не по порядку сортировки. Сортировка по углу
		# срывалась примерно на одном треугольнике из семисот — там, где две вершины грани
		# почти совпали, — и такой треугольник выпадал чёрной прорехой.
		if (second - first).cross(third - first).dot(plane.normal) > 0.0:
			var swap := second
			second = third
			third = swap
		vertices.append(first)
		vertices.append(second)
		vertices.append(third)
		for _corner in 3:
			normals.append(plane.normal)
