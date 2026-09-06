@abstract
extends RefCounted
class_name StuffShatter
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


## Коробка как список полупространств.
static func box(size: Vector3) -> Array[Plane]:
	var h := size * 0.5
	return [Plane(Vector3.RIGHT, h.x), Plane(Vector3.LEFT, h.x),
		Plane(Vector3.UP, h.y), Plane(Vector3.DOWN, h.y),
		Plane(Vector3.BACK, h.z), Plane(Vector3.FORWARD, h.z)] as Array[Plane]


## ЗЁРНА СТАВЯТСЯ ОТ ОЧАГА НАРУЖУ, а не по габариту предмета. Это и есть форма разлома.
##
## Первый заход разбрасывал зёрна равномерно по коробке и потом мягко подтягивал их к точке
## попадания. Получалось «предмет взорвался с уклоном в сторону дырки»: у четырёхметровой
## колонны в тридцати сантиметрах от попадания лежало 3% объёма, а куски улетали на два метра.
##
## Правильнее считать наоборот — от очага: расстояние берётся степенным законом, направление
## равномерно по сфере. Показатель `1/3` даёт равномерную плотность по объёму (это честный
## шар), а чем показатель больше, тем плотнее крошка садится в воронку.
static func spread(shape: Array[Plane], count: int, focus: Vector3, crater: float,
		rng: RandomNumberGenerator, least := 0.0) -> PackedVector3Array:
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
		# отходит крупными кусками. Раньше вместо этого был безразмерный «уклон к попаданию»,
		# и воронка у пули и у ракеты выходила одинаковой.
		var r: float
		if rng.randf() < IN_CRATER:
			r = crater * (pow(maxf(rng.randf(), 1e-6), -1.0 / 3.0) - 1.0)
		else:
			r = span * pow(rng.randf(), 1.0 / 3.0)
		var p := focus + away * minf(r, span)
		# МИНИМАЛЬНЫЙ ШАГ МЕЖДУ ЗЁРНАМИ — по зернистости материала. Без него зёрна сбивались в
		# кучу у самого очага, ячейки выходили мельче отсечки и ВЫБРАСЫВАЛИСЬ: объём переставал
		# сходиться (99.7% вместо 100.00%). Правило то же, что и у повторного скола: мельче
		# своей крошки материал не дробится.
		if least > 0.0:
			var crowded := false
			for q in out:
				if q.distance_squared_to(p) < least * least:
					crowded = true
					break
			if crowded:
				continue
		out.append(p)
	return out


## Докуда от очага в эту сторону есть материал: для выпуклой формы это ближайшее пересечение
## луча с её стенами.
static func _reach(shape: Array[Plane], from: Vector3, away: Vector3) -> float:
	var best := INF
	for pl in shape:
		var denom := pl.normal.dot(away)
		if denom <= 1e-6:
			continue
		var t := (pl.d - pl.normal.dot(from)) / denom
		if t >= 0.0:
			best = minf(best, t)
	return 0.0 if is_inf(best) else best


## ЗАТОЛКНУТЬ ТОЧКУ ВНУТРЬ ФОРМЫ. Луч возвращает точку попадания РОВНО на поверхности, а
## формально «на грани» — это снаружи: промах в четверть микрона, и очаг скола некуда ставить.
## Двигаем точку от самой нарушенной стены внутрь, пока не окажется под кожей.
static func tuck(shape: Array[Plane], p: Vector3, depth := 0.002) -> Vector3:
	var q := p
	for _i in 8:
		var worst := -INF
		var guilty := Plane(Vector3.UP, 0.0)
		for w in shape:
			var d := w.distance_to(q)
			if d > worst:
				worst = d
				guilty = w
		if worst <= -depth:
			return q
		q -= guilty.normal * (worst + depth)
	return q


## Плоскость между двумя зёрнами в растянутой метрике. При `grain = (1,1,1)` это обычный
## серединный перпендикуляр.
static func split(me: Vector3, other: Vector3, grain: Vector3) -> Plane:
	var g2 := grain * grain
	var w := (other - me) / g2
	var len := w.length()
	if len < 1e-9:
		return Plane(Vector3.UP, 1e9)
	var d := ((other / grain).length_squared() - (me / grain).length_squared()) * 0.5 / len
	return Plane(w / len, d)


## ГОТОВАЯ ЯЧЕЙКА. Кроме вершин, меша и объёма отдаёт СВОИ СТЕНЫ — те плоскости, что дали
## грань. Без них осколок нельзя расколоть ещё раз: он перестал бы быть описанной формой.
static func cell(shape: Array[Plane], seeds_all: PackedVector3Array, index: int,
		grain := Vector3.ONE, neighbours := NEIGHBOURS) -> Dictionary:
	var me := seeds_all[index]
	var near: Array[int] = []
	for j in seeds_all.size():
		if j != index:
			near.append(j)
	if near.size() > neighbours:
		near.sort_custom(func(a: int, b: int) -> bool:
			return ((seeds_all[a] - me) / grain).length_squared() \
				< ((seeds_all[b] - me) / grain).length_squared())
		near.resize(neighbours)

	var planes := shape.duplicate() as Array[Plane]
	for j in near:
		planes.append(split(me, seeds_all[j], grain))

	var points := Geometry3D.compute_convex_mesh_points(planes)
	if points.size() < 4:
		return {}
	var centre := Vector3.ZERO
	for p in points:
		centre += p
	centre /= points.size()

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var walls: Array[Plane] = []
	var seen := {}
	for pl in planes:
		var on: Array[int] = []
		for i in points.size():
			if absf(pl.distance_to(points[i])) < 0.0005:
				on.append(i)
		if on.size() < 3:
			continue
		on.sort()
		var key := str(on)
		if seen.has(key):
			continue
		seen[key] = true
		walls.append(Plane(pl.normal, pl.d - pl.normal.dot(centre)))

		var mid := Vector3.ZERO
		for i in on:
			mid += points[i]
		mid /= on.size()
		var ax := (points[on[0]] - mid).normalized()
		var ay := pl.normal.cross(ax)
		on.sort_custom(func(a: int, b: int) -> bool:
			var da := points[a] - mid
			var db := points[b] - mid
			return atan2(da.dot(ay), da.dot(ax)) > atan2(db.dot(ay), db.dot(ax)))
		for t in range(1, on.size() - 1):
			var a := points[on[0]] - centre
			var b := points[on[t]] - centre
			var c := points[on[t + 1]] - centre
			# Намотка закрепляется по нормали грани, а не по порядку сортировки: сортировка
			# срывается примерно на одном треугольнике из семисот, и он выпадает прорехой.
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
	return {"centre": centre, "points": local, "mesh": mesh, "volume": vol, "walls": walls}
