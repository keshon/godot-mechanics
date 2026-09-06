class_name MapView
extends Control

## The DRAWN map: one Control, one _draw, no nodes per cell.
##
## Probe 18 already paid for learning that a grid of Controls is the wrong shape. Here the
## reason is sharper: the map is not made of things, it is made of KNOWLEDGE. A cell you
## have never seen must not be drawn at all, and there is no node whose absence means that.

@export var big := false
## Cells across the view. For the minimap this is the whole design decision: how much of
## the world the player is allowed to hold in their head at once.
@export var span := 46.0

## A turned square shows its corners, so the window has to be widened by about root two
## before rotating, or those corners come out empty.
const CORNER := 1.45

var world: Node
var focus := Vector2(48.0, 48.0)
var drawn := 0

var _drag := false


func _draw() -> void:
	if world == null:
		return
	var n: int = world.N
	var centre := focus if big else Vector2(
		world.get_node("Player").global_position.x,
		world.get_node("Player").global_position.z)
	var px := size.x / span
	var half := span * 0.5
	# The BIG map never turns. A minimap is steered by; a full map is read, and a map that
	# swings under the cursor cannot be read at all.
	var rot: float = 0.0 if big else world.map_turn()
	var k := 1.0 if is_zero_approx(rot) else CORNER
	var fog: int = world.fog_mode

	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.08))
	# Everything below is drawn in a frame centred on the control and turned by `rot`, so
	# the cells never learn about the rotation at all.
	draw_set_transform(size * 0.5, rot, Vector2.ONE)
	var cells := 0
	if world.baked and world.tex != null:
		# The third answer, in two layers: ground baked once, fog over it. The window is a
		# source REGION, so panning, zooming and turning are arithmetic on a rectangle
		# rather than more drawing — the view costs the same at any size or angle.
		var w := Vector2(span, span * size.y / size.x) * k
		var src := Rect2(centre - w * 0.5, w)
		var dst := Rect2(-size * 0.5 * k, size * k)
		# Ground NEAREST: cells must stay cells. Fog LINEAR: the edge of sight is not a
		# real boundary, it is a fade, and one texel per cell makes a staircase of it.
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		draw_texture_rect_region(world.tex, dst, src)
		texture_filter = (CanvasItem.TEXTURE_FILTER_LINEAR if world.smooth_fog
			else CanvasItem.TEXTURE_FILTER_NEAREST)
		draw_texture_rect_region(world.fog_tex, dst, src)
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		drawn = 2
		_pins(centre, px, n, rot)
		return
	var hx := half * k
	var hy := half * k * size.y / size.x
	for y in range(maxi(int(centre.y - hy), 0), mini(int(centre.y + hy) + 1, n)):
		for x in range(maxi(int(centre.x - hx), 0), mini(int(centre.x + hx) + 1, n)):
			var s: int = world.seen[y * n + x]
			# A cell never seen is not drawn dark — it is NOT DRAWN. That is the whole
			# difference from a live map, which cannot help but show it.
			if fog > 0 and s == 0:
				continue
			var c: Color = world.tint(world.kind[y * n + x])
			if fog == 2 and s == 1:
				c = c.darkened(0.55)
			draw_rect(Rect2(_off(Vector2(float(x), float(y)), centre, px),
				Vector2(px + 1.0, px + 1.0)), c)
			cells += 1
	drawn = cells
	_pins(centre, px, n, rot)


## Markers, the player, the frame — the part a live map cannot do at all, because none of
## it is in the world. Drawn in SCREEN space, not in the turned frame: a marker pinned to
## the border has to follow the border, and the border does not turn.
func _pins(centre: Vector2, px: float, n: int, rot: float) -> void:
	draw_set_transform_matrix(Transform2D.IDENTITY)
	for p in world.pois:
		# you can only mark what you have found
		if world.seen[int(p.y) * n + int(p.x)] == 0:
			continue
		_marker(_screen(p + Vector2(0.5, 0.5), centre, px, rot))
	var pl: Vector3 = world.get_node("Player").global_position
	var v := _screen(Vector2(pl.x, pl.z) + Vector2(0.5, 0.5), centre, px, rot)
	# An arrow, not a dot. With the map turning, "which way am I facing" stops being
	# obvious; with it fixed, the arrow is the only thing that says so. One expression
	# serves both, because the arrow lives in the same turned frame as the ground.
	var a: float = world.heading + rot
	var r: float = maxf(px * 1.4, 6.0)
	draw_colored_polygon(PackedVector2Array([
		v + Vector2(r, 0.0).rotated(a),
		v + Vector2(-r * 0.6, r * 0.6).rotated(a),
		v + Vector2(-r * 0.6, -r * 0.6).rotated(a)]), Color(1.0, 0.85, 0.3))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.7, 0.78, 0.88, 0.5), false, 2.0)


## Offset from the centre of the view, in pixels, before any rotation.
func _off(cell: Vector2, centre: Vector2, px: float) -> Vector2:
	return (cell - centre) * px


func _screen(cell: Vector2, centre: Vector2, px: float, rot: float) -> Vector2:
	return _off(cell, centre, px).rotated(rot) + size * 0.5


## A marker outside the view is not dropped — it is pinned to the border in the direction
## it lies. Same geometry as probe 19's cooldown sweep: find where the ray leaves the
## RECTANGLE, not where it leaves a circle, or the corners come out wrong.
func _marker(v: Vector2) -> void:
	var col := Color(0.45, 0.85, 1.0)
	var inside := v.x > 6.0 and v.y > 6.0 and v.x < size.x - 6.0 and v.y < size.y - 6.0
	if inside:
		draw_circle(v, 4.0, col)
		return
	if big:
		return           # a full map has no outside: everything is on it already
	var d := v - size * 0.5
	if d.length() < 0.001:
		return
	var lim := size * 0.5 - Vector2(8.0, 8.0)
	var t: float = minf(lim.x / maxf(absf(d.x), 0.0001), lim.y / maxf(absf(d.y), 0.0001))
	draw_circle(size * 0.5 + d * t, 3.0, col.darkened(0.25))


func _gui_input(event: InputEvent) -> void:
	if not big:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_drag = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			span = maxf(span * 0.85, 12.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			span = minf(span * 1.18, float(world.N) * 1.4)
		queue_redraw()
	elif event is InputEventMouseMotion and _drag:
		focus -= event.relative / (size.x / span)
		queue_redraw()
