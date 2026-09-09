class_name BagGrid
extends RefCounted
## The bag with no pixels in it: which cells are taken, what fits where, and nothing
## about mice or Controls — so the packing can be measured without opening a window.
##
## Items are rectangles, Diablo style. That one decision is what makes a bag a puzzle
## instead of a list.

var columns := 10
var rows := 6
## One item per cell, its size ignored. Equipment slots work this way.
var compact := false
## Empty means the grid takes anything. Otherwise cell i only takes an item whose
## tag is tags[i].
var tags: PackedStringArray = []
## Each entry: definition, x, y. The definition is the shared read-only description
## of the thing; x and y are this copy's place in this grid.
var items: Array[Dictionary] = []


func setup(
		grid_columns: int,
		grid_rows: int,
		one_per_cell: bool,
		cell_tags: PackedStringArray) -> void:
	columns = grid_columns
	rows = grid_rows
	compact = one_per_cell
	tags = cell_tags
	items.clear()


func size_of(item: Dictionary) -> Vector2i:
	if compact:
		return Vector2i.ONE
	var definition: Dictionary = item["definition"]
	return Vector2i(definition["width"], definition["height"])


## Index of the item covering a cell, or -1.
func index_at(cell_x: int, cell_y: int) -> int:
	for i in items.size():
		var item: Dictionary = items[i]
		var span := size_of(item)
		var at_x: int = item["x"]
		var at_y: int = item["y"]
		if (
				cell_x >= at_x and cell_x < at_x + span.x
				and cell_y >= at_y and cell_y < at_y + span.y
		):
			return i
	return -1


## `skip` is the index of an item to ignore — the one being moved, which would
## otherwise collide with itself.
func fits(width: int, height: int, x: int, y: int, skip := -1, tag := "") -> bool:
	var span_x := 1 if compact else width
	var span_y := 1 if compact else height
	if x < 0 or y < 0 or x + span_x > columns or y + span_y > rows:
		return false
	if not tags.is_empty():
		var slot := y * columns + x
		if slot >= tags.size() or tags[slot] != tag:
			return false
	for cell_y in range(y, y + span_y):
		for cell_x in range(x, x + span_x):
			var index := index_at(cell_x, cell_y)
			if index != -1 and index != skip:
				return false
	return true


## First free place in reading order, or (-1, -1).
func find_spot(width: int, height: int, tag := "") -> Vector2i:
	for y in rows:
		for x in columns:
			if fits(width, height, x, y, -1, tag):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func add(definition: Dictionary, x: int, y: int) -> bool:
	if not fits(definition["width"], definition["height"], x, y, -1, definition["tag"]):
		return false
	items.append({"definition": definition, "x": x, "y": y})
	return true


func take(index: int) -> Dictionary:
	var item: Dictionary = items[index]
	items.remove_at(index)
	return item


func cells_used() -> int:
	var total := 0
	for item in items:
		var span := size_of(item)
		total += span.x * span.y
	return total


## First fit. The only difference between a bag that holds your loot and one that
## does not is what order you try things in.
func pack(definitions: Array[Dictionary], biggest_first: bool) -> int:
	items.clear()
	var order := definitions.duplicate()
	if biggest_first:
		order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a["width"] * a["height"] > b["width"] * b["height"])
	var placed := 0
	for definition in order:
		var at := find_spot(definition["width"], definition["height"], definition["tag"])
		if at.x >= 0:
			add(definition, at.x, at.y)
			placed += 1
	return placed
