class_name DungeonGen
extends Resource
## A generator is not one clever algorithm. It is a pipeline of dumb passes, and the
## level is what falls out at the end:
##
##   1 rooms    throw rectangles at the grid, keep the ones that do not overlap
##   2 links    decide which rooms connect
##   3 carve    dig the corridors
##   4 region   flood fill: which cells can actually be walked to
##   5 ends     put the stairs at the two ends of the longest walk
##
## Pass 4 is the one people skip, because passes 1-3 always produce something that
## looks like a dungeon. Then a room turns out to have no way in and you hear about
## it from a player.
##
## Nothing here touches a node, and nothing here calls randi(). Every random number
## comes out of _random, which is seeded once. Same seed, same dungeon, forever.

## What is in a cell. ROOM and HALL are both walkable; the difference is only
## which pass carved it, and the drawing uses it to shade corridors darker.
enum Cell {
	ROCK,
	ROOM,
	HALL,
}

enum Style {
	ROOMS,
	CAVE,
}

@export var width := 49
@export var height := 33
@export var style: Style = Style.ROOMS

@export_group("Rooms")
## rectangles thrown at the grid. most of them bounce off.
@export_range(4, 400) var room_tries := 60
@export_range(3, 15) var room_min := 5
@export_range(3, 20) var room_max := 11
## extra corridors beyond the spanning tree. 0 = a tree, only dead ends.
@export_range(0, 20) var loops := 4
## on: every room digs to its nearest neighbour. looks sane, quietly makes islands.
@export var naive_links := false

@export_group("Cave")
@export_range(0.35, 0.6) var cave_fill := 0.46
@export_range(0, 8) var cave_smooth := 4

@export_group("The guarantee")
## on: everything outside the biggest region is filled back in. off: see it break.
@export var keep_largest := false

var cells := PackedByteArray()
var rooms: Array[Rect2i] = []
var links: Array[Vector2i] = []
var region := PackedByteArray()
var entrance := Vector2i(-1, -1)
var stairs := Vector2i(-1, -1)
var stats := {}

var _random := RandomNumberGenerator.new()
var _far := 0
var _far_dist := 0


func build(seed_value: int, stop_after: int) -> void:
	_random.seed = seed_value
	cells = PackedByteArray()
	cells.resize(width * height)
	region = PackedByteArray()
	region.resize(width * height)
	rooms.clear()
	links.clear()
	entrance = Vector2i(-1, -1)
	stairs = Vector2i(-1, -1)
	stats = {}

	if style == Style.CAVE:
		_grow_cave()
	else:
		_place_rooms()
		if stop_after < 2:
			return
		_choose_links()
		if stop_after < 3:
			return
		_carve()
	if stop_after < 4:
		return
	_find_region()
	if stop_after < 5:
		return
	_place_ends()


func _place_rooms() -> void:
	for _i in room_tries:
		var room_width := _random.randi_range(room_min, room_max)
		var room_height := _random.randi_range(room_min, room_max)
		if room_width + 2 >= width or room_height + 2 >= height:
			continue
		var r := Rect2i(
			_random.randi_range(1, width - room_width - 2),
			_random.randi_range(1, height - room_height - 2), room_width, room_height)
		var clear := true
		for other in rooms:
			# grow by one so rooms never share a wall
			if r.grow(1).intersects(other):
				clear = false
				break
		if not clear:
			continue
		rooms.append(r)
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				cells[y * width + x] = Cell.ROOM
	stats["комнат"] = "%d оставлено из %d брошенных" % [rooms.size(), room_tries]


func _centre(i: int) -> Vector2i:
	return rooms[i].position + rooms[i].size / 2


func _link(a: int, b: int) -> void:
	if a < 0 or b < 0 or a == b:
		return
	var e := Vector2i(mini(a, b), maxi(a, b))
	if not links.has(e):
		links.append(e)


func _choose_links() -> void:
	if rooms.size() < 2:
		return
	if naive_links:
		# every room reaches for whoever is closest. two rooms that pick each other
		# form a pair the rest of the map never touches. nothing here notices.
		for i in rooms.size():
			var best := -1
			var best_distance := INF
			for j in rooms.size():
				if i == j:
					continue
				var d := Vector2(_centre(i) - _centre(j)).length_squared()
				if d < best_distance:
					best_distance = d
					best = j
			_link(i, best)
	else:
		# a spanning tree. every room joined exactly once: connectivity is not hoped
		# for, it is what the algorithm means.
		var inside: Array[int] = [0]
		var outside: Array[int] = []
		for i in range(1, rooms.size()):
			outside.append(i)
		while not outside.is_empty():
			var box_a := -1
			var box_b := -1
			var best_distance := INF
			for a in inside:
				for b in outside:
					var d := Vector2(_centre(a) - _centre(b)).length_squared()
					if d < best_distance:
						best_distance = d
						box_a = a
						box_b = b
			_link(box_a, box_b)
			inside.append(box_b)
			outside.erase(box_b)
		# extra edges turn the tree into a graph: circles to run around instead of
		# corridors you can only back out of
		for _i in loops:
			_link(
				_random.randi_range(0, rooms.size() - 1),
				_random.randi_range(0, rooms.size() - 1))
	stats["связей"] = str(links.size())


func _carve() -> void:
	for e in links:
		var a := _centre(e.x)
		var b := _centre(e.y)
		if _random.randi() % 2 == 0:
			_dig(Vector2i(a.x, a.y), Vector2i(b.x, a.y))
			_dig(Vector2i(b.x, a.y), Vector2i(b.x, b.y))
		else:
			_dig(Vector2i(a.x, a.y), Vector2i(a.x, b.y))
			_dig(Vector2i(a.x, b.y), Vector2i(b.x, b.y))


func _dig(from: Vector2i, to: Vector2i) -> void:
	var step := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
	var at := from
	while true:
		var i := at.y * width + at.x
		if cells[i] == Cell.ROCK:
			cells[i] = Cell.HALL
		if at == to:
			return
		at += step


func _grow_cave() -> void:
	for y in height:
		for x in width:
			var edge := x == 0 or y == 0 or x == width - 1 or y == height - 1
			cells[y * width + x] = Cell.ROCK if edge or _random.randf() < cave_fill else Cell.ROOM
	for _i in cave_smooth:
		var next := cells.duplicate()
		for y in range(1, height - 1):
			for x in range(1, width - 1):
				var solid := 0
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						if dx == 0 and dy == 0:
							continue
						if cells[(y + dy) * width + x + dx] == Cell.ROCK:
							solid += 1
				next[y * width + x] = Cell.ROCK if solid >= 5 else Cell.ROOM
		cells = next
	stats["комнат"] = "нет: пещера это одна форма"


func _find_region() -> void:
	var mark := PackedInt32Array()
	mark.resize(width * height)
	mark.fill(-1)
	var floor_cells := 0
	var best_id := -1
	var best_n := 0
	var parts := 0
	for start in width * height:
		if cells[start] == Cell.ROCK or mark[start] != -1:
			continue
		var queue: Array[int] = [start]
		mark[start] = parts
		var n := 0
		while not queue.is_empty():
			var c: int = queue.pop_back()
			n += 1
			for neighbour in _around(c):
				if cells[neighbour] != Cell.ROCK and mark[neighbour] == -1:
					mark[neighbour] = parts
					queue.append(neighbour)
		floor_cells += n
		if n > best_n:
			best_n = n
			best_id = parts
		parts += 1

	for i in width * height:
		region[i] = 1 if mark[i] == best_id else 0

	stats["пол"] = "клеток %d, кусков: %d" % [floor_cells, parts]
	var reach := 0 if floor_cells == 0 else roundi(100.0 * best_n / floor_cells)
	stats["доступно"] = "%d%% пола" % reach
	if keep_largest:
		var cut := 0
		for i in width * height:
			if cells[i] != Cell.ROCK and region[i] == 0:
				cells[i] = Cell.ROCK
				cut += 1
		stats["доступно"] = "100%% (залито обратно %d клеток)" % cut


func _place_ends() -> void:
	var start := -1
	for i in width * height:
		if region[i] == 1:
			start = i
			break
	if start < 0:
		return
	# walk twice. the cell farthest from anywhere is one true end of the map; the
	# cell farthest from *that* is the other. two floods, no cleverness.
	_walk_from(start)
	var a := _far
	_walk_from(a)
	entrance = Vector2i(a % width, a / width)
	stairs = Vector2i(_far % width, _far / width)
	stats["проход"] = "%d шагов из конца в конец" % _far_dist


func _walk_from(start: int) -> void:
	var dist := PackedInt32Array()
	dist.resize(width * height)
	dist.fill(-1)
	dist[start] = 0
	var queue: Array[int] = [start]
	var head := 0
	_far = start
	_far_dist = 0
	while head < queue.size():
		var c: int = queue[head]
		head += 1
		if dist[c] > _far_dist:
			_far_dist = dist[c]
			_far = c
		for neighbour in _around(c):
			if cells[neighbour] != Cell.ROCK and dist[neighbour] == -1:
				dist[neighbour] = dist[c] + 1
				queue.append(neighbour)


func _around(i: int) -> Array[int]:
	var x := i % width
	var y := i / width
	var found: Array[int] = []
	if x > 0:
		found.append(i - 1)
	if x < width - 1:
		found.append(i + 1)
	if y > 0:
		found.append(i - width)
	if y < height - 1:
		found.append(i + width)
	return found
