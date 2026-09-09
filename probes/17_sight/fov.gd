class_name SightFov
extends RefCounted
## Three ways to answer "what can I see from here". Press 1, 2, 3 and walk past
## a doorway — the difference is not subtle.
##
##   CIRCLE  everything within the radius. Walls do not exist. Wrong, and
##           useful: it is what the other two are trying not to be.
##   RAYS    fire a line at every cell on the rim and walk it until something
##           stops it. Obvious, common, and it leaves holes behind pillars that
##           no wall can explain.
##   SHADOW  recursive shadowcasting. Instead of asking about cells it carries
##           an angular wedge outward and splits it whenever a wall bites a
##           piece out. Every cell is visited once.

enum Mode {
	CIRCLE,
	RAYS,
	SHADOW,
}

## One octant per row, as the four elements of a 2x2 matrix: how to map (dx, dy)
## in octant space into the world. Eight of these are why shadowcasting only has
## to be written for one wedge.
const OCTANTS := [
	[1, 0, 0, 1],
	[0, 1, 1, 0],
	[0, -1, 1, 0],
	[-1, 0, 0, 1],
	[-1, 0, 0, -1],
	[0, -1, -1, 0],
	[0, 1, -1, 0],
	[1, 0, 0, -1],
]

var width := 0
var height := 0
var solid := PackedByteArray()
var lit := PackedByteArray()
## How many cells the last `look()` lit. The one number the three modes are
## compared by.
var seen := 0

var _origin_x := 0
var _origin_y := 0
var _radius := 8


func setup(map_width: int, map_height: int, blockers: PackedByteArray) -> void:
	width = map_width
	height = map_height
	solid = blockers
	lit = PackedByteArray()
	lit.resize(width * height)


func look(mode: Mode, from_x: int, from_y: int, radius: int) -> void:
	lit.fill(0)
	seen = 0
	_origin_x = from_x
	_origin_y = from_y
	_radius = radius
	_mark(from_x, from_y)
	match mode:
		Mode.CIRCLE:
			_circle()
		Mode.RAYS:
			_rays()
		Mode.SHADOW:
			for octant in OCTANTS:
				_shadow(1, 1.0, 0.0, octant[0], octant[1], octant[2], octant[3])


func is_visible(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height and lit[y * width + x] == 1


func _mark(x: int, y: int) -> void:
	if x < 0 or y < 0 or x >= width or y >= height:
		return
	if lit[y * width + x] == 0:
		lit[y * width + x] = 1
		seen += 1


func _blocks(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= width or y >= height:
		return true
	return solid[y * width + x] == 1


## No walls at all.
func _circle() -> void:
	for dy in range(-_radius, _radius + 1):
		for dx in range(-_radius, _radius + 1):
			if dx * dx + dy * dy <= _radius * _radius:
				_mark(_origin_x + dx, _origin_y + dy)


## A line to every cell on the rim.
func _rays() -> void:
	for i in range(-_radius, _radius + 1):
		_ray(_origin_x + i, _origin_y - _radius)
		_ray(_origin_x + i, _origin_y + _radius)
		_ray(_origin_x - _radius, _origin_y + i)
		_ray(_origin_x + _radius, _origin_y + i)


## Plain Bresenham, stopping at the first wall. The holes it leaves are not a
## bug in the line: two neighbouring rays simply skip over cells between them.
func _ray(to_x: int, to_y: int) -> void:
	var x := _origin_x
	var y := _origin_y
	var dx: int = absi(to_x - x)
	var dy: int = -absi(to_y - y)
	var step_x: int = 1 if to_x > x else -1
	var step_y: int = 1 if to_y > y else -1
	var error := dx + dy
	while true:
		var from_origin := (
				(x - _origin_x) * (x - _origin_x)
				+ (y - _origin_y) * (y - _origin_y)
		)
		if from_origin <= _radius * _radius:
			_mark(x, y)
		if _blocks(x, y) and not (x == _origin_x and y == _origin_y):
			return
		if x == to_x and y == to_y:
			return
		var doubled := error * 2
		if doubled >= dy:
			error += dy
			x += step_x
		if doubled <= dx:
			error += dx
			y += step_y


## Recursive shadowcasting over one octant. `xx`/`xy`/`yx`/`yy` are the four
## elements of that octant's matrix, straight out of OCTANTS.
func _shadow(
		row: int,
		start: float,
		end: float,
		xx: int,
		xy: int,
		yx: int,
		yy: int) -> void:
	if start < end:
		return
	var next_start := start
	for i in range(row, _radius + 1):
		var blocked := false
		var dy := -i
		var dx := -i - 1
		while dx <= 0:
			dx += 1
			var map_x := _origin_x + dx * xx + dy * xy
			var map_y := _origin_y + dx * yx + dy * yy
			# The wedge is measured in SLOPES, not in cells. This is the whole
			# trick, and it is why every cell is visited exactly once.
			var left_slope := (dx - 0.5) / (dy + 0.5)
			var right_slope := (dx + 0.5) / (dy - 0.5)
			if start < right_slope:
				continue
			if end > left_slope:
				break
			if dx * dx + dy * dy <= _radius * _radius:
				_mark(map_x, map_y)
			if blocked:
				if _blocks(map_x, map_y):
					next_start = right_slope
					continue
				blocked = false
				start = next_start
			elif _blocks(map_x, map_y) and i < _radius:
				# A wall bites a piece out of the wedge: recurse on what is left.
				blocked = true
				_shadow(i + 1, start, left_slope, xx, xy, yx, yy)
				next_start = right_slope
		if blocked:
			break
