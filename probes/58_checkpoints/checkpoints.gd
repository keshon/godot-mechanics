class_name CheckpointsRig
extends Node3D
## Reapply an authored room state in one call, reusing entities and clearing transient intentions.

@export var gate_duration := 6.0
var phase := "unpowered"
var gate_remaining := 0.0
var restores: int = 0
var devices: Array[int] = [-1, -1]
var read_input := true
var message := "Вставь ядро в розетку, включи рычаг, пройдите дверь вдвоём."
var _actions: Array[bool] = [false, false]
@onready var players: Array[CheckpointPlayer] = [$Player1, $Player2]
@onready var core: CheckpointCore = $Core
@onready var door: CheckpointDoor = $Door
@onready var checkpoint: PuzzleCheckpoint = $Checkpoint
@onready var socket: Marker3D = $Socket
@onready var lever: Marker3D = $Lever
@onready var _hud: RichTextLabel = $Ui/Info


func _ready() -> void:
	assign_devices()
	restore()
	restores = 0


func _physics_process(delta: float) -> void:
	for slot in range(2):
		if read_input:
			var move: Vector2 = read_move(slot)
			players[slot].wish = Vector3(move.x, 0, move.y)
		if _actions[slot]:
			interact(slot)
		_actions[slot] = false
	gate_remaining = maxf(0.0, gate_remaining - delta)
	if phase == "powered" and players.all(func(player: CheckpointPlayer) -> bool:
			return (player.is_on_floor() and player.position.z < -8
			and absf(player.position.x) < 5.0 and absf(player.position.y) < 0.3)):
		phase = "complete"
		gate_remaining = 0.0
		checkpoint.capture(phase)
		message = "Оба прошли. Финальная точка сохранена в памяти."
	door.set_open(phase == "complete" or gate_remaining > 0.0, players)
	if core.position.y < -4 or players.any(func(player: CheckpointPlayer) -> bool:
			return player.position.y < -4):
		restore()


func _process(_delta: float) -> void:
	_hud.text = "\n".join(PackedStringArray([
		"[b]58 · КОМНАТА ПОСЛЕ СБОЯ[/b] · " + {
			"unpowered": "нет питания", "powered": "питание есть", "complete": "оба прошли"}[phase],
		"Дверь: %s · таймер %.1f с · восстановлений %d" % [
			"ждёт выхода из проёма" if door.waiting else ("открыта" if door.opened else "закрыта"),
			gate_remaining, restores],
		checkpoint.message,
		message,
		"P1 WASD / E · P2 стрелки / ENTER · действие: взять, вставить, рычаг",
		"Пульт: стик / X · 0 назначить подключённые пульты",
		"C точка в памяти · R восстановить · F5 записать на диск · F9 загрузить",
		"N новая комната · 2 сбой и возврат · 1 время двери: %.0f с" % gate_duration,
		"Возврат восстанавливает этап: таймер обнулён, руки свободны, ядро на месте.",
		"После восстановления питания рычаг можно включать повторно.",
		"[color=#66ccff]гипотеза: контрольная точка возвращает решаемую комнату[/color]",
	]))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		var slot: int = devices.find(event.device)
		if slot >= 0 and event.button_index == JOY_BUTTON_X:
			_actions[slot] = true
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_E:
			_actions[0] = devices[0] < 0
		KEY_ENTER:
			_actions[1] = devices[1] < 0
		KEY_C:
			checkpoint.capture(phase)
		KEY_R, KEY_2:
			restore()
		KEY_N:
			checkpoint.capture("unpowered")
			restore()
		KEY_F5:
			checkpoint.save_file()
		KEY_F9:
			load_checkpoint()
		KEY_1:
			gate_duration = 12.0 if gate_duration < 10 else 6.0
		KEY_0:
			assign_devices()


func interact(slot: int) -> void:
	var player: CheckpointPlayer = players[slot]
	if phase == "powered" and player.position.distance_to(lever.position) < 2.0:
		gate_remaining = gate_duration
		message = "P%d включил дверь. Пройдите вместе." % (slot + 1)
	elif core.carrier == player:
		if core.position.distance_to(socket.position) < 2.0:
			core.restore(socket.position, true)
			phase = "powered"
			checkpoint.capture(phase)
			message = "Питание закреплено. Рычаг слева открывает дверь."
		else:
			core.carrier = null
			core.velocity = Vector3.ZERO
			message = "Ядро отпущено."
	elif not core.locked and core.carrier == null and core.reachable(player):
		core.carrier = player
		message = "Ядро у P%d." % (slot + 1)
	else:
		message = "Подойди к свободному ядру или к рычагу при включённом питании."


func restore() -> void:
	# These authored positions are clear of the door, even if failure happened in the doorway.
	phase = checkpoint.phase
	gate_remaining = 0.0
	_actions.assign([false, false])
	for slot in range(2):
		var position_z: float = 4.0 if phase == "unpowered" else (-2.0 if phase == "powered" else -10.0)
		players[slot].reset_at(Vector3(-1.2 + slot * 2.4, 0.05, position_z))
	core.restore(Vector3(0, 0.4, 2.5) if phase == "unpowered" else socket.position,
			phase != "unpowered")
	door.set_open(phase == "complete", players, true)
	restores += 1
	message = "Этап восстановлен; временные действия сброшены."


func load_checkpoint() -> bool:
	if not checkpoint.load_file():
		return false
	restore()
	return true


func assign_devices() -> void:
	core.carrier = null
	var pads: Array[int] = Input.get_connected_joypads()
	devices[1] = pads[0] if pads.size() > 0 else -1
	devices[0] = pads[1] if pads.size() > 1 else -1


func read_move(slot: int) -> Vector2:
	var device: int = devices[slot]
	if device >= 0:
		var value := Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X),
				Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
		return Vector2.ZERO if value.length() < 0.2 else value.limit_length()
	var keys: Array[Key] = [KEY_A, KEY_D, KEY_W, KEY_S]
	if slot == 1:
		keys.assign([KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN])
	return Vector2(float(Input.is_physical_key_pressed(keys[1]))
			- float(Input.is_physical_key_pressed(keys[0])),
			float(Input.is_physical_key_pressed(keys[3]))
			- float(Input.is_physical_key_pressed(keys[2]))).limit_length()
