extends Node
class_name Look
## A style is a set of constraints, not a set of assets.
##
## Every switch below removes something a modern renderer gives you for free.
## Turn them all off and this is a plain, slightly ugly Godot scene. Turn them
## on one at a time and watch which one you were actually reacting to — that is
## the whole exercise, and it is worth doing in that order rather than looking
## at the finished thing and calling it "PSX".
##
## Nothing here is nostalgia. Each constraint is a different part of the
## pipeline: the viewport, the vertex stage, the interpolator, the post pass.

const Art := preload("res://probes/07_psx/Art.gd")

@export_group("Resolution")
## How many times smaller than the window the world is actually drawn, before
## being blown up again with no smoothing. The single biggest contributor to
## the look, and the cheapest thing in the entire probe.
##
## Godot does this with SubViewportContainer.stretch_shrink rather than a fixed
## pixel size: a divisor keeps the aspect ratio honest whatever the window does.
@export_range(1, 12, 1) var shrink := 4:
	set(v):
		shrink = v
		if is_inside_tree():
			_screen.stretch_shrink = v
			# The snap grid is measured in rendered pixels, so it moves too, and the
			# scanline period is measured in window pixels per rendered row.
			_push()
			_push_post()

@export_group("Geometry")
@export var snap_vertices := true:
	set(v):
		snap_vertices = v
		_push()

## How coarse the vertex grid is, measured in rendered pixels.
##
## 1.0 is the honest setting: one step per pixel, which is all the precision
## the hardware had. That gives a wobble you notice but do not fight.
##
## The first version of this probe hard-coded the grid at 160x120 while the
## viewport was 250x140 — a step and a half per pixel, so about three times too
## much, and the floor under your feet boiled. Wrong, not stylised.
@export_range(0.25, 6.0, 0.05) var snap_coarseness := 1.0:
	set(v):
		snap_coarseness = v
		_push()

## How finely the floor is cut up.
##
## Not decoration. Affine warping is proportional to how big a triangle is on
## screen, so a seventy-metre floor made of two triangles is the worst case
## there is. Real games of the era chopped their geometry into small pieces
## precisely because of this — dense floors and sliced-up walls were the
## ARTISTS' answer to the hardware, and half of what the era looks like.
##
## Set this to 0 and the floor becomes two triangles again. That is what the
## first version of this probe shipped, and why the swim looked so unlike the
## Насколько мелко нарезан пол. Число решает БОЛЬШЕ, чем кажется: аффинное искажение
## пропорционально размеру треугольника, и при 13×13 на семьдесят метров оно выходит
## гораздо грубее, чем было на настоящей консоли. Игры эпохи резали геометрию мелко
## именно поэтому — плотные полы были ответом художников на отсутствие коррекции.
@export_range(0, 60, 1) var floor_subdivide := 30:
	set(v):
		floor_subdivide = v
		if is_inside_tree():
			var pm := ($Screen/View/World/Floor as MeshInstance3D).mesh as PlaneMesh
			pm.subdivide_width = v
			pm.subdivide_depth = v
## Textures interpolated without perspective correction — the swim.
@export var affine_uv := true:
	set(v):
		affine_uv = v
		_push()

## Bilinear texture filtering: what a PS2 did when running a PS1 disc. Same
## geometry, same wobble, smooth textures. Immediately of the wrong decade.
@export var smooth_textures := false:
	set(v):
		smooth_textures = v
		_push()

@export_group("Colour")
@export_range(2, 256, 1) var levels := 32:
	set(v):
		levels = v
		_push_post()
@export var dither := true:
	set(v):
		dither = v
		_push_post()
@export var scanlines := false:
	set(v):
		scanlines = v
		_push_post()
@export_range(0.0, 0.6, 0.01) var scanline_strength := 0.18:
	set(v):
		scanline_strength = v
		_push_post()
## ФИНАЛЬНЫЙ ПРОХОД: виньетка, лёгкий изгиб кинескопа, расплывание цвета по строке.
## Ни одно из трёх не имеет отношения к консоли — всё это делал ЭКРАН. Но именно они
## собирают набор отдельных приёмов в один образ: без них кадр выглядит списком
## артефактов, с ними — телевизором.
@export var crt := false:
	set(v):
		crt = v
		_push_post()

@export var post_enabled := true:
	set(v):
		post_enabled = v
		if is_inside_tree():
			_post.visible = v

@export_group("Camera")
@export_range(1.0, 40.0, 0.5) var fly_speed := 7.0
@export_range(0.0005, 0.01, 0.0001) var mouse_sensitivity := 0.0025

@onready var _screen: SubViewportContainer = $Screen
@onready var _view: SubViewport = $Screen/View
@onready var _post: ColorRect = $Screen/View/Post
## The display pass, outside the viewport and over the blown-up picture.
@onready var _scan: ColorRect = $Scanlines
@onready var _cam: Camera3D = $Screen/View/World/Camera
@onready var _world: Node3D = $Screen/View/World

var _mats: Array[ShaderMaterial] = []
var _yaw := 0.0
var _pitch := 0.0


func _ready() -> void:
	_screen.stretch_shrink = shrink
	# ТЕКСТУРЫ И ПРЕДМЕТЫ собираются в Art.gd. Шахматка была честной испытательной
	# поверхностью — перспективная коррекция невидима на плоском цвете и неотвратима на
	# сетке, — но сценой эпохи она не читается. Половина узнаваемости PSX живёт в
	# палитровых текстурах и в узнаваемых предметах, а не в артефактах растеризатора.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var tex_floor := Art.concrete(rng, false)
	var tex_wall := Art.brick(rng)
	var tex_prop := Art.metal(rng)
	for m in _world.find_children("*", "MeshInstance3D"):
		var mat := m.material_override as ShaderMaterial
		if mat == null or _mats.has(mat):
			continue
		var tex := tex_prop
		var scale := Vector2(3.0, 2.0)
		if m.name == "Floor":
			tex = tex_floor
			# Пол семьдесят метров на десять повторов: тексель одиннадцать сантиметров —
			# ровно тот крупный тексель, который на консоли было ВИДНО.
			scale = Vector2(10.0, 10.0)
		elif m.name.begins_with("Wall"):
			tex = tex_wall
			# Стена семьдесят на семь метров. Считаем от кирпича, а не от стены: четыре
			# кирпича в тайле по ширине и восемь рядов по высоте, кирпич полметра — значит
			# тайл два метра, то есть 35 повторов вдоль и 3.5 поперёк. Стояло 8×3, и
			# кирпичи выходили по два метра шириной.
			scale = Vector2(35.0, 3.5)
		mat.set_shader_parameter("albedo_tex", tex)
		mat.set_shader_parameter("albedo_smooth", tex)
		mat.set_shader_parameter("uv_scale", scale)
		_mats.append(mat)
	# Предметы приходят со своими материалами и тоже должны слушаться клавиш.
	#
	# ЧЕТВЁРТЫЙ АРГУМЕНТ `find_children` — `owned`, и он по умолчанию `true`. Владелец
	# есть только у узлов, сохранённых в сцене; всё, что добавлено кодом через
	# `add_child`, владельца не имеет и в выдачу НЕ ПОПАДАЕТ. Обход молча возвращал
	# только исходные стены и колонны, материалы арки, ящиков и бочек не набирались в
	# `_mats`, и клавиши на них не действовали: предметы стояли с параметрами шейдера по
	# умолчанию и не гасились вместе со сценой.
	var shader: Shader = (_mats[0] as ShaderMaterial).shader
	Art.populate(_world, shader)
	for m in _world.find_children("*", "MeshInstance3D", true, false):
		var mat := m.material_override as ShaderMaterial
		if mat != null and not _mats.has(mat):
			_mats.append(mat)
	floor_subdivide = floor_subdivide
	_yaw = _cam.rotation.y
	_pitch = _cam.rotation.x
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_push()
	_push_post()
	_post.visible = post_enabled


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity,
			-deg_to_rad(89.0), deg_to_rad(89.0))
		_cam.rotation = Vector3(_pitch, _yaw, 0.0)
	elif event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1: snap_vertices = not snap_vertices
		KEY_2: affine_uv = not affine_uv
		KEY_3: post_enabled = not post_enabled
		KEY_4: dither = not dither
		KEY_5: shrink = 1 if shrink > 1 else 4
		KEY_6: smooth_textures = not smooth_textures
		KEY_7: scanlines = not scanlines
		KEY_8: floor_subdivide = 0 if floor_subdivide > 0 else 30
		KEY_9: crt = not crt


func _process(delta: float) -> void:
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var lift := 1.0 if Input.is_action_pressed(&"jump") else 0.0
	var dir := _cam.global_basis * Vector3(input.x, 0.0, input.y) + Vector3.UP * lift
	var rush := 3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
	_cam.global_position += dir * fly_speed * rush * delta


func _push() -> void:
	if not is_inside_tree():
		return
	# One step of the grid lands on exactly one rendered pixel: normalised
	# device space runs -1..1 across `size` pixels, so the grid is size/2.
	var grid := Vector2(_view.size) * 0.5 / maxf(snap_coarseness, 0.01)
	for m in _mats:
		m.set_shader_parameter("snap_grid", grid)
		m.set_shader_parameter("snap_vertices", snap_vertices)
		m.set_shader_parameter("affine_uv", affine_uv)
		m.set_shader_parameter("smooth_textures", smooth_textures)


func _push_post() -> void:
	if not is_inside_tree():
		return
	var m := _post.material as ShaderMaterial
	m.set_shader_parameter("levels", levels)
	m.set_shader_parameter("dither", dither)
	var sm := _scan.material as ShaderMaterial
	sm.set_shader_parameter("scanlines", scanlines)
	sm.set_shader_parameter("scanline_strength", scanline_strength)
	# Период строк — в пикселях ОКНА на одну ОТРИСОВАННУЮ строку, то есть ровно
	# коэффициент уменьшения. Стояла двойка, привязанная к пикселю монитора: при 900
	# строках экрана узор оказывался тоньше различимого и читался просто затемнением.
	sm.set_shader_parameter("scan_period", float(shrink))
	sm.set_shader_parameter("crt", crt)
	# A full-screen pass that does nothing still copies every pixel. Hide it
	# rather than let it run as an expensive no-op.
	_scan.visible = scanlines or crt
