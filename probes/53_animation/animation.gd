class_name AnimationProbeRig
extends Node3D
## Input, orbit camera and comparison controls stay outside the controlled entity.

var _yaw := 0.0
var _pitch := -0.32
var _pad: int = -1
var _jump_before := false
var _previous_mouse: int = Input.MOUSE_MODE_VISIBLE
var _action_before := false
var _blend: int = 1
@onready var player: AnimationProbePlayer = $Player
@onready var _camera: Camera3D = $Camera
@onready var _hud: RichTextLabel = $Ui/Info


func _ready() -> void:
	_previous_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	reset()


func _exit_tree() -> void:
	Input.mouse_mode = _previous_mouse


func _physics_process(_delta: float) -> void:
	var pads: Array[int] = Input.get_connected_joypads()
	if not pads.has(_pad):
		_pad = pads[0] if not pads.is_empty() else -1
	var move := Vector2(float(Input.is_physical_key_pressed(KEY_D))
			- float(Input.is_physical_key_pressed(KEY_A)),
			float(Input.is_physical_key_pressed(KEY_S))
			- float(Input.is_physical_key_pressed(KEY_W)))
	var jump: bool = Input.is_physical_key_pressed(KEY_SPACE)
	if _pad >= 0:
		move += _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
		jump = jump or Input.is_joy_button_pressed(_pad, JOY_BUTTON_A)
	player.wish = Basis(Vector3.UP, _yaw) * Vector3(move.x, 0, move.y).limit_length()
	player.jump_pressed = jump and not _jump_before
	_jump_before = jump
	player.walking = Input.is_physical_key_pressed(KEY_SHIFT)
	player.turn_input = float(Input.is_physical_key_pressed(KEY_Q)) - float(
			Input.is_physical_key_pressed(KEY_E))
	var action: bool = Input.is_physical_key_pressed(KEY_F)
	if _pad >= 0:
		player.walking = player.walking or Input.is_joy_button_pressed(_pad, JOY_BUTTON_B)
		player.turn_input += float(Input.is_joy_button_pressed(_pad, JOY_BUTTON_LEFT_SHOULDER))
		player.turn_input -= float(Input.is_joy_button_pressed(_pad, JOY_BUTTON_RIGHT_SHOULDER))
		action = action or Input.is_joy_button_pressed(_pad, JOY_BUTTON_X)
	player.action_pressed = action and not _action_before
	_action_before = action


func _process(delta: float) -> void:
	if _pad >= 0:
		var look: Vector2 = _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)
		_yaw -= look.x * delta * 2.5
		_pitch = clampf(_pitch - look.y * delta * 1.8, -1.0, 0.2)
	var focus: Vector3 = player.visual.global_position + Vector3.UP
	var wanted: Vector3 = focus + Basis.from_euler(Vector3(_pitch, _yaw, 0)) * Vector3(0, 0, 4.5)
	var query := PhysicsRayQueryParameters3D.create(focus, wanted, 1, [player.get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		wanted = hit.position + hit.normal * 0.2
	_camera.position = _camera.position.lerp(wanted, 1.0 - exp(-15.0 * delta))
	_camera.look_at(focus)
	_readout()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * 0.003
		_pitch = clampf(_pitch - event.relative.y * 0.003, -1.0, 0.2)
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventJoypadButton and event.pressed and event.device == _pad:
		if event.button_index == JOY_BUTTON_Y:
			reset()
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		KEY_R:
			reset()
		KEY_1:
			_blend = (_blend + 1) % 3
			player.blend_time = [0.0, 0.12, 0.3][_blend]
		KEY_2:
			player.match_stride = not player.match_stride
		KEY_3:
			player.turn_speed = 4.0 if player.turn_speed > 10.0 else 18.0


func reset() -> void:
	player.reset_at(Vector3(0, 0.05, 4))
	_yaw = 0.0
	_pitch = -0.32
	_camera.position = player.position + Vector3(0, 3, 6)
	_camera.look_at(player.position + Vector3.UP)


func _stick(horizontal: JoyAxis, vertical: JoyAxis) -> Vector2:
	var value := Vector2(Input.get_joy_axis(_pad, horizontal), Input.get_joy_axis(_pad, vertical))
	return Vector2.ZERO if value.length() < 0.2 else value.normalized() * (
			minf(value.length(), 1.0) - 0.2) / 0.8


func _readout() -> void:
	_hud.text = "\n".join(PackedStringArray([
		"[b]53 · АНИМАЦИЯ ПЕРСОНАЖА[/b]",
		"состояние: %s · клип: %s · скорость %.2f м/с" % [
			player.state, player.animation.current_animation, player.ground_speed],
		"темп клипа %.2f · прерываний %d · посадок %d" % [
			player.animation.speed_scale, player.interruptions, player.landings],
		"WASD / левый стик · мышь / правый стик — камера",
		"SHIFT / B — шаг · ПРОБЕЛ / A — прыжок · F / X — взаимодействие",
		"Q/E / LB/RB — поворот на месте · R / Y — сброс · ESC — курсор",
		"1 смешивание %.2f с · 2 темп от скорости: %s · 3 разворот %.0f" % [
			player.blend_time, "вкл" if player.match_stride else "выкл", player.turn_speed],
		"Начни действие, прерви движением или прыжком. Развернись на бегу.",
		"Подиумы проверяют сход с края и приземление; полосы показывают скольжение стоп.",
		"[color=#66ccff]гипотеза: переходы читаются, не задерживая управление[/color]",
	]))
