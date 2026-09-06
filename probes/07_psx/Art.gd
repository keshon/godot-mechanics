extends RefCounted

## ТЕКСТУРЫ И ПРЕДМЕТЫ ЭПОХИ.
##
## Первая версия пробы обходилась одной шахматкой. Как испытательная поверхность она честна —
## перспективная коррекция невидима на плоском цвете и неотвратима на сетке, — но сцену из
## неё игрок не опознаёт: «сложно воспринимать как графику времён PSX, там были какие-никакие
## объекты со своими пиксельными текстурами». Верно, и это не придирка к сцене: **половина
## узнаваемости эпохи живёт в текстурах, а не в артефактах растеризатора.**
##
## Что здесь имитируется, помимо размера:
##
## ПАЛИТРА. Текстуры PSX были палитровыми: 4 бита — шестнадцать цветов, 8 бит — двести
## пятьдесят шесть. Это не мелочь: ограниченная палитра заставляет художника рисовать
## КОНТРАСТОМ, а не оттенками, и отсюда характерная плакатность.
##
## РАЗМЕР. 64×64 — рабочий размер той эпохи, 256×256 предел. При этом текстура растягивалась
## на целую стену, поэтому тексель был крупным и его было видно. Это и есть «пиксельная
## текстура»: не стилизация, а следствие бюджета видеопамяти в мегабайт.

const SIZE := 64


static func _quantise(c: Color, levels: int) -> Color:
	var s := float(levels - 1)
	return Color(round(c.r * s) / s, round(c.g * s) / s, round(c.b * s) / s)


static func _tex(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)


## КИРПИЧ. Ряды со смещением через один, шов между ними, и разброс тона на каждый кирпич —
## без разброса стена читается обоями, потому что настоящая кладка никогда не одноцветна.
static func brick(rng: RandomNumberGenerator) -> ImageTexture:
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var course := 8
	var mortar := Color(0.42, 0.40, 0.37)
	for y in SIZE:
		var row := y / course
		var shift := 0 if row % 2 == 0 else 8
		for x in SIZE:
			var bx := (x + shift) % 16
			var c: Color
			if y % course < 1 or bx < 1:
				c = mortar
			else:
				var t := rng.randf_range(-0.09, 0.09)
				c = Color(0.52 + t, 0.30 + t * 0.8, 0.24 + t * 0.7)
			img.set_pixel(x, y, _quantise(c, 16))
	return _tex(img)


## ДОСКИ. Вертикальные, с тёмным швом и продольной прожилкой. Ящик из такой текстуры
## опознаётся ящиком даже в двенадцати треугольниках — силуэт делает половину работы,
## текстура вторую.
static func planks(rng: RandomNumberGenerator) -> ImageTexture:
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for x in SIZE:
		var plank := x / 16
		var base := 0.40 + plank * 0.025 + rng.randf_range(-0.02, 0.02)
		for y in SIZE:
			var c: Color
			if x % 16 < 1:
				c = Color(0.16, 0.10, 0.06)
			else:
				var grain := sin(float(y) * 0.9 + plank * 3.0) * 0.045
				grain += rng.randf_range(-0.025, 0.025)
				# Дерево — коричневое, а не оранжевое. При шестнадцати уровнях насыщенный тон
				# уезжает в чистый оранжевый и ящик перестаёт отличаться от кирпича: узкая
				# палитра прощает контраст, но не прощает насыщенность.
				var g := base + grain
				c = Color(g, g * 0.74, g * 0.52)
			img.set_pixel(x, y, _quantise(c, 16))
	return _tex(img)


## БЕТОН. Пятна и трещина. Пятна — низкочастотный шум, трещина — ломаная линия: одна
## заметная особенность на текстуру ломает ощущение повтора сильнее, чем много мелких.
static func concrete(rng: RandomNumberGenerator, crack: bool = true) -> ImageTexture:
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var n := FastNoiseLite.new()
	n.seed = rng.randi()
	n.frequency = 0.09
	for y in SIZE:
		for x in SIZE:
			var v := n.get_noise_2d(x, y) * 0.09
			var g := 0.44 + v + rng.randf_range(-0.015, 0.015)
			img.set_pixel(x, y, _quantise(Color(g, g * 0.99, g * 0.95), 16))
	# На полу трещину отключаем. Тайл повторяется десятки раз, и одна заметная особенность,
	# размноженная сеткой, читается уже не трещиной, а узором обоев: приём, работающий на
	# отдельной стене, на большой плоскости оборачивается против себя.
	if not crack:
		return _tex(img)
	var cx := rng.randi_range(10, SIZE - 10)
	for y in SIZE:
		cx = clampi(cx + rng.randi_range(-1, 1), 1, SIZE - 2)
		for d in range(-1, 1):
			img.set_pixel(cx + d, y, _quantise(Color(0.24, 0.24, 0.23), 16))
	return _tex(img)


## МЕТАЛЛ. Панель с заклёпками по углам и полосой посередине. Заклёпки — тот самый крупный
## тексель: три пикселя на клёпку, и на стене они размером с кулак.
static func metal(rng: RandomNumberGenerator) -> ImageTexture:
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y in SIZE:
		for x in SIZE:
			var g := 0.30 + rng.randf_range(-0.02, 0.02)
			if absi(y - SIZE / 2) < 3:
				g = 0.22
			img.set_pixel(x, y, _quantise(Color(g, g * 1.02, g * 1.08), 16))
	for p in [Vector2i(6, 6), Vector2i(SIZE - 7, 6), Vector2i(6, SIZE - 7),
			Vector2i(SIZE - 7, SIZE - 7)]:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var c := Color(0.52, 0.54, 0.58) if dx + dy < 0 else Color(0.18, 0.19, 0.21)
				img.set_pixel(p.x + dx, p.y + dy, _quantise(c, 16))
	return _tex(img)


static func _mat(shader: Shader, tex: ImageTexture, scale: Vector2,
		tint: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("albedo_tex", tex)
	m.set_shader_parameter("albedo_smooth", tex)
	m.set_shader_parameter("uv_scale", scale)
	m.set_shader_parameter("tint", tint)
	return m


static func _box(world: Node3D, mat: ShaderMaterial, at: Vector3, size: Vector3,
		yaw: float = 0.0, pitch: float = 0.0) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	mi.transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), at)
	world.add_child(mi)


static func _barrel(world: Node3D, mat: ShaderMaterial, at: Vector3, yaw: float) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.42
	cm.bottom_radius = 0.42
	cm.height = 1.15
	# Восемь граней, а не тридцать: у консоли не было треугольников на круглые бока, и
	# гранёная бочка — это не упрощение ради скорости, а буквально то, что там стояло.
	cm.radial_segments = 8
	cm.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = mat
	mi.transform = Transform3D(Basis.from_euler(Vector3(0.0, yaw, 0.0)),
		at + Vector3(0.0, 0.575, 0.0))
	world.add_child(mi)


## СЦЕНА. Не бесконечная плоскость с колоннами, а закуток: арка, штабель ящиков, бочки,
## обломки. Смысл не в декоре — предметы дают глазу МАСШТАБ, без которого он не может
## оценить ни размер текселя, ни силу дрожания вершин.
static func populate(world: Node3D, shader: Shader) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 19941203      # дата выхода приставки в Японии
	var m_brick := _mat(shader, brick(rng), Vector2(4.0, 2.0), Color(1, 1, 1, 1))
	var m_wood := _mat(shader, planks(rng), Vector2(1.0, 1.0), Color(1, 1, 1, 1))
	var m_conc := _mat(shader, concrete(rng), Vector2(1.0, 1.0), Color(1, 1, 1, 1))
	var m_metal := _mat(shader, metal(rng), Vector2(1.0, 1.0), Color(1, 1, 1, 1))

	# арка в проёме
	_box(world, m_brick, Vector3(-6.0, 1.6, -9.0), Vector3(0.9, 3.2, 0.9))
	_box(world, m_brick, Vector3(-2.4, 1.6, -9.0), Vector3(0.9, 3.2, 0.9))
	_box(world, m_brick, Vector3(-4.2, 3.5, -9.0), Vector3(4.5, 0.7, 0.9))

	# штабель ящиков
	_box(world, m_wood, Vector3(3.0, 0.55, -5.5), Vector3(1.1, 1.1, 1.1), 0.2)
	_box(world, m_wood, Vector3(4.2, 0.55, -5.2), Vector3(1.1, 1.1, 1.1), -0.35)
	_box(world, m_wood, Vector3(3.4, 1.65, -5.4), Vector3(1.1, 1.1, 1.1), 0.55)
	_box(world, m_wood, Vector3(6.4, 0.55, -7.4), Vector3(1.1, 1.1, 1.1), 0.9)

	# бочки
	_barrel(world, m_metal, Vector3(1.2, 0.0, -7.6), 0.3)
	_barrel(world, m_metal, Vector3(2.0, 0.0, -8.3), 1.1)
	_barrel(world, m_metal, Vector3(-7.6, 0.0, -4.2), 2.2)

	# низкая стенка и обломки
	_box(world, m_conc, Vector3(7.5, 0.6, -1.0), Vector3(0.6, 1.2, 7.0))
	for i in 9:
		var a := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(2.0, 11.0)
		var s := rng.randf_range(0.22, 0.55)
		_box(world, m_conc, Vector3(cos(a) * r, s * 0.5, sin(a) * r - 4.0),
			Vector3(s, s * 0.7, s * 1.3), rng.randf_range(0.0, TAU),
			rng.randf_range(-0.3, 0.3))
