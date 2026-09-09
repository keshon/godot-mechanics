class_name UiSkeleton
extends Control
## Press L. Every Control in the tree draws its own rectangle and says its name.
##
## Anchors and containers are the part of Godot people fight longest, and the reason
## is that a Control's rectangle is invisible until something goes wrong. Made
## visible, the rules stop being mysterious: a Container OWNS its children's
## rectangles, and setting them by hand is silently thrown away on the next relayout.

var showing := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	if showing:
		queue_redraw()


func _draw() -> void:
	if not showing:
		return
	_draw_tree(get_tree().root, 0)


func _draw_tree(node: Node, depth: int) -> void:
	if node is Control and node != self:
		var control := node as Control
		if control.size.x > 1.0 and control.size.y > 1.0:
			var hue := fposmod(float(depth) * 0.17, 1.0)
			var colour := Color.from_hsv(hue, 0.6, 1.0, 0.85)
			draw_rect(Rect2(control.global_position, control.size), colour, false, 1.0)
			draw_string(
					get_theme_default_font(),
					control.global_position + Vector2(4, 12),
					"%s  %dx%d" % [control.name, int(control.size.x), int(control.size.y)],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 10, colour)
	for child in node.get_children():
		_draw_tree(child, depth + 1)
