class_name SaveWorld
extends RefCounted

# A small world with real state: a map dug from a seed, eight actors that move and
# hit each other, a turn counter, and a die that every decision is drawn from.
#
# Nothing here knows about files. It knows how to start from a seed, how to take one
# step, and how to reduce itself to a single number so two worlds can be compared.

const W := 31
const H := 21
const ROCK := 0
const FLOOR := 1
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

# These two are the BUILD, not the save. They are static on purpose: a save file
# cannot carry them, which is the entire problem this probe is about.
static var leak := false
static var patched := false

var seed_value := 1
var turn := 0
var map := PackedByteArray()
var actors: Array[Dictionary] = []
var actions: Array[Vector2i] = []
var rng := RandomNumberGenerator.new()


func begin(seed_v: int) -> void:
	seed_value = seed_v
	turn = 0
	rng = RandomNumberGenerator.new()
	rng.seed = seed_v
	actions = []
	map = PackedByteArray()
	map.resize(W * H)
	_carve()
	_spawn()


func _carve() -> void:
	var rooms: Array[Rect2i] = []
	for _i in 40:
		var rw := rng.randi_range(4, 7)
		var rh := rng.randi_range(3, 6)
		var r := Rect2i(rng.randi_range(1, W - rw - 2), rng.randi_range(1, H - rh - 2), rw, rh)
		var ok := true
		for o in rooms:
			if r.grow(1).intersects(o):
				ok = false
				break
		if not ok:
			continue
		rooms.append(r)
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				map[y * W + x] = FLOOR
	for i in range(1, rooms.size()):
		var a := rooms[i - 1].get_center()
		var b := rooms[i].get_center()
		for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
			map[a.y * W + x] = FLOOR
		for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
			map[y * W + b.x] = FLOOR


func _spawn() -> void:
	actors = []
	var open: Array[int] = []
	for i in W * H:
		if map[i] == FLOOR:
			open.append(i)
	if open.is_empty():
		return
	for k in 8:
		var i: int = open[rng.randi_range(0, open.size() - 1)]
		actors.append({"x": i % W, "y": i / W, "hp": 20, "speed": 60 + k * 11, "energy": 0})


# --- one step -----------------------------------------------------------------

func play(dir: Vector2i) -> void:
	actions.append(dir)
	if not actors.is_empty():
		var p: Dictionary = actors[0]
		var nx: int = p["x"] + dir.x
		var ny: int = p["y"] + dir.y
		if _open(nx, ny):
			p["x"] = nx
			p["y"] = ny
	step()


func step() -> void:
	turn += 1
	# the "patch": one rule constant a later build might have nudged. harmless,
	# invisible, and it changes every number downstream of it.
	var bonus := 6 if patched else 0
	for a in actors:
		a["energy"] += a["speed"] + bonus
	for a in actors:
		while a["energy"] >= 100:
			a["energy"] -= 100
			_act(a)


func _act(a: Dictionary) -> void:
	var d: Vector2i = DIRS[_roll(4)]
	var nx: int = a["x"] + d.x
	var ny: int = a["y"] + d.y
	if not _open(nx, ny):
		return
	for o in actors:
		if o["x"] == nx and o["y"] == ny:
			o["hp"] = maxi(o["hp"] - _roll(4) - 1, 0)
			return
	a["x"] = nx
	a["y"] = ny


func _roll(n: int) -> int:
	# The leak. One draw taken from the GLOBAL generator instead of ours. It looks
	# the same, it plays the same, and it quietly makes every replay worthless.
	if leak:
		return randi() % n
	return rng.randi() % n


func _open(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < W and y < H and map[y * W + x] == FLOOR


# --- the whole world as one number --------------------------------------------
#
# Note what is NOT in here: the position of the die. That is deliberate. A save can
# pass its own checksum and still be broken, and this is exactly how.

func digest() -> int:
	var h := 1469598103934665603
	h = _mix(h, turn)
	for b in map:
		h = _mix(h, b)
	for a in actors:
		h = _mix(h, a["x"])
		h = _mix(h, a["y"])
		h = _mix(h, a["hp"])
		h = _mix(h, a["energy"])
	return h


func _mix(h: int, v: int) -> int:
	return ((h ^ v) * 1099511628211) & 0x7FFFFFFFFFFFFFFF
