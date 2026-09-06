class_name PathField
extends RefCounted

## Two ways to answer "which way to the goal", and the difference is who pays.
##
##   A*        one question, one answer. Cost per AGENT. Godot has AStarGrid2D built in,
##             so this half is the engine's — rule 5 says take it.
##   ПОЛЕ      one sweep over the whole grid from the goal outwards, leaving a direction
##             in every cell. Cost per GRID. Every agent then reads one byte.
##
## Same shape of answer as probes 23 and 25: cost per point against cost per tile. Which
## one wins is a number, and the number is the crossover count of agents.

const N := 64

## Eight neighbours, in the order the flow field stores them.
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]

var solid := PackedByteArray()
var astar := AStarGrid2D.new()
var flow := PackedByteArray()      ## index into DIRS, or 8 for "nowhere to go"
var reach := PackedInt32Array()    ## steps to the goal, -1 unreachable
var open_cells: Array[Vector2i] = []

var us_path := 0.0        ## microseconds for one A* query
var us_field := 0.0       ## microseconds to sweep the whole grid
var visited := 0          ## cells the sweep actually touched


func build(seed_value: int) -> void:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = 0.075
	n.fractal_octaves = 3
	solid.resize(N * N)
	for y in N:
		for x in N:
			var wall := n.get_noise_2d(float(x), float(y)) > 0.16
			# a solid rim, so nothing can path around the outside of the world
			if x == 0 or y == 0 or x == N - 1 or y == N - 1:
				wall = true
			solid[y * N + x] = 1 if wall else 0
	_keep_largest()
	_rebuild()


## Everything not connected to the biggest open region becomes wall. Probe 12 learned this
## the hard way: generation that can produce two caves WILL produce two caves, and an agent
## standing in the wrong one has no path at all — which reads as a broken pathfinder.
func _keep_largest() -> void:
	var seen := PackedByteArray()
	seen.resize(N * N)
	var best: PackedInt32Array = PackedInt32Array()
	for start in N * N:
		if solid[start] == 1 or seen[start] == 1:
			continue
		var group := PackedInt32Array()
		var queue := PackedInt32Array([start])
		seen[start] = 1
		var head := 0
		while head < queue.size():
			var i := queue[head]
			head += 1
			group.append(i)
			for d in DIRS:
				var x := i % N + d.x
				var y := i / N + d.y
				if x < 0 or y < 0 or x >= N or y >= N:
					continue
				var j := y * N + x
				if solid[j] == 1 or seen[j] == 1:
					continue
				seen[j] = 1
				queue.append(j)
		if group.size() > best.size():
			best = group
	solid.fill(1)
	open_cells.clear()
	for i in best:
		solid[i] = 0
		open_cells.append(Vector2i(i % N, i / N))


func _rebuild() -> void:
	astar.region = Rect2i(0, 0, N, N)
	astar.cell_size = Vector2.ONE
	# ONLY_IF_NO_OBSTACLES: a diagonal step is allowed only when both cells beside it are
	# open, so nothing cuts a corner through a wall. The mode is free; noticing that the
	# default lets you slice diagonally through masonry is not.
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for i in N * N:
		if solid[i] == 1:
			astar.set_point_solid(Vector2i(i % N, i / N), true)


func block(cell: Vector2i, on: bool) -> void:
	if cell.x <= 0 or cell.y <= 0 or cell.x >= N - 1 or cell.y >= N - 1:
		return
	solid[cell.y * N + cell.x] = 1 if on else 0
	astar.set_point_solid(cell, on)


func walkable(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < N and y < N and solid[y * N + x] == 0


## One A* query, timed. This is the whole of what the engine gives.
func path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var t0 := Time.get_ticks_usec()
	var p := astar.get_id_path(from, to)
	us_path = float(Time.get_ticks_usec() - t0)
	return p


## The sweep. Breadth first from the goal outwards, leaving in every cell the direction of
## the neighbour that is one step closer. Costs the whole grid once, then answers every
## agent for free — and answers agents that have not even been created yet.
func sweep(goal: Vector2i) -> void:
	var t0 := Time.get_ticks_usec()
	flow.resize(N * N)
	flow.fill(8)
	reach.resize(N * N)
	reach.fill(-1)
	if not walkable(goal.x, goal.y):
		us_field = float(Time.get_ticks_usec() - t0)
		visited = 0
		return
	var queue := PackedInt32Array([goal.y * N + goal.x])
	reach[goal.y * N + goal.x] = 0
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var cx := i % N
		var cy := i / N
		for k in 8:
			var d: Vector2i = DIRS[k]
			var x := cx + d.x
			var y := cy + d.y
			if not walkable(x, y):
				continue
			# no cutting corners on the diagonal, same rule as the A* mode above
			if d.x != 0 and d.y != 0 and not (walkable(cx + d.x, cy) and walkable(cx, cy + d.y)):
				continue
			var j := y * N + x
			if reach[j] >= 0:
				continue
			reach[j] = reach[i] + 1
			# the cell points BACK the way the wave came from, i.e. towards the goal
			flow[j] = (k + 4) % 8
			queue.append(j)
	visited = queue.size()
	us_field = float(Time.get_ticks_usec() - t0)


func step(cell: Vector2i) -> Vector2i:
	if not walkable(cell.x, cell.y):
		return Vector2i.ZERO
	var k := flow[cell.y * N + cell.x]
	return Vector2i.ZERO if k == 8 else DIRS[k]


## STRING PULLING. A grid path is a staircase, because a grid has eight directions and the
## world does not. Walk it and drop every waypoint you can already see past: what is left
## is the same route with the corners cut off. This is the first thing the engine does not
## do for you, and the first thing anybody notices.
func smooth(p: Array[Vector2i]) -> Array[Vector2i]:
	if p.size() < 3:
		return p
	var out: Array[Vector2i] = [p[0]]
	var anchor := 0
	var probe := 2
	while probe < p.size():
		if not clear(p[anchor], p[probe]):
			out.append(p[probe - 1])
			anchor = probe - 1
		probe += 1
	out.append(p[p.size() - 1])
	return out


## Line of sight between two cells: Bresenham, and every cell the line touches must be open.
func clear(a: Vector2i, b: Vector2i) -> bool:
	var d := Vector2i(absi(b.x - a.x), -absi(b.y - a.y))
	var s := Vector2i(1 if a.x < b.x else -1, 1 if a.y < b.y else -1)
	var err := d.x + d.y
	var at := a
	for _guard in N * 4:
		if not walkable(at.x, at.y):
			return false
		if at == b:
			return true
		var e2 := err * 2
		if e2 >= d.y:
			err += d.y
			at.x += s.x
		if e2 <= d.x:
			err += d.x
			at.y += s.y
	return false


func length_of(p: Array[Vector2i]) -> float:
	var sum := 0.0
	for i in range(1, p.size()):
		sum += Vector2(p[i] - p[i - 1]).length()
	return sum
