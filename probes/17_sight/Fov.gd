class_name SightFov
extends RefCounted

# Three ways to answer "what can I see from here". Press 1, 2, 3 and walk past a
# doorway — the difference is not subtle.
#
#   CIRCLE  everything within the radius. Walls do not exist. Wrong, and useful:
#           it is what the other two are trying not to be.
#   RAYS    fire a line at every cell on the rim and walk it until something stops
#           it. Obvious, common, and it leaves holes behind pillars that no wall
#           can explain.
#   SHADOW  recursive shadowcasting. Instead of asking about cells it carries an
#           angular wedge outward and splits it whenever a wall bites a piece out.
#           Every cell is visited once.

enum Mode { CIRCLE, RAYS, SHADOW }

var w := 0
var h := 0
var solid := PackedByteArray()
var lit := PackedByteArray()
var seen := 0

# one octant per row: how to map (dx, dy) in octant space into the world
const OCT := [
	[1, 0, 0, 1], [0, 1, 1, 0], [0, -1, 1, 0], [-1, 0, 0, 1],
	[-1, 0, 0, -1], [0, -1, -1, 0], [0, 1, -1, 0], [1, 0, 0, -1],
]

var _ox := 0
var _oy := 0
var _r := 8


func setup(width: int, height: int, blockers: PackedByteArray) -> void:
	w = width
	h = height
	solid = blockers
	lit = PackedByteArray()
	lit.resize(w * h)


func look(mode: Mode, ox: int, oy: int, radius: int) -> void:
	lit.fill(0)
	seen = 0
	_ox = ox
	_oy = oy
	_r = radius
	_mark(ox, oy)
	match mode:
		Mode.CIRCLE:
			_circle()
		Mode.RAYS:
			_rays()
		Mode.SHADOW:
			for o in 8:
				_shadow(1, 1.0, 0.0, OCT[o][0], OCT[o][1], OCT[o][2], OCT[o][3])


func visible(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h and lit[y * w + x] == 1


func _mark(x: int, y: int) -> void:
	if x < 0 or y < 0 or x >= w or y >= h:
		return
	if lit[y * w + x] == 0:
		lit[y * w + x] = 1
		seen += 1


func _blocks(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= w or y >= h:
		return true
	return solid[y * w + x] == 1


# --- 1. no walls at all -------------------------------------------------------

func _circle() -> void:
	for dy in range(-_r, _r + 1):
		for dx in range(-_r, _r + 1):
			if dx * dx + dy * dy <= _r * _r:
				_mark(_ox + dx, _oy + dy)


# --- 2. a line to every cell on the rim ---------------------------------------

func _rays() -> void:
	for i in range(-_r, _r + 1):
		_ray(_ox + i, _oy - _r)
		_ray(_ox + i, _oy + _r)
		_ray(_ox - _r, _oy + i)
		_ray(_ox + _r, _oy + i)


func _ray(tx: int, ty: int) -> void:
	# plain Bresenham, stopping at the first wall. the holes it leaves are not a bug
	# in the line: two neighbouring rays simply skip over cells between them.
	var x := _ox
	var y := _oy
	var dx: int = absi(tx - x)
	var dy: int = -absi(ty - y)
	var sx: int = 1 if tx > x else -1
	var sy: int = 1 if ty > y else -1
	var err := dx + dy
	while true:
		if (x - _ox) * (x - _ox) + (y - _oy) * (y - _oy) <= _r * _r:
			_mark(x, y)
		if _blocks(x, y) and not (x == _ox and y == _oy):
			return
		if x == tx and y == ty:
			return
		var e2 := err * 2
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy


# --- 3. recursive shadowcasting -----------------------------------------------

func _shadow(row: int, start: float, end: float, xx: int, xy: int, yx: int, yy: int) -> void:
	if start < end:
		return
	var next_start := start
	for i in range(row, _r + 1):
		var blocked := false
		var dy := -i
		var dx := -i - 1
		while dx <= 0:
			dx += 1
			var mx := _ox + dx * xx + dy * xy
			var my := _oy + dx * yx + dy * yy
			# the wedge is measured in slopes, not in cells. this is the whole trick.
			var l_slope := (dx - 0.5) / (dy + 0.5)
			var r_slope := (dx + 0.5) / (dy - 0.5)
			if start < r_slope:
				continue
			if end > l_slope:
				break
			if dx * dx + dy * dy <= _r * _r:
				_mark(mx, my)
			if blocked:
				if _blocks(mx, my):
					next_start = r_slope
					continue
				blocked = false
				start = next_start
			elif _blocks(mx, my) and i < _r:
				# a wall bites a piece out of the wedge: recurse on what is left
				blocked = true
				_shadow(i + 1, start, l_slope, xx, xy, yx, yy)
				next_start = r_slope
		if blocked:
			break
