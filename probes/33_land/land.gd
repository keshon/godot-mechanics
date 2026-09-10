class_name LandBench
extends Node3D
## 33 — РЕЛЬЕФ КАК ИСТОЧНИК ИМПУЛЬСА
##
## 32-я проба кончилась выводом: пока трасса плоская, скольжение — украшение. Терять
## скорость оно умеет, набирать — нет. В Tribes скорость даёт СКЛОН, и оттуда же берётся
## навык: маршрут через карту становится решением, а не дорогой.
##
## Значит вопрос пробы такой: **что стоит рельеф и что он даёт.**
##
##   1  шум fBm            иначе плоскость
##   2  гребни             ridged вместо fBm: горы, а не холмы
##   3  искажение области  domain warp — складки и промоины
##   4  LOD по расстоянию  дальние чанки грубее
##   5  юбки на швах       вертикальный бортик, закрывающий щель между LOD
##   6  коллизия вблизи    HeightMapShape3D только рядом с игроком
##   7  раскраска          трава/камень/снег по уклону и высоте
##   8  лыжи               на склоне трения нет
##   9  джетпак            меняет скорость обратно на высоту

@export var use_fbm := true
@export var use_ridged := false
@export var use_warp := true
@export var use_lod := true
@export var use_skirt := true
@export var near_collision := true
@export var use_paint := true

@export_group("Форма")
@export_range(8.0, 64.0) var chunk_size := 32.0
## Чанков по стороне. Девять на девять — это 288 метров, на которых уже видно и горизонт,
## и цену LOD.
@export_range(3, 15) var grid := 9
## Ячеек на сторону чанка при LOD 0. Вершин будет на одну больше.
@export_range(8, 64) var resolution := 32
@export_range(5.0, 120.0) var amplitude := 45.0
@export var frequency := 0.0035
@export_range(1, 8) var octaves := 5
@export_range(0.0, 60.0) var warp_amount := 24.0
@export_range(0.2, 4.0) var skirt_depth := 1.6

var chunks := 0
var tris := 0
var solid := 0
var build_ms := 0.0
var frame_ms := 0.0
var gpu_ms := 0.0
var cpu_ms := 0.0

var _noise := FastNoiseLite.new()
var _warp := FastNoiseLite.new()
## Каждый: {body, mesh, collider, at, lod}.
var _tiles: Array[Dictionary] = []
var _material: ShaderMaterial

@onready var _skier: LandSkier = $Skier
@onready var _label: RichTextLabel = $Ui/Label


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = load("res://probes/33_land/land.gdshader")
	# Просим движок мерить время отрисовки отдельно. `delta` — это ВЕСЬ кадр, вместе с
	# ожиданием vsync: при мониторе на 200 Гц он покажет ровно 5.0 мс, чем бы сцена ни
	# была занята, и цену работы по нему прочитать нельзя. Урок 23-й пробы.
	RenderingServer.viewport_set_measure_render_time(
			get_viewport().get_viewport_rid(), true)
	_tune_noise()
	_build()
	_drop_player()


func _process(delta: float) -> void:
	frame_ms = lerpf(frame_ms, delta * 1000.0, 0.08)
	var viewport := get_viewport().get_viewport_rid()
	gpu_ms = lerpf(
			gpu_ms, RenderingServer.viewport_get_measured_render_time_gpu(viewport), 0.08)
	cpu_ms = lerpf(
			cpu_ms, RenderingServer.viewport_get_measured_render_time_cpu(viewport), 0.08)
	_refresh(false)
	_draw_hud()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var redo := false
	match event.physical_keycode:
		KEY_1:
			use_fbm = not use_fbm
			redo = true
		KEY_2:
			use_ridged = not use_ridged
			redo = true
		KEY_3:
			use_warp = not use_warp
			redo = true
		KEY_4:
			use_lod = not use_lod
			redo = true
		KEY_5:
			use_skirt = not use_skirt
			redo = true
		KEY_6:
			near_collision = not near_collision
			redo = true
		KEY_7:
			use_paint = not use_paint
		KEY_8:
			_skier.skiing_on = not _skier.skiing_on
		KEY_9:
			_skier.jet_on = not _skier.jet_on
		KEY_0:
			use_fbm = true
			use_warp = true
			use_lod = true
			use_skirt = true
			near_collision = true
			use_paint = true
			_skier.skiing_on = true
			_skier.jet_on = true
			redo = true
		KEY_EQUAL, KEY_PLUS:
			amplitude = minf(amplitude + 10.0, 120.0)
			redo = true
		KEY_MINUS:
			amplitude = maxf(amplitude - 10.0, 5.0)
			redo = true
		KEY_R:
			_drop_player()
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if redo:
		_tune_noise()
		_build()
		_drop_player()


## ВЫСОТА В ТОЧКЕ. Единственный источник правды: и меш, и коллизия, и лыжник спрашивают
## одну и ту же функцию. Разъедься они — рельеф начнёт врать физике, и ошибки не будет.
func height_at(x: float, z: float) -> float:
	if not use_fbm and not use_ridged:
		return 0.0
	var sample_x := x
	var sample_z := z
	if use_warp:
		# ИСКАЖЕНИЕ ОБЛАСТИ: не «шум поверх шума», а сдвиг самих координат перед выборкой.
		# Отсюда складки и промоины — линии перестают быть прямыми, потому что кривой
		# стала сама сетка, по которой их считают.
		sample_x += _warp.get_noise_2d(x, z) * warp_amount
		sample_z += _warp.get_noise_2d(x + 411.0, z - 187.0) * warp_amount
	var height := _noise.get_noise_2d(sample_x, sample_z)
	if use_ridged:
		# Ridged в Godot даёт −1…1 со сдвинутым нулём.
		height = height * 0.5 + 0.5
	return height * amplitude


## Нормаль считается АНАЛИТИЧЕСКИ из той же функции высоты, а не усреднением
## треугольников. Иначе она зависит от LOD: на грубом чанке нормали грубее, и один и тот
## же склон светится по-разному в зависимости от расстояния до игрока.
func normal_at(x: float, z: float) -> Vector3:
	var step := 0.6
	var slope_x := height_at(x + step, z) - height_at(x - step, z)
	var slope_z := height_at(x, z + step) - height_at(x, z - step)
	return Vector3(-slope_x, 2.0 * step, -slope_z).normalized()


## Весь фрактал берётся у движка. FastNoiseLite умеет и октавы, и гребни, и искажение
## области — писать это руками значило бы прятать Godot, а не показывать его.
func _tune_noise() -> void:
	_noise.seed = 20260901
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = frequency
	if use_ridged:
		_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	elif use_fbm:
		_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	else:
		_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	_noise.fractal_octaves = octaves
	_noise.fractal_lacunarity = 2.05
	_noise.fractal_gain = 0.47
	_warp.seed = 771
	_warp.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_warp.frequency = frequency * 0.6


func _build() -> void:
	var started := Time.get_ticks_usec()
	for tile in _tiles:
		tile["body"].queue_free()
	_tiles.clear()
	chunks = 0
	tris = 0
	var half := (grid - 1) * 0.5
	for row in grid:
		for column in grid:
			var at := Vector3(
					(column - half) * chunk_size, 0.0, (row - half) * chunk_size)
			var body := StaticBody3D.new()
			body.position = at
			var mesh := MeshInstance3D.new()
			mesh.material_override = _material
			body.add_child(mesh)
			var collider := CollisionShape3D.new()
			body.add_child(collider)
			add_child(body)
			_tiles.append({
				"body": body, "mesh": mesh, "collider": collider, "at": at, "lod": -1,
			})
			chunks += 1
	_refresh(true)
	build_ms = (Time.get_ticks_usec() - started) / 1000.0


## Пересборка того, что изменилось. Чанк перестраивается ТОЛЬКО при смене LOD — иначе
## каждый кадр уходил бы на генерацию восьмидесяти одного меша.
func _refresh(force: bool) -> void:
	var eye := _skier.global_position
	tris = 0
	solid = 0
	for tile in _tiles:
		var at: Vector3 = tile["at"]
		var away := Vector2(at.x - eye.x, at.z - eye.z).length()
		var lod := 0
		if use_lod:
			if away > chunk_size * 3.5:
				lod = 2
			elif away > chunk_size * 1.6:
				lod = 1
		if force or tile["lod"] != lod:
			tile["lod"] = lod
			_mesh_tile(tile, lod)
		# ИМЕННО index_len: `surface_get_array_len` возвращает число ВЕРШИН, и счётчик
		# треугольников молча показывал бы чужую величину.
		var mesh: MeshInstance3D = tile["mesh"]
		var built: ArrayMesh = mesh.mesh
		tris += built.surface_get_array_index_len(0) / 3
		# КОЛЛИЗИЯ ТОЛЬКО ВБЛИЗИ. Игрок физически не может коснуться дальнего чанка, а
		# HeightMapShape3D на весь мир — это восемьдесят одна форма по тысяче с лишним
		# точек.
		var collider: CollisionShape3D = tile["collider"]
		var wanted := (not near_collision) or away < chunk_size * 2.2
		if wanted and collider.shape == null:
			collider.shape = _collision_for(at)
			# МАСШТАБ СТАВИТСЯ ЗДЕСЬ ЖЕ. Он стоял отдельно, в `_process`, то есть новая
			# форма один кадр жила с масштабом 1 вместо метра на клетку — искажённая в
			# тридцать два раза поверхность, которая ВЫБРАСЫВАЛА игрока. В логе это
			# выглядело как прыжок с 22 м на 42 м и падение под рельеф; ни ошибки, ни
			# предупреждения.
			collider.scale = Vector3.ONE * (chunk_size / float(resolution))
		elif not wanted and collider.shape != null:
			collider.shape = null
		if collider.shape != null:
			solid += 1


func _mesh_tile(tile: Dictionary, lod: int) -> void:
	var step := 1 << lod
	# Ячеек по стороне.
	var cells := resolution / step
	var cell := chunk_size / float(cells)
	var at: Vector3 = tile["at"]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var index := PackedInt32Array()
	var side := cells + 1
	for row in side:
		for column in side:
			var local_x := -chunk_size * 0.5 + column * cell
			var local_z := -chunk_size * 0.5 + row * cell
			var world_x := at.x + local_x
			var world_z := at.z + local_z
			verts.append(Vector3(local_x, height_at(world_x, world_z), local_z))
			norms.append(normal_at(world_x, world_z))
			uvs.append(Vector2(world_x, world_z) * 0.05)
	for row in cells:
		for column in cells:
			var corner := row * side + column
			# ОБХОД. Godot отсекает задние грани по часовой стрелке; при обратном порядке
			# рельеф исправной формы просто не виден сверху — чёрный провал без единой
			# ошибки, а видны только юбки, у которых обход случайно оказался другим.
			index.append_array([
				corner, corner + 1, corner + side,
				corner + 1, corner + side + 1, corner + side,
			])
	if use_skirt:
		_add_skirt(verts, norms, uvs, index, side, cells)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = index
	var built := ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mesh: MeshInstance3D = tile["mesh"]
	mesh.mesh = built


## ЮБКА. Соседние чанки с разным LOD стоят на общей границе, но берут высоту в РАЗНЫХ
## точках: грубый пропускает промежуточные вершины, и между ними появляется щель, сквозь
## которую видно небо. Сшивать сетки честно — дорого и муторно; вертикальный бортик по
## краю чанка закрывает щель целиком и стоит один ряд треугольников.
func _add_skirt(
		verts: PackedVector3Array,
		norms: PackedVector3Array,
		uvs: PackedVector2Array,
		index: PackedInt32Array,
		side: int,
		cells: int) -> void:
	_skirt_strip(verts, norms, uvs, index, side, cells, 0, 1, 1)
	_skirt_strip(verts, norms, uvs, index, side, cells, cells * side, 1, 0)
	_skirt_strip(verts, norms, uvs, index, side, cells, 0, side, 0)
	_skirt_strip(verts, norms, uvs, index, side, cells, cells, side, 1)


func _skirt_strip(
		verts: PackedVector3Array,
		norms: PackedVector3Array,
		uvs: PackedVector2Array,
		index: PackedInt32Array,
		side: int,
		cells: int,
		start: int,
		stride: int,
		flip: int) -> void:
	var first := verts.size()
	for k in side:
		var edge := start + k * stride
		var top: Vector3 = verts[edge]
		verts.append(Vector3(top.x, top.y - skirt_depth, top.z))
		norms.append(norms[edge])
		uvs.append(uvs[edge])
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


## КОЛЛИЗИЯ. HeightMapShape3D — родная форма Godot под рельеф: она хранит только высоты
## и пересекается с лучом почти даром, в отличие от полигонального супа из того же меша.
##
## Ловушка в шаге: форма считает расстояние между соседними точками равным ЕДИНИЦЕ и
## центрируется в нуле. Чтобы клетка стала 1 метр при чанке 32 и сетке 32, шаг совпал
## случайно; при любом другом соотношении форму надо масштабировать — и тогда высоты
## приходится делить на тот же коэффициент, иначе рельеф под ногами не совпадёт с видимым.
func _collision_for(at: Vector3) -> HeightMapShape3D:
	var side := resolution + 1
	var cell := chunk_size / float(resolution)
	var data := PackedFloat32Array()
	data.resize(side * side)
	for row in side:
		for column in side:
			var world_x := at.x - chunk_size * 0.5 + column * cell
			var world_z := at.z - chunk_size * 0.5 + row * cell
			data[row * side + column] = height_at(world_x, world_z) / cell
	var shape := HeightMapShape3D.new()
	shape.map_width = side
	shape.map_depth = side
	shape.map_data = data
	return shape


func _drop_player() -> void:
	_skier.global_position = Vector3(0.0, height_at(0.0, 0.0) + 2.0, 0.0)
	_skier.velocity = Vector3.ZERO


func _row(on: bool, key: String, text: String) -> String:
	var tint := "88ff99" if on else "666666"
	return "[color=#%s]%s\t%s[/color]\n" % [tint, key, text]


func _draw_hud() -> void:
	var at := _skier.global_position
	var normal := normal_at(at.x, at.z)
	var text := "[font_size=34][b]%.1f[/b][/font_size] м/с   " % _skier.speed
	text += "высота [b]%.0f[/b] м   уклон %.0f°\n" % [
		at.y, rad_to_deg(acos(clampf(normal.y, -1.0, 1.0)))]
	var energy := _skier.energy
	text += "%s   энергия [color=#%s]%s[/color] %.0f\n" % [
		"[color=#66ccff]НА ЛЫЖАХ[/color]" if _skier.skiing else "пешком",
		"ffcc55" if _skier.jetting else "667788",
		"".rpad(int(energy / 5.0), "|").rpad(20, "."), energy]
	text += "чанков %d   треугольников %d   с коллизией %d   сборка %.0f мс   " % [
		chunks, tris, solid, build_ms]
	text += "отрисовка %.2f мс (GPU) + %.2f (CPU)   кадр %.2f\n\n" % [
		gpu_ms, cpu_ms, frame_ms]
	text += _row(use_fbm, "1", "шум fBm, октав %d" % octaves)
	text += _row(use_ridged, "2", "гребни (ridged): горы вместо холмов")
	text += _row(use_warp, "3", "искажение области: складки и промоины")
	text += _row(use_lod, "4", "LOD по расстоянию")
	text += _row(use_skirt, "5", "юбки на швах между LOD")
	text += _row(near_collision, "6", "коллизия только вблизи")
	text += _row(use_paint, "7", "раскраска по уклону и высоте")
	text += _row(_skier.skiing_on, "8", "лыжи: на склоне трения нет")
	text += _row(_skier.jet_on, "9", "джетпак: скорость обратно в высоту")
	text += "\n[b]ПРОБЕЛ (держать) — лыжи   SHIFT или ПКМ (держать) — джетпак[/b]\n"
	text += "WASD — руль   CTRL — лыжи всё время   R — на вершину   ESC — мышь\n"
	text += "1…9 — слои   0 — включить всё   +/− — амплитуда %.0f м\n" % amplitude
	text += "[color=#66ccff]съехал — разогнался — поддал джетом — улетел дальше[/color]"
	_label.text = text
	_material.set_shader_parameter("paint", 1.0 if use_paint else 0.0)
	_material.set_shader_parameter("amplitude", amplitude)
