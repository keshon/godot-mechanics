class_name CompositionRig
extends Node3D
## The rig routes two independent inputs and cameras into a shared world.

var section: int = 0
var devices: Array[int] = [-1, -1]
var _jump_before: Array[bool] = [false, false]
var _dash_before: Array[bool] = [false, false]
var _previous_mouse: int = Input.MOUSE_MODE_VISIBLE
@onready var players: Array[CompositionPlayer] = [$Player1, $Player2]
@onready var cameras: Array[CompositionCamera] = [
	$Ui/Left/View/Camera, $Ui/Right/View/Camera,
]
@onready var _hud: RichTextLabel = $Ui/Info


func _ready() -> void:
	_previous_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var zones: Array[CompositionZone] = []
	for zone in $Course/Zones.get_children():
		zones.append(zone)
	$Ui/Left/View.world_3d = get_viewport().world_3d
	$Ui/Right/View.world_3d = get_viewport().world_3d
	for slot in range(2):
		cameras[slot].configure(players[slot], zones)
	assign_devices()
	reset()


func _exit_tree() -> void:
	Input.mouse_mode = _previous_mouse


func _process(delta: float) -> void:
	for slot in range(2):
		var look_input: Vector2 = stick(devices[slot], JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)
		if slot == 1 and devices[slot] < 0:
			look_input = keys(KEY_J, KEY_L, KEY_I, KEY_K)
		cameras[slot].look(look_input * delta * 2.0)
	_hud.text = "\n".join(PackedStringArray([
		"[b]55 · ДВЕ КАМЕРЫ[/b] · " + ["коридор", "высота", "раздельные пути"][section],
		"P1: %s · %.1f м | P2: %s · %.1f м" % [cameras[0].zone_caption,
			cameras[0].arm_length, cameras[1].zone_caption, cameras[1].arm_length],
		"Устройства P1: %s / P2: %s" % [source(0), source(1)],
		"P1 WASD / мышь · ПРОБЕЛ прыжок · SHIFT рывок",
		"P2 стрелки / IJKL · ENTER прыжок · CTRL рывок",
		"Пульт: стики / A / X · 0 назначить подключённые пульты",
		"R сброс · TAB участок · ESC курсор · клик захват",
		"1 защита камеры: %s · 2 зоны: %s · 3 переход: %.1f" % [
			"вкл" if cameras[0].collision_enabled else "выкл",
			"вкл" if cameras[0].zones_enabled else "выкл", cameras[0].blend_speed],
		"Пройди коридор, уступы и две ветки; выйди из зоны во время перехода.",
		"[color=#66ccff]гипотеза: каждый вид сохраняет посадку и ориентиры[/color]",
	]))


func _physics_process(_delta: float) -> void:
	for slot in range(2):
		var device: int = devices[slot]
		var move: Vector2 = keys(KEY_A, KEY_D, KEY_W, KEY_S) if slot == 0 else (
				keys(KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN))
		var jump: bool = Input.is_physical_key_pressed(KEY_SPACE if slot == 0 else KEY_ENTER)
		var dash: bool = Input.is_physical_key_pressed(KEY_SHIFT if slot == 0 else KEY_CTRL)
		if device >= 0:
			move = stick(device, JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
			jump = Input.is_joy_button_pressed(device, JOY_BUTTON_A)
			dash = Input.is_joy_button_pressed(device, JOY_BUTTON_X)
		players[slot].wish = Basis(Vector3.UP, cameras[slot].view_yaw) * Vector3(move.x, 0, move.y)
		players[slot].jump_pressed = jump and not _jump_before[slot]
		players[slot].jump_held = jump
		players[slot].dash_pressed = dash and not _dash_before[slot]
		_jump_before[slot] = jump
		_dash_before[slot] = dash


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if devices[0] < 0:
			cameras[0].look(event.relative * 0.003)
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		KEY_0:
			assign_devices()
		KEY_R:
			reset()
		KEY_TAB:
			section = (section + 1) % 3
			reset()
		KEY_1:
			for camera in cameras:
				camera.collision_enabled = not camera.collision_enabled
		KEY_2:
			for camera in cameras:
				camera.zones_enabled = not camera.zones_enabled
		KEY_3:
			for camera in cameras:
				camera.blend_speed = 15.0 if camera.blend_speed < 10 else 3.0


func reset() -> void:
	for slot in range(2):
		var point: Vector3 = [Vector3(-1.0 + slot * 2, 0.1, 5),
				Vector3(-1.0 + slot * 2, 0.1, -18),
				Vector3(-8.0 + slot * 16, 0.1, -39)][section]
		players[slot].reset_at(point)
		cameras[slot].reset()
		_jump_before[slot] = false
		_dash_before[slot] = false


func assign_devices() -> void:
	var pads: Array[int] = Input.get_connected_joypads()
	devices[1] = pads[0] if pads.size() > 0 else -1
	devices[0] = pads[1] if pads.size() > 1 else -1


func source(slot: int) -> String:
	if devices[slot] < 0:
		return "клавиатура"
	return "пульт %d%s" % [devices[slot],
			"" if Input.get_connected_joypads().has(devices[slot]) else " (отключён)"]


func keys(left: Key, right: Key, forward: Key, back: Key) -> Vector2:
	return Vector2(float(Input.is_physical_key_pressed(right))
			- float(Input.is_physical_key_pressed(left)), float(Input.is_physical_key_pressed(back))
			- float(Input.is_physical_key_pressed(forward))).limit_length()


func stick(device: int, horizontal: JoyAxis, vertical: JoyAxis) -> Vector2:
	if device < 0 or not Input.get_connected_joypads().has(device):
		return Vector2.ZERO
	var value := Vector2(Input.get_joy_axis(device, horizontal), Input.get_joy_axis(device, vertical))
	return Vector2.ZERO if value.length() < 0.2 else value.normalized() * (
			minf(value.length(), 1.0) - 0.2) / 0.8
