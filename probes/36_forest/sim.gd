class_name ForestSim
extends RefCounted
## РАССТАНОВКА. Лес — это не «много деревьев», это **распределение**: чащи, поляны, опушки,
## коридоры. Равномерная россыпь читается как парк или как сад, но не как лес; ощущение
## чащи рождается тем, что видно недалеко и что просветы неравномерны.
##
## Плотность берётся из шума с большим периодом: где значение высокое — стена, где низкое —
## поляна. Плюс лёгкое отталкивание: два дерева в одной точке выглядят одним толстым, а не
## двумя.
##
## КЛЕТКАМИ, как трава в 35-й. Дальность отсечения тут даже важнее: дерево это тысячи
## треугольников против трёх у травинки.

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
## Дальность травы куда меньше, чем у деревьев: пучок в полметра за тридцать метров
## занимает меньше пикселя и превращается в мерцающий мусор.
var grass_range := 34.0
var grass_density := 6.0
var cull := 150.0

var trees := 0
var bushes := 0
var grass := 0
var deadwood := 0
var visible_now := 0
var tris_per_tree := 0

## Vector2i -> {at, fields, grass}.
var _cells := {}
var _meshes: Array[ArrayMesh] = []
var _bush_meshes: Array[ArrayMesh] = []
var _grass_meshes: Array[ArrayMesh] = []
var _dead_meshes: Array[ArrayMesh] = []
var _random := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _species := FastNoiseLite.new()
var _root: Node3D
var _material: Material
var _ground: ForestGround


func setup(ground: ForestGround, root: Node3D, material: Material) -> void:
	_root = root
	_material = material
	_ground = ground
	_noise.seed = 5150
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 0.012
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 3
	_species.seed = 3141
	_species.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_species.frequency = 0.009
	var maker := ForestTree.new()
	for i in VARIANTS:
		var kind := ForestTree.Kind.CONIFER if i % 2 == 0 else ForestTree.Kind.BROAD
		_meshes.append(maker.build(1000 + i * 61, kind))
	# Кусты — ОТДЕЛЬНАЯ форма, а не ужатое дерево: под пологом подрост растёт вширь.
	for i in BUSHES:
		_bush_meshes.append(maker.build(300 + i * 29, ForestTree.Kind.BUSH))
	for i in GRASSES:
		_grass_meshes.append(maker.build(500 + i * 17, ForestTree.Kind.GRASS))
	for i in DEAD:
		var kind := ForestTree.Kind.LOG if i < 2 else ForestTree.Kind.STUMP
		_dead_meshes.append(maker.build(700 + i * 23, kind))
	for mesh in _meshes:
		tris_per_tree += mesh.surface_get_array_len(0) / 3
	tris_per_tree /= VARIANTS
	rebuild()


func clear() -> void:
	for key in _cells:
		for field in _cells[key]["fields"]:
			field.queue_free()
		for field in _cells[key]["grass"]:
			field.queue_free()
	_cells.clear()
	trees = 0
	bushes = 0
	grass = 0
	deadwood = 0


func rebuild() -> void:
	clear()
	_random.seed = 20260902
	var buckets := {}
	# Семьсот деревьев на 220 метрах — это редколесье, а не чаща; попыток нужно втрое
	# больше площади.
	var tries := int(area * area * 0.16)
	var placed: Array[Vector3] = []
	for i in tries:
		var x := _random.randf_range(-area * 0.5, area * 0.5)
		var z := _random.randf_range(-area * 0.5, area * 0.5)
		if _random.randf() > _density_at(x, z):
			continue
		# Отталкивание: два дерева в одной точке — это одно толстое, а не два. Минимум
		# четыре метра между стволами: при высоте в двадцать метров два с половиной метра
		# дают сросшиеся стволы.
		var clear_spot := true
		for spot in placed:
			if Vector2(spot.x - x, spot.z - z).length_squared() < 16.0:
				clear_spot = false
				break
		if not clear_spot:
			continue
		var y := _ground.height(x, z)
		placed.append(Vector3(x, y, z))
		var key := Vector2i(int(floor(x / CELL)), int(floor(z / CELL)))
		if not buckets.has(key):
			buckets[key] = {}
		# ВАРИАТИВНОСТЬ: без неё все деревья одной формы, и лес читается как обои.
		# ПОРОДА ПЯТНАМИ, а не случайно на каждое дерево. В природе ели растут ельником,
		# берёзы рощей; случайный выбор на каждый ствол даёт равномерную мешанину, в
		# которой глаз не находит ни одного «места». Второй шум задаёт, чья это область, а
		# внутри области форма выбирается уже случайно.
		var variant := 0
		if vary:
			var species := 0 if _species.get_noise_2d(x, z) < 0.0 else 1
			variant = species + 2 * (_random.randi() % (VARIANTS / 2))
		if not buckets[key].has(variant):
			buckets[key][variant] = []
		buckets[key][variant].append(Vector3(x, y, z))
		trees += 1

	for key in buckets:
		var fields: Array[MultiMeshInstance3D] = []
		for variant in buckets[key]:
			fields.append(_make_field(_meshes[variant], buckets[key][variant], 0.8, 1.25))
		_cells[key] = {"at": _centre_of(key), "fields": fields, "grass": []}

	if undergrowth:
		_add_undergrowth(placed)
	if floor_layer:
		_add_floor(placed)


func update(eye: Vector3) -> void:
	visible_now = 0
	var margin := CELL * 0.71
	for key in _cells:
		var at: Vector3 = _cells[key]["at"]
		var away := Vector2(at.x - eye.x, at.z - eye.z).length() - margin
		var showing := away < cull
		for field in _cells[key]["fields"]:
			field.visible = showing
			if showing:
				visible_now += field.multimesh.instance_count
		var grass_showing := away < grass_range
		for field in _cells[key]["grass"]:
			field.visible = grass_showing
			if grass_showing:
				visible_now += field.multimesh.instance_count


## СКОЛЬКО ВИДНО — число, которым меряется «ощущение чащи». Из точки наблюдателя пускаем
## лучи по кругу и смотрим, на каком расстоянии первый ствол. Медиана этого расстояния и
## есть ответ на вопрос «лес или парк»: в лесу видно на десятки метров, в парке — на сотни.
##
## Считается по положениям стволов, а не физикой: у MultiMesh коллизии нет вовсе, и заводить
## её ради замера значило бы менять предмет измерения.
func sight(eye: Vector3, rays := 72) -> float:
	var found: Array[float] = []
	for i in rays:
		var angle := TAU * float(i) / rays
		var direction := Vector2(cos(angle), sin(angle))
		var nearest := cull
		for key in _cells:
			for field in _cells[key]["fields"]:
				var multi: MultiMesh = field.multimesh
				for j in multi.instance_count:
					var at := multi.get_instance_transform(j).origin
					var to_trunk := Vector2(at.x - eye.x, at.z - eye.z)
					var along := to_trunk.dot(direction)
					if along <= 0.5 or along >= nearest:
						continue
					# Ствол считаем цилиндром радиусом в четверть метра.
					var across := to_trunk.x * direction.y - to_trunk.y * direction.x
					if absf(across) < 0.5:
						nearest = along
		found.append(nearest)
	found.sort()
	return found[found.size() / 2]


func cells() -> int:
	return _cells.size()


## ПЛОТНОСТЬ В ТОЧКЕ. Без полян — ровное поле; с полянами — шум, поднятый в степень, чтобы
## пустые места были действительно пустыми, а не «чуть реже».
func _density_at(x: float, z: float) -> float:
	if not clearings:
		return 0.72 * density
	var value := _noise.get_noise_2d(x, z) * 0.5 + 0.5
	return pow(value, 1.7) * 1.6 * density


## ПОДЛЕСОК. Кусты ставятся у стволов и в полутени, а не на полянах: под пологом леса
## подрост и есть то, что заполняет промежутки между взрослыми деревьями.
func _add_undergrowth(near: Array[Vector3]) -> void:
	var by_cell := {}
	for spot in near:
		if _random.randf() > 0.9:
			continue
		for j in _random.randi_range(2, 5):
			var angle := _random.randf_range(0.0, TAU)
			var away := _random.randf_range(1.5, 7.0)
			var x := spot.x + cos(angle) * away
			var z := spot.z + sin(angle) * away
			var key := Vector2i(int(floor(x / CELL)), int(floor(z / CELL)))
			if not by_cell.has(key):
				by_cell[key] = []
			by_cell[key].append(Vector3(x, _ground.height(x, z), z))
			bushes += 1
	for key in by_cell:
		var mesh := _bush_meshes[_random.randi() % BUSHES]
		_cell_at(key)["fields"].append(_make_field(mesh, by_cell[key], 0.7, 1.6))


## НАПОЧВЕННЫЙ ЯРУС И ВАЛЕЖНИК. Трава ковром между стволами, брёвна и пни редко.
##
## Трава кладётся в СВОИ списки со своей дальностью отсечения — втрое меньшей, чем у
## деревьев. Иначе платишь за то, что всё равно мельче пикселя, и получаешь мерцание в
## придачу.
##
## Валежник — это «история». Лес, где ничего никогда не падало, выглядит расставленным, а
## не выросшим; одно бревно на семь деревьев меняет впечатление непропорционально цене.
func _add_floor(near: Array[Vector3]) -> void:
	var grass_cells := {}
	var dead_cells := {}
	var half := area * 0.5
	for i in int(area * area * 0.6 * grass_density):
		var x := _random.randf_range(-half, half)
		var z := _random.randf_range(-half, half)
		# Трава гуще там, где реже деревья: под сомкнутым пологом ей не хватает света. Та
		# же карта плотности, прочитанная наоборот, — и ярусы сразу связаны друг с другом.
		if _random.randf() > 1.15 - _density_at(x, z) * 0.75:
			continue
		var key := Vector2i(int(floor(x / CELL)), int(floor(z / CELL)))
		if not grass_cells.has(key):
			grass_cells[key] = []
		grass_cells[key].append(Vector3(x, _ground.height(x, z), z))
		grass += 1
	for spot in near:
		if _random.randf() > 0.14:
			continue
		var angle := _random.randf_range(0.0, TAU)
		var away := _random.randf_range(1.0, 6.0)
		var x := spot.x + cos(angle) * away
		var z := spot.z + sin(angle) * away
		var key := Vector2i(int(floor(x / CELL)), int(floor(z / CELL)))
		if not dead_cells.has(key):
			dead_cells[key] = []
		dead_cells[key].append(Vector3(x, _ground.height(x, z), z))
		deadwood += 1
	for key in dead_cells:
		var mesh := _dead_meshes[_random.randi() % DEAD]
		_cell_at(key)["fields"].append(_make_field(mesh, dead_cells[key], 0.7, 1.4))
	for key in grass_cells:
		var mesh := _grass_meshes[_random.randi() % GRASSES]
		var field := _make_field(mesh, grass_cells[key], 0.8, 1.8)
		field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_cell_at(key)["grass"].append(field)


func _centre_of(key: Vector2i) -> Vector3:
	return Vector3((key.x + 0.5) * CELL, 0.0, (key.y + 0.5) * CELL)


func _cell_at(key: Vector2i) -> Dictionary:
	if not _cells.has(key):
		_cells[key] = {"at": _centre_of(key), "fields": [], "grass": []}
	return _cells[key]


func _make_field(
		mesh: ArrayMesh, spots: Array, low: float, high: float) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	# Данные экземпляра нужны ради ФАЗЫ ветра: без неё весь лес качается синхронно.
	multi.use_custom_data = true
	multi.mesh = mesh
	multi.instance_count = spots.size()
	for i in spots.size():
		var scale := _random.randf_range(low, high)
		var basis := Basis(Vector3.UP, _random.randf_range(0.0, TAU)).scaled(
				Vector3(scale, scale, scale))
		multi.set_instance_transform(i, Transform3D(basis, spots[i]))
		multi.set_instance_custom_data(
				i, Color(_random.randf(), _random.randf(), 0.0, 0.0))
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	instance.material_override = _material
	# Тени от каждого дерева стоят дороже самого дерева; на лоу-поли лесу хватает
	# затенения кроной по нормали, а тени оставлены только ближним.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_root.add_child(instance)
	return instance
