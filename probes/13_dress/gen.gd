class_name DressGen
extends Resource
## The same pipeline as probe 12, cut down to what this probe needs: rooms, a spanning
## tree, corridors, props, flood fill. No cave, no broken-links mode, no step-by-step.
##
## What matters here is the OUTPUT: a byte per cell and nothing else. Four meanings.
## Not one word about how any of it looks.

## What is in a cell. The tiler reads nothing else.
enum Cell {
	ROCK,
	ROOM,
	HALL,
	PROP,
	WATER,
}

const AROUND: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

# Hand-drawn rooms. A generator will never invent these, and that is the whole point.
#   O pillar    ~ water    . leave whatever the generator put there
const PREFABS := [
	[
		".........",
		".O.O.O.O.",
		".........",
		".........",
		".O.O.O.O.",
		".........",
	],
	[
		".........",
		"...~~~...",
		"..~~~~~..",
		"..~~~~~..",
		"...~~~...",
		".........",
	],
	[
		"O.O.O.O",
		".......",
		"O.....O",
		".......",
		"O.O.O.O",
	],
	[
		"..~~~..",
		"..~~~..",
		"O.~~~.O",
		"..~~~..",
		"..~~~..",
	],
]

@export var width := 41
@export var height := 27
@export_range(4, 200) var room_tries := 90
@export_range(4, 15) var room_min := 4
@export_range(4, 20) var room_max := 8
@export_range(0, 12) var loops := 3
## how many rooms get a hand-drawn pattern stamped into them
@export_range(0, 6) var prefabs := 3

var cells := PackedByteArray()
var rooms: Array[Rect2i] = []
var region := PackedByteArray()
var stamped: Array[Rect2i] = []
var stats := {}

var _random := RandomNumberGenerator.new()


func build(seed_value: int, with_prefabs: bool) -> void:
	_random.seed = seed_value
	cells = PackedByteArray()
	cells.resize(width * height)
	region = PackedByteArray()
	region.resize(width * height)
	rooms.clear()
	stamped.clear()
	stats = {}
	_place_rooms()
	_carve(_choose_links())
	if with_prefabs:
		_stamp()
	_find_region()


func at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return Cell.ROCK
	return cells[y * width + x]


func walkable(x: int, y: int) -> bool:
	var c := at(x, y)
	return c == Cell.ROOM or c == Cell.HALL


func _place_rooms() -> void:
	for _i in room_tries:
		var rw := _random.randi_range(room_min, room_max)
		var rh := _random.randi_range(room_min, room_max)
		if rw + 3 >= width or rh + 3 >= height:
			continue
		var r := Rect2i(_random.randi_range(1, width - rw - 2),
			_random.randi_range(1, height - rh - 2), rw, rh)
		var clear := true
		for other in rooms:
			if r.grow(1).intersects(other):
				clear = false
				break
		if not clear:
			continue
		rooms.append(r)
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				cells[y * width + x] = Cell.ROOM
	stats["комнат"] = str(rooms.size())


func _choose_links() -> Array[Vector2i]:
	var links: Array[Vector2i] = []
	if rooms.size() < 2:
		return links
	var inside: Array[int] = [0]
	var outside: Array[int] = []
	for i in range(1, rooms.size()):
		outside.append(i)
	while not outside.is_empty():
		var ba := -1
		var bb := -1
		var bd := INF
		for a in inside:
			for b in outside:
				var d := Vector2(_centre(a) - _centre(b)).length_squared()
				if d < bd:
					bd = d
					ba = a
					bb = b
		links.append(Vector2i(ba, bb))
		inside.append(bb)
		outside.erase(bb)
	for _i in loops:
		links.append(Vector2i(_random.randi_range(0, rooms.size() - 1),
			_random.randi_range(0, rooms.size() - 1)))
	return links


func _centre(i: int) -> Vector2i:
	return rooms[i].position + rooms[i].size / 2


func _carve(links: Array[Vector2i]) -> void:
	for e in links:
		if e.x == e.y:
			continue
		var a := _centre(e.x)
		var b := _centre(e.y)
		if _random.randi() % 2 == 0:
			_dig(a, Vector2i(b.x, a.y))
			_dig(Vector2i(b.x, a.y), b)
		else:
			_dig(a, Vector2i(a.x, b.y))
			_dig(Vector2i(a.x, b.y), b)


func _dig(from: Vector2i, to: Vector2i) -> void:
	var step := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
	var at_ := from
	while true:
		var i := at_.y * width + at_.x
		if cells[i] == Cell.ROCK:
			cells[i] = Cell.HALL
		if at_ == to:
			return
		at_ += step


func _stamp() -> void:
	var props := 0
	var skipped := 0
	var used := 0
	for r in rooms:
		if used >= prefabs:
			break
		var pat: Array = PREFABS[_random.randi_range(0, PREFABS.size() - 1)]
		var ph: int = pat.size()
		var pw: int = (pat[0] as String).length()
		if r.size.x < pw or r.size.y < ph:
			continue
		used += 1
		stamped.append(r)
		var ox: int = r.position.x + (r.size.x - pw) / 2
		var oy: int = r.position.y + (r.size.y - ph) / 2
		for y in ph:
			for x in pw:
				var glyph: String = (pat[y] as String)[x]
				if glyph == ".":
					continue
				var cx := ox + x
				var cy := oy + y
				# never block a corridor or the mouth of one
				if at(cx, cy) != Cell.ROOM or _near_hall(cx, cy):
					skipped += 1
					continue
				cells[cy * width + cx] = Cell.PROP if glyph == "O" else Cell.WATER
				props += 1
	stats["рисованных"] = "комнат %d, реквизита %d (пропущено из-за проёма %d)" % [
			used, props, skipped]


func _near_hall(x: int, y: int) -> bool:
	for d: Vector2i in AROUND:
		if at(x + d.x, y + d.y) == Cell.HALL:
			return true
	return false


func _find_region() -> void:
	var mark := PackedInt32Array()
	mark.resize(width * height)
	mark.fill(-1)
	var total := 0
	var best_id := -1
	var best_n := 0
	var parts := 0
	for start in width * height:
		if not walkable(start % width, start / width) or mark[start] != -1:
			continue
		var queue: Array[int] = [start]
		mark[start] = parts
		var n := 0
		while not queue.is_empty():
			var c: int = queue.pop_back()
			n += 1
			var cx := c % width
			var cy := c / width
			for d: Vector2i in AROUND:
				var nx: int = cx + d.x
				var ny: int = cy + d.y
				if not walkable(nx, ny):
					continue
				var ni: int = ny * width + nx
				if mark[ni] == -1:
					mark[ni] = parts
					queue.append(ni)
		total += n
		if n > best_n:
			best_n = n
			best_id = parts
		parts += 1
	for i in width * height:
		region[i] = 1 if mark[i] == best_id else 0
	stats["доступно"] = "%d%%, кусков: %d" % [
		0 if total == 0 else roundi(100.0 * best_n / total), parts]
