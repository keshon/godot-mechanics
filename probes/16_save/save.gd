class_name SaveBench
extends Node3D
## What in the world is true.
##
## The experiment, run whole every time you press T:
##
##   play A turns  ->  remember the digest  ->  save both ways
##   keep playing B turns in the live world  ->  this is the truth
##   load each file, check it matches the past, play the same B turns,
##   check it matches the truth
##
## Two verdicts per format. PAST asks "did the file bring back the moment I
## saved". FUTURE asks "does the world carry on the way it would have". They
## fail separately, and which one fails tells you which mistake you made.

const STATE_PATH := "user://probe16_state.sav"
const REPLAY_PATH := "user://probe16_replay.sav"
## Which world the board is showing, in the order the keys 1 2 3 pick them.
const VIEWS := ["truth", "state", "replay"]

@export_range(10, 400) var turns_before := 60
@export_range(10, 200) var turns_after := 40

@export_group("The build that loads the file")
## Save where the die had got to. Off is the classic bug.
@export var keep_die := true
## One decision drawn from the global generator instead of the world's own.
@export var leak := false
## Pretend a later build nudged one rule constant.
@export var patched := false

var seed_value := 3
## 1, 2 or 3 — which of VIEWS is on the board.
var show := 1
var bytes_state := 0
var bytes_replay := 0
## How long the whole experiment took, ms.
var experiment_ms := 0.0
var verdict := {}
var worlds := {}

var _last_signature := ""

@onready var _floor: MultiMeshInstance3D = $Floor
@onready var _actors: MultiMeshInstance3D = $Actors
@onready var _camera: Camera3D = $Camera
@onready var _hud: RichTextLabel = $Ui/Info


func _ready() -> void:
	run_test()


func _process(_delta: float) -> void:
	var now := "%d|%d|%d|%s|%s|%s" % [
		seed_value, turns_before, turns_after, keep_die, leak, patched]
	if now != _last_signature:
		_last_signature = now
		run_test()
	_draw_hud()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_T:
			run_test()
		KEY_SPACE:
			seed_value = randi() & 0xFFFF
		KEY_LEFT:
			seed_value -= 1
		KEY_RIGHT:
			seed_value += 1
		KEY_K:
			keep_die = not keep_die
		KEY_L:
			leak = not leak
		KEY_V:
			patched = not patched
		KEY_1, KEY_2, KEY_3:
			show = event.keycode - KEY_1 + 1
			_draw_world()


func run_test() -> void:
	var started := Time.get_ticks_usec()
	var script := _move_script(seed_value, turns_before + turns_after)

	# The build that WROTE the file is always a clean one.
	SaveWorld.leak = false
	SaveWorld.patched = false

	var live := SaveWorld.new()
	live.begin(seed_value)
	for i in turns_before:
		live.play(script[i])
	var at_save := live.digest()
	bytes_state = SaveIO.write_state(live, STATE_PATH, keep_die)
	bytes_replay = SaveIO.write_replay(live, REPLAY_PATH)

	# From here on we are the build that READS it.
	SaveWorld.leak = leak
	SaveWorld.patched = patched

	for i in range(turns_before, script.size()):
		live.play(script[i])
	var truth := live.digest()

	var results := {}
	var loaded := {
		"state": SaveIO.read_state(STATE_PATH),
		"replay": SaveIO.read_replay(REPLAY_PATH),
	}
	for format in loaded:
		var world: SaveWorld = loaded[format]
		if world == null:
			results[format] = {"past": false, "future": false}
			continue
		var past: bool = world.digest() == at_save
		for i in range(turns_before, script.size()):
			world.play(script[i])
		results[format] = {"past": past, "future": world.digest() == truth}
		worlds[format] = world
	worlds["truth"] = live

	SaveWorld.leak = false
	SaveWorld.patched = false
	verdict = results
	experiment_ms = (Time.get_ticks_usec() - started) / 1000.0
	_draw_world()


## A fixed list of moves, so every run of the experiment is the same game.
func _move_script(from_seed: int, count: int) -> Array[Vector2i]:
	var random := RandomNumberGenerator.new()
	random.seed = from_seed * 7919 + 13
	var moves: Array[Vector2i] = []
	for _i in count:
		moves.append(SaveWorld.DIRS[random.randi() % 4])
	return moves


func _draw_world() -> void:
	var world: SaveWorld = worlds.get(VIEWS[show - 1])
	if world == null:
		return

	var floors: Array[Transform3D] = []
	for i in world.map.size():
		if world.map[i] == SaveWorld.Cell.FLOOR:
			floors.append(Transform3D(
					Basis.IDENTITY,
					Vector3(i % SaveWorld.WIDTH, 0.0, i / SaveWorld.WIDTH)))
	var floor_mesh: MultiMesh = _floor.multimesh
	floor_mesh.instance_count = floors.size()
	for i in floors.size():
		floor_mesh.set_instance_transform(i, floors[i])

	var actor_mesh: MultiMesh = _actors.multimesh
	actor_mesh.instance_count = world.actors.size()
	for i in world.actors.size():
		var actor: Dictionary = world.actors[i]
		actor_mesh.set_instance_transform(
				i,
				Transform3D(Basis.IDENTITY, Vector3(actor["x"], 0.7, actor["y"])))
		var hurt := float(actor["hp"]) / 20.0
		actor_mesh.set_instance_color(i, (
				Color(1.0, 0.35 + hurt * 0.6, 0.3 + hurt * 0.6) if i > 0
				else Color(0.5, 0.9, 1.0)
		))

	var mid := Vector3(SaveWorld.WIDTH * 0.5, 0.0, SaveWorld.HEIGHT * 0.5)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 26.0
	_camera.position = mid + Vector3(1.0, 1.0, 1.0).normalized() * 70.0
	_camera.look_at(mid, Vector3.UP)


func _draw_hud() -> void:
	var agreed := _all_ok()
	var names := ["правда (не сохранялась)", "загружено из СОСТОЯНИЯ",
			"загружено из ЗАПИСИ"]
	var text := "зерно [b]%d[/b]   сохранено на %d ходу, сыграно ещё %d   %s\n" % [
		seed_value, turns_before, turns_after,
		"[color=#7fe08a]все четыре сходятся[/color]" if agreed
			else "[color=#ff8a6a]расходятся[/color]"]
	text += "на доске: [b]%s[/b]\n\n" % names[show - 1]

	text += "[table=3][cell][b]формат[/b]  [/cell][cell][b]вернул прошлое[/b]  [/cell]"
	text += "[cell][b]то же будущее[/b][/cell]"
	for format in ["state", "replay"]:
		var one: Dictionary = verdict.get(format, {})
		text += "[cell]%-11s  [/cell][cell]%s  [/cell][cell]%s[/cell]" % [
			"состояние" if format == "state" else "запись",
			_mark(one.get("past", false)), _mark(one.get("future", false))]
	text += "[/table]\n\n[table=2]"
	text += "[cell]файл состояния  [/cell][cell]%d байт[/cell]" % bytes_state
	text += "[cell]файл записи  [/cell][cell]%d байт[/cell]" % bytes_replay
	text += "[cell]весь опыт  [/cell][cell]%.1f мс[/cell]" % experiment_ms
	text += "[/table]\n\n"

	text += "T прогнать опыт   ПРОБЕЛ новое зерно   ← → зерно −1 +1\n"
	text += "1 2 3 показать правду, загрузку состояния, загрузку записи\n"
	text += "K сохранять положение кубика: %s\n" % _switch(keep_die)
	text += "L течь: один бросок из общего генератора: %s\n" % _switch(leak)
	text += "V грузит сборка с правкой правила: %s\n\n" % _switch(patched)
	text += "[color=#66ccff]два вердикта, а не один: прошлое спрашивает, вернулась ли та"
	text += " минута, будущее — пойдёт ли мир дальше так же[/color]"
	_hud.text = text


func _all_ok() -> bool:
	for format in ["state", "replay"]:
		var one: Dictionary = verdict.get(format, {})
		if not one.get("past", false) or not one.get("future", false):
			return false
	return true


func _mark(passed: bool) -> String:
	return "[color=#7fe08a]да[/color]" if passed else "[color=#ff8a6a]НЕТ[/color]"


func _switch(on: bool) -> String:
	return "[color=#7fe08a]вкл[/color]" if on else "выкл"

