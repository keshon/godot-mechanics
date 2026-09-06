extends RefCounted
class_name DetailGround

## ЗЕМЛЯ И ТЕКСТУРЫ. Тут нет ни стриминга, ни уровней детализации — тридцать четвёртая проба
## про это уже ответила. Здесь один кусок в 256 метров с шагом в метр, и весь вопрос в том,
## **что происходит на его поверхности между вершинами.**
##
## Ассетов по-прежнему нет: карта нормалей и макро-вариация считаются кодом при загрузке.
## Это не только ради самодостаточности — так видно, из чего они сделаны.
##
## МИП-УРОВНИ ОБЯЗАТЕЛЬНЫ. Текстура без них на дальних пикселях выбирается в случайных
## точках, и картинка кипит при малейшем движении камеры. С ними видеокарта усредняет сама.
## Но для КАРТЫ НОРМАЛЕЙ мипы решают не всё: усреднённая нормаль плоская, а блик от неё —
## нет, и мерцание бликов остаётся. Именно поэтому деталь всё равно приходится гасить с
## расстоянием, и именно это проба и меряет.

const SIZE := 256.0
const CELLS := 256
const TEX := 256

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
	# Мелкий шум для карты нормалей — намеренно высокочастотный: это «камешки и трава»,
	# то, чего в вершинах никогда не будет.
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
	var d := 0.5
	return Vector3(height(x - d, z) - height(x + d, z), 2.0 * d,
		height(x, z - d) - height(x, z + d)).normalized()


func _build_mesh() -> void:
	var cell := SIZE / float(CELLS)
	var side := CELLS + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for j in side:
		for i in side:
			var x := -SIZE * 0.5 + i * cell
			var z := -SIZE * 0.5 + j * cell
			verts.append(Vector3(x, height(x, z), z))
			norms.append(normal_at(x, z))
			uvs.append(Vector2(x, z))
	for j in CELLS:
		for i in CELLS:
			var a := j * side + i
			idx.append_array([a, a + 1, a + side, a + 1, a + side + 1, a + side])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	tris = idx.size() / 3


## КАРТА НОРМАЛЕЙ ИЗ ВЫСОТ. Считается ровно так же, как нормаль рельефа — разностью
## соседей, — только высоты тут мелкие и частые. Кодируется в цвет: −1…1 в 0…1.
##
## Тайл замкнут по краям (выборка шума по кругу), иначе на стыках повторов пойдёт шов,
## который куда заметнее самого повтора.
func _bake_detail() -> void:
	# RGBA, а не RGB: в альфе едет ВЫСОТА. Первая версия хранила только нормаль, а параллакс
	# маршировал по каналу `.z` — то есть по вертикальной составляющей нормали, которая почти
	# постоянна. Цикл выходил на первом шаге, и параллакса не было вовсе.
	var img := Image.create_empty(TEX, TEX, true, Image.FORMAT_RGBA8)
	var h := PackedFloat32Array()
	h.resize(TEX * TEX)
	var r := float(TEX) / TAU
	for j in TEX:
		for i in TEX:
			var a := float(i) / TEX * TAU
			var b := float(j) / TEX * TAU
			# бесшовность: координата берётся с окружности, а не с отрезка
			h[j * TEX + i] = _fine.get_noise_3d(cos(a) * r, sin(a) * r, cos(b) * r)
	for j in TEX:
		for i in TEX:
			var l := h[j * TEX + posmod(i - 1, TEX)]
			var rr := h[j * TEX + posmod(i + 1, TEX)]
			var u := h[posmod(j - 1, TEX) * TEX + i]
			var d := h[posmod(j + 1, TEX) * TEX + i]
			# Вертикальная составляющая маленькая НАМЕРЕННО: чем она меньше, тем круче
			# склоны в карте нормалей. При 0.6 разности шума давали наклон градусов в
			# девять, и деталь на земле была почти не видна — гладкий пластик.
			var n := Vector3(l - rr, 0.12, u - d).normalized()
			img.set_pixel(i, j, Color(n.x * 0.5 + 0.5, n.z * 0.5 + 0.5, n.y * 0.5 + 0.5,
				h[j * TEX + i] * 0.5 + 0.5))
	img.generate_mipmaps()
	detail_tex = ImageTexture.create_from_image(img)


## СЛОИ МАТЕРИАЛА — НАСТОЯЩИМИ ТЕКСТУРАМИ, а не плоскими цветами.
##
## Первая версия смешивала четыре константы, и замер честно показал ноль миллисекунд: я
## мерил стоимость того, чего не построил. Слои дороги ровно потому, что каждый — это
## выборка (а в игре три: цвет, нормаль, шероховатость), и стоимость растёт с их числом.
##
## Массив текстур, а не четыре отдельных: одна привязка вместо четырёх, и индекс слоя
## становится обычным числом — можно выбирать слои в цикле.
func _bake_layers() -> void:
	var tint := [Color(0.24, 0.34, 0.15), Color(0.47, 0.43, 0.24),
		Color(0.33, 0.31, 0.30), Color(0.66, 0.60, 0.42)]
	var grain := [0.32, 0.26, 0.5, 0.14]
	var imgs: Array[Image] = []
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 4
	var side := 1024
	var r := float(side) / TAU
	for k in 4:
		n.seed = 1000 + k * 37
		n.frequency = 0.06 + k * 0.02
		var img := Image.create_empty(side, side, false, Image.FORMAT_RGB8)
		for j in side:
			for i in side:
				var a := float(i) / side * TAU
				var b := float(j) / side * TAU
				var v: float = n.get_noise_3d(cos(a) * r, sin(a) * r, cos(b) * r)
				var c: Color = tint[k] * (1.0 + v * grain[k])
				img.set_pixel(i, j, c)
		imgs.append(img)
	for px in [1024, 512, 128]:
		var arr: Array[Image] = []
		for img in imgs:
			var c := img.duplicate() as Image
			if px != side:
				c.resize(px, px, Image.INTERPOLATE_LANCZOS)
			c.generate_mipmaps()
			arr.append(c)
		var t := Texture2DArray.new()
		t.create_from_images(arr)
		layers_by_size[px] = t
	set_layer_size(layer_size)


## Мегабайты, которые слои занимают в памяти видеокарты. Именно это число, а не количество
## строк в шейдере, определяет, дорогой у тебя рельеф или нет.
func layer_mb() -> float:
	return 4.0 * float(layer_size * layer_size) * 3.0 * 1.33 / 1048576.0


func set_layer_size(px: int) -> void:
	layer_size = px
	layers_tex = layers_by_size[px]


func _bake_macro() -> void:
	var img := Image.create_empty(TEX, TEX, true, Image.FORMAT_R8)
	for j in TEX:
		for i in TEX:
			var v := _macro.get_noise_2d(i * 4.0, j * 4.0) * 0.5 + 0.5
			img.set_pixel(i, j, Color(v, 0.0, 0.0))
	img.generate_mipmaps()
	macro_tex = ImageTexture.create_from_image(img)
