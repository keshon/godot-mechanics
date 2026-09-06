@abstract
extends RefCounted
class_name VoroShatter
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

## Ячейки тоньше этого не имеют смысла: их не видно, а тело они занимают полноценное.
const MIN_VOLUME := 0.0004


## Зёрна внутри коробки. `focus` — точка удара; чем больше `bias`, тем гуще зёрна возле неё.
##
## СГУЩЕНИЕ ВОЗЛЕ УДАРА — не украшение, а способ уложиться в бюджет тел. Мелкие осколки нужны
## там, куда попали; остальной предмет может расколоться на две-три крупные части. Так делают
## все, кто дробит в реальном времени.
static func seeds(size: Vector3, count: int, focus: Vector3, bias: float,
		rng: RandomNumberGenerator) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in count:
		var p := Vector3(rng.randf() - 0.5, rng.randf() - 0.5, rng.randf() - 0.5) * size
		if bias > 0.0:
			# Тянем зерно к точке удара тем сильнее, чем ближе оно к ней оказалось.
			var t: float = pow(rng.randf(), 1.0 + bias * 3.0)
			p = p.lerp(focus, t * clampf(bias, 0.0, 1.0))
		out.append(p)
	return out


## Одна ячейка: полупространства между своим зерном и чужими, плюс грани самой коробки.
##
## ТОЛЬКО БЛИЖАЙШИЕ СОСЕДИ. Резать каждую ячейку плоскостями от всех зёрен — честно, но
## квадратично: 128 ячеек считались 1.37 с. Ячейку Вороного ограничивают только соседи
## поблизости, далёкое зерно даёт плоскость, которая её и не касается. Отбор ближайших
## `NEIGHBOURS` — приближение, и проба обязана проверить его тем же объёмом: недорезанная
## ячейка вылезет за оригинал и сумма перевалит за сто процентов.
const NEIGHBOURS := 48

static func cell_planes(size: Vector3, seeds_all: PackedVector3Array, index: int,
		neighbours := NEIGHBOURS) -> Array[Plane]:
	var planes: Array[Plane] = []
	var h := size * 0.5
	planes.append(Plane(Vector3.RIGHT, h.x))
	planes.append(Plane(Vector3.LEFT, h.x))
	planes.append(Plane(Vector3.UP, h.y))
	planes.append(Plane(Vector3.DOWN, h.y))
	planes.append(Plane(Vector3.BACK, h.z))
	planes.append(Plane(Vector3.FORWARD, h.z))
	var me := seeds_all[index]

	var near: Array[int] = []
	for j in seeds_all.size():
		if j != index:
			near.append(j)
	if near.size() > neighbours:
		near.sort_custom(func(a: int, b: int) -> bool:
			return me.distance_squared_to(seeds_all[a]) 				< me.distance_squared_to(seeds_all[b]))
		near.resize(neighbours)

	for j in near:
		var other := seeds_all[j]
		var dir := other - me
		var d := dir.length()
		if d < 0.0001:
			continue
		dir /= d
		# Серединный перпендикуляр: всё, что ближе к «моему» зерну, остаётся внутри.
		planes.append(Plane(dir, (me + other).dot(dir) * 0.5))
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
static func cell(size: Vector3, seeds_all: PackedVector3Array, index: int,
		neighbours := NEIGHBOURS) -> Dictionary:
	var planes := cell_planes(size, seeds_all, index, neighbours)
	var points := Geometry3D.compute_convex_mesh_points(planes)
	if points.size() < 4:
		return {}

	var centre := Vector3.ZERO
	for p in points:
		centre += p
	centre /= points.size()

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var seen := {}
	for pl in planes:
		var on: Array[int] = []
		for i in points.size():
			if absf(pl.distance_to(points[i])) < 0.0005:
				on.append(i)
		if on.size() < 3:
			# Плоскость лишняя: соседнее зерно слишком далеко, чтобы срезать эту ячейку.
			continue
		# Две почти совпавшие плоскости дали бы одну грань дважды. Ключ — сам набор точек.
		on.sort()
		var key := str(on)
		if seen.has(key):
			continue
		seen[key] = true

		var mid := Vector3.ZERO
		for i in on:
			mid += points[i]
		mid /= on.size()
		var ax := (points[on[0]] - mid).normalized()
		var ay := pl.normal.cross(ax)
		# По часовой стрелке, если смотреть снаружи: у Godot это лицевая сторона.
		on.sort_custom(func(a: int, b: int) -> bool:
			var da := points[a] - mid
			var db := points[b] - mid
			return atan2(da.dot(ay), da.dot(ax)) > atan2(db.dot(ay), db.dot(ax)))
		for t in range(1, on.size() - 1):
			var a := points[on[0]] - centre
			var b := points[on[t]] - centre
			var c := points[on[t + 1]] - centre
			# Намотку закрепляем ПО НОРМАЛИ, а не по порядку сортировки. Сортировка по углу
			# срывалась примерно на одном треугольнике из семисот — там, где две вершины грани
			# почти совпали, — и такой треугольник выпадал чёрной прорехой.
			if (b - a).cross(c - a).dot(pl.normal) > 0.0:
				var swap := b
				b = c
				c = swap
			verts.append(a)
			verts.append(b)
			verts.append(c)
			for _u in 3:
				norms.append(pl.normal)
	if verts.size() < 3:
		return {}

	# Объём — сумма тетраэдров «центр + грань». Он же приёмка: сумма по ячейкам обязана
	# сойтись с объёмом исходной коробки.
	var vol := 0.0
	for i in range(0, verts.size(), 3):
		vol += absf(verts[i].dot(verts[i + 1].cross(verts[i + 2]))) / 6.0

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var local := PackedVector3Array()
	for p in points:
		local.append(p - centre)
	return {"centre": centre, "points": local, "mesh": mesh, "volume": vol}
