extends Node3D

# 22 — one wave, two counters. Where does the ship actually float?
#
# The white buoys sit at the height the SHADER draws: the full 48-component Gerstner
# surface, with the horizontal displacement solved by iteration.
#
# The orange buoys sit at the height the PHYSICS returns: a plain sum of sines over the
# first `reads` components, no horizontal solve. That is what a hull, a swimmer, a
# cannonball and a deck are all standing on.
#
# Two buoys, one point of water. The gap between them is the lie.

const COLS := 9
const ROWS := 7
const STEP := 9.0

# Sea states, not kinds of water: this probe has no `absorb`, so ocean/river/pool would
# mean nothing here. What it has is the spectrum, and the spectrum is the weather.
# The numbers follow his own set_force(): longer and taller together, steeper with it.
const SEAS := [
	{"name": "штиль", "len": 24.0, "h": 0.3, "steep": 0.16, "storm": 0.0, "over": 0.000},
	{"name": "зыбь", "len": 60.0, "h": 1.2, "steep": 0.38, "storm": 0.15, "over": 0.004},
	{"name": "рабочее море", "len": 60.0, "h": 2.4, "steep": 0.55, "storm": 0.45, "over": 0.010},
	{"name": "шторм", "len": 95.0, "h": 6.5, "steep": 0.82, "storm": 1.0, "over": 0.022},
]

@export_range(1, 48) var reads := 8
@export_range(0, 3) var sea_state := 2
@export var running := true
@export var show_buoys := true
@export var fly_speed := 22.0

var sea := Swell.new()
var clock := 0.0
var rms := 0.0
var worst := 0.0
var us_phys := 0.0
var us_truth := 0.0

var fold_now := 1.0

var _mat: ShaderMaterial
var _spots: Array[Vector2] = []
var _yaw := 0.42
var _pitch := -0.16
var _look := false


func _ready() -> void:
	_mat = ($Surface as MeshInstance3D).material_override
	for gz in ROWS:
		for gx in COLS:
			_spots.append(Vector2(
				(float(gx) - float(COLS - 1) * 0.5) * STEP,
				(float(gz) - float(ROWS - 1) * 0.5) * STEP))
	_rebuild()


func _rebuild() -> void:
	var st: Dictionary = SEAS[sea_state]
	sea.build(float(st["len"]), float(st["h"]), float(st["steep"]))
	_mat.set_shader_parameter("storm", float(st["storm"]))

	_mat.set_shader_parameter("wn", Swell.N)
	_mat.set_shader_parameter("steepness", sea.steepness)
	_mat.set_shader_parameter("wdirs", sea.dirs)
	_mat.set_shader_parameter("wks", sea.ks)
	_mat.set_shader_parameter("wamps", sea.amps)
	_mat.set_shader_parameter("wphs", sea.phases)
	_mat.set_shader_parameter("womg", sea.omegas)
	_mat.set_shader_parameter("wmr", sea.mrate)
	_mat.set_shader_parameter("wmp", sea.mphase)
	# the foam threshold is calibrated, not chosen: find the worst compression that
	# actually happens in this sea, then paint just above it.
	fold_now = sea.steep_of(clock)
	_mat.set_shader_parameter("fold", fold_now + float(st["over"]))
	_measure()


func _process(delta: float) -> void:
	_fly(delta)
	if running:
		clock += delta
	# one clock, pushed into the shader. this is the only reason the two counters can
	# be compared at all: TIME would be a second clock nobody controls.
	_mat.set_shader_parameter("wave_time", clock)
	($Seen as MultiMeshInstance3D).visible = show_buoys
	($Felt as MultiMeshInstance3D).visible = show_buoys
	_place()
	_hud()


func _place() -> void:
	var seen: MultiMesh = $Seen.multimesh
	var felt: MultiMesh = $Felt.multimesh
	seen.instance_count = _spots.size()
	felt.instance_count = _spots.size()
	var sum2 := 0.0
	worst = 0.0
	for i in _spots.size():
		var p: Vector2 = _spots[i]
		var h_seen := sea.truth(p.x, p.y, clock)
		var h_felt := sea.phys(p.x, p.y, clock, reads)
		seen.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(p.x, h_seen, p.y)))
		felt.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(p.x, h_felt, p.y)))
		var e := h_felt - h_seen
		sum2 += e * e
		worst = maxf(worst, absf(e))
	rms = sqrt(sum2 / _spots.size())


func _measure() -> void:
	var t0 := Time.get_ticks_usec()
	for k in 800:
		sea.phys(float(k) * 0.7, float(k) * 1.3, 5.0, reads)
	us_phys = float(Time.get_ticks_usec() - t0) / 800.0
	t0 = Time.get_ticks_usec()
	for k in 120:
		sea.truth(float(k) * 0.7, float(k) * 1.3, 5.0)
	us_truth = float(Time.get_ticks_usec() - t0) / 120.0


func _fly(delta: float) -> void:
	var cam: Camera3D = $Cam
	var v := Vector3(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		0.0,
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward"))
	if Input.is_key_pressed(KEY_SHIFT):
		v.y -= 1.0
	if Input.is_key_pressed(KEY_CTRL):
		v.y += 1.0
	if v != Vector3.ZERO:
		cam.global_position += cam.global_transform.basis * v.normalized() * fly_speed * delta
	cam.rotation = Vector3(_pitch, _yaw, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_look = event.pressed
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if _look else Input.MOUSE_MODE_VISIBLE)
		return
	if event is InputEventMouseMotion and _look:
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


func _hud() -> void:
	var st: Dictionary = SEAS[sea_state]
	var t := "[b]%s[/b]    1 штиль   2 зыбь   3 рабочее море   4 шторм\n\n" % str(st["name"]).to_upper()
	t += "[color=#dddddd]белые[/color] — поверхность, которую рисует шейдер: 48 компонент, "
	t += "снос Герстнера решён итерацией\n"
	t += "[color=#ff9a4a]оранжевые[/color] — то, что возвращает физика: %d компонент, "
	t += "чистая сумма синусов\n\n"
	t = t % reads
	t += "[table=2]"
	t += "[cell]море  [/cell][cell]длина %.0f м, высота %.1f м[/cell]" % [sea.wave_len, sea.wave_height]
	t += "[cell]физика читает  [/cell][cell]%d из 48[/cell]" % reads
	t += "[cell]расхождение RMS  [/cell][cell]%.3f м[/cell]" % rms
	t += "[cell]худшее сейчас  [/cell][cell]%.3f м   (%.0f%% высоты волны)[/cell]" % [
		worst, 100.0 * worst / maxf(sea.wave_height, 0.01)]
	t += "[cell]сжатие в худшей точке  [/cell][cell]%.3f   (пена ниже %.3f)[/cell]" % [
		fold_now, fold_now + float(st["over"])]
	t += "[cell]цена вызова  [/cell][cell]%.2f мкс против %.1f мкс за честный ответ[/cell]" % [
		us_phys, us_truth]
	t += "[/table]\n\n"
	t += "Z X C V — физика читает 4 / 8 / 16 / 48 компонент\n"
	t += "H — убрать буи и просто смотреть на воду    SPACE — стоп-кадр\n"
	t += "WASD летать, CTRL/SHIFT вверх-вниз, правая кнопка — осмотреться"
	$Ui/Info.text = t
