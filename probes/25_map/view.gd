class_name MapView
extends Control
## The DRAWN map: one Control, one `_draw`, no nodes per cell.
##
## Probe 18 already paid for learning that a grid of Controls is the wrong shape. Here
## the reason is sharper: the map is not made of things, it is made of KNOWLEDGE. A cell
## you have never seen must not be drawn at all, and there is no node whose absence
## means that.

## A turned square shows its corners, so the window has to be widened by about root two
## before rotating, or those corners come out empty.
const CORNER := 1.45

@export var full := false
## Cells across the view. For the minimap this is the whole design decision: how much of
## the world the player is allowed to hold in their head at once.
@export var span := 46.0

var world: MapWorld
## Middle of the view for the full map, in cells. The minimap follows the player.
var focus := Vector2(48.0, 48.0)
## Where the player is and which way they face — pushed in by the world, so the view
## never reaches into somebody else tree for it.
var player := Vector2.ZERO
var heading := 0.0
var cells_drawn := 0

var _dragging := false


func _draw() -> void:
	if world == null:
		return
	var across: int = world.SIZE
	var centre := focus if full else player
	var pixels := size.x / span
	# The FULL map never turns. A minimap is steered by; a full map is read, and a map
	# that swings under the cursor cannot be read at all.
	var turn := 0.0 if full else world.map_turn()
	var widen := 1.0 if is_zero_approx(turn) else CORNER

	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.08))
	# Everything below is drawn in a frame centred on the control and turned by `turn`,
	# so the cells never learn about the rotation at all.
	draw_set_transform(size * 0.5, turn, Vector2.ONE)
	if world.baked and world.ground_texture != null:
		_draw_baked(centre, widen)
		cells_drawn = 2
		_draw_pins(centre, pixels, across, turn)
		return
	cells_drawn = _draw_cells(centre, pixels, across, widen)
	_draw_pins(centre, pixels, across, turn)


func _gui_input(event: InputEvent) -> void:
	if not full:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			span = maxf(span * 0.85, 12.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			span = minf(span * 1.18, float(world.SIZE) * 1.4)
		queue_redraw()
	elif event is InputEventMouseMotion and _dragging:
		focus -= event.relative / (size.x / span)
		queue_redraw()


## The third answer, in two layers: ground baked once, fog over it. The window is a
## source REGION, so panning, zooming and turning are arithmetic on a rectangle rather
## than more drawing — the view costs the same at any size or angle.
func _draw_baked(centre: Vector2, widen: float) -> void:
	var window := Vector2(span, span * size.y / size.x) * widen
	var source := Rect2(centre - window * 0.5, window)
	var target := Rect2(-size * 0.5 * widen, size * widen)
	# Ground NEAREST: cells must stay cells. Fog LINEAR: the edge of sight is not a real
	# boundary, it is a fade, and one texel per cell makes a staircase of it.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	draw_texture_rect_region(world.ground_texture, target, source)
	texture_filter = (
			CanvasItem.TEXTURE_FILTER_LINEAR if world.smooth_fog
			else CanvasItem.TEXTURE_FILTER_NEAREST)
	draw_texture_rect_region(world.fog_texture, target, source)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _draw_cells(centre: Vector2, pixels: float, across: int, widen: float) -> int:
	var fog: int = world.fog_mode
	var half_x := span * 0.5 * widen
	var half_y := half_x * size.y / size.x
	var painted := 0
	for y in range(maxi(int(centre.y - half_y), 0), mini(int(centre.y + half_y) + 1, across)):
		for x in range(maxi(int(centre.x - half_x), 0), mini(int(centre.x + half_x) + 1, across)):
			var state: int = world.seen[y * across + x]
			# A cell never seen is not drawn dark — it is NOT DRAWN. That is the whole
			# difference from a live map, which cannot help but show it.
			if fog > 0 and state == 0:
				continue
			var colour: Color = world.tint(world.kind[y * across + x])
			if fog == 2 and state == 1:
				colour = colour.darkened(0.55)
			draw_rect(
					Rect2(
							_offset(Vector2(float(x), float(y)), centre, pixels),
							Vector2(pixels + 1.0, pixels + 1.0)),
					colour)
			painted += 1
	return painted


## Markers, the player, the frame — the part a live map cannot do at all, because none of
## it is in the world. Drawn in SCREEN space, not in the turned frame: a marker pinned to
## the border has to follow the border, and the border does not turn.
func _draw_pins(centre: Vector2, pixels: float, across: int, turn: float) -> void:
	draw_set_transform_matrix(Transform2D.IDENTITY)
	for poi in world.pois:
		# You can only mark what you have found.
		if world.seen[int(poi.y) * across + int(poi.x)] == 0:
			continue
		_draw_marker(_screen_of(poi + Vector2(0.5, 0.5), centre, pixels, turn))
	var at := _screen_of(player + Vector2(0.5, 0.5), centre, pixels, turn)
	# An arrow, not a dot. With the map turning, "which way am I facing" stops being
	# obvious; with it fixed, the arrow is the only thing that says so. One expression
	# serves both, because the arrow lives in the same turned frame as the ground.
	var angle := heading + turn
	var radius := maxf(pixels * 1.4, 6.0)
	draw_colored_polygon(
			PackedVector2Array([
				at + Vector2(radius, 0.0).rotated(angle),
				at + Vector2(-radius * 0.6, radius * 0.6).rotated(angle),
				at + Vector2(-radius * 0.6, -radius * 0.6).rotated(angle),
			]),
			Color(1.0, 0.85, 0.3))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.7, 0.78, 0.88, 0.5), false, 2.0)


## Offset from the centre of the view, in pixels, before any rotation.
func _offset(cell: Vector2, centre: Vector2, pixels: float) -> Vector2:
	return (cell - centre) * pixels


func _screen_of(cell: Vector2, centre: Vector2, pixels: float, turn: float) -> Vector2:
	return _offset(cell, centre, pixels).rotated(turn) + size * 0.5


## A marker outside the view is not dropped — it is pinned to the border in the direction
## it lies. Same geometry as the cooldown sweep of probe 19: find where the ray leaves
## the RECTANGLE, not where it leaves a circle, or the corners come out wrong.
func _draw_marker(at: Vector2) -> void:
	var colour := Color(0.45, 0.85, 1.0)
	if at.x > 6.0 and at.y > 6.0 and at.x < size.x - 6.0 and at.y < size.y - 6.0:
		draw_circle(at, 4.0, colour)
		return
	if full:
		# A full map has no outside: everything is on it already.
		return
	var away := at - size * 0.5
	if away.length() < 0.001:
		return
	var limit := size * 0.5 - Vector2(8.0, 8.0)
	var reach := minf(
			limit.x / maxf(absf(away.x), 0.0001),
			limit.y / maxf(absf(away.y), 0.0001))
	draw_circle(size * 0.5 + away * reach, 3.0, colour.darkened(0.25))
