class_name BagGrid
extends RefCounted

# The bag with no pixels in it. Which cells are taken, what fits where, and nothing
# about mice or Controls — so the packing can be measured without opening a window.
#
# Items are rectangles, Diablo style. That one decision is what makes a bag a puzzle
# instead of a list.

var cols := 10
var rows := 6
## one item per cell, its size ignored. equipment slots work this way.
var compact := false
## empty = takes anything. otherwise cell i only takes an item tagged tags[i].
var tags: PackedStringArray = []

var items: Array[Dictionary] = []


func setup(c: int, r: int, comp: bool, tg: PackedStringArray) -> void:
	cols = c
	rows = r
	compact = comp
	tags = tg
	items.clear()


func size_of(it: Dictionary) -> Vector2i:
	if compact:
		return Vector2i.ONE
	return Vector2i(it["w"], it["h"])


func item_at(cx: int, cy: int) -> int:
	for i in items.size():
		var it: Dictionary = items[i]
		var s := size_of(it)
		if cx >= it["x"] and cy >= it["y"] and cx < int(it["x"]) + s.x and cy < int(it["y"]) + s.y:
			return i
	return -1


func fits(w: int, h: int, x: int, y: int, skip := -1, tag := "") -> bool:
	if compact:
		w = 1
		h = 1
	if x < 0 or y < 0 or x + w > cols or y + h > rows:
		return false
	if not tags.is_empty():
		var slot := y * cols + x
		if slot >= tags.size() or tags[slot] != tag:
			return false
	for cy in range(y, y + h):
		for cx in range(x, x + w):
			var i := item_at(cx, cy)
			if i != -1 and i != skip:
				return false
	return true


func find_spot(w: int, h: int, tag := "") -> Vector2i:
	for y in rows:
		for x in cols:
			if fits(w, h, x, y, -1, tag):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func add(def: Dictionary, x: int, y: int) -> bool:
	if not fits(def["w"], def["h"], x, y, -1, def["tag"]):
		return false
	items.append({"def": def, "x": x, "y": y, "w": def["w"], "h": def["h"]})
	return true


func take(i: int) -> Dictionary:
	var it: Dictionary = items[i]
	items.remove_at(i)
	return it


func used() -> int:
	var n := 0
	for it in items:
		var s := size_of(it)
		n += s.x * s.y
	return n


func pack(defs: Array, biggest_first: bool) -> int:
	# First fit. The only difference between a bag that holds your loot and one that
	# does not is what order you try things in.
	items.clear()
	var order: Array = defs.duplicate()
	if biggest_first:
		order.sort_custom(func(a, b): return a["w"] * a["h"] > b["w"] * b["h"])
	var got := 0
	for d in order:
		var at := find_spot(d["w"], d["h"], d["tag"])
		if at.x >= 0:
			add(d, at.x, at.y)
			got += 1
	return got
