extends Control
## Numbers, plus the two things that have to be drawn rather than written: the
## selection rectangle and the orders standing in each unit's queue.
##
## Both are drawn in _draw(), in plain screen pixels, over the 3D. Getting the
## orders there means asking the camera where a world point lands on screen —
## `unproject_position`, the same call the box selection uses. Once you have
## that one function, anything in the world can have a label on it.

## One draw call for every line, instead of one per line.
##
## Kept as a switch, and worth being honest about: it is worth almost nothing.
## Measured with 504 units and two waypoints each — 2.99 ms batched against
## 3.07 ms one by one. A thousand draw_line calls are simply cheap.
##
## The switch stays because batching draw calls is the right habit, and because
## watching it NOT matter here is as instructive as watching it matter in probe
## 04. The thing that actually cost fifteen milliseconds was the dots.
@export var batch_lines := true

## How the waypoint markers are drawn. THE knob, and not the one expected.
##
## Measured with 504 units selected, two waypoints each:
##
##   CIRCLES  ->  frame 14.65 ms,  _draw 8.00 ms
##   CROSSES  ->  frame  2.99 ms,  _draw 1.02 ms
##   NONE     ->  frame  3.01 ms,  _draw 0.92 ms
##
## Crosses cost the same as drawing nothing at all.
##
## A thousand draw_circle calls cost eight milliseconds inside the script alone,
## before the renderer sees them: each circle is a tessellated polygon built
## from scratch every frame. A cross is two straight segments, and two straight
## segments can join the multiline that is already being sent.
enum Dots {CIRCLES, CROSSES, NONE}
@export var dot_style: Dots = Dots.CROSSES

## Whether every unit gets its own thread of orders, or every ORDER does.
##
## PER_UNIT is what this probe shipped with, and it is a design mistake before
## it is a slow one. Send two thousand units to the same place and you get two
## thousand lines converging on one dot: unreadable. No released strategy game
## does this — StarCraft draws one marker per order.
##
## Measured, 2000 units all selected:
##
##                    per unit          per order
##   4 waypoints    15.04 ms  66 fps    5.57 ms  180 fps    2000 threads -> 1
##   8 waypoints    22.59 ms  44 fps    5.61 ms  178 fps    2000 threads -> 1
##
## Four times faster is not the interesting part. Look at the two per-order
## rows: 5.57 and 5.61. The length of the trail stopped costing anything at
## all, because there is one thread either way and a few more segments on it
## are free. Per unit, every extra waypoint was two thousand more segments.
##
## PER_ORDER groups the selection by the COMMAND it was given — every unit told
## to move by one click carries the same order id — and draws one line from the
## middle of each group. Two thousand units marching together collapse to one
## thread.
##
## The first attempt grouped by matching waypoint lists instead. It worked only
## while every unit went to the exact same spot, which stops being true the
## moment anything spreads them into a formation. Grouping belongs to the
## command, not to a coincidence in the data.
enum Paths {PER_UNIT, PER_ORDER}
@export var path_style: Paths = Paths.PER_ORDER

@export var field_path: NodePath = ^"../../Field"

@onready var field: Field = get_node(field_path)
@onready var _big: Label = $Big
@onready var _detail: RichTextLabel = $Detail

const SELECT_FILL := Color(0.45, 0.75, 1.0, 0.12)
const SELECT_EDGE := Color(0.55, 0.82, 1.0, 0.85)
const ORDER_LINE := Color(0.55, 0.9, 0.6, 0.55)
const ORDER_DOT := Color(0.6, 1.0, 0.65, 0.9)

## Microseconds the last _draw took, start to finish. Immune to vsync, which
## the frames-per-second number is not.
var draw_usec := 0
var _seg := PackedVector2Array()
var _dots := PackedVector2Array()
var _groups := {}
## How many distinct routes the selection is actually following. Shown on the
## HUD next to the selected count: the gap between the two numbers is how much
## work PER_UNIT was doing for nothing.
var group_count := 0


func _process(_delta: float) -> void:
	queue_redraw()
	var paused := get_tree().paused
	_big.text = "%d" % field.selected.size()
	var moving := 0
	for u in field.units():
		if u.busy():
			moving += 1
	_detail.text = "\n".join([
		"selected",
		"units    %d    moving    %d    routes    [b]%d[/b]"
			% [field.units().size(), moving, group_count],
		"time     %s" % ("[color=#ffcf7a][b]PAUSED[/b][/color]" if paused
			else "[b]x%.0f[/b]" % Engine.time_scale),
		"draw     [b]%.2f ms[/b]   lines %s, dots %s" % [draw_usec / 1000.0,
			"batched" if batch_lines else "[color=#ffcf7a]one by one[/color]",
			["[color=#ff8f7a]circles[/color]", "crosses", "off"][dot_style]],
		"",
		"[color=#8ecbff]orders still register while paused —[/color]",
		"[color=#8ecbff]that is the whole point of a tactical pause[/color]",
	])


func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	var cam: Camera3D = field.get_node(^"CamPivot/Camera3D")
	_seg.clear()
	_dots.clear()

	if path_style == Paths.PER_ORDER:
		_grouped(cam)
	else:
		_per_unit(cam)

	if not _seg.is_empty():
		draw_multiline(_seg, ORDER_LINE, 2.0)
	if not _dots.is_empty():
		draw_multiline(_dots, ORDER_DOT, 2.0)

	if field.dragging:
		var box := Rect2(field.drag_from, get_global_mouse_position() - field.drag_from).abs()
		draw_rect(box, SELECT_FILL, true)
		draw_rect(box, SELECT_EDGE, false, 1.5)

	draw_usec = Time.get_ticks_usec() - t0


## One thread per distinct route.
##
## The key is the order id the unit was handed when it was told to move.
func _grouped(cam: Camera3D) -> void:
	_groups.clear()
	for u in field.selected:
		var p := u.path()
		if p.is_empty():
			continue
		var key := u.order_id
		if _groups.has(key):
			var g: Dictionary = _groups[key]
			g.sum += u.global_position
			g.n += 1
		else:
			_groups[key] = {"sum": u.global_position, "n": 1, "path": p}
	group_count = _groups.size()
	for g in _groups.values():
		_thread(cam, g.sum / float(g.n), g.path)


## One thread per unit. Kept so the difference can be measured, not used.
func _per_unit(cam: Camera3D) -> void:
	group_count = field.selected.size()
	for u in field.selected:
		_thread(cam, u.global_position, u.path())


func _thread(cam: Camera3D, from: Vector3, path: Array[Vector3]) -> void:
	if cam.is_position_behind(from):
		return
	var prev := cam.unproject_position(from)
	for point in path:
		if cam.is_position_behind(point):
			continue
		var at := cam.unproject_position(point)
		if batch_lines:
			_seg.append(prev)
			_seg.append(at)
		else:
			draw_line(prev, at, ORDER_LINE, 2.0)
		match dot_style:
			Dots.CIRCLES:
				draw_circle(at, 4.0, ORDER_DOT)
			Dots.CROSSES:
				_dots.append(at + Vector2(-3.0, 0.0))
				_dots.append(at + Vector2(3.0, 0.0))
				_dots.append(at + Vector2(0.0, -3.0))
				_dots.append(at + Vector2(0.0, 3.0))
		prev = at
