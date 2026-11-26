class_name OwnershipRig
extends Node3D
## A session routes requests; each object remains the authority for its own ownership.

var devices: Array[int] = [-1, -1]
var connected: Array[bool] = [true, true]
var cooldown: Array[float] = [0.0, 0.0]
var messages: Array[String] = ["подойди к ядру", "подойди к ядру"]
var _actions: Array[bool] = [false, false]
@onready var players: Array[OwnershipPlayer] = [$Player1, $Player2]
@onready var items: Array[OwnershipItem] = [$Core1, $Core2]
@onready var socket: Marker3D = $Socket
@onready var _hud: RichTextLabel = $Ui/Info


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_connection_changed)
	assign_devices()
	for item in items:
		item.claimed.connect(_on_item_claimed.bind(item))
		item.released.connect(_on_item_released)


func _physics_process(delta: float) -> void:
	for slot in range(2):
		cooldown[slot] = maxf(0, cooldown[slot] - delta)
		players[slot].available = connected[slot] and cooldown[slot] == 0.0
		var move: Vector2 = read_move(slot) if players[slot].available else Vector2.ZERO
		players[slot].wish = Vector3(move.x, 0, move.y)
		if _actions[slot] and players[slot].available:
			interact(slot)
		_actions[slot] = false


func _process(_delta: float) -> void:
	var lines: Array[String] = ["[b]56 · КОМУ ПРИНАДЛЕЖИТ ПРЕДМЕТ[/b]"]
	for slot in range(2):
		var status: String = "готов" if players[slot].available else "нет / восстановление"
		lines.append("P%d (%s): %s · %s" % [slot + 1, status, prompt(slot), messages[slot]])
	lines.append("Использований у розетки: %d · споры: очередь P%d / P%d" % [
			items[0].uses + items[1].uses, items[0].next_priority + 1, items[1].next_priority + 1])
	lines.append("P1 WASD · E взять / отпустить / применить · Q отмена · F смерть")
	lines.append("P2 стрелки · ENTER действие · BACKSPACE отмена · DELETE смерть")
	lines.append("Пульт: стик · X действие · B отмена · Y смерть · START возврат")
	lines.append("1 / 2 отключить слот: %s / %s · 0 назначить пульты · R сброс" % [
			"в сети" if connected[0] else "нет", "в сети" if connected[1] else "нет"])
	lines.append("3 одновременная заявка · у барьера захват сквозь стену запрещён")
	lines.append("Принеси ядро к зелёной розетке и нажми действие; затем поменяйтесь.")
	lines.append("[color=#66ccff]гипотеза: спор имеет одного победителя, "
			+ "отказ освобождает предмет[/color]")
	_hud.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		var slot: int = devices.find(event.device)
		if slot >= 0:
			match event.button_index:
				JOY_BUTTON_X:
					_actions[slot] = true
				JOY_BUTTON_B:
					cancel(slot)
				JOY_BUTTON_Y:
					fail(slot)
				JOY_BUTTON_START:
					set_connected(slot, true)
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_E:
			_actions[0] = devices[0] < 0
		KEY_ENTER:
			_actions[1] = devices[1] < 0
		KEY_Q:
			cancel(0)
		KEY_BACKSPACE:
			cancel(1)
		KEY_F:
			fail(0)
		KEY_DELETE:
			fail(1)
		KEY_1, KEY_2:
			var slot: int = event.keycode - KEY_1
			set_connected(slot, not connected[slot])
		KEY_3:
			_actions.assign([true, true])
		KEY_0:
			assign_devices()
		KEY_R:
			reset()


func interact(slot: int) -> void:
	if not players[slot].available:
		return
	for item in items:
		if item.owner_slot == slot:
			if not item.use_at(slot, socket_for(item)):
				item.release("отпущено")
			return
	var item: OwnershipItem = nearest(slot)
	if item == null:
		messages[slot] = "далеко или за стеной"
	elif item.owner_slot >= 0:
		messages[slot] = "занято P%d" % (item.owner_slot + 1)
	else:
		item.request(slot, players[slot])
		messages[slot] = "заявка на " + item.caption


func nearest(slot: int) -> OwnershipItem:
	var selected: OwnershipItem = null
	var distance := INF
	for item in items:
		var candidate: float = item.position.distance_squared_to(players[slot].position)
		if candidate < distance and item.can_reach(players[slot]):
			selected = item
			distance = candidate
	return selected


func prompt(slot: int) -> String:
	if not players[slot].available:
		return "—"
	for item in items:
		if item.owner_slot == slot:
			return "применить" if item.can_use_at(slot, socket_for(item)) else "отпустить"
	var item: OwnershipItem = nearest(slot)
	return "подойди" if item == null else ("взять " + item.caption if item.owner_slot < 0
			else "занято P%d" % (item.owner_slot + 1))


func cancel(slot: int) -> void:
	_actions[slot] = false
	for item in items:
		item.cancel(slot)


func socket_for(item: OwnershipItem) -> Vector3:
	return socket.global_position + Vector3(-0.5 + items.find(item), 0, 0)


func set_connected(slot: int, present: bool) -> void:
	cancel(slot)
	connected[slot] = present
	players[slot].available = present and cooldown[slot] == 0.0
	players[slot].wish = Vector3.ZERO
	messages[slot] = "подключён" if present else "отключён; предмет освобождён"


func fail(slot: int) -> void:
	cancel(slot)
	cooldown[slot] = 1.0
	players[slot].available = false
	players[slot].reset_at(Vector3(-1 + slot * 2, 0.1, 3))
	messages[slot] = "смерть; возврат через 1 с"


func reset() -> void:
	for slot in range(2):
		cancel(slot)
		cooldown[slot] = 0
		players[slot].reset_at(Vector3(-1 + slot * 2, 0.1, 3))
	for item in items:
		item.reset()


func assign_devices() -> void:
	var pads: Array[int] = Input.get_connected_joypads()
	for slot in range(2):
		set_connected(slot, true)
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
			- float(Input.is_physical_key_pressed(keys[0])), float(Input.is_physical_key_pressed(keys[3]))
			- float(Input.is_physical_key_pressed(keys[2]))).limit_length()


func _on_connection_changed(device: int, present: bool) -> void:
	if not present and devices.has(device):
		set_connected(devices.find(device), false)


func _on_item_claimed(slot: int, item: OwnershipItem) -> void:
	messages[slot] = "взял " + item.caption
	var other: int = 1 - slot
	if messages[other] == "заявка на " + item.caption:
		messages[other] = "спор: первым P%d" % (slot + 1)


func _on_item_released(slot: int, reason: String) -> void:
	messages[slot] = reason
