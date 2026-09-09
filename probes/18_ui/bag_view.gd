class_name BagView
extends Control
## One Control for the whole grid, not one per cell. Sixty slots would be sixty nodes
## with sixty sets of signals; this is one node with a `_draw` and three callbacks.
##
## The three callbacks are Godot's own drag and drop, and most people never find them
## and write a worse one:
##
##   _get_drag_data(pos)          pick something up, and set_drag_preview() to show it
##   _can_drop_data(pos, data)    called on every motion over this control
##   _drop_data(pos, data)        let go
##
## The engine handles the picking up, the carrying, the release, the cursor, and the
## case where you drop on nothing at all.

signal changed

@export var columns := 10
@export var rows := 6
@export var cell := 46
@export var compact := false
@export var slot_tags: PackedStringArray = []
@export var title := "bag"

var grid := BagGrid.new()
## Mouse buttons this view received. The other half of the mouse_filter measurement:
## the panel's count and this one always add up to the clicks made.
var clicks := 0

var _hover := Vector2i(-1, -1)
var _ghost := Vector2i(-1, -1)
var _ghost_ok := false
var _ghost_size := Vector2i.ONE


func _ready() -> void:
	grid.setup(columns, rows, compact, slot_tags)
	custom_minimum_size = Vector2(columns * cell, rows * cell)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _get_drag_data(at_position: Vector2) -> Variant:
	var cursor := cell_at(at_position)
	var index := grid.index_at(cursor.x, cursor.y)
	if index == -1:
		return null
	var item := grid.take(index)
	changed.emit()
	queue_redraw()
	var definition: Dictionary = item["definition"]
	var span := grid.size_of(item)
	var preview := ColorRect.new()
	preview.size = Vector2(span.x * cell, span.y * cell) * 0.9
	preview.color = definition["colour"]
	preview.pivot_offset = preview.size * 0.5
	set_drag_preview(preview)
	return {"item": item, "from": self}


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not data.has("item"):
		return false
	var item: Dictionary = data["item"]
	var definition: Dictionary = item["definition"]
	var span := grid.size_of(item)
	var cursor := cell_at(at_position)
	_ghost = cursor
	_ghost_size = span
	_ghost_ok = grid.fits(span.x, span.y, cursor.x, cursor.y, -1, definition["tag"])
	queue_redraw()
	return _ghost_ok


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var item: Dictionary = data["item"]
	var cursor := cell_at(at_position)
	grid.add(item["definition"], cursor.x, cursor.y)
	_ghost = Vector2i(-1, -1)
	changed.emit()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT:
		_ghost = Vector2i(-1, -1)
		_hover = Vector2i(-1, -1)
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		clicks += 1
	if event is InputEventMouseMotion:
		var cursor := cell_at(event.position)
		if cursor != _hover:
			_hover = cursor
			# The engine's own tooltip: set the text, it does the delay and the box.
			var index := grid.index_at(cursor.x, cursor.y)
			tooltip_text = "" if index == -1 else _describe(grid.items[index])
			queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(
			Rect2(Vector2.ZERO, Vector2(columns * cell, rows * cell)),
			Color(0.09, 0.1, 0.13, 0.92))
	for y in rows:
		for x in columns:
			var box := Rect2(x * cell + 1, y * cell + 1, cell - 2, cell - 2)
			draw_rect(box, Color(1, 1, 1, 0.05))
			var slot := y * columns + x
			if slot < slot_tags.size():
				draw_string(
						font,
						Vector2(box.position.x + 6, box.end.y - 6),
						slot_tags[slot],
						HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.28))

	for item in grid.items:
		var definition: Dictionary = item["definition"]
		var span := grid.size_of(item)
		var box := Rect2(
				int(item["x"]) * cell + 3,
				int(item["y"]) * cell + 3,
				span.x * cell - 6,
				span.y * cell - 6)
		var colour: Color = definition["colour"]
		draw_rect(box, colour)
		draw_rect(box, colour.lightened(0.35), false, 2.0)
		draw_string(
				font,
				box.position + Vector2(6, 16),
				str(definition["name"]).substr(0, 2),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0, 0, 0, 0.65))

	if _ghost.x >= 0:
		var box := Rect2(
				_ghost.x * cell, _ghost.y * cell,
				_ghost_size.x * cell, _ghost_size.y * cell)
		var tint := Color(0.4, 1.0, 0.5) if _ghost_ok else Color(1.0, 0.35, 0.3)
		draw_rect(box, Color(tint, 0.25))
		draw_rect(box, tint, false, 2.0)
	elif _hover.x >= 0 and _hover.x < columns and _hover.y >= 0 and _hover.y < rows:
		draw_rect(
				Rect2(_hover.x * cell, _hover.y * cell, cell, cell),
				Color(1, 1, 1, 0.08))

	draw_string(
			font,
			Vector2(2, -6),
			"%s   %d/%d" % [title, grid.cells_used(), columns * rows],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.55))


func cell_at(at_position: Vector2) -> Vector2i:
	return Vector2i(int(at_position.x) / cell, int(at_position.y) / cell)


## Turn the item under the cursor a quarter. Returns false when it would not fit
## turned, and then nothing has moved.
func rotate_hovered() -> bool:
	var index := grid.index_at(_hover.x, _hover.y)
	if index == -1 or compact:
		return false
	var item: Dictionary = grid.items[index]
	var definition: Dictionary = item["definition"]
	var turned := definition.duplicate()
	turned["width"] = definition["height"]
	turned["height"] = definition["width"]
	var x: int = item["x"]
	var y: int = item["y"]
	grid.take(index)
	if grid.add(turned, x, y):
		changed.emit()
		queue_redraw()
		return true
	grid.add(definition, x, y)
	return false


func _describe(item: Dictionary) -> String:
	var definition: Dictionary = item["definition"]
	return "%s\n%d x %d   %s" % [
		definition["name"], definition["width"], definition["height"], definition["tag"]]
