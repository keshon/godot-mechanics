extends Control
## Показания плюс две вещи, которые надо рисовать, а не писать: рамка выделения и приказы,
## стоящие в очереди у каждого юнита.
##
## И то и другое рисуется в `_draw()`, в экранных точках, поверх трёхмерного мира. Чтобы
## приказы туда попали, у камеры спрашивают, куда мировая точка легла на экран, —
## `unproject_position`, тот же вызов, которым пользуется выделение рамкой. С этой одной
## функцией подпись можно повесить на что угодно в мире.

enum DotStyle {
	CIRCLES,
	CROSSES,
	NONE,
}

enum PathStyle {
	PER_UNIT,
	PER_ORDER,
}

const SELECT_FILL := Color(0.45, 0.75, 1.0, 0.12)
const SELECT_EDGE := Color(0.55, 0.82, 1.0, 0.85)
const ORDER_LINE := Color(0.55, 0.9, 0.6, 0.55)
const ORDER_DOT := Color(0.6, 1.0, 0.65, 0.9)
## Half-width of a cross marker, pixels.
const DOT_REACH := 3.0

## One draw call for every line, instead of one per line.
##
## Kept as a switch, and worth being honest about: it is worth almost nothing.
## Measured with 504 units and two waypoints each — 2.99 ms batched against
## 3.07 ms one by one. A thousand draw_line calls are simply cheap.
##
## The switch stays because batching draw calls is the right habit, and because
## watching it NOT matter here is as instructive as watching it matter in probe
## 04. The thing that actually cost fifteen milliseconds was the dots.
@export var use_batched_lines := true

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
@export var dot_style: DotStyle = DotStyle.CROSSES

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
@export var path_style: PathStyle = PathStyle.PER_ORDER

@export var field_path: NodePath = ^"../../Field"

## Microseconds the last _draw took, start to finish. Immune to vsync, which
## the frames-per-second number is not.
var draw_usec := 0
## How many distinct routes the selection is actually following. Shown on the
## HUD next to the selected count: the gap between the two numbers is how much
## work PER_UNIT was doing for nothing.
var group_count := 0

var _segments := PackedVector2Array()
var _dot_segments := PackedVector2Array()
var _groups := {}

@onready var field: CommandField = get_node(field_path)

@onready var _info: RichTextLabel = $Info


func _process(_delta: float) -> void:
	queue_redraw()
	var all_units := field.units()
	var moving := 0
	for unit in all_units:
		if unit.is_busy():
			moving += 1
	_info.text = "\n".join(PackedStringArray([
		"выделено [b]%d[/b] из %d   идут %d   ниток приказов [b]%d[/b]" % [
			field.selected.size(), all_units.size(), moving, group_count],
		"время: %s   отрисовка [b]%.2f[/b] мс" % [
			"[color=#ffd479][b]ПАУЗА[/b][/color]" if get_tree().paused
				else "[b]×%.0f[/b]" % Engine.time_scale,
			draw_usec / 1000.0],
		"",
		"WASD камера   КОЛЕСО приближение   ЛКМ выделить, рамкой или SHIFT добавить",
		"ПКМ приказ   SHIFT+ПКМ точка маршрута   ПРОБЕЛ пауза   1/2/3 время ×1 ×2 ×4",
		"нитки приказов: %s   точки: %s   линии: %s" % [
			"[b]по приказу[/b]" if path_style == PathStyle.PER_ORDER
				else "[color=#ff8a6a]по юниту[/color]",
			["[color=#ff8a6a]кружками[/color]", "крестами", "выключены"][dot_style],
			"пачкой" if use_batched_lines else "[color=#ffd479]по одной[/color]"],
		"",
		"[color=#66ccff]приказы принимаются и на паузе — в этом весь смысл"
			+ " тактической паузы[/color]",
	]))


func _draw() -> void:
	var draw_start: int = Time.get_ticks_usec()
	var camera := field.camera()
	_segments.clear()
	_dot_segments.clear()

	if path_style == PathStyle.PER_ORDER:
		_draw_grouped(camera)
	else:
		_draw_per_unit(camera)

	if not _segments.is_empty():
		draw_multiline(_segments, ORDER_LINE, 2.0)
	if not _dot_segments.is_empty():
		draw_multiline(_dot_segments, ORDER_DOT, 2.0)

	if field.dragging:
		var corner := get_global_mouse_position() - field.drag_from
		var box := Rect2(field.drag_from, corner).abs()
		draw_rect(box, SELECT_FILL, true)
		draw_rect(box, SELECT_EDGE, false, 1.5)

	draw_usec = Time.get_ticks_usec() - draw_start


## One thread per distinct route.
##
## The key is the order id the unit was handed when it was told to move.
func _draw_grouped(camera: Camera3D) -> void:
	_groups.clear()
	for unit in field.selected:
		var path := unit.path()
		if path.is_empty():
			continue
		var key := unit.order_id
		if _groups.has(key):
			var group: Dictionary = _groups[key]
			group.sum += unit.global_position
			group.count += 1
		else:
			_groups[key] = {"sum": unit.global_position, "count": 1, "path": path}
	group_count = _groups.size()
	for group in _groups.values():
		_draw_thread(camera, group.sum / float(group.count), group.path)


## One thread per unit. Kept so the difference can be measured, not used.
func _draw_per_unit(camera: Camera3D) -> void:
	group_count = field.selected.size()
	for unit in field.selected:
		_draw_thread(camera, unit.global_position, unit.path())


func _draw_thread(camera: Camera3D, from: Vector3, path: Array[Vector3]) -> void:
	if camera.is_position_behind(from):
		return
	var previous := camera.unproject_position(from)
	for point in path:
		if camera.is_position_behind(point):
			continue
		var at := camera.unproject_position(point)
		if use_batched_lines:
			_segments.append(previous)
			_segments.append(at)
		else:
			draw_line(previous, at, ORDER_LINE, 2.0)
		match dot_style:
			DotStyle.CIRCLES:
				draw_circle(at, 4.0, ORDER_DOT)
			DotStyle.CROSSES:
				_dot_segments.append(at + Vector2(-DOT_REACH, 0.0))
				_dot_segments.append(at + Vector2(DOT_REACH, 0.0))
				_dot_segments.append(at + Vector2(0.0, -DOT_REACH))
				_dot_segments.append(at + Vector2(0.0, DOT_REACH))
		previous = at

