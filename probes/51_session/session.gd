class_name SessionRig
extends Node3D
## Explicit device ownership. Disconnected slots are reserved until claimed or released.
## Reconnection requires Start: OS device numbers are not persistent identities.

const EMPTY: int = -2
const KEYBOARD: int = -1
@export_range(0.05, 0.5, 0.05) var deadzone := 0.2
var devices: Array[int] = [EMPTY, EMPTY]
var connected: Array[bool] = [false, false]
var paused := false
var pause_owner: int = -1
var message := "ENTER / START — присоединиться"
@onready var players: Array[SessionPlayer] = [$Player1, $Player2]
@onready var _hud: RichTextLabel = $Ui/Info


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_connection_changed)


func _process(_delta: float) -> void:
	var lines: Array[String] = ["[b]51 · ДВА ИГРОКА / ОДНА СЕССИЯ[/b]"]
	for slot in range(2):
		var device: int = devices[slot]
		var source: String = "свободно" if device == EMPTY else (
				"клавиатура" if device == KEYBOARD else "геймпад %d" % device)
		if device != EMPTY and not connected[slot]:
			source += " — отключён; START любого свободного пульта вернёт слот"
		lines.append("Игрок %d: %s | доставок %d | груз %s" % [slot + 1, source,
				players[slot].deliveries, "есть" if players[slot].carrying else "нет"])
	lines.append("ПАУЗА · владелец: игрок %d" % (pause_owner + 1) if paused else "ИГРА")
	lines.append(message)
	lines.append("От своего дальнего круга к ближнему: возьми груз и доставь его.")
	lines.append("ENTER вход · WASD ходьба · P пауза/продолжить · BACKSPACE выйти")
	lines.append("Геймпад: START вход/пауза · левый стик ходьба · BACK выйти")
	lines.append("DELETE освободить отключённые слоты · 1 мёртвая зона: %.2f" % deadzone)
	lines.append("Пауза общая; продолжает её владелец. При отключении движение заморожено.")
	lines.append("[color=#66ccff]гипотеза: явные слоты сохраняют управление и прогресс[/color]")
	_hud.text = "\n".join(lines)


func _physics_process(_delta: float) -> void:
	for slot in range(2):
		players[slot].active = connected[slot] and not paused
		players[slot].wish = read_move(devices[slot]) if players[slot].active else Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ENTER:
				join(KEYBOARD)
			KEY_P:
				toggle_pause(KEYBOARD)
			KEY_BACKSPACE:
				leave(KEYBOARD)
			KEY_DELETE:
				for slot in range(2):
					if devices[slot] != EMPTY and not connected[slot]:
						leave(devices[slot])
			KEY_1:
				deadzone = 0.35 if deadzone < 0.3 else 0.1
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_START:
			if devices.has(event.device) and connected[devices.find(event.device)]:
				toggle_pause(event.device)
			else:
				join(event.device)
		elif event.button_index == JOY_BUTTON_BACK:
			leave(event.device)


func join(device: int) -> int:
	var slot: int = devices.find(device)
	if slot >= 0 and connected[slot]:
		return slot
	if slot < 0:
		# Reserve progress before filling a new slot; explicit confirmation avoids silent swaps.
		for candidate in range(2):
			if devices[candidate] != EMPTY and not connected[candidate]:
				slot = candidate
				break
	if slot < 0:
		slot = devices.find(EMPTY)
	if slot < 0:
		message = "Оба слота заняты; сначала выйди из одного."
		return -1
	devices[slot] = device
	connected[slot] = true
	if paused and pause_owner < 0:
		pause_owner = slot
	message = "Игрок %d вошёл. Прогресс сохранён." % (slot + 1)
	if paused:
		message += " Владелец паузы нажимает P / START для продолжения."
	return slot


func leave(device: int) -> void:
	var slot: int = devices.find(device)
	if slot < 0:
		return
	devices[slot] = EMPTY
	connected[slot] = false
	players[slot].wish = Vector2.ZERO
	players[slot].active = false
	if pause_owner == slot:
		pause_owner = connected.find(true)
	if not connected.has(true) and not devices.any(func(value: int) -> bool: return value != EMPTY):
		paused = false
		pause_owner = -1
	message = "Слот освобождён; позиция и доставки остаются до выхода из пробы."


func toggle_pause(device: int) -> void:
	var slot: int = devices.find(device)
	if slot < 0 or not connected[slot]:
		return
	if paused:
		if slot != pause_owner or has_missing_device():
			message = "Нужны все занятые пульты и подтверждение владельца паузы."
			return
		paused = false
		pause_owner = -1
	else:
		paused = true
		pause_owner = slot


func has_missing_device() -> bool:
	for slot in range(2):
		if devices[slot] != EMPTY and not connected[slot]:
			return true
	return false


func read_move(device: int) -> Vector2:
	if device == KEYBOARD:
		return Vector2(float(Input.is_physical_key_pressed(KEY_D))
				- float(Input.is_physical_key_pressed(KEY_A)),
				float(Input.is_physical_key_pressed(KEY_S))
				- float(Input.is_physical_key_pressed(KEY_W))).limit_length()
	if device < 0:
		return Vector2.ZERO
	return filter_stick(Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X),
			Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)))


func filter_stick(value: Vector2) -> Vector2:
	var length: float = value.length()
	if length <= deadzone:
		return Vector2.ZERO
	return value.normalized() * minf((length - deadzone) / (1.0 - deadzone), 1.0)


func _on_connection_changed(device: int, present: bool) -> void:
	var slot: int = devices.find(device)
	if present or slot < 0:
		return
	connected[slot] = false
	players[slot].wish = Vector2.ZERO
	paused = true
	pause_owner = slot
	message = "Пульт отключён. START свободного пульта возвращает зарезервированный слот."
