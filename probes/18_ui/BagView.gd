class_name BagView
extends Control

# One Control for the whole grid, not one per cell. Sixty slots would be sixty nodes
# with sixty sets of signals; this is one node with a _draw and three callbacks.
#
# The three callbacks are Godot's built-in drag and drop, and most people never find
# them and write their own worse one:
#
#   _get_drag_data(pos)          pick something up, and set_drag_preview() to show it
#   _can_drop_data(pos, data)    called on every motion over this control
#   _drop_data(pos, data)        let go
#
# The engine handles the picking up, the carrying, the release, the cursor, and the
# case where you drop on nothing at all.

signal changed

@export var cols := 10
@export var rows := 6
@export var cell := 46
@export var compact := false
@export var slot_tags: PackedStringArray = []
@export var title := "bag"

var grid := BagGrid.new()

var clicks := 0

var _hover := Vector2i(-1, -1)
var _ghost := Vector2i(-1, -1)
var _ghost_ok := false
var _ghost_size := Vector2i.ONE


func _ready() -> void:
	grid.setup(cols, rows, compact, slot_tags)
	custom_minimum_size = Vector2(cols * cell, rows * cell)
	mouse_filter = Control.MOUSE_FILTER_STOP


func at_mouse(pos: Vector2) -> Vector2i:
	return Vector2i(int(pos.x) / cell, int(pos.y) / cell)


# --- drag and drop ------------------------------------------------------------

func _get_drag_data(pos: Vector2) -> Variant:
	var c := at_mouse(pos)
	var i := grid.item_at(c.x, c.y)
	if i == -1:
		return null
	var it: Dictionary = grid.take(i)
	changed.emit()
	queue_redraw()
	var preview := ColorRect.new()
	var s := grid.size_of(it)
	preview.size = Vector2(s.x * cell, s.y * cell) * 0.9
	preview.color = it["def"]["col"]
	preview.pivot_offset = preview.size * 0.5
	set_drag_preview(preview)
	return {"item": it, "from": self}


func _can_drop_data(pos: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not data.has("item"):
		return false
	var it: Dictionary = data["item"]
	var s: Vector2i = grid.size_of(it)
	var c := at_mouse(pos)
	_ghost = c
	_ghost_size = s
	_ghost_ok = grid.fits(s.x, s.y, c.x, c.y, -1, it["def"]["tag"])
	queue_redraw()
	return _ghost_ok


func _drop_data(pos: Vector2, data: Variant) -> void:
	var it: Dictionary = data["item"]
	var c := at_mouse(pos)
	grid.add(it["def"], c.x, c.y)
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
		var c := at_mouse(event.position)
		if c != _hover:
			_hover = c
			# the engine's own tooltip: set the text, it does the delay and the box
			var i := grid.item_at(c.x, c.y)
			tooltip_text = "" if i == -1 else _describe(grid.items[i])
			queue_redraw()


func _describe(it: Dictionary) -> String:
	var d: Dictionary = it["def"]
	return "%s\n%d x %d   %s" % [d["name"], d["w"], d["h"], d["tag"]]


func rotate_hovered() -> bool:
	var i := grid.item_at(_hover.x, _hover.y)
	if i == -1 or compact:
		return false
	var it: Dictionary = grid.items[i]
	var d: Dictionary = it["def"].duplicate()
	var tmp: int = d["w"]
	d["w"] = d["h"]
	d["h"] = tmp
	grid.take(i)
	if grid.add(d, it["x"], it["y"]):
		changed.emit()
		queue_redraw()
		return true
	grid.add(it["def"], it["x"], it["y"])  # would not fit turned; put it back
	return false


# --- drawing ------------------------------------------------------------------

func _draw() -> void:
	var back := Color(0.09, 0.1, 0.13, 0.92)
	draw_rect(Rect2(Vector2.ZERO, Vector2(cols * cell, rows * cell)), back)
	for y in rows:
		for x in cols:
			var r := Rect2(x * cell + 1, y * cell + 1, cell - 2, cell - 2)
			draw_rect(r, Color(1, 1, 1, 0.05))
			if not slot_tags.is_empty():
				var slot := y * cols + x
				if slot < slot_tags.size():
					draw_string(get_theme_default_font(), Vector2(r.position.x + 6, r.end.y - 6),
						slot_tags[slot], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.28))

	for it in grid.items:
		var s: Vector2i = grid.size_of(it)
		var r := Rect2(int(it["x"]) * cell + 3, int(it["y"]) * cell + 3,
			s.x * cell - 6, s.y * cell - 6)
		var c: Color = it["def"]["col"]
		draw_rect(r, c)
		draw_rect(r, c.lightened(0.35), false, 2.0)
		draw_string(get_theme_default_font(), r.position + Vector2(6, 16),
			str(it["def"]["name"]).substr(0, 2), HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(0, 0, 0, 0.65))

	if _ghost.x >= 0:
		var g := Rect2(_ghost.x * cell, _ghost.y * cell,
			_ghost_size.x * cell, _ghost_size.y * cell)
		draw_rect(g, Color(0.35, 1.0, 0.45, 0.25) if _ghost_ok else Color(1.0, 0.3, 0.25, 0.25))
		draw_rect(g, Color(0.4, 1.0, 0.5) if _ghost_ok else Color(1.0, 0.35, 0.3), false, 2.0)
	elif _hover.x >= 0 and _hover.x < cols and _hover.y >= 0 and _hover.y < rows:
		draw_rect(Rect2(_hover.x * cell, _hover.y * cell, cell, cell), Color(1, 1, 1, 0.08))

	draw_string(get_theme_default_font(), Vector2(2, -6), "%s   %d/%d" % [
		title, grid.used(), cols * rows], HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(1, 1, 1, 0.55))
