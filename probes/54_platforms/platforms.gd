class_name PlatformProbeRig
extends Node3D
## Input, orbit camera and comparison controls stay outside the controlled entity.

var _yaw := 0.0
var _pitch := -0.32
var _pad: int = -1
var _jump_before := false
var _dash_before := false
var _previous_mouse: int = Input.MOUSE_MODE_VISIBLE
var section: int = 0
var _reset_ticks: int = 0
var _anchor := Vector3.ZERO
var _anchored := false
var _drift := 0.0
@onready var player: PlatformProbePlayer = $Player
@onready var _camera: Camera3D = $Camera
@onready var _hud: RichTextLabel = $Ui/Info
@onready var platforms: Array[MovingProbePlatform] = [
	$Course/Shuttle, $Course/Rotor, $Course/Lift, $Course/Drop,
]


func _ready() -> void:
	_previous_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	reset()


func _exit_tree() -> void:
	Input.mouse_mode = _previous_mouse


func _physics_process(_delta: float) -> void:
	if _reset_ticks > 0:
		_reset_ticks -= 1
		if _reset_ticks == 0:
			player.reset_at(platforms[section].global_transform * Vector3(1.3, 0.36, 0))
			player.set_physics_process(true)
		return
	if player.position.y < -6:
		reset()
		return
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
	player.jump_held = jump
	player.dash_pressed = dash and not _dash_before
	_jump_before = jump
	_dash_before = dash
	if player.support == platforms[section] and player.wish.length_squared() < 0.01:
		var local: Vector3 = platforms[section].global_transform.affine_inverse() * player.position
		if not _anchored:
			_anchor = local
			_anchored = true
		_drift = Vector2(local.x - _anchor.x, local.z - _anchor.z).length()
	else:
		_anchored = false


func _process(delta: float) -> void:
	if _pad >= 0:
		var look: Vector2 = _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)
		_yaw -= look.x * delta * 2.5
		_pitch = clampf(_pitch - look.y * delta * 1.8, -1.0, 0.2)
	var focus: Vector3 = player.visual.global_position + Vector3.UP
	var wanted: Vector3 = focus + Basis.from_euler(Vector3(_pitch, _yaw, 0)) * Vector3(0, 0, 6)
	var query := PhysicsRayQueryParameters3D.create(focus, wanted, 5, [player.get_rid()])
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
		if event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			section = (section + 1) % platforms.size()
			reset()
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		KEY_R:
			reset()
		KEY_TAB:
			section = (section + 1) % platforms.size()
			reset()
		KEY_1:
			player.platform_on_leave = (player.platform_on_leave + 1) % 3
		KEY_2:
			for platform in platforms:
				platform.rate = 0.5 if platform.rate > 0.75 else 1.5
		KEY_3:
			for platform in platforms:
				platform.running = not platform.running
		KEY_4:
			player.floor_snap_length = 0.0 if player.floor_snap_length > 0 else 0.3
		KEY_5:
			player.double_enabled = not player.double_enabled
		KEY_6:
			player.dash_enabled = not player.dash_enabled


func reset() -> void:
	player.set_physics_process(false)
	platforms[section].reset_motion()
	# Jolt needs several ticks to replace the velocity estimate after a platform teleport.
	_reset_ticks = 4
	_anchored = false
	_drift = 0.0
	player.reset_at(platforms[section].global_transform * Vector3(1.3, 0.36, 0))
	_yaw = 0.0
	_pitch = -0.32
	_camera.position = player.position + Vector3(0, 3, 6)
	_camera.look_at(player.position + Vector3.UP)


func _stick(horizontal: JoyAxis, vertical: JoyAxis) -> Vector2:
	var value := Vector2(Input.get_joy_axis(_pad, horizontal), Input.get_joy_axis(_pad, vertical))
	return Vector2.ZERO if value.length() < 0.2 else value.normalized() * (
			minf(value.length(), 1.0) - 0.2) / 0.8


func _readout() -> void:
	var platform: MovingProbePlatform = platforms[section]
	_hud.text = "\n".join(PackedStringArray([
		"[b]54 · ДВИЖУЩИЕСЯ ПЛАТФОРМЫ[/b] · " + ["перенос", "вращение", "лифт", "падение"][section],
		"опора: %s · скорость опоры %.2f м/с · дрейф на палубе %.3f м" % [
			player.support.name if player.support != null else "нет",
			player.get_platform_velocity().length(), _drift],
		"последний сход: (%.2f, %.2f, %.2f) м/с · прыжков %d · посадок %d" % [
			player.departure.x, player.departure.y, player.departure.z, player.jumps, player.landings],
		"WASD / левый стик · мышь / правый стик — камера",
		"ПРОБЕЛ / A — прыжок и второй прыжок · удерживай для высоты · SHIFT / X — рывок",
		"R / Y — повторить · TAB / RB — участок · ESC — курсор",
		"1 скорость при сходе: " + ["вся", "без движения вниз", "не добавлять"][player.platform_on_leave],
		"2 темп %.1f · 3 движение: %s · 4 привязка к полу %.1f м" % [
			platform.rate, "вкл" if platform.running else "выкл", player.floor_snap_length],
		"5 второй прыжок: %s · 6 рывок: %s · воздух %.0f м/с²" % [
			"вкл" if player.double_enabled else "выкл", "вкл" if player.dash_enabled else "выкл",
			player.air_acceleration],
		"Маршрут вперёд: перенос → вращение → лифт → падение → финиш. Есть боковые площадки.",
		"Падающая палуба ждёт 0.6 с после касания; R возвращает её наверх.",
		"[color=#66ccff]гипотеза: опора несёт игрока, а сход предсказуемо сохраняет импульс[/color]",
	]))
