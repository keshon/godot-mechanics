extends Node3D

# 13 — dressing. The same dungeon, three times over.
#
# Three layers, and nothing below ever knows about the layer above it:
#
#   Gen.gd     bytes. four meanings per cell. no idea it will ever be drawn.
#   Dress.gd   bytes -> transforms. reads neighbours, picks a piece, turns it.
#   this file  transforms -> nodes. and the keys.
#
# Press 1 / 2 / 3 to peel the layers back. It is the same seed every time.

const LEVEL_NAME := [
	"",
	"1  plain — one box per wall cell, flat floor. this is probe 12.",
	"2  dressed — the neighbour mask picks a piece and turns it",
	"3  dressed + hand-drawn rooms stamped into the generated ones",
]

@export var cfg: DressGen
@export_range(14.0, 50.0) var view_size := 30.0

var seed_value := 3
var level := 3

var _dress := DungeonDress.new()
var _focus := Vector3.ZERO
var _sig := ""


func _ready() -> void:
	if cfg == null:
		cfg = DressGen.new()
	_focus = Vector3(float(cfg.width - 1) * 0.5, 0.0, float(cfg.height - 1) * 0.5)
	_rebuild()


func _process(delta: float) -> void:
	var pan := Vector3(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		0.0,
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward"))
	if pan != Vector3.ZERO:
		# WASD moves the map the way it looks on screen, not the way the grid runs
		_focus += Basis.from_euler(Vector3(0, PI * 0.25, 0)) * pan * delta * view_size * 0.9
	_place_camera()
	var now := "%d|%d|%d|%d|%d|%d|%d" % [seed_value, level, cfg.room_tries,
		cfg.room_min, cfg.room_max, cfg.loops, cfg.prefabs]
	if now != _sig:
		_sig = now
		_rebuild()
	_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				seed_value = randi() & 0xFFFF
			KEY_LEFT:
				seed_value -= 1
			KEY_RIGHT:
				seed_value += 1
			KEY_1, KEY_2, KEY_3:
				level = event.keycode - KEY_1 + 1
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			view_size = maxf(view_size - 2.0, 14.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			view_size = minf(view_size + 2.0, 50.0)


func _rebuild() -> void:
	cfg.build(seed_value, level >= 3)
	_dress.dress(cfg, level == 1)
	# every piece already sits in the scene as an empty MultiMesh with its own mesh
	# and material. this only refills them.
	for kind in _dress.pieces:
		var list: Array = _dress.pieces[kind]
		var mm: MultiMesh = get_node("Board/" + kind).multimesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
			if kind == "floor":
				mm.set_instance_color(i, _dress.floor_col[i])


func _place_camera() -> void:
	var cam: Camera3D = $Camera
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = view_size
	cam.position = _focus + Vector3(1.0, 1.0, 1.0).normalized() * 80.0
	cam.look_at(_focus, Vector3.UP)


func _hud() -> void:
	$Ui/Hud/Big.text = "SEED %d" % seed_value
	var t := "[b]%s[/b]\n\n[table=2]" % LEVEL_NAME[level]
	for k in cfg.stats:
		t += "[cell]%s  [/cell][cell]%s[/cell]" % [k, cfg.stats[k]]
	for k in _dress.stats:
		t += "[cell]%s  [/cell][cell]%s[/cell]" % [k, _dress.stats[k]]
	t += "[/table]\n\n"
	var row := ""
	for m in 16:
		if _dress.masks[m] > 0:
			row += "%d:%d  " % [m, _dress.masks[m]]
	t += "wall cells by neighbour mask\n%s" % row
	$Ui/Hud/Detail.text = t
