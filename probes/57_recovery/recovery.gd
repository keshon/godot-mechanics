class_name RecoveryRig
extends Node3D
## Shared safe points are monotonic; a wipe cancels all individual respawn timers.

@export var respawn_delay := 1.2
@export var wipe_delay := 1.8
var checkpoint: int = 0
var dead: Array[bool] = [false, false]
var remaining: Array[float] = [0.0, 0.0]
var devices: Array[int] = [-1, -1]
var paused := false
var wipe_remaining := 0.0
var wipes: int = 0
var returns: Array[int] = [0, 0]
var message := "Дойдите до зелёного острова."
var read_input := true
var _jump_before: Array[bool] = [false, false]
var _dash_before: Array[bool] = [false, false]
@onready var players: Array[RecoveryPlayer] = [$Player1, $Player2]
@onready var anchors: Array[Marker3D] = [$Start, $Middle, $Finish]
@onready var cameras: Array[Camera3D] = [$Ui/Left/View/Camera, $Ui/Right/View/Camera]
@onready var _hud: RichTextLabel = $Ui/Info


func _ready() -> void:
	$Ui/Left/View.world_3d = get_viewport().world_3d
	$Ui/Right/View.world_3d = get_viewport().world_3d
	assign_devices()
	reset_all()


func _physics_process(delta: float) -> void:
	for slot in range(2):
		players[slot].active = not paused and not dead[slot]
	if paused:
		return
	# Collect both failures before advancing either timer, including a near-simultaneous fall.
	for slot in range(2):
		if not dead[slot] and players[slot].position.y < -3.0:
			fail(slot)
	# Commit safe points before timers, so slot order cannot choose an older spawn on this tick.
	for slot in range(2):
		if not dead[slot] and players[slot].is_on_floor():
			for index in range(checkpoint + 1, anchors.size()):
				var offset: Vector3 = players[slot].position - anchors[index].position
				if absf(offset.x) < 4.5 and absf(offset.z) < 1.5 and absf(offset.y) < 0.3:
					checkpoint = index
					message = "P%d закрепил точку %d для обоих." % [slot + 1, checkpoint]
	if dead[0] and dead[1]:
		wipe_remaining = maxf(0.0, wipe_remaining - delta)
		if wipe_remaining == 0.0:
			wipes += 1
			for slot in range(2):
				respawn(slot)
			message = "Оба вернулись к общей точке %d." % checkpoint
		return
	for slot in range(2):
		if dead[slot]:
			remaining[slot] = maxf(0.0, remaining[slot] - delta)
			if remaining[slot] == 0.0:
				respawn(slot)
	if read_input:
		_drive()


func _process(_delta: float) -> void:
	for slot in range(2):
		var focus: Vector3 = players[slot].visual_position() + Vector3.UP
		if dead[slot]:
			focus = anchors[checkpoint].position + Vector3.UP
		cameras[slot].position = focus + Vector3(0, 5, 7)
		cameras[slot].look_at(focus + Vector3.FORWARD * 2.0)
	var lines: Array[String] = ["[b]57 · ВОЗВРАЩАЕМСЯ ВМЕСТЕ[/b] · точка %d / 2" % checkpoint]
	for slot in range(2):
		var state: String = "возврат через %.1f с" % remaining[slot] if dead[slot] else "в игре"
		if dead[0] and dead[1]:
			state = "ждёт общего повтора"
		lines.append("P%d: %s · возвратов %d" % [slot + 1,
				state, returns[slot]])
	var status: String = "Оба в безопасности у финиша." if both_safe() else message
	lines.append("Общий повтор через %.1f с" % wipe_remaining if dead[0] and dead[1] else status)
	lines.append("P1 WASD · ПРОБЕЛ прыжок / второй · SHIFT рывок · F падение")
	lines.append("P2 стрелки · ENTER прыжок / второй · CTRL рывок · DELETE падение")
	lines.append("Пульт: стик · A прыжок · X рывок · Y падение · 0 назначить пульты")
	lines.append("R повтор от точки · N с начала · 3 оба падают · P пауза: %s" % (
			"да" if paused else "нет"))
	lines.append("1 личный возврат: %.1f с · 2 общий: %.1f с · общих повторов %d" % [
			respawn_delay, wipe_delay, wipes])
	lines.append("Зелёная полоса — общая точка. Достаточно одного игрока на земле.")
	lines.append("[color=#66ccff]гипотеза: ошибка одного не останавливает другого[/color]")
	_hud.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		var slot: int = devices.find(event.device)
		if slot >= 0 and event.button_index == JOY_BUTTON_Y:
			fail(slot)
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_F:
			fail(0)
		KEY_DELETE:
			fail(1)
		KEY_3:
			fail(0)
			fail(1)
		KEY_P:
			paused = not paused
		KEY_R:
			restart()
		KEY_N:
			reset_all()
		KEY_0:
			assign_devices()
		KEY_1:
			respawn_delay = 2.5 if respawn_delay < 2.0 else 1.2
		KEY_2:
			wipe_delay = 3.0 if wipe_delay < 2.5 else 1.8


func fail(slot: int) -> void:
	if paused or dead[slot]:
		return
	dead[slot] = true
	remaining[slot] = respawn_delay
	players[slot].active = false
	players[slot].wish = Vector3.ZERO
	players[slot].get_node("Body").visible = false
	if dead[0] and dead[1]:
		wipe_remaining = wipe_delay
		remaining.assign([0.0, 0.0])
	else:
		message = "P%d продолжает; партнёр вернётся к общей точке." % (2 - slot)


func respawn(slot: int) -> void:
	dead[slot] = false
	remaining[slot] = 0.0
	players[slot].reset_at(anchors[checkpoint].position + Vector3(-1.2 + 2.4 * slot, 0, 0))
	players[slot].active = not paused
	players[slot].get_node("Body").visible = true
	returns[slot] += 1
	_jump_before[slot] = true
	_dash_before[slot] = true


func restart() -> void:
	wipe_remaining = 0.0
	for slot in range(2):
		respawn(slot)
	message = "Повтор от общей точки %d." % checkpoint


func reset_all() -> void:
	checkpoint = 0
	paused = false
	restart()
	wipes = 0
	returns.assign([0, 0])


func both_safe() -> bool:
	return checkpoint == 2 and not dead.has(true) and players.all(
			func(player: RecoveryPlayer) -> bool:
				return player.is_on_floor() and player.position.distance_to(anchors[2].position) < 3.0)


func assign_devices() -> void:
	var pads: Array[int] = Input.get_connected_joypads()
	devices[1] = pads[0] if pads.size() > 0 else -1
	devices[0] = pads[1] if pads.size() > 1 else -1


func _drive() -> void:
	for slot in range(2):
		var keys: Array[Key] = [KEY_A, KEY_D, KEY_W, KEY_S]
		if slot == 1:
			keys.assign([KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN])
		var move := Vector2(float(Input.is_physical_key_pressed(keys[1]))
				- float(Input.is_physical_key_pressed(keys[0])),
				float(Input.is_physical_key_pressed(keys[3]))
				- float(Input.is_physical_key_pressed(keys[2])))
		var jump: bool = Input.is_physical_key_pressed(KEY_SPACE if slot == 0 else KEY_ENTER)
		var dash: bool = Input.is_physical_key_pressed(KEY_SHIFT if slot == 0 else KEY_CTRL)
		if devices[slot] >= 0:
			move = Vector2(Input.get_joy_axis(devices[slot], JOY_AXIS_LEFT_X),
					Input.get_joy_axis(devices[slot], JOY_AXIS_LEFT_Y))
			if move.length() < 0.2:
				move = Vector2.ZERO
			jump = Input.is_joy_button_pressed(devices[slot], JOY_BUTTON_A)
			dash = Input.is_joy_button_pressed(devices[slot], JOY_BUTTON_X)
		players[slot].wish = Vector3(move.x, 0, move.y).limit_length() if not dead[slot] else Vector3.ZERO
		players[slot].jump_pressed = jump and not _jump_before[slot] and not dead[slot]
		players[slot].jump_held = jump and not dead[slot]
		players[slot].dash_pressed = dash and not _dash_before[slot] and not dead[slot]
		_jump_before[slot] = jump
		_dash_before[slot] = dash
