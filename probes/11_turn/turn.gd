class_name TurnWorld
extends Node3D
## Turns. The world only moves when you do.
##
## Every actor gains `speed` energy on each tick and pays TURN_COST to act.
## Speed 200 therefore acts twice per tick, speed 50 once every second tick.
## That single rule is the whole scheduler — everything a roguelike calls
## initiative falls out of it.
##
## The other half of the probe: the picture is allowed to lag behind the rules,
## and it must never be allowed to hold them up. Press T to break that on
## purpose.

## What one action costs. Energy per tick is measured against this and nothing
## else, so it is the unit the whole scheduler is written in.
const TURN_COST := 100
## Ceiling on scheduler steps between two player turns. Only a guard against a
## rule change that stops handing control back; the loop never gets near it.
const MAX_STEPS := 4096

## The map IS the level. Edit it and press R.
## `@` you, `f` fast, `m` normal, `s` slow, `#` wall.
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
	"@": {"name": "ты", "speed": 100, "color": Color(0.93, 0.96, 1.0)},
	"f": {"name": "быстрый", "speed": 200, "color": Color(0.95, 0.34, 0.28)},
	"m": {"name": "обычный", "speed": 100, "color": Color(0.95, 0.66, 0.24)},
	"s": {"name": "медленный", "speed": 50, "color": Color(0.42, 0.56, 0.78)},
}

@export var actor_scene: PackedScene

@export_group("Feel")
## How long a step takes to draw, s. The rules never wait for it.
@export_range(0.0, 0.4) var move_time := 0.12
## How fast turns repeat while a direction is held, s.
@export_range(0.02, 0.3) var hold_repeat := 0.055

@export_group("The mistake")
## On: refuse input until every actor has finished sliding. This is the trap,
## and it is here to be switched on and felt.
@export var wait_for_anim := false

@export_group("View")
## Half-height of the orthogonal camera, m.
@export_range(10.0, 44.0) var view_size := 18.0

var turns := 0
var ticks := 0

var _actors: Array[TurnActor] = []
var _player: TurnActor
var _walls := {}
var _held := Vector2i.ZERO
var _held_wait := false
var _repeat := 0.0

@onready var _tiles: MultiMeshInstance3D = $Tiles
@onready var _wall_mesh: MultiMeshInstance3D = $Walls
@onready var _actors_root: Node3D = $Actors
@onready var _camera: Camera3D = $Camera
@onready var _hud: RichTextLabel = $Ui/Info


func _ready() -> void:
	_build_map()
	_spawn()
	_frame_camera()
	_run_until_player()


func _process(delta: float) -> void:
	_read_input(delta)
	_draw_hud()


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


## Whether a key would be acted on right now. False only while the trap is
## switched on and something is still sliding.
func is_accepting() -> bool:
	if not wait_for_anim:
		return true
	for actor in _actors:
		if not actor.is_settled():
			return false
	return true


## Whoever has the most energy above the cost of an action, or nothing if the
## whole board has to wait for another tick.
func _next_actor() -> TurnActor:
	var best: TurnActor = null
	for actor in _actors:
		if actor.energy >= TURN_COST and (best == null or actor.energy > best.energy):
			best = actor
	return best


## Run the board forward until it is the player's move again, then stop dead.
##
## THERE IS NO GAME LOOP. This returns from the middle of the world's turn, so
## the world is not "paused" — it is inside a function call that has not
## finished. The next key press continues it from the same place. That is
## inside out compared with probes 01-10, where the frame drove everything, and
## it is the one thing about this file that needs explaining out loud.
func _run_until_player() -> void:
	for _step in MAX_STEPS:
		var who := _next_actor()
		if who == null:
			for actor in _actors:
				actor.energy += actor.speed
			ticks += 1
			continue
		if who == _player:
			return
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


func _take(actor: TurnActor, step: Vector2i) -> void:
	if step == Vector2i.ZERO:
		return
	var to: Vector2i = actor.cell + step
	if _walls.has(to):
		return  # walked into a wall, and the turn is spent anyway
	var other := _actor_at(to)
	if other != null:
		if actor == _player:
			var pushed: Vector2i = to + step
			if not _walls.has(pushed) and _actor_at(pushed) == null:
				other.cell = pushed
				other.slide_to(pushed, move_time)
		elif other == _player:
			other.hits += 1
		actor.bump(step, move_time)
		return
	actor.cell = to
	actor.slide_to(to, move_time)


## Greedy, not a pathfinder: it walks into a corner and stays there. Real paths
## are a different probe, and hiding that here would blur which is which.
func _chase(actor: TurnActor) -> Vector2i:
	var towards: Vector2i = _player.cell - actor.cell
	var want := Vector2i(signi(towards.x), signi(towards.y))
	if want == Vector2i.ZERO:
		return Vector2i.ZERO
	var tries: Array[Vector2i] = [want]
	if absi(towards.x) >= absi(towards.y):
		tries.append(Vector2i(want.x, 0))
		tries.append(Vector2i(0, want.y))
	else:
		tries.append(Vector2i(0, want.y))
		tries.append(Vector2i(want.x, 0))
	for step in tries:
		if step == Vector2i.ZERO:
			continue
		var to: Vector2i = actor.cell + step
		if to == _player.cell:
			return step
		if not _walls.has(to) and _actor_at(to) == null:
			return step
	return Vector2i.ZERO


func _actor_at(at: Vector2i) -> TurnActor:
	for actor in _actors:
		if actor.cell == at:
			return actor
	return null


func _read_input(delta: float) -> void:
	var step := Vector2i(
			int(Input.is_action_pressed(&"move_right"))
					- int(Input.is_action_pressed(&"move_left")),
			int(Input.is_action_pressed(&"move_back"))
					- int(Input.is_action_pressed(&"move_forward")))
	var waiting := Input.is_action_pressed(&"jump")
	if step == Vector2i.ZERO and not waiting:
		_repeat = 0.0
		_held = Vector2i.ZERO
		_held_wait = false
		return
	if step != _held or waiting != _held_wait:
		_repeat = 0.0  # a fresh key acts on the frame it is pressed
		_held = step
		_held_wait = waiting
	_repeat -= delta
	if _repeat > 0.0:
		return
	if not is_accepting():
		return
	_repeat = hold_repeat
	_player_turn(step)


func _build_map() -> void:
	var floors: Array[Vector2i] = []
	var walls: Array[Vector2i] = []
	_walls.clear()
	for y in MAP.size():
		var row: String = MAP[y]
		for x in row.length():
			var at := Vector2i(x, y)
			if row[x] == "#":
				walls.append(at)
				_walls[at] = true
			else:
				floors.append(at)
	_tiles.multimesh = _fill(_box(Vector3(0.97, 0.1, 0.97)), floors, -0.05, true)
	_wall_mesh.multimesh = _fill(_box(Vector3(1.0, 0.5, 1.0)), walls, 0.25, false)


func _fill(mesh: Mesh, cells: Array[Vector2i], y: float, checkered: bool) -> MultiMesh:
	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.use_colors = true
	multi_mesh.mesh = mesh
	multi_mesh.instance_count = cells.size()
	for i in cells.size():
		var at: Vector2i = cells[i]
		multi_mesh.set_instance_transform(
				i,
				Transform3D(Basis.IDENTITY, Vector3(float(at.x), y, float(at.y))))
		var shade := 1.0
		if checkered and (at.x + at.y) % 2 == 1:
			shade = 0.7
		multi_mesh.set_instance_color(i, Color(shade, shade, shade))
	return multi_mesh


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _spawn() -> void:
	for actor in _actors:
		actor.queue_free()
	_actors.clear()
	for y in MAP.size():
		var row: String = MAP[y]
		for x in row.length():
			var key: String = row[x]
			if not KINDS.has(key):
				continue
			var actor: TurnActor = actor_scene.instantiate()
			_actors_root.add_child(actor)
			var of_kind: Dictionary = KINDS[key]
			actor.setup(of_kind["name"], of_kind["speed"], of_kind["color"], Vector2i(x, y))
			_actors.append(actor)
			if key == "@":
				_player = actor


func _frame_camera() -> void:
	var mid := Vector3(
			float(MAP[0].length() - 1) * 0.5,
			0.0,
			float(MAP.size() - 1) * 0.5)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = view_size
	_camera.position = mid + Vector3(1.0, 1.0, 1.0).normalized() * 60.0
	_camera.look_at(mid, Vector3.UP)


func _draw_hud() -> void:
	var rows := "ход [b]%d[/b]   попаданий %d   тиков %d   ожидание анимации: %s\n\n" % [
		turns, _player.hits, ticks,
		"[color=#ff8a6a]вкл[/color]" if wait_for_anim else "выкл"]
	rows += "[table=4][cell][b]кто  [/b][/cell][cell][b]скорость  [/b][/cell]"
	rows += "[cell][b]ходов  [/b][/cell][cell][b]энергия[/b][/cell]"
	for actor in _actors:
		rows += "[cell]%s  [/cell][cell]%d  [/cell][cell]%d  [/cell][cell]%d[/cell]" % [
			actor.kind, actor.speed, actor.acted, actor.energy]
	rows += "[/table]\n\n"
	rows += "WASD шаг на клетку (две сразу — по диагонали)   ПРОБЕЛ ждать\n"
	rows += "войти в кого-нибудь — оттолкнуть   КОЛЕСО приближение   R заново\n"
	rows += "T ожидание анимации: %s\n" % (
			"[color=#ff8a6a]ввод ждёт картинку — зажми клавишу и почувствуй[/color]"
			if wait_for_anim else "ввод мгновенный, картинка догоняет сама")
	rows += "карта — блок текста в начале turn.gd: правь и жми R\n\n"
	rows += "[color=#66ccff]энергия — единственное правило очерёдности, и из неё растёт"
	rows += " всё, что жанр зовёт инициативой и ускорениями[/color]"
	_hud.text = rows

