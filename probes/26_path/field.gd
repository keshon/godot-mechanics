class_name PathField
extends RefCounted
## Two ways to answer "which way to the goal", and the difference is who pays.
##
##   A*        one question, one answer. Cost per AGENT. Godot has AStarGrid2D built in,
##             so this half is the engine — rule 5 says take it.
##   ПОЛЕ      one sweep over the whole grid from the goal outwards, leaving a direction
##             in every cell. Cost per GRID. Every agent then reads one byte.
##
## Same shape of answer as probes 23 and 25: cost per point against cost per tile. Which
## one wins is a number, and the number is the crossover count of agents.

const SIZE := 64

## Eight neighbours, in the order the flow field stores them.
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, 1),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(-1, 0),
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
]

var solid := PackedByteArray()
var astar := AStarGrid2D.new()
## Index into DIRS, or 8 for "nowhere to go".
var flow := PackedByteArray()
## Steps to the goal, -1 unreachable.
var reach := PackedInt32Array()
var open_cells: Array[Vector2i] = []

## Microseconds for one A* query.
var query_usec := 0.0
## Microseconds to sweep the whole grid.
var sweep_usec := 0.0
## Cells the sweep actually touched.
var visited := 0


func build(seed_value: int) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.075
	noise.fractal_octaves = 3
	solid.resize(SIZE * SIZE)
	for y in SIZE:
		for x in SIZE:
			var wall := noise.get_noise_2d(float(x), float(y)) > 0.16
			# A solid rim, so nothing can path around the outside of the world.
			if x == 0 or y == 0 or x == SIZE - 1 or y == SIZE - 1:
				wall = true
			solid[y * SIZE + x] = 1 if wall else 0
	_keep_largest()
	_rebuild()


func is_walkable(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < SIZE and y < SIZE and solid[y * SIZE + x] == 0


## One A* query, timed. This is the whole of what the engine gives.
func path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var started := Time.get_ticks_usec()
	var found := astar.get_id_path(from, to)
	query_usec = float(Time.get_ticks_usec() - started)
	return found


## The sweep. Breadth first from the goal outwards, leaving in every cell the direction
## of the neighbour that is one step closer. Costs the whole grid once, then answers
## every agent for free — and answers agents that have not even been created yet.
func sweep(goal: Vector2i) -> void:
	var started := Time.get_ticks_usec()
	flow.resize(SIZE * SIZE)
	flow.fill(8)
	reach.resize(SIZE * SIZE)
	reach.fill(-1)
	if not is_walkable(goal.x, goal.y):
		sweep_usec = float(Time.get_ticks_usec() - started)
		visited = 0
		return
	var queue := PackedInt32Array([goal.y * SIZE + goal.x])
	reach[goal.y * SIZE + goal.x] = 0
	var head := 0
	while head < queue.size():
		var index := queue[head]
		head += 1
		var from_x := index % SIZE
		var from_y := index / SIZE
		for side in 8:
			var step: Vector2i = DIRS[side]
			var x := from_x + step.x
			var y := from_y + step.y
			if not is_walkable(x, y):
				continue
			# No cutting corners on the diagonal, same rule as the A* mode below.
			if step.x != 0 and step.y != 0:
				if not is_walkable(from_x + step.x, from_y):
					continue
				if not is_walkable(from_x, from_y + step.y):
					continue
			var into := y * SIZE + x
			if reach[into] >= 0:
				continue
			reach[into] = reach[index] + 1
			# The cell points BACK the way the wave came from, i.e. towards the goal.
			flow[into] = (side + 4) % 8
			queue.append(into)
	visited = queue.size()
	sweep_usec = float(Time.get_ticks_usec() - started)


func direction_at(cell: Vector2i) -> Vector2i:
	if not is_walkable(cell.x, cell.y):
		return Vector2i.ZERO
	var side := flow[cell.y * SIZE + cell.x]
	if side == 8:
		return Vector2i.ZERO
	return DIRS[side]


## STRING PULLING. A grid path is a staircase, because a grid has eight directions and
## the world does not. Walk it and drop every waypoint you can already see past: what is
## left is the same route with the corners cut off. This is the first thing the engine
## does not do for you, and the first thing anybody notices.
func smoothed(route: Array[Vector2i]) -> Array[Vector2i]:
	if route.size() < 3:
		return route
	var cut: Array[Vector2i] = [route[0]]
	var anchor := 0
	var probe := 2
	while probe < route.size():
		if not is_clear(route[anchor], route[probe]):
			cut.append(route[probe - 1])
			anchor = probe - 1
		probe += 1
	cut.append(route[route.size() - 1])
	return cut


## Line of sight between two cells: Bresenham, and every cell the line touches must be
## open.
func is_clear(from: Vector2i, to: Vector2i) -> bool:
	var span := Vector2i(absi(to.x - from.x), -absi(to.y - from.y))
	var step := Vector2i(1 if from.x < to.x else -1, 1 if from.y < to.y else -1)
	var error := span.x + span.y
	var at := from
	for _guard in SIZE * 4:
		if not is_walkable(at.x, at.y):
			return false
		if at == to:
			return true
		var doubled := error * 2
		if doubled >= span.y:
			error += span.y
			at.x += step.x
		if doubled <= span.x:
			error += span.x
			at.y += step.y
	return false


func length_of(route: Array[Vector2i]) -> float:
	var total := 0.0
	for i in range(1, route.size()):
		total += Vector2(route[i] - route[i - 1]).length()
	return total


## Everything not connected to the biggest open region becomes wall. Probe 12 learned
## this the hard way: generation that can produce two caves WILL produce two caves, and
## an agent standing in the wrong one has no path at all — which reads as a broken
## pathfinder.
func _keep_largest() -> void:
	var seen := PackedByteArray()
	seen.resize(SIZE * SIZE)
	var best := PackedInt32Array()
	for start in SIZE * SIZE:
		if solid[start] == 1 or seen[start] == 1:
			continue
		var group := PackedInt32Array()
		var queue := PackedInt32Array([start])
		seen[start] = 1
		var head := 0
		while head < queue.size():
			var index := queue[head]
			head += 1
			group.append(index)
			for step in DIRS:
				var x := index % SIZE + step.x
				var y := index / SIZE + step.y
				if x < 0 or y < 0 or x >= SIZE or y >= SIZE:
					continue
				var into := y * SIZE + x
				if solid[into] == 1 or seen[into] == 1:
					continue
				seen[into] = 1
				queue.append(into)
		if group.size() > best.size():
			best = group
	solid.fill(1)
	open_cells.clear()
	for index in best:
		solid[index] = 0
		open_cells.append(Vector2i(index % SIZE, index / SIZE))


func _rebuild() -> void:
	astar.region = Rect2i(0, 0, SIZE, SIZE)
	astar.cell_size = Vector2.ONE
	# ONLY_IF_NO_OBSTACLES: a diagonal step is allowed only when both cells beside it are
	# open, so nothing cuts a corner through a wall. The mode is free; noticing that the
	# default lets you slice diagonally through masonry is not.
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for index in SIZE * SIZE:
		if solid[index] == 1:
			astar.set_point_solid(Vector2i(index % SIZE, index / SIZE), true)
