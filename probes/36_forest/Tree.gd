extends RefCounted
class_name ForestTree

## ДЕРЕВО, СОБРАННОЕ КОДОМ. Лоу-поли — это не «мало треугольников», это **честные грани**:
## плоское затенение, читаемый силуэт, крупные плоскости. Вершины здесь НЕ переиспользуются
## между гранями — у каждого треугольника свои три, со своей нормалью. Общие вершины дали бы
## гладкую интерполяцию, то есть ровно то, чего в стиле быть не должно.
##
## МАСШТАБ РЕШАЕТ БОЛЬШЕ ФОРМЫ. Первая версия ставила деревья по 5–9 метров, и лес читался
## подростом: кроны на уровне взгляда, небо между ними, силуэты мелкие. Настоящая ель 20–30
## метров, и когда камера смотрит снизу вверх на ствол в полметра толщиной, ощущение чащи
## появляется само, без единого нового приёма.
##
## В ЦВЕТЕ ВЕРШИНЫ ЕДУТ ТРИ ЧИСЛА — единственный способ передать их в вершинный шейдер без
## второго набора буферов:
##   R — вес раскачки: 0 у комля, 1 на кончиках.
##   G — 1 для листвы, 0 для древесины.
##   B — разброс оттенка внутри кроны.

const CONIFER := 0
const BROAD := 1
const BUSH := 2
const GRASS := 3
const LOG := 4
const STUMP := 5

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var cols := PackedColorArray()
var height := 0.0
var _rng := RandomNumberGenerator.new()


func build(seed_value: int, kind: int) -> ArrayMesh:
	verts = PackedVector3Array()
	norms = PackedVector3Array()
	cols = PackedColorArray()
	_rng.seed = seed_value
	match kind:
		CONIFER:
			height = _rng.randf_range(15.0, 27.0)
			_conifer(height)
		BROAD:
			height = _rng.randf_range(11.0, 19.0)
			_broad(height)
		BUSH:
			height = _rng.randf_range(0.9, 2.4)
			_bush(height)
		GRASS:
			height = _rng.randf_range(0.35, 0.8)
			_grass(height)
		LOG:
			height = _rng.randf_range(4.0, 11.0)
			_log(height)
		_:
			height = _rng.randf_range(0.5, 1.3)
			_stump(height)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## ХВОЙНОЕ. Ствол насквозь и стопка юбок, радиус которых падает к макушке не линейно, а по
## степени — иначе выходит ровный конус, а у ели профиль вогнутый: низ разлапистый, верх
## быстро сходится. Одно число `taper` отличает узкую пихту от разлапистой ели, и разница
## силуэтов на горизонте держится именно на нём.
func _conifer(h: float) -> void:
	var r_base := h * 0.021
	_taper(Vector3.ZERO, Vector3(0.0, h * 0.99, 0.0), r_base, r_base * 0.18, 7, 0.0, 0.0)
	var tiers := _rng.randi_range(7, 11)
	var spread := h * _rng.randf_range(0.13, 0.21)
	var taper := _rng.randf_range(0.7, 1.5)
	# ГОЛЫЙ КОМЕЛЬ — от четверти до половины высоты. Это не украшение: в густом лесу нижние
	# ветви отмирают без света, и именно поэтому под пологом можно ходить и видеть стволы.
	# При десяти процентах ярусы начинались на полутора метрах, и камера шла внутри кроны —
	# зелёная стена вместо леса.
	var bare := _rng.randf_range(0.26, 0.46)
	for i in tiers:
		var k := float(i) / float(tiers - 1)
		var y := h * (bare + k * (1.0 - bare))
		var r := pow(1.0 - k, taper) * spread + h * 0.008
		_skirt(Vector3(0.0, y, 0.0), r, r * _rng.randf_range(0.42, 0.62),
			_rng.randi_range(7, 9), 0.25 + 0.75 * k, _rng.randf_range(0.0, 1.0))


## ЛИСТВЕННОЕ. Ствол до сорока процентов высоты, дальше КУПОЛ из перекрывающихся комков.
##
## Первая версия расставляла комки на концах длинных ветвей — получалась «рука с шарами»:
## тонкие палки, торчащие из ствола, и отдельные шары на них. Настоящая крона это сплошной
## объём, внутри которого ветвей не видно вовсе. Поэтому ветви короткие и служат только тому,
## чтобы комки не сидели в одной точке, а купол собирается из четырёх-шести шаров, каждый
## смещён от центра меньше чем на свой радиус — тогда они сливаются.
func _broad(h: float) -> void:
	var r_base := h * 0.026
	var fork := h * _rng.randf_range(0.44, 0.55)
	_taper(Vector3.ZERO, Vector3(0.0, fork, 0.0), r_base, r_base * 0.55, 6, 0.0, 0.0)
	var crown := h * _rng.randf_range(0.30, 0.40)
	var centre := Vector3(0.0, fork + crown * 0.75, 0.0)
	var arms := _rng.randi_range(3, 5)
	for i in arms:
		var a := TAU * float(i) / arms + _rng.randf_range(-0.35, 0.35)
		var out := Vector3(cos(a), 0.0, sin(a)) * crown * 0.42
		var to := centre + out + Vector3(0.0, crown * _rng.randf_range(-0.25, 0.15), 0.0)
		_taper(Vector3(0.0, fork * 0.9, 0.0), to, r_base * 0.5, r_base * 0.22, 4, 0.15, 0.0)
		_blob(to, Vector3.ONE * crown * _rng.randf_range(0.52, 0.72),
			0.6 + 0.4 * (to.y / h), _rng.randf_range(0.0, 1.0))
	_blob(centre + Vector3(0.0, crown * 0.2, 0.0),
		Vector3.ONE * crown * _rng.randf_range(0.62, 0.8), 1.0, _rng.randf_range(0.0, 1.0))


## КУСТ. Ни ствола, ни ветвей — низкий широкий ком из нескольких шаров почти на земле.
## Именно ширина отличает куст от маленького дерева: подлеску тянуться вверх некуда, и он
## растёт вширь. Раньше кустами работали ужатые деревья, и подлесок выглядел игрушечным.
func _bush(h: float) -> void:
	var n := _rng.randi_range(3, 5)
	for i in n:
		var a := TAU * float(i) / n + _rng.randf_range(-0.5, 0.5)
		var r := h * _rng.randf_range(0.25, 0.55)
		var at := Vector3(cos(a) * r, h * _rng.randf_range(0.30, 0.55), sin(a) * r)
		_blob(at, Vector3(h * _rng.randf_range(0.45, 0.7), h * _rng.randf_range(0.34, 0.5),
			h * _rng.randf_range(0.45, 0.7)), 0.5 + 0.5 * (at.y / h),
			_rng.randf_range(0.0, 1.0))


## ТРАВЯНОЙ ЯРУС. Пучок сужающихся листьев — самая дешёвая геометрия в пробе и самая
## заметная: пол леса это то, что игрок видит на уровне взгляда всё время. Ровная тёмная
## плоскость под ногами убивает ощущение вернее, чем любая ошибка в кронах.
func _grass(h: float) -> void:
	var n := _rng.randi_range(4, 7)
	for i in n:
		var a := TAU * float(i) / n + _rng.randf_range(-0.6, 0.6)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-dir.z, 0.0, dir.x) * h * _rng.randf_range(0.05, 0.09)
		var tip := Vector3(0.0, h * _rng.randf_range(0.7, 1.0), 0.0) + dir * h * _rng.randf_range(0.2, 0.5)
		var t := _rng.randf_range(0.0, 1.0)
		_face(-side, side, tip, 0.0, 1.0, t)
		_face(side, -side, tip, 1.0, 1.0, t)


## ВАЛЕЖНИК. Упавший ствол — это «история»: лес, где ничего никогда не падало, выглядит
## расставленным. Лежит он под случайным углом и слегка утоплен в землю, иначе парит.
func _log(h: float) -> void:
	var r := _rng.randf_range(0.22, 0.45)
	var a := _rng.randf_range(0.0, TAU)
	var dir := Vector3(cos(a), _rng.randf_range(-0.06, 0.06), sin(a))
	_taper(Vector3(0.0, r * 0.75, 0.0), dir * h + Vector3(0.0, r * 0.75, 0.0),
		r, r * _rng.randf_range(0.55, 0.85), 6, 0.0, 0.0)


## ПЕНЬ. Обломанный ствол с рваным верхом — там, где дерево не упало целиком.
func _stump(h: float) -> void:
	var r := _rng.randf_range(0.3, 0.6)
	_taper(Vector3.ZERO, Vector3(_rng.randf_range(-0.1, 0.1), h, _rng.randf_range(-0.1, 0.1)),
		r, r * 0.82, 7, 0.0, 0.0)


func _face(a: Vector3, b: Vector3, c: Vector3, sway: float, leaf: float, tint: float) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-9:
		return
	n = n.normalized()
	for v in [a, b, c]:
		verts.append(v)
		norms.append(n)
		cols.append(Color(sway, leaf, tint, 1.0))


## Сужающаяся призма между двумя точками — ствол или ветвь.
func _taper(from: Vector3, to: Vector3, r0: float, r1: float, sides: int,
		sway0: float, leaf: float) -> void:
	var axis := to - from
	var len_ := axis.length()
	if len_ < 0.001:
		return
	axis /= len_
	var up := Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT
	var t := up.cross(axis).normalized()
	var b := axis.cross(t)
	var sway1 := sway0 + (1.0 - sway0) * 0.5
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := from + (t * cos(a0) + b * sin(a0)) * r0
		var p1 := from + (t * cos(a1) + b * sin(a1)) * r0
		var q0 := to + (t * cos(a0) + b * sin(a0)) * r1
		var q1 := to + (t * cos(a1) + b * sin(a1)) * r1
		_face(p0, q0, p1, sway0, leaf, 0.0)
		_face(p1, q0, q1, sway1, leaf, 0.0)


## Юбка хвойного яруса: конус вниз-наружу, без донышка — оно давало z-конфликт по кромке, а
## после переворота нормалей у задних граней юбка и так видна с обеих сторон.
func _skirt(at: Vector3, radius: float, drop: float, sides: int,
		sway: float, tint: float) -> void:
	var tip := at + Vector3(0.0, drop, 0.0)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		# лёгкая неровность кромки: идеальный круг читается зонтиком, а не лапами
		var w0 := radius * (1.0 + _rng.randf_range(-0.16, 0.16))
		var w1 := radius * (1.0 + _rng.randf_range(-0.16, 0.16))
		var p0 := at + Vector3(cos(a0) * w0, -drop * 0.4, sin(a0) * w0)
		var p1 := at + Vector3(cos(a1) * w1, -drop * 0.4, sin(a1) * w1)
		_face(tip, p0, p1, sway, 1.0, tint)


## Гранёный комок кроны: октаэдр с одним разбиением и случайным сдвигом вершин. Ровный шар в
## лоу-поли смотрится мячом; неправильность и есть весь стиль.
func _blob(at: Vector3, size: Vector3, sway: float, tint: float) -> void:
	var base := [
		Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0),
		Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	var faces := [
		[0, 2, 4], [2, 1, 4], [1, 3, 4], [3, 0, 4],
		[2, 0, 5], [1, 2, 5], [3, 1, 5], [0, 3, 5]]
	for f in faces:
		var a: Vector3 = base[f[0]]
		var b: Vector3 = base[f[1]]
		var c: Vector3 = base[f[2]]
		var ab := (a + b).normalized()
		var bc := (b + c).normalized()
		var ca := (c + a).normalized()
		for tri in [[a, ab, ca], [ab, b, bc], [ca, bc, c], [ab, bc, ca]]:
			var p := []
			for v in tri:
				var j := Vector3(_rng.randf_range(-0.16, 0.16), _rng.randf_range(-0.16, 0.16),
					_rng.randf_range(-0.16, 0.16))
				p.append(at + (v + j) * size)
			_face(p[0], p[1], p[2], sway, 1.0, tint)
