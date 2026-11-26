class_name PuzzleCheckpoint
extends Node
## Versioned authored states: transient timers, carriers and arbitrary positions are not persisted.

const PHASES: Array[String] = ["unpowered", "powered", "complete"]
@export var path := "user://probe58_checkpoint.json"
var phase := "unpowered"
var message := "Контрольная точка: начало"


func capture(current: String) -> void:
	if PHASES.has(current):
		phase = current
		message = "Точка в памяти: " + phase


func save_file() -> bool:
	var temporary: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		message = "Не удалось открыть файл для записи."
		return false
	file.store_string(JSON.stringify({"kind": "puzzle58", "version": 1, "phase": phase}))
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(temporary, path)
	message = "Точка записана на диск." if error == OK else "Ошибка записи; прежний файл сохранён."
	return error == OK


func load_file() -> bool:
	if not FileAccess.file_exists(path):
		message = "Файла нет; состояние комнаты сохранено."
		return false
	var parser := JSON.new()
	var error: Error = parser.parse(FileAccess.get_file_as_string(path))
	if error != OK or not valid(parser.data):
		message = "Файл повреждён или несовместим; комната не изменена."
		return false
	phase = parser.data["phase"]
	message = "Точка загружена с диска: " + phase
	return true


func valid(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if typeof(value.get("version")) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	if not value.get("kind") is String:
		return false
	if value.get("kind") != "puzzle58" or value.get("version") != 1:
		return false
	return value.get("phase") is String and PHASES.has(value["phase"])
