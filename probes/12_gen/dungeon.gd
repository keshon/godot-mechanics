class_name DungeonWorld
extends Node3D
## Generation. A number goes in, a dungeon comes out.
##
## This file only draws and takes keys. All the generating is in gen.gd, which
## never touches a node — that split is most of why it can be checked at all.
##
## The knobs live on the DungeonGen resource in the inspector. Turn one while
## the game runs and the map rebuilds on the spot, from the same seed.

const PASS_NAME := [
	"",
	"1  rooms thrown at the grid",
	"2  links chosen (amber line = a corridor that will be dug)",
	"3  corridors carved",
	"4  flood fill: red is floor you cannot walk to",
	"5  stairs at the two ends of the longest walk",
]

@export var rules: DungeonGen
## Half-height of the orthogonal camera, m.
@export_range(20.0, 60.0) var view_size := 36.0

var seed_value := 7
## Which pass to stop after, 1 to 5. The whole point of the probe is watching
## them one at a time.
var shown := 5

## What the knobs looked like last frame. Any difference rebuilds the same seed,
## which is what makes the inspector feel live.
var _last_signature := ""

@onready var _floor: MultiMeshInstance3D = $Floor
@onready var _walls: MultiMeshInstance3D = $Walls
@onready var _links: MultiMeshInstance3D = $Links
@onready var _entrance: MeshInstance3D = $Entrance
@onready var _stairs: MeshInstance3D = $Stairs
@onready var _camera: Camera3D = $Camera
@onready var _seed_label: Label = $Ui/Hud/Seed
@onready var _detail: RichTextLabel = $Ui/Hud/Detail


func _ready() -> void:
	if rules == null:
		rules = DungeonGen.new()
	_rebuild()
	_frame_camera()


func _process(_delta: float) -> void:
	var now := _signature()
	if now != _last_signature:
		_last_signature = now
		_rebuild()
	_draw_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				seed_value = randi() & 0xFFFFFF
			KEY_LEFT:
				seed_value -= 1
			KEY_RIGHT:
				seed_value += 1
			KEY_S:
				rules.style = (
						DungeonGen.Style.CAVE if rules.style == DungeonGen.Style.ROOMS
						else DungeonGen.Style.ROOMS
				)
			KEY_L:
				rules.naive_links = not rules.naive_links
			KEY_K:
				rules.keep_largest = not rules.keep_largest
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				shown = event.keycode - KEY_1 + 1
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			view_size = maxf(view_size - 2.0, 20.0)
			_frame_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			view_size = minf(view_size + 2.0, 60.0)
			_frame_camera()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			seed_value = randi() & 0xFFFFFF


func _signature() -> String:
	return "%d|%d|%d|%d|%d|%d|%d|%s|%.2f|%d|%s" % [
		seed_value, shown, rules.style, rules.room_tries, rules.room_min,
		rules.room_max, rules.loops, rules.naive_links, rules.cave_fill,
		rules.cave_smooth, rules.keep_largest]


func _rebuild() -> void:
	rules.build(seed_value, shown)
	_draw_floor()
	_draw_walls()
	_draw_links()
	_draw_ends()


func _draw_floor() -> void:
	var places: Array[Vector2i] = []
	var colours: Array[Color] = []
	for i in rules.cells.size():
		if rules.cells[i] == DungeonGen.Cell.ROCK:
			continue
		places.append(Vector2i(i % rules.width, i / rules.width))
		if shown >= 4 and rules.region[i] == 0:
			colours.append(Color(0.85, 0.3, 0.26))  # carved, and nobody can get here
		elif rules.cells[i] == DungeonGen.Cell.HALL:
			colours.append(Color(0.46, 0.44, 0.42))
		else:
			colours.append(Color(0.95, 0.95, 0.97))
	_floor.multimesh = _fill(_box(Vector3(0.95, 0.1, 0.95)), places, -0.05, colours)


## Only rock that touches floor. The rest of the rock is not a wall, it is
## nothing, and drawing it would cost more than the whole dungeon.
func _draw_walls() -> void:
	var places: Array[Vector2i] = []
	var colours: Array[Color] = []
	for i in rules.cells.size():
		if rules.cells[i] != DungeonGen.Cell.ROCK:
			continue
		var touches := false
		for neighbour in _around(i):
			if rules.cells[neighbour] != DungeonGen.Cell.ROCK:
				touches = true
				break
		if touches:
			places.append(Vector2i(i % rules.width, i / rules.width))
			colours.append(Color.WHITE)
	_walls.multimesh = _fill(_box(Vector3(1.0, 0.55, 1.0)), places, 0.275, colours)


func _draw_links() -> void:
	var places: Array[Vector2i] = []
	var colours: Array[Color] = []
	if shown == 2:
		for link in rules.links:
			var from: Vector2i = (
					rules.rooms[link.x].position + rules.rooms[link.x].size / 2)
			var to: Vector2i = (
					rules.rooms[link.y].position + rules.rooms[link.y].size / 2)
			var steps: int = maxi(absi(to.x - from.x), absi(to.y - from.y))
			for step in range(steps + 1):
				var along := 0.0 if steps == 0 else float(step) / float(steps)
				places.append(Vector2i(
						roundi(lerpf(from.x, to.x, along)),
						roundi(lerpf(from.y, to.y, along))))
				colours.append(Color(1.0, 0.72, 0.3))
	_links.multimesh = _fill(_box(Vector3(0.38, 0.38, 0.38)), places, 1.0, colours)


func _draw_ends() -> void:
	_entrance.visible = shown >= 5 and rules.entrance.x >= 0
	_stairs.visible = shown >= 5 and rules.stairs.x >= 0
	if _entrance.visible:
		_entrance.position = Vector3(rules.entrance.x, 0.5, rules.entrance.y)
		_stairs.position = Vector3(rules.stairs.x, 0.5, rules.stairs.y)


func _around(i: int) -> Array[int]:
	var x := i % rules.width
	var y := i / rules.width
	var found: Array[int] = []
	if x > 0:
		found.append(i - 1)
	if x < rules.width - 1:
		found.append(i + 1)
	if y > 0:
		found.append(i - rules.width)
	if y < rules.height - 1:
		found.append(i + rules.width)
	return found


func _fill(
		mesh: Mesh,
		cells: Array[Vector2i],
		y: float,
		colours: Array[Color]) -> MultiMesh:
	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.use_colors = true
	multi_mesh.mesh = mesh
	multi_mesh.instance_count = cells.size()
	for i in cells.size():
		multi_mesh.set_instance_transform(
				i,
				Transform3D(Basis.IDENTITY, Vector3(float(cells[i].x), y, float(cells[i].y))))
		multi_mesh.set_instance_color(i, colours[i])
	return multi_mesh


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _frame_camera() -> void:
	var mid := Vector3(float(rules.width - 1) * 0.5, 0.0, float(rules.height - 1) * 0.5)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = view_size
	_camera.position = mid + Vector3(1.0, 1.0, 1.0).normalized() * 90.0
	_camera.look_at(mid, Vector3.UP)


func _draw_hud() -> void:
	_seed_label.text = "SEED %d" % seed_value
	var text := "[b]%s[/b]\n\n[table=2]" % PASS_NAME[shown]
	for key in rules.stats:
		text += "[cell]%s  [/cell][cell]%s[/cell]" % [key, rules.stats[key]]
	text += "[/table]\n\n"
	text += "style: %s\n" % (
			"cave" if rules.style == DungeonGen.Style.CAVE else "rooms + corridors")
	if rules.style == DungeonGen.Style.ROOMS:
		if rules.naive_links:
			text += "[color=#ff8a6a]links: nearest neighbour[/color]"
			text += " — no promise the map is one piece\n"
		else:
			text += "links: spanning tree + %d loops — one piece by construction\n" % rules.loops
	text += "fill the unreachable back in: %s" % (
			"ON" if rules.keep_largest else "[color=#ff8a6a]OFF[/color]")
	_detail.text = text
