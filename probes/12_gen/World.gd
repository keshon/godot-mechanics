extends Node3D

# 12 — generation. A number goes in, a dungeon comes out.
#
# This file only draws and takes keys. All the generating is in Gen.gd, which never
# touches a node — that split is most of why it can be checked at all.
#
# The knobs live on the DungeonGen resource in the inspector. Turn one while the game
# runs and the map rebuilds on the spot, from the same seed.

const PASS_NAME := [
	"",
	"1  rooms thrown at the grid",
	"2  links chosen (amber line = a corridor that will be dug)",
	"3  corridors carved",
	"4  flood fill: red is floor you cannot walk to",
	"5  stairs at the two ends of the longest walk",
]

@export var cfg: DungeonGen
@export_range(20.0, 60.0) var view_size := 36.0

var seed_value := 7
var shown := 5

var _sig := ""


func _ready() -> void:
	if cfg == null:
		cfg = DungeonGen.new()
	_rebuild()
	_frame_camera()


func _process(_delta: float) -> void:
	# knobs turned in the inspector rebuild the same seed at once
	var now := _signature()
	if now != _sig:
		_sig = now
		_rebuild()
	_hud()


func _signature() -> String:
	return "%d|%d|%d|%d|%d|%d|%d|%s|%.2f|%d|%s" % [
		seed_value, shown, cfg.style, cfg.room_tries, cfg.room_min, cfg.room_max,
		cfg.loops, cfg.naive_links, cfg.cave_fill, cfg.cave_smooth, cfg.keep_largest]


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
				cfg.style = DungeonGen.Style.CAVE if cfg.style == DungeonGen.Style.ROOMS else DungeonGen.Style.ROOMS
			KEY_L:
				cfg.naive_links = not cfg.naive_links
			KEY_K:
				cfg.keep_largest = not cfg.keep_largest
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


# --- drawing ------------------------------------------------------------------

func _rebuild() -> void:
	cfg.build(seed_value, shown)
	_draw_floor()
	_draw_walls()
	_draw_links()
	_draw_ends()


func _draw_floor() -> void:
	var at: Array[Vector2i] = []
	var col: Array[Color] = []
	for i in cfg.cells.size():
		if cfg.cells[i] == DungeonGen.ROCK:
			continue
		at.append(Vector2i(i % cfg.width, i / cfg.width))
		if shown >= 4 and cfg.region[i] == 0:
			col.append(Color(0.85, 0.3, 0.26))  # carved, and nobody can get here
		elif cfg.cells[i] == DungeonGen.HALL:
			col.append(Color(0.46, 0.44, 0.42))
		else:
			col.append(Color(0.95, 0.95, 0.97))
	$Floor.multimesh = _fill(_box(Vector3(0.95, 0.1, 0.95)), at, -0.05, col)


func _draw_walls() -> void:
	# only rock that touches floor. the rest of the rock is not a wall, it is nothing.
	var at: Array[Vector2i] = []
	var col: Array[Color] = []
	for i in cfg.cells.size():
		if cfg.cells[i] != DungeonGen.ROCK:
			continue
		var touches := false
		for nb in _around(i):
			if cfg.cells[nb] != DungeonGen.ROCK:
				touches = true
				break
		if touches:
			at.append(Vector2i(i % cfg.width, i / cfg.width))
			col.append(Color.WHITE)
	$Walls.multimesh = _fill(_box(Vector3(1.0, 0.55, 1.0)), at, 0.275, col)


func _draw_links() -> void:
	var at: Array[Vector2i] = []
	var col: Array[Color] = []
	if shown == 2:
		for e in cfg.links:
			var a: Vector2i = cfg.rooms[e.x].position + cfg.rooms[e.x].size / 2
			var b: Vector2i = cfg.rooms[e.y].position + cfg.rooms[e.y].size / 2
			var steps: int = maxi(absi(b.x - a.x), absi(b.y - a.y))
			for s in range(steps + 1):
				var t := 0.0 if steps == 0 else float(s) / float(steps)
				at.append(Vector2i(roundi(lerpf(a.x, b.x, t)), roundi(lerpf(a.y, b.y, t))))
				col.append(Color(1.0, 0.72, 0.3))
	$Links.multimesh = _fill(_box(Vector3(0.38, 0.38, 0.38)), at, 1.0, col)


func _draw_ends() -> void:
	$Entrance.visible = shown >= 5 and cfg.entrance.x >= 0
	$Stairs.visible = shown >= 5 and cfg.stairs.x >= 0
	if $Entrance.visible:
		$Entrance.position = Vector3(cfg.entrance.x, 0.5, cfg.entrance.y)
		$Stairs.position = Vector3(cfg.stairs.x, 0.5, cfg.stairs.y)


func _around(i: int) -> Array[int]:
	var x := i % cfg.width
	var y := i / cfg.width
	var out: Array[int] = []
	if x > 0:
		out.append(i - 1)
	if x < cfg.width - 1:
		out.append(i + 1)
	if y > 0:
		out.append(i - cfg.width)
	if y < cfg.height - 1:
		out.append(i + cfg.width)
	return out


func _fill(mesh: Mesh, cells: Array[Vector2i], y: float, col: Array[Color]) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = cells.size()
	for i in cells.size():
		mm.set_instance_transform(i,
			Transform3D(Basis.IDENTITY, Vector3(float(cells[i].x), y, float(cells[i].y))))
		mm.set_instance_color(i, col[i])
	return mm


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _frame_camera() -> void:
	var mid := Vector3(float(cfg.width - 1) * 0.5, 0.0, float(cfg.height - 1) * 0.5)
	var cam: Camera3D = $Camera
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = view_size
	cam.position = mid + Vector3(1.0, 1.0, 1.0).normalized() * 90.0
	cam.look_at(mid, Vector3.UP)


func _hud() -> void:
	$Ui/Hud/Big.text = "SEED %d" % seed_value
	var t := "[b]%s[/b]\n\n" % PASS_NAME[shown]
	t += "[table=2]"
	for k in cfg.stats:
		t += "[cell]%s  [/cell][cell]%s[/cell]" % [k, cfg.stats[k]]
	t += "[/table]\n\n"
	t += "style: %s\n" % ("cave" if cfg.style == DungeonGen.Style.CAVE else "rooms + corridors")
	if cfg.style == DungeonGen.Style.ROOMS:
		if cfg.naive_links:
			t += "[color=#ff8a6a]links: nearest neighbour[/color] — no promise the map is one piece\n"
		else:
			t += "links: spanning tree + %d loops — one piece by construction\n" % cfg.loops
	t += "fill the unreachable back in: %s" % ("ON" if cfg.keep_largest else "[color=#ff8a6a]OFF[/color]")
	$Ui/Hud/Detail.text = t
