extends RefCounted
class_name ForestSim

## `Tree` — имя нативного класса Godot, поэтому константа названа иначе.

## РАССТАНОВКА. Лес — это не «много деревьев», это **распределение**: чащи, поляны, опушки,
## коридоры. Равномерная россыпь читается как парк или как сад, но не как лес; ощущение чащи
## рождается тем, что видно недалеко и что просветы неравномерны.
##
## Плотность берётся из шума с большим периодом: где значение высокое — стена, где низкое —
## поляна. Плюс лёгкое отталкивание: два дерева в одной точке выглядят одним толстым, а не
## двумя.
##
## КЛЕТКАМИ, как трава в тридцать пятой. Дальность отсечения тут даже важнее: дерево это
## тысячи треугольников против трёх у травинки.

const CELL := 24.0
const VARIANTS := 8
const BUSHES := 4
const GRASSES := 4
const DEAD := 3

var area := 220.0
var density := 1.0
var vary := true
var clearings := true
var undergrowth := true
var floor_layer := true
## Дальность травы куда меньше, чем у деревьев: пучок в полметра за тридцать метров занимает
## меньше пикселя и превращается в мерцающий мусор.
var grass_range := 34.0
var grass_density := 6.0
var cull := 150.0

var trees := 0
var bushes := 0
var grass := 0
var deadwood := 0
var visible_now := 0
var tris_per_tree := 0

var _cells := {}          # Vector2i -> {"pos": Vector3, "mm": [MultiMeshInstance3D]}
var _meshes: Array[ArrayMesh] = []
var _bushes: Array[ArrayMesh] = []
var _grasses: Array[ArrayMesh] = []
var _dead: Array[ArrayMesh] = []
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _species := FastNoiseLite.new()
var _root: Node3D
var _mat: Material
var _ground


func setup(ground, root: Node3D, mat: Material) -> void:
	_root = root
	_mat = mat
	_ground = ground
	_noise.seed = 5150
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 0.012
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 3
	_species.seed = 3141
	_species.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_species.frequency = 0.009
	var t := ForestTree.new()
	for i in VARIANTS:
		_meshes.append(t.build(1000 + i * 61, ForestTree.CONIFER if i % 2 == 0 else ForestTree.BROAD))
	# Кусты — ОТДЕЛЬНАЯ форма, а не ужатое дерево. Ужатое дерево с крохотным стволиком и
	# кроной-шариком читается игрушкой; куст растёт вширь и без ствола вовсе.
	for i in BUSHES:
		_bushes.append(t.build(300 + i * 29, ForestTree.BUSH))
	for i in GRASSES:
		_grasses.append(t.build(500 + i * 17, ForestTree.GRASS))
	for i in DEAD:
		_dead.append(t.build(700 + i * 23, ForestTree.LOG if i < 2 else ForestTree.STUMP))
	for m in _meshes:
		tris_per_tree += m.surface_get_array_len(0) / 3
	tris_per_tree /= VARIANTS
	rebuild()


func clear() -> void:
	for k in _cells:
		for mi in _cells[k]["mm"]:
			mi.queue_free()
	for k in _cells:
		if _cells[k].has("grass"):
			for mi in _cells[k]["grass"]:
				mi.queue_free()
	_cells.clear()
	trees = 0
	bushes = 0
	grass = 0
	deadwood = 0


## ПЛОТНОСТЬ В ТОЧКЕ. Без полян — ровное поле; с полянами — шум, поднятый в степень, чтобы
## пустые места были действительно пустыми, а не «чуть реже».
func _density_at(x: float, z: float) -> float:
	if not clearings:
		return 0.72 * density
	var n := _noise.get_noise_2d(x, z) * 0.5 + 0.5
	return pow(n, 1.7) * 1.6 * density


func rebuild() -> void:
	clear()
	_rng.seed = 20260902
	var buckets := {}
	# Втрое больше попыток: игрок сказал «нет общей лесистости», и это была правда —
	# семьсот деревьев на 220 метрах это редколесье, а не чаща.
	var tries := int(area * area * 0.16)
	var placed: Array[Vector3] = []
	for i in tries:
		var x := _rng.randf_range(-area * 0.5, area * 0.5)
		var z := _rng.randf_range(-area * 0.5, area * 0.5)
		if _rng.randf() > _density_at(x, z):
			continue
		# Отталкивание: два дерева в одной точке — это одно толстое, а не два.
		var ok := true
		for p in placed:
			# Минимум четыре метра между стволами: деревья стали втрое выше, и прежние
			# два с половиной метра давали сросшиеся стволы.
			if Vector2(p.x - x, p.z - z).length_squared() < 16.0:
				ok = false
				break
		if not ok:
			continue
		var y: float = _ground.height(x, z)
		placed.append(Vector3(x, y, z))
		var k := Vector2i(int(floor(x / CELL)), int(floor(z / CELL)))
		if not buckets.has(k):
			buckets[k] = {}
		# ВАРИАТИВНОСТЬ: без неё все деревья одной формы, и лес читается как обои.
		# ПОРОДА ПЯТНАМИ, а не случайно на каждое дерево. В природе ели растут ельником,
		# берёзы рощей; случайный выбор на каждый ствол даёт равномерную мешанину, в которой
		# глаз не находит ни одного «места». Второй шум задаёт, чья это область, а внутри
		# области форма выбирается уже случайно.
		var v := 0
		if vary:
			var species := 0 if _species.get_noise_2d(x, z) < 0.0 else 1
			v = species + 2 * (_rng.randi() % (VARIANTS / 2))
		if not buckets[k].has(v):
			buckets[k][v] = []
		buckets[k][v].append(Vector3(x, y, z))
		trees += 1

	for k in buckets:
		var list: Array[MultiMeshInstance3D] = []
		for v in buckets[k]:
			list.append(_mm(_meshes[v], buckets[k][v], 0.8, 1.25))
		var c := Vector3((k.x + 0.5) * CELL, 0.0, (k.y + 0.5) * CELL)
		_cells[k] = {"pos": c, "mm": list, "grass": []}

	if undergrowth:
		_add_undergrowth(placed)
	if floor_layer:
		_add_floor(placed)


## ПОДЛЕСОК. Кусты — те же деревья, ужатые до полуметра. Не ради экономии кода: под пологом
## леса подрост и есть маленькие деревья, и одинаковый силуэт читается как «то же самое, но
## молодое». Ставятся они у стволов и в полутени, а не на полянах.
func _add_undergrowth(near: Array[Vector3]) -> void:
	var by_cell := {}
	for i in near.size():
		if _rng.randf() > 0.9:
			continue
		for j in _rng.randi_range(2, 5):
			var a := _rng.randf_range(0.0, TAU)
			var r := _rng.randf_range(1.5, 7.0)
			var x: float = near[i].x + cos(a) * r
			var z: float = near[i].z + sin(a) * r
			var k := Vector2i(int(floor(x / CELL)), int(floor(z / CELL)))
			if not by_cell.has(k):
				by_cell[k] = []
			by_cell[k].append(Vector3(x, _ground.height(x, z), z))
			bushes += 1
	for k in by_cell:
		_ensure(k)["mm"].append(_mm(_bushes[_rng.randi() % BUSHES], by_cell[k], 0.7, 1.6))


## НАПОЧВЕННЫЙ ЯРУС И ВАЛЕЖНИК. Трава ковром между стволами, брёвна и пни редко.
##
## Трава кладётся в СВОИ списки со своей дальностью отсечения — втрое меньшей, чем у
## деревьев. Иначе платишь за то, что всё равно мельче пикселя, и получаешь мерцание в
## придачу.
##
## Валежник — это «история». Лес, где ничего никогда не падало, выглядит расставленным, а
## не выросшим; одно бревно на семь деревьев меняет впечатление непропорционально цене.
func _add_floor(near: Array[Vector3]) -> void:
	var g_cells := {}
	var d_cells := {}
	var half := area * 0.5
	for i in int(area * area * 0.6 * grass_density):
		var x := _rng.randf_range(-half, half)
		var z := _rng.randf_range(-half, half)
		# Трава гуще там, где реже деревья: под сомкнутым пологом ей не хватает света.
		# Та же карта плотности, прочитанная наоборот, — и ярусы сразу связаны друг с другом.
		if _rng.randf() > 1.15 - _density_at(x, z) * 0.75:
			continue
		var k := Vector2i(int(floor(x / CELL)), int(floor(z / CELL)))
		if not g_cells.has(k):
			g_cells[k] = []
		g_cells[k].append(Vector3(x, _ground.height(x, z), z))
		grass += 1
	for p in near:
		if _rng.randf() > 0.14:
			continue
		var a := _rng.randf_range(0.0, TAU)
		var r := _rng.randf_range(1.0, 6.0)
		var x: float = p.x + cos(a) * r
		var z: float = p.z + sin(a) * r
		var k := Vector2i(int(floor(x / CELL)), int(floor(z / CELL)))
		if not d_cells.has(k):
			d_cells[k] = []
		d_cells[k].append(Vector3(x, _ground.height(x, z), z))
		deadwood += 1
	for k in d_cells:
		_ensure(k)["mm"].append(_mm(_dead[_rng.randi() % DEAD], d_cells[k], 0.7, 1.4))
	for k in g_cells:
		var mi := _mm(_grasses[_rng.randi() % GRASSES], g_cells[k], 0.8, 1.8)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ensure(k)["grass"].append(mi)


func _ensure(k: Vector2i) -> Dictionary:
	if not _cells.has(k):
		_cells[k] = {"pos": Vector3((k.x + 0.5) * CELL, 0.0, (k.y + 0.5) * CELL),
			"mm": [], "grass": []}
	elif not _cells[k].has("grass"):
		_cells[k]["grass"] = []
	return _cells[k]


func _mm(mesh: ArrayMesh, pos: Array, lo: float, hi: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	# Данные экземпляра нужны ради ФАЗЫ ветра: без неё весь лес качается синхронно.
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = pos.size()
	for i in pos.size():
		var s := _rng.randf_range(lo, hi)
		var b := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3(s, s, s))
		mm.set_instance_transform(i, Transform3D(b, pos[i]))
		mm.set_instance_custom_data(i, Color(_rng.randf(), _rng.randf(), 0.0, 0.0))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _mat
	# Тени от каждого дерева стоят дороже самого дерева; на лоу-поли лесу хватает
	# затенения кроной по нормали, а тени оставлены только ближним.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_root.add_child(mi)
	return mi


func update(eye: Vector3) -> void:
	visible_now = 0
	var margin := CELL * 0.71
	for k in _cells:
		var d: float = Vector2(_cells[k]["pos"].x - eye.x, _cells[k]["pos"].z - eye.z).length() - margin
		var on := d < cull
		for mi in _cells[k]["mm"]:
			mi.visible = on
			if on:
				visible_now += mi.multimesh.instance_count
		if _cells[k].has("grass"):
			var gon := d < grass_range
			for mi in _cells[k]["grass"]:
				mi.visible = gon
				if gon:
					visible_now += mi.multimesh.instance_count


## СКОЛЬКО ВИДНО — число, которым меряется «ощущение чащи». Из точки наблюдателя пускаем
## лучи по кругу и смотрим, на каком расстоянии первый ствол. Медиана этого расстояния и
## есть ответ на вопрос «лес или парк»: в лесу видно на десятки метров, в парке — на сотни.
##
## Считается по положениям стволов, а не физикой: у MultiMesh коллизии нет вовсе, и заводить
## её ради замера значило бы менять предмет измерения.
func sight(eye: Vector3, rays: int = 72) -> float:
	var found: Array[float] = []
	for i in rays:
		var a := TAU * float(i) / rays
		var dir := Vector2(cos(a), sin(a))
		var best := cull
		for k in _cells:
			for mi in _cells[k]["mm"]:
				var mm: MultiMesh = mi.multimesh
				for j in mm.instance_count:
					var p: Vector3 = mm.get_instance_transform(j).origin
					var to := Vector2(p.x - eye.x, p.z - eye.z)
					var along := to.dot(dir)
					if along <= 0.5 or along >= best:
						continue
					# ствол считаем цилиндром радиусом в четверть метра
					if absf(to.x * dir.y - to.y * dir.x) < 0.5:
						best = along
		found.append(best)
	found.sort()
	return found[found.size() / 2]


func cells() -> int:
	return _cells.size()
