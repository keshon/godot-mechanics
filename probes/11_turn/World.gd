extends Node3D

# 11 — turns. The world only moves when you do.
#
# Every actor gains `speed` energy on each tick and pays TURN_COST to act. Speed 200
# therefore acts twice per tick, speed 50 once every second tick. That single rule is
# the whole scheduler — everything a roguelike calls initiative falls out of it.
#
# The other half of the probe: the picture is allowed to lag behind the rules, and it
# must never be allowed to hold them up. Press T to break that on purpose.

const TURN_COST := 100

# the map is the level. edit it and press R.
# @ you   f fast   m normal   s slow   # wall
const MAP := [
	"#####################",
	"#....#..........#...#",
	"#....#..#####...#.f.#",
	"#.......#...#.......#",
	"#..###..#...#..###..#",
	"#....#..#...#....#..#",
	"#....#...........#..#",
	"#.......@.......s...#",
	"#..#....#........#..#",
	"#..#..###...###..#..#",
	"#..#........#....#..#",
	"#.....####..#..###..#",
	"#..m.....#..........#",
	"#........#.......#..#",
	"#####################",
]

const KINDS := {
	"@": {"name": "you", "speed": 100, "color": Color(0.93, 0.96, 1.0)},
	"f": {"name": "fast", "speed": 200, "color": Color(0.95, 0.34, 0.28)},
	"m": {"name": "normal", "speed": 100, "color": Color(0.95, 0.66, 0.24)},
	"s": {"name": "slow", "speed": 50, "color": Color(0.42, 0.56, 0.78)},
}

@export var actor_scene: PackedScene

@export_group("Feel")
## how long a step takes to draw. the rules never wait for it.
@export_range(0.0, 0.4) var move_time := 0.12
## how fast turns repeat while you hold a direction
@export_range(0.02, 0.3) var hold_repeat := 0.055

@export_group("The mistake")
## on: refuse input until every actor has finished sliding. this is the trap.
@export var wait_for_anim := false

@export_group("View")
@export_range(10.0, 44.0) var view_size := 18.0

var turns := 0
var ticks := 0

var _actors: Array[TurnActor] = []
var _player: TurnActor
var _walls := {}
var _held := Vector2i.ZERO
var _held_wait := false
var _repeat := 0.0


func _ready() -> void:
	_build_map()
	_spawn()
	_frame_camera()
	_run_until_player()


# --- the scheduler ------------------------------------------------------------

func _ready_actor() -> TurnActor:
	var best: TurnActor = null
	for a in _actors:
		if a.energy >= TURN_COST and (best == null or a.energy > best.energy):
			best = a
	return best


func _run_until_player() -> void:
	for _i in 4096:
		var who := _ready_actor()
		if who == null:
			for a in _actors:
				a.energy += a.speed
			ticks += 1
			continue
		if who == _player:
			return  # the world stops here and waits for a key
		who.energy -= TURN_COST
		who.acted += 1
		_take(who, _chase(who))
	push_error("scheduler never handed control back")


func _player_turn(step: Vector2i) -> void:
	_player.energy -= TURN_COST
	_player.acted += 1
	turns += 1
	_take(_player, step)
	_run_until_player()


func _take(a: TurnActor, step: Vector2i) -> void:
	if step == Vector2i.ZERO:
		return
	var to: Vector2i = a.cell + step
	if _walls.has(to):
		return  # walked into a wall. the turn is spent anyway
	var other := _at(to)
	if other != null:
		if a == _player:
			var pushed: Vector2i = to + step
			if not _walls.has(pushed) and _at(pushed) == null:
				other.cell = pushed
				other.slide_to(pushed, move_time)
		elif other == _player:
			other.hits += 1
		a.bump(step, move_time)
		return
	a.cell = to
	a.slide_to(to, move_time)


func _chase(a: TurnActor) -> Vector2i:
	# greedy, not a pathfinder: it walks into a corner and stays there. real paths
	# are a different probe, and hiding that here would blur which is which.
	var d: Vector2i = _player.cell - a.cell
	var want := Vector2i(signi(d.x), signi(d.y))
	if want == Vector2i.ZERO:
		return Vector2i.ZERO
	var tries: Array[Vector2i] = [want]
	if absi(d.x) >= absi(d.y):
		tries.append(Vector2i(want.x, 0))
		tries.append(Vector2i(0, want.y))
	else:
		tries.append(Vector2i(0, want.y))
		tries.append(Vector2i(want.x, 0))
	for step in tries:
		if step == Vector2i.ZERO:
			continue
		var to: Vector2i = a.cell + step
		if to == _player.cell:
			return step
		if not _walls.has(to) and _at(to) == null:
			return step
	return Vector2i.ZERO


func _at(c: Vector2i) -> TurnActor:
	for a in _actors:
		if a.cell == c:
			return a
	return null


# --- input --------------------------------------------------------------------

func accepting() -> bool:
	if not wait_for_anim:
		return true
	for a in _actors:
		if not a.settled():
			return false
	return true


func _process(delta: float) -> void:
	_read_input(delta)
	_hud()


func _read_input(delta: float) -> void:
	var step := Vector2i(
		int(Input.is_action_pressed("move_right")) - int(Input.is_action_pressed("move_left")),
		int(Input.is_action_pressed("move_back")) - int(Input.is_action_pressed("move_forward")))
	var wait: bool = Input.is_action_pressed("jump")
	if step == Vector2i.ZERO and not wait:
		_repeat = 0.0
		_held = Vector2i.ZERO
		_held_wait = false
		return
	if step != _held or wait != _held_wait:
		_repeat = 0.0  # a fresh key acts on the frame it is pressed
		_held = step
		_held_wait = wait
	_repeat -= delta
	if _repeat > 0.0:
		return
	if not accepting():
		return
	_repeat = hold_repeat
	_player_turn(step)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_T:
			wait_for_anim = not wait_for_anim
		elif event.keycode == KEY_R:
			_spawn()
			turns = 0
			ticks = 0
			_run_until_player()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			view_size = maxf(view_size - 1.5, 10.0)
			_frame_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			view_size = minf(view_size + 1.5, 44.0)
			_frame_camera()


# --- board --------------------------------------------------------------------

func _build_map() -> void:
	var floors: Array[Vector2i] = []
	var walls: Array[Vector2i] = []
	_walls.clear()
	for y in MAP.size():
		var row: String = MAP[y]
		for x in row.length():
			var c := Vector2i(x, y)
			if row[x] == "#":
				walls.append(c)
				_walls[c] = true
			else:
				floors.append(c)
	$Tiles.multimesh = _fill(_box(Vector3(0.97, 0.1, 0.97)), floors, -0.05, true)
	$Walls.multimesh = _fill(_box(Vector3(1.0, 0.5, 1.0)), walls, 0.25, false)


func _fill(mesh: Mesh, cells: Array[Vector2i], y: float, checker: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = cells.size()
	for i in cells.size():
		var c: Vector2i = cells[i]
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(float(c.x), y, float(c.y))))
		var shade := 1.0
		if checker and (c.x + c.y) % 2 == 1:
			shade = 0.7
		mm.set_instance_color(i, Color(shade, shade, shade))
	return mm


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _spawn() -> void:
	for a in _actors:
		a.queue_free()
	_actors.clear()
	for y in MAP.size():
		var row: String = MAP[y]
		for x in row.length():
			var k: String = row[x]
			if not KINDS.has(k):
				continue
			var a: TurnActor = actor_scene.instantiate()
			$Actors.add_child(a)
			var d: Dictionary = KINDS[k]
			a.setup(d["name"], d["speed"], d["color"], Vector2i(x, y))
			_actors.append(a)
			if k == "@":
				_player = a


func _frame_camera() -> void:
	var mid := Vector3(float(MAP[0].length() - 1) * 0.5, 0.0, float(MAP.size() - 1) * 0.5)
	var cam: Camera3D = $Camera
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = view_size
	cam.position = mid + Vector3(1.0, 1.0, 1.0).normalized() * 60.0
	cam.look_at(mid, Vector3.UP)


func _hud() -> void:
	$Ui/Hud/Big.text = "TURN %d    HIT %d" % [turns, _player.hits]
	var t := "[table=4][cell][b]  [/b][/cell][cell][b]speed  [/b][/cell][cell][b]turns  [/b][/cell][cell][b]energy[/b][/cell]"
	for a in _actors:
		t += "[cell]%s  [/cell][cell]%d  [/cell][cell]%d  [/cell][cell]%d[/cell]" % [a.kind, a.speed, a.acted, a.energy]
	t += "[/table]\n\nticks %d\n\n" % ticks
	if wait_for_anim:
		t += "[color=#ff8a6a]input waits for the animation[/color]  hold a key and feel it drag"
	else:
		t += "input is instant  the picture catches up on its own"
	$Ui/Hud/Detail.text = t
