class_name ForestTree
extends RefCounted
## ДЕРЕВО, СОБРАННОЕ КОДОМ. Лоу-поли — это не «мало треугольников», это **честные грани**:
## плоское затенение, читаемый силуэт, крупные плоскости. Вершины здесь НЕ переиспользуются
## между гранями — у каждого треугольника свои три, со своей нормалью. Общие вершины дали бы
## гладкую интерполяцию, то есть ровно то, чего в стиле быть не должно.
##
## МАСШТАБ РЕШАЕТ БОЛЬШЕ ФОРМЫ. Деревья по 5–9 метров читаются подростом: кроны на уровне
## взгляда, небо между ними, силуэты мелкие. Настоящая ель 20–30 метров, и когда камера
## смотрит снизу вверх на ствол в полметра толщиной, ощущение чащи появляется само, без
## единого нового приёма.
##
## В ЦВЕТЕ ВЕРШИНЫ ЕДУТ ТРИ ЧИСЛА — единственный способ передать их в вершинный шейдер без
## второго набора буферов:
##   R — вес раскачки: 0 у комля, 1 на кончиках.
##   G — 1 для листвы, 0 для древесины.
##   B — разброс оттенка внутри кроны.
##
## `Tree` — имя нативного класса Godot, поэтому класс здесь `ForestTree`.

enum Kind {
	CONIFER,
	BROAD,
	BUSH,
	GRASS,
	LOG,
	STUMP,
}

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var cols := PackedColorArray()
var height := 0.0

var _random := RandomNumberGenerator.new()


func build(seed_value: int, kind: Kind) -> ArrayMesh:
	verts = PackedVector3Array()
	norms = PackedVector3Array()
	cols = PackedColorArray()
	_random.seed = seed_value
	match kind:
		Kind.CONIFER:
			height = _random.randf_range(15.0, 27.0)
			_conifer(height)
		Kind.BROAD:
			height = _random.randf_range(11.0, 19.0)
			_broad(height)
		Kind.BUSH:
			height = _random.randf_range(0.9, 2.4)
			_bush(height)
		Kind.GRASS:
			height = _random.randf_range(0.35, 0.8)
			_grass(height)
		Kind.LOG:
			height = _random.randf_range(4.0, 11.0)
			_fallen(height)
		_:
			height = _random.randf_range(0.5, 1.3)
			_stump(height)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## ХВОЙНОЕ. Ствол насквозь и стопка юбок, радиус которых падает к макушке не линейно, а по
## степени — иначе выходит ровный конус, а у ели профиль вогнутый: низ разлапистый, верх
## быстро сходится. Одно число `taper` отличает узкую пихту от разлапистой ели, и разница
## силуэтов на горизонте держится именно на нём.
func _conifer(total: float) -> void:
	var trunk := total * 0.021
	_taper(
			Vector3.ZERO, Vector3(0.0, total * 0.99, 0.0),
			trunk, trunk * 0.18, 7, 0.0, 0.0)
	var tiers := _random.randi_range(7, 11)
	var spread := total * _random.randf_range(0.13, 0.21)
	var taper := _random.randf_range(0.7, 1.5)
	# ГОЛЫЙ КОМЕЛЬ — от четверти до половины высоты. Это не украшение: в густом лесу нижние
	# ветви отмирают без света, и именно поэтому под пологом можно ходить и видеть стволы.
	# При десяти процентах ярусы начинаются на полутора метрах, камера идёт внутри кроны —
	# зелёная стена вместо леса.
	var bare := _random.randf_range(0.26, 0.46)
	for i in tiers:
		var along := float(i) / float(tiers - 1)
		var y := total * (bare + along * (1.0 - bare))
		var radius := pow(1.0 - along, taper) * spread + total * 0.008
		_skirt(
				Vector3(0.0, y, 0.0),
				radius,
				radius * _random.randf_range(0.42, 0.62),
				_random.randi_range(7, 9),
				0.25 + 0.75 * along,
				_random.randf_range(0.0, 1.0))


## ЛИСТВЕННОЕ. Ствол до сорока процентов высоты, дальше КУПОЛ из перекрывающихся комков.
##
## Комки на концах длинных ветвей дают «руку с шарами»: тонкие палки, торчащие из ствола, и
## отдельные шары на них. Настоящая крона это сплошной объём, внутри которого ветвей не
## видно вовсе. Поэтому ветви короткие и служат только тому, чтобы комки не сидели в одной
## точке, а купол собирается из четырёх-шести шаров, каждый смещён от центра меньше чем на
## свой радиус — тогда они сливаются.
func _broad(total: float) -> void:
	var trunk := total * 0.026
	var fork := total * _random.randf_range(0.44, 0.55)
	_taper(Vector3.ZERO, Vector3(0.0, fork, 0.0), trunk, trunk * 0.55, 6, 0.0, 0.0)
	var crown := total * _random.randf_range(0.30, 0.40)
	var centre := Vector3(0.0, fork + crown * 0.75, 0.0)
	var arms := _random.randi_range(3, 5)
	for i in arms:
		var angle := TAU * float(i) / arms + _random.randf_range(-0.35, 0.35)
		var out := Vector3(cos(angle), 0.0, sin(angle)) * crown * 0.42
		var to := centre + out + Vector3(
				0.0, crown * _random.randf_range(-0.25, 0.15), 0.0)
		_taper(
				Vector3(0.0, fork * 0.9, 0.0), to,
				trunk * 0.5, trunk * 0.22, 4, 0.15, 0.0)
		_blob(
				to,
				Vector3.ONE * crown * _random.randf_range(0.52, 0.72),
				0.6 + 0.4 * (to.y / total),
				_random.randf_range(0.0, 1.0))
	_blob(
			centre + Vector3(0.0, crown * 0.2, 0.0),
			Vector3.ONE * crown * _random.randf_range(0.62, 0.8),
			1.0,
			_random.randf_range(0.0, 1.0))


## КУСТ. Ни ствола, ни ветвей — низкий широкий ком из нескольких шаров почти на земле.
## Именно ширина отличает куст от маленького дерева: подлеску тянуться вверх некуда, и он
## растёт вширь. Ужатое дерево с крохотным стволиком и кроной-шариком читается игрушкой.
func _bush(total: float) -> void:
	var blobs := _random.randi_range(3, 5)
	for i in blobs:
		var angle := TAU * float(i) / blobs + _random.randf_range(-0.5, 0.5)
		var radius := total * _random.randf_range(0.25, 0.55)
		var at := Vector3(
				cos(angle) * radius,
				total * _random.randf_range(0.30, 0.55),
				sin(angle) * radius)
		_blob(
				at,
				Vector3(
					total * _random.randf_range(0.45, 0.7),
					total * _random.randf_range(0.34, 0.5),
					total * _random.randf_range(0.45, 0.7)),
				0.5 + 0.5 * (at.y / total),
				_random.randf_range(0.0, 1.0))


## ТРАВЯНОЙ ЯРУС. Пучок сужающихся листьев — самая дешёвая геометрия в пробе и самая
## заметная: пол леса это то, что игрок видит на уровне взгляда всё время. Ровная тёмная
## плоскость под ногами убивает ощущение вернее, чем любая ошибка в кронах.
func _grass(total: float) -> void:
	var blades := _random.randi_range(4, 7)
	for i in blades:
		var angle := TAU * float(i) / blades + _random.randf_range(-0.6, 0.6)
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-out.z, 0.0, out.x) * total * _random.randf_range(0.05, 0.09)
		var tip := (
				Vector3(0.0, total * _random.randf_range(0.7, 1.0), 0.0)
				+ out * total * _random.randf_range(0.2, 0.5)
		)
		var tint := _random.randf_range(0.0, 1.0)
		_face(-side, side, tip, 0.0, 1.0, tint)
		_face(side, -side, tip, 1.0, 1.0, tint)


## ВАЛЕЖНИК. Упавший ствол — это «история»: лес, где ничего никогда не падало, выглядит
## расставленным. Лежит он под случайным углом и слегка утоплен в землю, иначе парит.
func _fallen(total: float) -> void:
	var radius := _random.randf_range(0.22, 0.45)
	var angle := _random.randf_range(0.0, TAU)
	var along := Vector3(cos(angle), _random.randf_range(-0.06, 0.06), sin(angle))
	_taper(
			Vector3(0.0, radius * 0.75, 0.0),
			along * total + Vector3(0.0, radius * 0.75, 0.0),
			radius, radius * _random.randf_range(0.55, 0.85), 6, 0.0, 0.0)


## ПЕНЬ. Обломанный ствол с рваным верхом — там, где дерево не упало целиком.
func _stump(total: float) -> void:
	var radius := _random.randf_range(0.3, 0.6)
	_taper(
			Vector3.ZERO,
			Vector3(
				_random.randf_range(-0.1, 0.1), total, _random.randf_range(-0.1, 0.1)),
			radius, radius * 0.82, 7, 0.0, 0.0)


func _face(
		a: Vector3, b: Vector3, c: Vector3,
		sway: float, leaf: float, tint: float) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 1e-9:
		return
	normal = normal.normalized()
	for vertex in [a, b, c]:
		verts.append(vertex)
		norms.append(normal)
		cols.append(Color(sway, leaf, tint, 1.0))


## Сужающаяся призма между двумя точками — ствол или ветвь.
func _taper(
		from: Vector3,
		to: Vector3,
		radius_from: float,
		radius_to: float,
		sides: int,
		sway_from: float,
		leaf: float) -> void:
	var axis := to - from
	var length := axis.length()
	if length < 0.001:
		return
	axis /= length
	var up := Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT
	var across := up.cross(axis).normalized()
	var other := axis.cross(across)
	var sway_to := sway_from + (1.0 - sway_from) * 0.5
	for i in sides:
		var angle_a := TAU * i / sides
		var angle_b := TAU * (i + 1) / sides
		var ring_a := across * cos(angle_a) + other * sin(angle_a)
		var ring_b := across * cos(angle_b) + other * sin(angle_b)
		var near_a := from + ring_a * radius_from
		var near_b := from + ring_b * radius_from
		var far_a := to + ring_a * radius_to
		var far_b := to + ring_b * radius_to
		_face(near_a, far_a, near_b, sway_from, leaf, 0.0)
		_face(near_b, far_a, far_b, sway_to, leaf, 0.0)


## Юбка хвойного яруса: конус вниз-наружу, без донышка — оно давало z-конфликт по кромке, а
## после переворота нормалей у задних граней юбка и так видна с обеих сторон.
func _skirt(
		at: Vector3, radius: float, drop: float,
		sides: int, sway: float, tint: float) -> void:
	var tip := at + Vector3(0.0, drop, 0.0)
	for i in sides:
		var angle_a := TAU * i / sides
		var angle_b := TAU * (i + 1) / sides
		# Лёгкая неровность кромки: идеальный круг читается зонтиком, а не лапами.
		var width_a := radius * (1.0 + _random.randf_range(-0.16, 0.16))
		var width_b := radius * (1.0 + _random.randf_range(-0.16, 0.16))
		var edge_a := at + Vector3(
				cos(angle_a) * width_a, -drop * 0.4, sin(angle_a) * width_a)
		var edge_b := at + Vector3(
				cos(angle_b) * width_b, -drop * 0.4, sin(angle_b) * width_b)
		_face(tip, edge_a, edge_b, sway, 1.0, tint)


## Гранёный комок кроны: октаэдр с одним разбиением и случайным сдвигом вершин. Ровный шар
## в лоу-поли смотрится мячом; неправильность и есть весь стиль.
func _blob(at: Vector3, size: Vector3, sway: float, tint: float) -> void:
	var corners := [
		Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0),
		Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1),
	]
	var faces := [
		[0, 2, 4], [2, 1, 4], [1, 3, 4], [3, 0, 4],
		[2, 0, 5], [1, 2, 5], [3, 1, 5], [0, 3, 5],
	]
	for face in faces:
		var a: Vector3 = corners[face[0]]
		var b: Vector3 = corners[face[1]]
		var c: Vector3 = corners[face[2]]
		var ab := (a + b).normalized()
		var bc := (b + c).normalized()
		var ca := (c + a).normalized()
		for triangle in [[a, ab, ca], [ab, b, bc], [ca, bc, c], [ab, bc, ca]]:
			var points := []
			for corner in triangle:
				var jitter := Vector3(
						_random.randf_range(-0.16, 0.16),
						_random.randf_range(-0.16, 0.16),
						_random.randf_range(-0.16, 0.16))
				points.append(at + (corner + jitter) * size)
			_face(points[0], points[1], points[2], sway, 1.0, tint)
