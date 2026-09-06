extends Node3D

## 33 — РЕЛЬЕФ КАК ИСТОЧНИК ИМПУЛЬСА
##
## Тридцать вторая проба кончилась выводом: пока трасса плоская, скольжение — украшение.
## Терять скорость оно умеет, набирать — нет. В Tribes скорость даёт СКЛОН, и оттуда же
## берётся навык: маршрут через карту становится решением, а не дорогой.
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
@export_range(8, 64) var res := 32
@export_range(5.0, 120.0) var amplitude := 45.0
@export var frequency := 0.0035
@export_range(1, 8) var octaves := 5
@export_range(0.0, 60.0) var warp_amount := 24.0
@export_range(0.2, 4.0) var skirt_depth := 1.6

var chunks := 0
var tris := 0
var solid := 0
var build_ms := 0.0
var ms_frame := 0.0
var ms_gpu := 0.0
var ms_cpu := 0.0

var _noise := FastNoiseLite.new()
var _warp := FastNoiseLite.new()
var _tiles: Array = []          # [{"body": StaticBody3D, "mi": MeshInstance3D, "cs": CollisionShape3D, "at": Vector3, "lod": int}]
var _mat: ShaderMaterial
var _player: Node3D


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://probes/33_land/land.gdshader")
	_player = $Skier
	# Просим движок мерить время отрисовки отдельно. `delta` — это ВЕСЬ кадр, вместе с
	# ожиданием vsync: при мониторе на 200 Гц он покажет ровно 5.0 мс, чем бы сцена ни
	# была занята, и цену работы по нему прочитать нельзя. Урок двадцать третьей пробы.
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_tune_noise()
	_build()
	_drop_player()


## Весь фрактал берётся у движка. FastNoiseLite умеет и октавы, и гребни, и искажение
## области — писать это руками значило бы прятать Godot, а не показывать его.
func _tune_noise() -> void:
	_noise.seed = 20260901
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = frequency
	_noise.fractal_type = (FastNoiseLite.FRACTAL_RIDGED if use_ridged
		else (FastNoiseLite.FRACTAL_FBM if use_fbm else FastNoiseLite.FRACTAL_NONE))
	_noise.fractal_octaves = octaves
	_noise.fractal_lacunarity = 2.05
	_noise.fractal_gain = 0.47
	_warp.seed = 771
	_warp.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_warp.frequency = frequency * 0.6


## ВЫСОТА В ТОЧКЕ. Единственный источник правды: и меш, и коллизия, и лыжник спрашивают
## одну и ту же функцию. Разъедься они — рельеф начнёт врать физике, и ошибки не будет.
func height_at(x: float, z: float) -> float:
	if not use_fbm and not use_ridged:
		return 0.0
	var px := x
	var pz := z
	if use_warp:
		# ИСКАЖЕНИЕ ОБЛАСТИ: не «шум поверх шума», а сдвиг самих координат перед выборкой.
		# Отсюда складки и промоины — линии перестают быть прямыми, потому что кривой стала
		# сама сетка, по которой их считают.
		px += _warp.get_noise_2d(x, z) * warp_amount
		pz += _warp.get_noise_2d(x + 411.0, z - 187.0) * warp_amount
	var h := _noise.get_noise_2d(px, pz)
	if use_ridged:
		h = h * 0.5 + 0.5      # ridged в Godot даёт −1…1 со сдвинутым нулём
	return h * amplitude


## Нормаль считается АНАЛИТИЧЕСКИ из той же функции высоты, а не усреднением треугольников.
## Иначе она зависит от LOD: на грубом чанке нормали грубее, и один и тот же склон светится
## по-разному в зависимости от расстояния до игрока.
func normal_at(x: float, z: float) -> Vector3:
	var d := 0.6
	var hx := height_at(x + d, z) - height_at(x - d, z)
	var hz := height_at(x, z + d) - height_at(x, z - d)
	return Vector3(-hx, 2.0 * d, -hz).normalized()


func _build() -> void:
	var t0 := Time.get_ticks_usec()
	for t in _tiles:
		t["body"].queue_free()
	_tiles.clear()
	chunks = 0
	tris = 0
	var half := (grid - 1) * 0.5
	for cz in grid:
		for cx in grid:
			var at := Vector3((cx - half) * chunk_size, 0.0, (cz - half) * chunk_size)
			var body := StaticBody3D.new()
			body.position = at
			var mi := MeshInstance3D.new()
			mi.material_override = _mat
			body.add_child(mi)
			var cs := CollisionShape3D.new()
			body.add_child(cs)
			add_child(body)
			_tiles.append({"body": body, "mi": mi, "cs": cs, "at": at, "lod": -1})
			chunks += 1
	_refresh(true)
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0


## Пересборка того, что изменилось. Чанк перестраивается ТОЛЬКО при смене LOD — иначе
## каждый кадр уходил бы на генерацию восьмидесяти одного меша.
func _refresh(force: bool) -> void:
	var eye: Vector3 = _player.global_position
	tris = 0
	solid = 0
	for t in _tiles:
		var d: float = Vector2(t["at"].x - eye.x, t["at"].z - eye.z).length()
		var lod := 0
		if use_lod:
			if d > chunk_size * 3.5:
				lod = 2
			elif d > chunk_size * 1.6:
				lod = 1
		if force or t["lod"] != lod:
			t["lod"] = lod
			_mesh_tile(t, lod)
		# ИМЕННО index_len: `surface_get_array_len` возвращает число ВЕРШИН, и счётчик
		# треугольников молча показывал бы чужую величину.
		tris += (t["mi"].mesh as ArrayMesh).surface_get_array_index_len(0) / 3
		# КОЛЛИЗИЯ ТОЛЬКО ВБЛИЗИ. Игрок физически не может коснуться дальнего чанка, а
		# HeightMapShape3D на весь мир — это восемьдесят одна форма по тысяче с лишним точек.
		var want := (not near_collision) or d < chunk_size * 2.2
		if want and t["cs"].shape == null:
			t["cs"].shape = _collision_for(t["at"])
			# МАСШТАБ СТАВИТСЯ ЗДЕСЬ ЖЕ. Он стоял отдельно, в `_process`, то есть новая форма
			# один кадр жила с масштабом 1 вместо метра на клетку — искажённая в тридцать два
			# раза поверхность, которая ВЫБРАСЫВАЛА игрока. В логе это выглядело как прыжок
			# с 22 м на 42 м и падение под рельеф; ни ошибки, ни предупреждения.
			t["cs"].scale = Vector3.ONE * (chunk_size / float(res))
		elif not want and t["cs"].shape != null:
			t["cs"].shape = null
		if t["cs"].shape != null:
			solid += 1


func _mesh_tile(t: Dictionary, lod: int) -> void:
	var step := 1 << lod
	var n := res / step                       # ячеек по стороне
	var cell := chunk_size / float(n)
	var at: Vector3 = t["at"]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var side := n + 1
	for j in side:
		for i in side:
			var lx := -chunk_size * 0.5 + i * cell
			var lz := -chunk_size * 0.5 + j * cell
			var wx := at.x + lx
			var wz := at.z + lz
			verts.append(Vector3(lx, height_at(wx, wz), lz))
			norms.append(normal_at(wx, wz))
			uvs.append(Vector2(wx, wz) * 0.05)
	for j in n:
		for i in n:
			var a := j * side + i
			# ОБХОД. Godot отсекает задние грани по часовой стрелке; при обратном порядке
			# рельеф исправной формы просто не виден сверху — чёрный провал без единой
			# ошибки, а видны только юбки, у которых обход случайно оказался другим.
			idx.append_array([a, a + 1, a + side, a + 1, a + side + 1, a + side])
	if use_skirt:
		_add_skirt(verts, norms, uvs, idx, side, n, cell, at)

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	t["mi"].mesh = m


## ЮБКА. Соседние чанки с разным LOD стоят на общей границе, но берут высоту в РАЗНЫХ
## точках: грубый пропускает промежуточные вершины, и между ними появляется щель, сквозь
## которую видно небо. Сшивать сетки честно — дорого и муторно; вертикальный бортик по краю
## чанка закрывает щель целиком и стоит один ряд треугольников.
func _add_skirt(verts: PackedVector3Array, norms: PackedVector3Array,
		uvs: PackedVector2Array, idx: PackedInt32Array,
		side: int, n: int, cell: float, at: Vector3) -> void:
	_skirt_strip(verts, norms, uvs, idx, side, n, 0, 1, 1)              # север
	_skirt_strip(verts, norms, uvs, idx, side, n, n * side, 1, 0)       # юг
	_skirt_strip(verts, norms, uvs, idx, side, n, 0, side, 0)           # запад
	_skirt_strip(verts, norms, uvs, idx, side, n, n, side, 1)           # восток


func _skirt_strip(verts: PackedVector3Array, norms: PackedVector3Array,
		uvs: PackedVector2Array, idx: PackedInt32Array,
		side: int, n: int, start: int, stride: int, flip: int) -> void:
	var first := verts.size()
	for k in side:
		var e := start + k * stride
		var v: Vector3 = verts[e]
		verts.append(Vector3(v.x, v.y - skirt_depth, v.z))
		norms.append(norms[e])
		uvs.append(uvs[e])
	for k in n:
		var a := start + k * stride
		var b := start + (k + 1) * stride
		var la := first + k
		var lb := first + k + 1
		if flip == 0:
			idx.append_array([a, la, b, b, la, lb])
		else:
			idx.append_array([a, b, la, b, lb, la])


## КОЛЛИЗИЯ. HeightMapShape3D — родная форма Godot под рельеф: она хранит только высоты и
## пересекается с лучом почти даром, в отличие от полигонального супа из того же меша.
##
## Ловушка в шаге: форма считает расстояние между соседними точками равным ЕДИНИЦЕ и
## центрируется в нуле. Чтобы клетка стала 1 метр при чанке 32 и сетке 32, шаг совпал
## случайно; при любом другом соотношении форму надо масштабировать — и тогда высоты
## приходится делить на тот же коэффициент, иначе рельеф под ногами не совпадёт с видимым.
func _collision_for(at: Vector3) -> HeightMapShape3D:
	var side := res + 1
	var cell := chunk_size / float(res)
	var data := PackedFloat32Array()
	data.resize(side * side)
	for j in side:
		for i in side:
			var wx := at.x - chunk_size * 0.5 + i * cell
			var wz := at.z - chunk_size * 0.5 + j * cell
			data[j * side + i] = height_at(wx, wz) / cell
	var s := HeightMapShape3D.new()
	s.map_width = side
	s.map_depth = side
	s.map_data = data
	return s


func _drop_player() -> void:
	_player.global_position = Vector3(0.0, height_at(0.0, 0.0) + 2.0, 0.0)
	_player.set("velocity", Vector3.ZERO)


func _process(delta: float) -> void:
	ms_frame = lerpf(ms_frame, delta * 1000.0, 0.08)
	var rid := get_viewport().get_viewport_rid()
	ms_gpu = lerpf(ms_gpu, RenderingServer.viewport_get_measured_render_time_gpu(rid), 0.08)
	ms_cpu = lerpf(ms_cpu, RenderingServer.viewport_get_measured_render_time_cpu(rid), 0.08)
	_refresh(false)
	_hud()


func _rebuild() -> void:
	_tune_noise()
	_build()
	_drop_player()


func _row(on: bool, key: String, text: String) -> String:
	var c := "88ff99" if on else "666666"
	return "[color=#%s]%s\t%s[/color]\n" % [c, key, text]


func _hud() -> void:
	var p := _player
	var h := height_at(p.global_position.x, p.global_position.z)
	var nrm := normal_at(p.global_position.x, p.global_position.z)
	var s := "[font_size=34][b]%.1f[/b][/font_size] м/с   высота [b]%.0f[/b] м   уклон %.0f°\n" % [
		p.get("speed"), p.global_position.y, rad_to_deg(acos(clampf(nrm.y, -1.0, 1.0)))]
	var e: float = p.get("energy")
	s += "%s   энергия [color=#%s]%s[/color] %.0f\n" % [
		"[color=#88ddff]НА ЛЫЖАХ[/color]" if p.get("skiing") else "пешком",
		"ffcc55" if p.get("jetting") else "667788",
		"".rpad(int(e / 5.0), "|").rpad(20, "."), e]
	s += "чанков %d   треугольников %d   с коллизией %d   сборка %.0f мс   отрисовка %.2f мс (GPU) + %.2f (CPU)   кадр %.2f\n\n" % [
		chunks, tris, solid, build_ms, ms_gpu, ms_cpu, ms_frame]
	s += _row(use_fbm, "1", "шум fBm, октав %d" % octaves)
	s += _row(use_ridged, "2", "гребни (ridged): горы вместо холмов")
	s += _row(use_warp, "3", "искажение области: складки и промоины")
	s += _row(use_lod, "4", "LOD по расстоянию")
	s += _row(use_skirt, "5", "юбки на швах между LOD")
	s += _row(near_collision, "6", "коллизия только вблизи")
	s += _row(use_paint, "7", "раскраска по уклону и высоте")
	s += _row(p.get("skiing_on"), "8", "лыжи: на склоне трения нет")
	s += _row(p.get("jet_on"), "9", "джетпак: скорость обратно в высоту")
	s += "\n[b]ПРОБЕЛ (держать) — лыжи   SHIFT или ПКМ (держать) — джетпак[/b]\n"
	s += "WASD — руль   CTRL — лыжи всё время   R — на вершину   ESC — мышь\n"
	s += "1…9 — слои   0 — включить всё   +/− — амплитуда %.0f м\n" % amplitude
	s += "[color=#66ccff]съехал — разогнался — поддал джетом — улетел дальше[/color]"
	($Ui/Label as RichTextLabel).text = s
	_mat.set_shader_parameter("paint", 1.0 if use_paint else 0.0)
	_mat.set_shader_parameter("amplitude", amplitude)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return
	var k := (event as InputEventKey).physical_keycode
	var redo := false
	match k:
		KEY_1: use_fbm = not use_fbm; redo = true
		KEY_2: use_ridged = not use_ridged; redo = true
		KEY_3: use_warp = not use_warp; redo = true
		KEY_4: use_lod = not use_lod; redo = true
		KEY_5: use_skirt = not use_skirt; redo = true
		KEY_6: near_collision = not near_collision; redo = true
		KEY_7: use_paint = not use_paint
		KEY_8: _player.set("skiing_on", not _player.get("skiing_on"))
		KEY_9: _player.set("jet_on", not _player.get("jet_on"))
		KEY_0:
			use_fbm = true; use_warp = true; use_lod = true; use_skirt = true
			near_collision = true; use_paint = true
			_player.set("skiing_on", true)
			_player.set("jet_on", true)
			redo = true
		KEY_EQUAL, KEY_PLUS:
			amplitude = minf(amplitude + 10.0, 120.0); redo = true
		KEY_MINUS:
			amplitude = maxf(amplitude - 10.0, 5.0); redo = true
		KEY_R: _drop_player()
		KEY_ESCAPE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if redo:
		_rebuild()
