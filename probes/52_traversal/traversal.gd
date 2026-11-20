class_name TraversalRig
extends Node3D
## Input, camera orbit and experiment settings; no movement state lives in the rig.

const SECTIONS: Array[String] = ["длина прыжка", "второй прыжок / рывок", "узкие посадки"]
@export var mouse_sensitivity := 0.003
@export var camera_distance := 6.5
var section: int = 0
var _yaw := 0.0
var _pitch := -0.3
var _pad: int = -1
var _jump_before := false
var _dash_before := false
var _previous_mouse: int = Input.MOUSE_MODE_VISIBLE
@onready var player: TraversalPlayer = $Player
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
	var dash: bool = Input.is_physical_key_pressed(KEY_SHIFT)
	if _pad >= 0:
		move += _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
		jump = jump or Input.is_joy_button_pressed(_pad, JOY_BUTTON_A)
		dash = dash or Input.is_joy_button_pressed(_pad, JOY_BUTTON_X)
	player.wish = Basis(Vector3.UP, _yaw) * Vector3(move.x, 0, move.y).limit_length()
	player.jump_pressed = jump and not _jump_before
	player.dash_pressed = dash and not _dash_before
	player.jump_held = jump
	_jump_before = jump
	_dash_before = dash


func _process(delta: float) -> void:
	# Look input belongs to the render clock; movement still consumes yaw on physics ticks.
	if _pad >= 0:
		var look: Vector2 = _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)
		_yaw -= look.x * delta * 2.5
		_pitch = clampf(_pitch - look.y * delta * 1.8, -1.0, 0.35)
	var focus: Vector3 = player.visual_position() + Vector3.UP * 1.1
	var offset: Vector3 = Basis.from_euler(Vector3(_pitch, _yaw, 0)) * Vector3.BACK
	var wanted: Vector3 = focus + offset * camera_distance
	var query := PhysicsRayQueryParameters3D.create(focus, wanted, 1, [player.get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		wanted = hit.position + hit.normal * 0.2
	_camera.position = _camera.position.lerp(wanted, 1.0 - exp(-15.0 * delta))
	_camera.look_at(focus)
	_hud.text = "\n".join(PackedStringArray([
		"[b]52 · ТРЕТЬЕ ЛИЦО[/b]   участок: " + SECTIONS[section],
		"скорость %.1f м/с · %s · последний прыжок: %s" % [
			Vector2(player.velocity.x, player.velocity.z).length(),
			"земля" if player.is_on_floor() else "воздух", player.last_jump],
		"последняя посадка: %.2f с / %.2f м · падений %d" % [
			player.last_airtime, player.last_distance, player.falls],
		"текущий полёт %.2f с · пик текущего/последнего полёта %.2f м" % [
			player.airtime, player.peak_height],
		"WASD / левый стик · мышь / правый стик — камера",
		"ПРОБЕЛ / A — прыжок (удерживай для высоты) · SHIFT / X — рывок",
		"R / Y — заново · TAB / RB — участок · ESC — курсор · клик — захват",
		"1 койот-тайм: %s · 2 буфер: %s" % [_on(player.coyote_enabled), _on(player.buffer_enabled)],
		"3 переменная высота: %s · 4 второй прыжок: %s" % [
			_on(player.variable_jump), _on(player.double_enabled)],
		"5 рывок: %s · 6 воздух: %.0f м/с²" % [_on(player.dash_enabled), player.air_acceleration],
		"7 интерполяция вида: %s · физика %d Гц / кадры %d" % [_on(player.smooth_visuals),
			Engine.physics_ticks_per_second, Engine.get_frames_per_second()],
		"Для проверки буфера и койот-тайма отключи второй прыжок (4).",
		"[color=#66ccff]гипотеза: помощь прощает ввод, сохраняя предсказуемую посадку[/color]",
	]))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -1.0, 0.35)
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventJoypadButton and event.pressed and event.device == _pad:
		if event.button_index == JOY_BUTTON_Y:
			reset()
		if event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			section = (section + 1) % 3
			reset()
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		KEY_R:
			reset()
		KEY_TAB:
			section = (section + 1) % 3
			reset()
		KEY_1:
			player.coyote_enabled = not player.coyote_enabled
		KEY_2:
			player.buffer_enabled = not player.buffer_enabled
		KEY_3:
			player.variable_jump = not player.variable_jump
		KEY_4:
			player.double_enabled = not player.double_enabled
		KEY_5:
			player.dash_enabled = not player.dash_enabled
		KEY_6:
			player.air_acceleration = 5.0 if player.air_acceleration > 10.0 else 24.0
		KEY_7:
			player.smooth_visuals = not player.smooth_visuals


func reset() -> void:
	var point := Vector3(section * 18.0, 0.05, 5)
	player.reset_at(point)
	_yaw = 0.0
	_pitch = -0.3
	_camera.position = point + Vector3(0, 3, 6)
	_camera.look_at(point + Vector3.UP)


func _stick(horizontal: JoyAxis, vertical: JoyAxis) -> Vector2:
	var value := Vector2(Input.get_joy_axis(_pad, horizontal), Input.get_joy_axis(_pad, vertical))
	return Vector2.ZERO if value.length() < 0.2 else value.normalized() * (
			minf(value.length(), 1.0) - 0.2) / 0.8


func _on(enabled: bool) -> String:
	return "вкл" if enabled else "выкл"
