class_name DressTiler
extends RefCounted
## Dressing: grid of meanings -> pile of transforms.
##
## The whole trick is one number per cell. Look at the four neighbours, set a bit for
## each one you can walk on, and you get 0..15. That number picks the piece.
##
## And you do not draw 16 pieces. You draw TWO — a wall slab and a corner post — and
## let rotation do the other fourteen. Every autotiled game you have ever played is
## this, with nicer art and eight neighbours instead of four.
##
## The keys of `pieces` ARE node names under Board in the scene. Adding a
## piece means adding a node and a key, and touching no drawing code.

const N := 1
const E := 2
const S := 4
const W := 8

const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const YAW := [0.0, -PI * 0.5, PI, PI * 0.5]

var pieces := {}
var floor_tint: Array[Color] = []
var masks := PackedInt32Array()
var stats := {}


func dress(grid: DressGen, plain: bool) -> void:
	pieces = {"Floor": [], "Plain": [], "Slab": [], "Post": [], "Pillar": [],
		"Water": [], "Beam": []}
	floor_tint.clear()
	masks = PackedInt32Array()
	masks.resize(16)
	stats = {}

	for y in grid.height:
		for x in grid.width:
			match grid.at(x, y):
				DressGen.Cell.ROCK:
					_rock(grid, x, y, plain)
				DressGen.Cell.WATER:
					_put("Water", x, y, -0.22)
				DressGen.Cell.PROP:
					_floor(grid, x, y, plain)
					_put("Pillar", x, y, 0.65)
				_:
					_floor(grid, x, y, plain)
					if not plain and grid.at(x, y) == DressGen.Cell.HALL:
						_maybe_door(grid, x, y)

	var used := 0
	for m in masks:
		if m > 0:
			used += 1
	stats["masks seen"] = "%d of 16" % used
	stats["pieces drawn"] = "2 shapes, rotated" if not plain else "1 shape, a box"
	var total := 0
	for k in pieces:
		total += (pieces[k] as Array).size()
	stats["instances"] = str(total)
	stats["doorways"] = str((pieces["Beam"] as Array).size())


func _rock(grid: DressGen, x: int, y: int, plain: bool) -> void:
	var mask := 0
	for i in 4:
		if grid.walkable(x + DIRS[i].x, y + DIRS[i].y):
			mask |= 1 << i
	var diag := false
	for dx in [-1, 1]:
		for dy in [-1, 1]:
			if grid.walkable(x + dx, y + dy):
				diag = true
	if mask == 0 and not diag:
		return  # rock with nothing next to it is not a wall, it is nothing
	masks[mask] += 1
	if plain:
		_put("Plain", x, y, 0.3)
		return

	# one slab per open side, turned to face it
	for i in 4:
		if mask & (1 << i):
			var d: Vector2i = DIRS[i]
			_put_t("Slab", Vector3(x + d.x * 0.39, 0.35, y + d.y * 0.39), YAW[i])

	# a post wherever two slabs of this cell meet, and in the concave corners
	for i in 4:
		var j := (i + 1) % 4
		if (mask & (1 << i)) and (mask & (1 << j)):
			var d: Vector2i = DIRS[i] + DIRS[j]
			_put_t("Post", Vector3(x + d.x * 0.39, 0.42, y + d.y * 0.39), 0.0)
	if mask == 0:
		for dx in [-1, 1]:
			for dy in [-1, 1]:
				if grid.walkable(x + dx, y + dy):
					_put_t("Post", Vector3(x + dx * 0.5, 0.42, y + dy * 0.5), 0.0)


func _floor(grid: DressGen, x: int, y: int, plain: bool) -> void:
	_put("Floor", x, y, -0.05)
	if grid.walkable(x, y) and grid.region[y * grid.width + x] == 0:
		# cut off from the rest of the map. at level 3 this is almost always a
		# hand-drawn room whose props walled something in.
		floor_tint.append(Color(0.82, 0.31, 0.27))
		return
	var base := (
			Color(0.86, 0.86, 0.88) if grid.at(x, y) == DressGen.Cell.ROOM
			else Color(0.55, 0.53, 0.5)
	)
	if plain:
		floor_tint.append(base)
		return
	# same cell, same shade, every run. randf() here would boil the floor every frame.
	var h: int = ((x * 73856093) ^ (y * 19349663)) & 255
	var jitter := 0.88 + float(h) / 255.0 * 0.2
	floor_tint.append(Color(base.r * jitter, base.g * jitter, base.b * jitter))


func _maybe_door(grid: DressGen, x: int, y: int) -> void:
	# A corridor cell with a room next to it is NOT a doorway on its own: a corridor
	# that happens to run flush along a room wall touches it the whole way, and you
	# get a comb of door frames. A doorway is also a pinch — rock on both flanks.
	for i in 4:
		var d: Vector2i = DIRS[i]
		if grid.at(x + d.x, y + d.y) != DressGen.Cell.ROOM:
			continue
		var perp := Vector2i(-d.y, d.x)
		if grid.walkable(x + perp.x, y + perp.y) or grid.walkable(x - perp.x, y - perp.y):
			continue
		var side := Vector3(-float(d.y), 0.0, float(d.x)) * 0.42
		var mid := Vector3(x + d.x * 0.5, 0.0, y + d.y * 0.5)
		_put_t("Post", mid + side + Vector3(0, 0.42, 0), 0.0)
		_put_t("Post", mid - side + Vector3(0, 0.42, 0), 0.0)
		_put_t("Beam", mid + Vector3(0, 0.88, 0), YAW[i])
		return


func _put(kind: String, x: int, y: int, h: float) -> void:
	_put_t(kind, Vector3(x, h, y), 0.0)


func _put_t(kind: String, at: Vector3, yaw: float) -> void:
	var b := Basis.IDENTITY if is_zero_approx(yaw) else Basis.from_euler(Vector3(0, yaw, 0))
	(pieces[kind] as Array).append(Transform3D(b, at))
