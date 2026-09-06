extends Node3D

# 16 — what in the world is true.
#
# The experiment, run whole every time you press T:
#
#   play A turns  ->  remember the digest  ->  save both ways
#   keep playing B turns in the live world  ->  this is the truth
#   load each file, check it matches the past, play the same B turns,
#   check it matches the truth
#
# Two verdicts per format. PAST asks "did the file bring back the moment I saved".
# FUTURE asks "does the world carry on the way it would have". They fail separately,
# and which one fails tells you which mistake you made.

const STATE_PATH := "user://probe16_state.sav"
const REPLAY_PATH := "user://probe16_replay.sav"

@export_range(10, 400) var turns_before := 60
@export_range(10, 200) var turns_after := 40

@export_group("The build that loads the file")
## save where the die had got to. off = the classic bug.
@export var keep_die := true
## one decision drawn from the global generator instead of the world's own
@export var leak := false
## pretend a later build nudged one rule constant
@export var patched := false

var seed_value := 3
var show := 1
var bytes_state := 0
var bytes_replay := 0
var ms := 0.0
var verdict := {}
var worlds := {}

var _sig := ""


func _ready() -> void:
	run_test()


func _process(_delta: float) -> void:
	var now := "%d|%d|%d|%s|%s|%s" % [seed_value, turns_before, turns_after, keep_die, leak, patched]
	if now != _sig:
		_sig = now
		run_test()
	_hud()


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


# --- the experiment -----------------------------------------------------------

func run_test() -> void:
	var t0 := Time.get_ticks_usec()
	var script := _script(seed_value, turns_before + turns_after)

	# the build that WROTE the file is always a clean one
	SaveWorld.leak = false
	SaveWorld.patched = false

	var live := SaveWorld.new()
	live.begin(seed_value)
	for i in turns_before:
		live.play(script[i])
	var at_save := live.digest()
	bytes_state = SaveIO.write_state(live, STATE_PATH, keep_die)
	bytes_replay = SaveIO.write_replay(live, REPLAY_PATH)

	# from here on we are the build that READS it
	SaveWorld.leak = leak
	SaveWorld.patched = patched

	for i in range(turns_before, script.size()):
		live.play(script[i])
	var truth := live.digest()

	var out := {}
	for pair in [["state", SaveIO.read_state(STATE_PATH)], ["replay", SaveIO.read_replay(REPLAY_PATH)]]:
		var name: String = pair[0]
		var w: SaveWorld = pair[1]
		if w == null:
			out[name] = {"past": false, "future": false}
			continue
		var past: bool = w.digest() == at_save
		for i in range(turns_before, script.size()):
			w.play(script[i])
		out[name] = {"past": past, "future": w.digest() == truth}
		worlds[name] = w
	worlds["truth"] = live

	SaveWorld.leak = false
	SaveWorld.patched = false
	verdict = out
	ms = (Time.get_ticks_usec() - t0) / 1000.0
	_draw_world()


func _script(s: int, n: int) -> Array[Vector2i]:
	# a fixed list of moves, so every run of the experiment is the same game
	var r := RandomNumberGenerator.new()
	r.seed = s * 7919 + 13
	var out: Array[Vector2i] = []
	for _i in n:
		out.append(SaveWorld.DIRS[r.randi() % 4])
	return out


# --- board --------------------------------------------------------------------

func _draw_world() -> void:
	var key: String = ["truth", "state", "replay"][show - 1]
	var w: SaveWorld = worlds.get(key)
	if w == null:
		return
	var floors: Array[Transform3D] = []
	for i in w.map.size():
		if w.map[i] == SaveWorld.FLOOR:
			floors.append(Transform3D(Basis.IDENTITY, Vector3(i % SaveWorld.W, 0.0, i / SaveWorld.W)))
	var mmf: MultiMesh = $Floor.multimesh
	mmf.instance_count = floors.size()
	for i in floors.size():
		mmf.set_instance_transform(i, floors[i])

	var mma: MultiMesh = $Actors.multimesh
	mma.instance_count = w.actors.size()
	for i in w.actors.size():
		var a: Dictionary = w.actors[i]
		mma.set_instance_transform(i,
			Transform3D(Basis.IDENTITY, Vector3(a["x"], 0.7, a["y"])))
		var hurt := float(a["hp"]) / 20.0
		mma.set_instance_color(i, Color(1.0, 0.35 + hurt * 0.6, 0.3 + hurt * 0.6) if i > 0
			else Color(0.5, 0.9, 1.0))

	var mid := Vector3(SaveWorld.W * 0.5, 0.0, SaveWorld.H * 0.5)
	var cam: Camera3D = $Camera
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 26.0
	cam.position = mid + Vector3(1.0, 1.0, 1.0).normalized() * 70.0
	cam.look_at(mid, Vector3.UP)


func _hud() -> void:
	$Ui/Hud/Big.text = "all four agree" if _all_ok() else "they disagree"
	$Ui/Hud/Big.modulate = Color(0.6, 1, 0.7) if _all_ok() else Color(1, 0.6, 0.5)

	var t := "[b]seed %d    %d turns saved, %d more played[/b]\n\n" % [
		seed_value, turns_before, turns_after]
	t += "[table=3]"
	t += "[cell][b]format[/b]  [/cell][cell][b]brings back the past[/b]  [/cell][cell][b]same future[/b][/cell]"
	for k in ["state", "replay"]:
		var v: Dictionary = verdict.get(k, {})
		t += "[cell]%-7s  [/cell][cell]%s  [/cell][cell]%s[/cell]" % [k,
			_mark(v.get("past", false)), _mark(v.get("future", false))]
	t += "[/table]\n\n"
	t += "[table=2]"
	t += "[cell]state file  [/cell][cell]%d bytes[/cell]" % bytes_state
	t += "[cell]replay file  [/cell][cell]%d bytes[/cell]" % bytes_replay
	t += "[cell]whole experiment  [/cell][cell]%.1f ms[/cell]" % ms
	t += "[/table]\n\n"
	t += "K  save the die's position   %s\n" % _sw(keep_die)
	t += "L  leak: one draw from the global generator   %s\n" % _sw(leak)
	t += "V  loaded by a patched build   %s\n" % _sw(patched)
	$Ui/Hud/Detail.text = t

	var names := ["truth (never saved)", "loaded from STATE", "loaded from REPLAY"]
	$Ui/Hud/Which.text = "showing: [b]%s[/b]      1 2 3 to switch" % names[show - 1]


func _all_ok() -> bool:
	for k in ["state", "replay"]:
		var v: Dictionary = verdict.get(k, {})
		if not v.get("past", false) or not v.get("future", false):
			return false
	return true


func _mark(b: bool) -> String:
	return "[color=#7fe08a]yes[/color]" if b else "[color=#ff8a6a]NO[/color]"


func _sw(b: bool) -> String:
	return "[color=#7fe08a]on[/color]" if b else "[color=#888888]off[/color]"
