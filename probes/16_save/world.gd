class_name SaveWorld
extends RefCounted
## A small world with real state: a map dug from a seed, eight actors that move
## and hit each other, a turn counter, and a die that every decision is drawn
## from.
##
## Nothing here knows about files. It knows how to start from a seed, how to
## take one step, and how to reduce itself to a single number so two worlds can
## be compared.

enum Cell {
	ROCK,
	FLOOR,
}

const WIDTH := 31
const HEIGHT := 21
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

## These two are the BUILD, not the save. They are static on purpose: a save
## file cannot carry them, which is the entire problem this probe is about.
static var leak := false
static var patched := false

var seed_value := 1
var turn := 0
var map := PackedByteArray()
var actors: Array[Dictionary] = []
## Every move ever played, in order. A replay is this list and the seed.
var actions: Array[Vector2i] = []
var rng := RandomNumberGenerator.new()


func begin(from_seed: int) -> void:
	seed_value = from_seed
	turn = 0
	rng = RandomNumberGenerator.new()
	rng.seed = from_seed
	actions = []
	map = PackedByteArray()
	map.resize(WIDTH * HEIGHT)
	_carve()
	_spawn()


func play(direction: Vector2i) -> void:
	actions.append(direction)
	if not actors.is_empty():
		var player: Dictionary = actors[0]
		var to_x: int = player["x"] + direction.x
		var to_y: int = player["y"] + direction.y
		if _is_open(to_x, to_y):
			player["x"] = to_x
			player["y"] = to_y
	step()


func step() -> void:
	turn += 1
	# The "patch": one rule constant a later build might have nudged. Harmless,
	# invisible, and it changes every number downstream of it.
	var bonus := 6 if patched else 0
	for actor in actors:
		actor["energy"] += actor["speed"] + bonus
	for actor in actors:
		while actor["energy"] >= 100:
			actor["energy"] -= 100
			_act(actor)


## The whole world as one number.
##
## Note what is NOT in here: the position of the die. That is deliberate. A save
## can pass its own checksum and still be broken, and this is exactly how.
func digest() -> int:
	var hashed := 1469598103934665603
	hashed = _mix(hashed, turn)
	for cell in map:
		hashed = _mix(hashed, cell)
	for actor in actors:
		hashed = _mix(hashed, actor["x"])
		hashed = _mix(hashed, actor["y"])
		hashed = _mix(hashed, actor["hp"])
		hashed = _mix(hashed, actor["energy"])
	return hashed


func _carve() -> void:
	var rooms: Array[Rect2i] = []
	for _try in 40:
		var room_width := rng.randi_range(4, 7)
		var room_height := rng.randi_range(3, 6)
		var room := Rect2i(
				rng.randi_range(1, WIDTH - room_width - 2),
				rng.randi_range(1, HEIGHT - room_height - 2),
				room_width,
				room_height)
		var clear := true
		for other in rooms:
			if room.grow(1).intersects(other):
				clear = false
				break
		if not clear:
			continue
		rooms.append(room)
		for y in range(room.position.y, room.end.y):
			for x in range(room.position.x, room.end.x):
				map[y * WIDTH + x] = Cell.FLOOR
	for i in range(1, rooms.size()):
		var from := rooms[i - 1].get_center()
		var to := rooms[i].get_center()
		for x in range(mini(from.x, to.x), maxi(from.x, to.x) + 1):
			map[from.y * WIDTH + x] = Cell.FLOOR
		for y in range(mini(from.y, to.y), maxi(from.y, to.y) + 1):
			map[y * WIDTH + to.x] = Cell.FLOOR


func _spawn() -> void:
	actors = []
	var open: Array[int] = []
	for i in WIDTH * HEIGHT:
		if map[i] == Cell.FLOOR:
			open.append(i)
	if open.is_empty():
		return
	for index in 8:
		var at: int = open[rng.randi_range(0, open.size() - 1)]
		actors.append({
			"x": at % WIDTH,
			"y": at / WIDTH,
			"hp": 20,
			"speed": 60 + index * 11,
			"energy": 0,
		})


func _act(actor: Dictionary) -> void:
	var direction: Vector2i = DIRS[_roll(4)]
	var to_x: int = actor["x"] + direction.x
	var to_y: int = actor["y"] + direction.y
	if not _is_open(to_x, to_y):
		return
	for other in actors:
		if other["x"] == to_x and other["y"] == to_y:
			other["hp"] = maxi(other["hp"] - _roll(4) - 1, 0)
			return
	actor["x"] = to_x
	actor["y"] = to_y


## The leak. One draw taken from the GLOBAL generator instead of ours. It looks
## the same, it plays the same, and it quietly makes every replay worthless.
func _roll(sides: int) -> int:
	if leak:
		return randi() % sides
	return rng.randi() % sides


func _is_open(x: int, y: int) -> bool:
	return (
			x >= 0 and y >= 0 and x < WIDTH and y < HEIGHT
			and map[y * WIDTH + x] == Cell.FLOOR
	)


func _mix(hashed: int, value: int) -> int:
	return ((hashed ^ value) * 1099511628211) & 0x7FFFFFFFFFFFFFFF
