extends Control

# Press L. Every Control in the tree draws its own rectangle and says its name.
#
# Anchors and containers are the part of Godot people fight longest, and the reason is
# that a Control's rectangle is invisible until something goes wrong. Made visible, the
# rules stop being mysterious: a Container OWNS its children's rects, and setting them
# by hand is silently thrown away on the next relayout.

var on := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	if on:
		queue_redraw()


func _draw() -> void:
	if not on:
		return
	_walk(get_tree().root, 0)


func _walk(node: Node, depth: int) -> void:
	if node is Control and node != self:
		var c := node as Control
		if c.size.x > 1.0 and c.size.y > 1.0:
			var hue := fposmod(float(depth) * 0.17, 1.0)
			var col := Color.from_hsv(hue, 0.6, 1.0, 0.85)
			draw_rect(Rect2(c.global_position, c.size), col, false, 1.0)
			draw_string(get_theme_default_font(), c.global_position + Vector2(4, 12),
				"%s  %dx%d" % [c.name, int(c.size.x), int(c.size.y)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
	for child in node.get_children():
		_walk(child, depth + 1)
