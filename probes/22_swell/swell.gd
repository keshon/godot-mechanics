class_name SwellWorld
extends Node3D
## 22 — one wave, two counters. Where does the ship actually float?
##
## The white buoys sit at the height the SHADER draws: the full 48-component Gerstner
## surface, with the horizontal displacement solved by iteration.
##
## The orange buoys sit at the height the PHYSICS returns: a plain sum of sines over
## the first `reads` components, no horizontal solve. That is what a hull, a swimmer,
## a cannonball and a deck are all standing on.
##
## Two buoys, one point of water. The gap between them is the lie.

const COLUMNS := 9
const ROWS := 7
## Metres between buoys.
const STEP := 9.0

## Sea states, not kinds of water: this probe has no `absorb`, so ocean/river/pool
## would mean nothing here. What it has is the spectrum, and the spectrum is the
## weather. The numbers follow his own set_force(): longer and taller together,
## steeper with it.
const SEAS: Array[Dictionary] = [
	{"name": "штиль", "length": 24.0, "height": 0.3, "steep": 0.16,
		"storm": 0.0, "over": 0.000},
	{"name": "зыбь", "length": 60.0, "height": 1.2, "steep": 0.38,
		"storm": 0.15, "over": 0.004},
	{"name": "рабочее море", "length": 60.0, "height": 2.4, "steep": 0.55,
		"storm": 0.45, "over": 0.010},
	{"name": "шторм", "length": 95.0, "height": 6.5, "steep": 0.82,
		"storm": 1.0, "over": 0.022},
]

@export_range(1, 48) var reads := 8
@export_range(0, 3) var sea_state := 2
@export var running := true
@export var show_buoys := true
@export var fly_speed := 22.0

var sea := SwellSea.new()
## Wave time, seconds. One clock, pushed into the shader.
var clock := 0.0
## Root mean square gap between the two answers, metres.
var rms := 0.0
## Largest gap on the grid right now, metres.
var worst := 0.0
## Cost of one height query, microseconds.
var felt_usec := 0.0
var seen_usec := 0.0
## Smallest horizontal jacobian in this sea: 1 is flat, 0 is folding over.
var fold_now := 1.0

var _spots: Array[Vector2] = []
var _yaw := 0.42
var _pitch := -0.16
var _looking := false

@onready var _camera: Camera3D = $Camera
@onready var _seen: MultiMeshInstance3D = $Seen
@onready var _felt: MultiMeshInstance3D = $Felt
@onready var _info: RichTextLabel = $Ui/Info
@onready var _surface_mesh: MeshInstance3D = $Surface
@onready var _surface := _surface_mesh.material_override as ShaderMaterial


func _ready() -> void:
	for row in ROWS:
		for column in COLUMNS:
			_spots.append(Vector2(
					(float(column) - float(COLUMNS - 1) * 0.5) * STEP,
					(float(row) - float(ROWS - 1) * 0.5) * STEP))
	_rebuild()


func _process(delta: float) -> void:
	_fly(delta)
	if running:
		clock += delta
	# One clock, pushed into the shader. This is the only reason the two counters can
	# be compared at all: TIME would be a second clock nobody controls.
	_surface.set_shader_parameter("wave_time", clock)
	_seen.visible = show_buoys
	_felt.visible = show_buoys
	_place()
	_draw_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_looking = event.pressed
			Input.set_mouse_mode(
					Input.MOUSE_MODE_CAPTURED if _looking else Input.MOUSE_MODE_VISIBLE)
		return
	if event is InputEventMouseMotion and _looking:
		_yaw -= event.relative.x * 0.0035
		_pitch = clampf(_pitch - event.relative.y * 0.0035, -1.4, 1.4)
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4:
			sea_state = event.keycode - KEY_1
			_rebuild()
		KEY_Z:
			reads = 4
			_measure()
		KEY_X:
			reads = 8
			_measure()
		KEY_C:
			reads = 16
			_measure()
		KEY_V:
			reads = 48
			_measure()
		KEY_H:
			show_buoys = not show_buoys
		KEY_SPACE:
			running = not running


func _rebuild() -> void:
	var state: Dictionary = SEAS[sea_state]
	sea.build(float(state["length"]), float(state["height"]), float(state["steep"]))
	_surface.set_shader_parameter("storm", float(state["storm"]))
	_surface.set_shader_parameter("wn", SwellSea.COMPONENTS)
	_surface.set_shader_parameter("steepness", sea.steepness)
	_surface.set_shader_parameter("wdirs", sea.directions)
	_surface.set_shader_parameter("wks", sea.wave_numbers)
	_surface.set_shader_parameter("wamps", sea.amplitudes)
	_surface.set_shader_parameter("wphs", sea.phases)
	_surface.set_shader_parameter("womg", sea.omegas)
	_surface.set_shader_parameter("wmr", sea.group_rate)
	_surface.set_shader_parameter("wmp", sea.group_phase)
	# The foam threshold is calibrated, not chosen: find the worst compression that
	# actually happens in this sea, then paint just above it.
	fold_now = sea.worst_squeeze(clock)
	_surface.set_shader_parameter("fold", fold_now + float(state["over"]))
	_measure()


func _place() -> void:
	var seen: MultiMesh = _seen.multimesh
	var felt: MultiMesh = _felt.multimesh
	seen.instance_count = _spots.size()
	felt.instance_count = _spots.size()
	var sum_squares := 0.0
	worst = 0.0
	for i in _spots.size():
		var spot := _spots[i]
		var seen_y := sea.seen_height(spot.x, spot.y, clock)
		var felt_y := sea.felt_height(spot.x, spot.y, clock, reads)
		seen.set_instance_transform(
				i, Transform3D(Basis.IDENTITY, Vector3(spot.x, seen_y, spot.y)))
		felt.set_instance_transform(
				i, Transform3D(Basis.IDENTITY, Vector3(spot.x, felt_y, spot.y)))
		var error := felt_y - seen_y
		sum_squares += error * error
		worst = maxf(worst, absf(error))
	rms = sqrt(sum_squares / _spots.size())


func _measure() -> void:
	var started := Time.get_ticks_usec()
	for i in 800:
		sea.felt_height(float(i) * 0.7, float(i) * 1.3, 5.0, reads)
	felt_usec = float(Time.get_ticks_usec() - started) / 800.0
	started = Time.get_ticks_usec()
	for i in 120:
		sea.seen_height(float(i) * 0.7, float(i) * 1.3, 5.0)
	seen_usec = float(Time.get_ticks_usec() - started) / 120.0


func _fly(delta: float) -> void:
	var wanted := Vector3(
			Input.get_action_strength(&"move_right")
			- Input.get_action_strength(&"move_left"),
			0.0,
			Input.get_action_strength(&"move_back")
			- Input.get_action_strength(&"move_forward"))
	if Input.is_key_pressed(KEY_SHIFT):
		wanted.y -= 1.0
	if Input.is_key_pressed(KEY_CTRL):
		wanted.y += 1.0
	if wanted != Vector3.ZERO:
		_camera.global_position += (
				_camera.global_transform.basis * wanted.normalized() * fly_speed * delta)
	_camera.rotation = Vector3(_pitch, _yaw, 0.0)


func _draw_hud() -> void:
	var state: Dictionary = SEAS[sea_state]
	var text := "[b]%s[/b]    1 штиль   2 зыбь   3 рабочее море   4 шторм\n\n" % (
			str(state["name"]).to_upper())
	text += "белые — поверхность, которую рисует шейдер: "
	text += "48 компонент, снос Герстнера решён итерацией\n"
	text += "[color=#ffd479]оранжевые[/color] — то, что возвращает физика: "
	text += "%d компонент, чистая сумма синусов\n\n" % reads
	text += "[table=2]"
	text += "[cell]море  [/cell][cell]длина %.0f м, высота %.1f м[/cell]" % [
		sea.wave_len, sea.wave_height]
	text += "[cell]физика читает  [/cell][cell]%d из 48[/cell]" % reads
	text += "[cell]расхождение RMS  [/cell][cell]%.3f м[/cell]" % rms
	text += "[cell]худшее сейчас  [/cell][cell]%.3f м   (%.0f%% высоты волны)[/cell]" % [
		worst, 100.0 * worst / maxf(sea.wave_height, 0.01)]
	text += "[cell]сжатие в худшей точке  [/cell][cell]%.3f   (пена ниже %.3f)[/cell]" % [
		fold_now, fold_now + float(state["over"])]
	text += "[cell]цена вызова  [/cell][cell]%.2f мкс против %.1f мкс за честный ответ[/cell]" % [
		felt_usec, seen_usec]
	text += "[/table]\n\n"
	text += "Z X C V — физика читает 4 / 8 / 16 / 48 компонент\n"
	text += "H — убрать буи и просто смотреть на воду    SPACE — стоп-кадр\n"
	text += "WASD летать, CTRL/SHIFT вверх-вниз, правая кнопка — осмотреться\n\n"
	text += "[color=#66ccff]из двух упрощений оправдано было то, за которое я"
	text += " оправдывался: снос стоит два сантиметра, восемь компонент из"
	text += " сорока восьми — двадцать семь[/color]"
	_info.text = text
