class_name DetailGround
extends RefCounted
## ЗЕМЛЯ И ТЕКСТУРЫ. Тут нет ни стриминга, ни уровней детализации — 34-я проба про это уже
## ответила. Здесь один кусок в 256 метров с шагом в метр, и весь вопрос в том, **что
## происходит на его поверхности между вершинами.**
##
## Ассетов по-прежнему нет: карта нормалей и макро-вариация считаются кодом при загрузке.
## Это не только ради самодостаточности — так видно, из чего они сделаны.
##
## МИП-УРОВНИ ОБЯЗАТЕЛЬНЫ. Текстура без них на дальних пикселях выбирается в случайных
## точках, и картинка кипит при малейшем движении камеры. С ними видеокарта усредняет
## сама. Но для КАРТЫ НОРМАЛЕЙ мипы решают не всё: усреднённая нормаль плоская, а блик от
## неё — нет, и мерцание бликов остаётся. Именно поэтому деталь всё равно приходится гасить
## с расстоянием, и именно это проба и меряет.

const SIZE := 256.0
const CELLS := 256
## Сторона запекаемых карт нормали и макро-вариации, тексели.
const TEXTURE_SIZE := 256
## Сторона слоя материала до уменьшения, тексели.
const LAYER_SIZE := 1024
const LAYER_SIZES := [1024, 512, 128]

var mesh: ArrayMesh
var detail_tex: ImageTexture
var macro_tex: ImageTexture
## Три разрешения одной и той же карты слоёв. Содержимое идентично — крупная печётся один
## раз, мелкие получаются уменьшением, — поэтому сравнение показывает РОВНО размер, а не
## разную картинку.
var layers_by_size := {}
var layer_size := 128
var layers_tex: Texture2DArray
var tris := 0

var _shape := FastNoiseLite.new()
var _fine := FastNoiseLite.new()
var _macro := FastNoiseLite.new()


func _init() -> void:
	_shape.seed = 90210
	_shape.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_shape.frequency = 0.006
	_shape.fractal_type = FastNoiseLite.FRACTAL_FBM
	_shape.fractal_octaves = 5
	# Мелкий шум для карты нормалей — намеренно высокочастотный: это «камешки и трава», то,
	# чего в вершинах никогда не будет.
	_fine.seed = 4242
	_fine.noise_type = FastNoiseLite.TYPE_SIMPLEX
	# 0.035, а не 0.09. Параллакс читается на КРУПНЫХ формах: он смещает выборку, а если
	# рельеф мельче пикселя, смещать нечего — эффект есть в числах и невидим глазу. Мелкая
	# рябь при этом никуда не делась, она живёт в старших октавах.
	_fine.frequency = 0.035
	_fine.fractal_type = FastNoiseLite.FRACTAL_FBM
	_fine.fractal_octaves = 5
	# Макро-вариация — наоборот, очень низкочастотная. Её работа: сломать видимый повтор
	# тайла. Тайл размером в метр повторяется каждый метр, и глаз ловит решётку мгновенно;
	# умножение на плавное пятно с периодом в десятки метров решётку разбивает.
	_macro.seed = 777
	_macro.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_macro.frequency = 0.011
	_build_mesh()
	_bake_detail()
	_bake_macro()
	_bake_layers()


func height(x: float, z: float) -> float:
	return _shape.get_noise_2d(x, z) * 22.0


func normal_at(x: float, z: float) -> Vector3:
	var step := 0.5
	return Vector3(
			height(x - step, z) - height(x + step, z),
			2.0 * step,
			height(x, z - step) - height(x, z + step)).normalized()


func set_layer_size(pixels: int) -> void:
	layer_size = pixels
	layers_tex = layers_by_size[pixels]


## Мегабайты, которые слои занимают в памяти видеокарты. Именно это число, а не количество
## строк в шейдере, определяет, дорогой у тебя рельеф или нет.
func layer_mb() -> float:
	return 4.0 * float(layer_size * layer_size) * 3.0 * 1.33 / 1048576.0


func _build_mesh() -> void:
	var cell := SIZE / float(CELLS)
	var side := CELLS + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var index := PackedInt32Array()
	for row in side:
		for column in side:
			var x := -SIZE * 0.5 + column * cell
			var z := -SIZE * 0.5 + row * cell
			verts.append(Vector3(x, height(x, z), z))
			norms.append(normal_at(x, z))
			uvs.append(Vector2(x, z))
	for row in CELLS:
		for column in CELLS:
			var corner := row * side + column
			index.append_array([
				corner, corner + 1, corner + side,
				corner + 1, corner + side + 1, corner + side,
			])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = index
	mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	tris = index.size() / 3


## КАРТА НОРМАЛЕЙ ИЗ ВЫСОТ. Считается ровно так же, как нормаль рельефа — разностью
## соседей, — только высоты тут мелкие и частые. Кодируется в цвет: −1…1 в 0…1.
##
## Тайл замкнут по краям (выборка шума по кругу), иначе на стыках повторов пойдёт шов,
## который куда заметнее самого повтора.
func _bake_detail() -> void:
	# RGBA, а не RGB: в альфе едет ВЫСОТА. Храня только нормаль, параллакс маршировал бы по
	# каналу `.z` — то есть по вертикальной составляющей нормали, которая почти постоянна:
	# цикл выходит на первом шаге, и параллакса нет вовсе.
	var image := Image.create_empty(
			TEXTURE_SIZE, TEXTURE_SIZE, true, Image.FORMAT_RGBA8)
	var heights := PackedFloat32Array()
	heights.resize(TEXTURE_SIZE * TEXTURE_SIZE)
	var radius := float(TEXTURE_SIZE) / TAU
	for row in TEXTURE_SIZE:
		for column in TEXTURE_SIZE:
			var around_x := float(column) / TEXTURE_SIZE * TAU
			var around_y := float(row) / TEXTURE_SIZE * TAU
			# Бесшовность: координата берётся с окружности, а не с отрезка.
			heights[row * TEXTURE_SIZE + column] = _fine.get_noise_3d(
					cos(around_x) * radius,
					sin(around_x) * radius,
					cos(around_y) * radius)
	for row in TEXTURE_SIZE:
		for column in TEXTURE_SIZE:
			var here := heights[row * TEXTURE_SIZE + column]
			var left := heights[row * TEXTURE_SIZE + posmod(column - 1, TEXTURE_SIZE)]
			var right := heights[row * TEXTURE_SIZE + posmod(column + 1, TEXTURE_SIZE)]
			var up := heights[posmod(row - 1, TEXTURE_SIZE) * TEXTURE_SIZE + column]
			var down := heights[posmod(row + 1, TEXTURE_SIZE) * TEXTURE_SIZE + column]
			# Вертикальная составляющая маленькая НАМЕРЕННО: чем она меньше, тем круче
			# склоны в карте нормалей. При 0.6 разности шума давали наклон градусов в
			# девять, и деталь на земле была почти не видна — гладкий пластик.
			var normal := Vector3(left - right, 0.12, up - down).normalized()
			image.set_pixel(column, row, Color(
					normal.x * 0.5 + 0.5,
					normal.z * 0.5 + 0.5,
					normal.y * 0.5 + 0.5,
					here * 0.5 + 0.5))
	image.generate_mipmaps()
	detail_tex = ImageTexture.create_from_image(image)


func _bake_macro() -> void:
	var image := Image.create_empty(TEXTURE_SIZE, TEXTURE_SIZE, true, Image.FORMAT_R8)
	for row in TEXTURE_SIZE:
		for column in TEXTURE_SIZE:
			var value := _macro.get_noise_2d(column * 4.0, row * 4.0) * 0.5 + 0.5
			image.set_pixel(column, row, Color(value, 0.0, 0.0))
	image.generate_mipmaps()
	macro_tex = ImageTexture.create_from_image(image)


## СЛОИ МАТЕРИАЛА — НАСТОЯЩИМИ ТЕКСТУРАМИ, а не плоскими цветами. Смешивание четырёх
## констант стоит ровно ноль миллисекунд: так меряется стоимость того, чего не построил.
## Слои дороги именно потому, что каждый — это выборка (а в игре три: цвет, нормаль,
## шероховатость), и стоимость растёт с их числом.
##
## Массив текстур, а не четыре отдельных: одна привязка вместо четырёх, и индекс слоя
## становится обычным числом — можно выбирать слои в цикле.
func _bake_layers() -> void:
	var tint := [
		Color(0.24, 0.34, 0.15),
		Color(0.47, 0.43, 0.24),
		Color(0.33, 0.31, 0.30),
		Color(0.66, 0.60, 0.42),
	]
	var grain := [0.32, 0.26, 0.5, 0.14]
	var baked: Array[Image] = []
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	var radius := float(LAYER_SIZE) / TAU
	for layer in 4:
		noise.seed = 1000 + layer * 37
		noise.frequency = 0.06 + layer * 0.02
		var image := Image.create_empty(
				LAYER_SIZE, LAYER_SIZE, false, Image.FORMAT_RGB8)
		for row in LAYER_SIZE:
			for column in LAYER_SIZE:
				var around_x := float(column) / LAYER_SIZE * TAU
				var around_y := float(row) / LAYER_SIZE * TAU
				var value := noise.get_noise_3d(
						cos(around_x) * radius,
						sin(around_x) * radius,
						cos(around_y) * radius)
				image.set_pixel(column, row, tint[layer] * (1.0 + value * grain[layer]))
		baked.append(image)
	for pixels in LAYER_SIZES:
		var scaled: Array[Image] = []
		for image in baked:
			var copy := image.duplicate() as Image
			if pixels != LAYER_SIZE:
				copy.resize(pixels, pixels, Image.INTERPOLATE_LANCZOS)
			copy.generate_mipmaps()
			scaled.append(copy)
		var array := Texture2DArray.new()
		array.create_from_images(scaled)
		layers_by_size[pixels] = array
	set_layer_size(layer_size)
