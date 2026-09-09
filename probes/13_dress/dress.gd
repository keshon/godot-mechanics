class_name DressWorld
extends Node3D
## Dressing. The same dungeon, three times over.
##
## Three layers, and nothing below ever knows about the layer above it:
##
##   gen.gd     bytes. Four meanings per cell. No idea it will ever be drawn.
##   tiler.gd   bytes -> transforms. Reads neighbours, picks a piece, turns it.
##   this file  transforms -> nodes. And the keys.
##
## Press 1 / 2 / 3 to peel the layers back. It is the same seed every time.

const LEVEL_NAME := [
	"",
	"1  plain — one box per wall cell, flat floor. this is probe 12.",
	"2  dressed — the neighbour mask picks a piece and turns it",
	"3  dressed + hand-drawn rooms stamped into the generated ones",
]

@export var rules: DressGen
## Half-height of the orthogonal camera, m.
@export_range(14.0, 50.0) var view_size := 30.0

var seed_value := 3
## Which of the three layers to show, 1 to 3.
var level := 3

var _tiler := DressTiler.new()
var _focus := Vector3.ZERO
## What the knobs looked like last frame. Any difference rebuilds the same seed.
var _last_signature := ""

@onready var _board: Node3D = $Board
@onready var _camera: Camera3D = $Camera
@onready var _seed_label: Label = $Ui/Hud/Seed
@onready var _detail: RichTextLabel = $Ui/Hud/Detail


func _ready() -> void:
	if rules == null:
		rules = DressGen.new()
	_focus = Vector3(float(rules.width - 1) * 0.5, 0.0, float(rules.height - 1) * 0.5)
	_rebuild()


func _process(delta: float) -> void:
	var pan := Vector3(
			Input.get_action_strength(&"move_right")
					- Input.get_action_strength(&"move_left"),
			0.0,
			Input.get_action_strength(&"move_back")
					- Input.get_action_strength(&"move_forward"))
	if pan != Vector3.ZERO:
		# WASD moves the map the way it LOOKS on screen, not the way the grid
		# runs: the camera stands at 45 degrees, so the pan is turned to match.
		_focus += Basis.from_euler(Vector3(0.0, PI * 0.25, 0.0)) * pan * delta * view_size * 0.9
	_place_camera()

	var now := "%d|%d|%d|%d|%d|%d|%d" % [
		seed_value, level, rules.room_tries, rules.room_min, rules.room_max,
		rules.loops, rules.prefabs]
	if now != _last_signature:
		_last_signature = now
		_rebuild()
	_draw_hud()


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


## Every piece already sits in the scene as an empty MultiMesh with its own mesh
## and material, and the tiler's dictionary keys ARE those node names. This only
## refills them — adding a piece means adding a node and a key, never code here.
func _rebuild() -> void:
	rules.build(seed_value, level >= 3)
	_tiler.dress(rules, level == 1)
	for kind in _tiler.pieces:
		var placings: Array = _tiler.pieces[kind]
		var multi_mesh: MultiMesh = _board.get_node(NodePath(kind)).multimesh
		multi_mesh.instance_count = placings.size()
		for i in placings.size():
			multi_mesh.set_instance_transform(i, placings[i])
			if kind == "Floor":
				multi_mesh.set_instance_color(i, _tiler.floor_tint[i])


func _place_camera() -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = view_size
	_camera.position = _focus + Vector3(1.0, 1.0, 1.0).normalized() * 80.0
	_camera.look_at(_focus, Vector3.UP)


func _draw_hud() -> void:
	_seed_label.text = "SEED %d" % seed_value
	var text := "[b]%s[/b]\n\n[table=2]" % LEVEL_NAME[level]
	for key in rules.stats:
		text += "[cell]%s  [/cell][cell]%s[/cell]" % [key, rules.stats[key]]
	for key in _tiler.stats:
		text += "[cell]%s  [/cell][cell]%s[/cell]" % [key, _tiler.stats[key]]
	text += "[/table]\n\n"
	var row := ""
	for mask in 16:
		if _tiler.masks[mask] > 0:
			row += "%d:%d  " % [mask, _tiler.masks[mask]]
	text += "wall cells by neighbour mask\n%s" % row
	_detail.text = text
