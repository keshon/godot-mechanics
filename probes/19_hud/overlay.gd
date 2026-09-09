class_name HudOverlay
extends Control
## World to screen. One Control draws every health bar, every damage number and every
## off-screen arrow — two hundred of them cost one `_draw`, not two hundred nodes.
##
## The trap lives in one line. `Camera3D.unproject_position` happily returns a point
## for something BEHIND the camera, and that point is mirrored: a monster at your back
## grows a health bar on the far side of the screen. `is_position_behind` is the
## guard, and press U to take it away and watch.

## Off: no is_position_behind check. Bars for things behind you appear mirrored.
@export var guard := true
## Distance from the middle to the ring the arrows sit on, pixels.
@export var edge := 46.0

## Floating numbers. A dead slot is reused instead of appended to, the same pool
## trick as the effects in probe 09 — numbers appear several times a second.
var floats: Array[Dictionary] = []
var behind_now := 0
var arrows_now := 0
## Arrows pointing at the opposite side of the screen because the guard is off.
var wrong_arrows := 0
var draw_usec := 0.0

var _camera: Camera3D
var _enemies: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	if _camera == null:
		return
	var started := Time.get_ticks_usec()
	var font := get_theme_default_font()
	var mid := size * 0.5
	behind_now = 0
	arrows_now = 0
	wrong_arrows = 0

	for enemy in _enemies:
		if enemy["hp"] <= 0.0:
			continue
		var head: Vector3 = enemy["position"] + Vector3(0, 1.5, 0)
		var behind := _camera.is_position_behind(head)
		if behind:
			behind_now += 1
		var at := _camera.unproject_position(head)
		var on_screen := (
				not behind
				and at.x > 0.0 and at.x < size.x
				and at.y > 0.0 and at.y < size.y
		)

		if on_screen or not guard:
			var box := Rect2(at.x - 27.0, at.y - 6.0, 54.0, 7.0)
			draw_rect(box.grow(1.0), Color(0, 0, 0, 0.6))
			var share := clampf(enemy["hp"] / enemy["hp_max"], 0.0, 1.0)
			draw_rect(
					Rect2(box.position, Vector2(box.size.x * share, box.size.y)),
					Color(0.95, 0.35, 0.3).lerp(Color(0.4, 0.9, 0.45), share))
		if not on_screen:
			_draw_rim_arrow(at - mid, mid, behind)

	for number in floats:
		if number["age"] >= 1.0:
			continue
		var age: float = number["age"]
		var world: Vector3 = number["at"]
		if _camera.is_position_behind(world):
			continue
		var at := _camera.unproject_position(world)
		at.y -= age * 54.0
		at.x += number["drift"] * age
		var colour: Color = number["colour"]
		colour.a = 1.0 - age * age
		var glyphs := 18 + int((1.0 - age) * 6)
		draw_string(
				font, at + Vector2(1, 1), number["text"],
				HORIZONTAL_ALIGNMENT_CENTER, 60, glyphs, Color(0, 0, 0, colour.a * 0.7))
		draw_string(
				font, at, number["text"],
				HORIZONTAL_ALIGNMENT_CENTER, 60, glyphs, colour)
	draw_usec = float(Time.get_ticks_usec() - started)


## The camera is handed in by the scene that owns both of us: an overlay that had to
## find its own camera would only work in one tree.
func setup(camera: Camera3D) -> void:
	_camera = camera


func tick(delta: float, enemies: Array[Dictionary]) -> void:
	_enemies = enemies
	for number in floats:
		if number["age"] < 1.0:
			number["age"] = minf(number["age"] + delta / 1.1, 1.0)
	queue_redraw()


func add_float(at: Vector3, text: String, colour: Color) -> void:
	for number in floats:
		if number["age"] >= 1.0:
			number["at"] = at
			number["text"] = text
			number["colour"] = colour
			number["age"] = 0.0
			number["drift"] = randf_range(-26.0, 26.0)
			return
	floats.append({
		"at": at,
		"text": text,
		"colour": colour,
		"age": 0.0,
		"drift": randf_range(-26.0, 26.0),
	})


func live_count() -> int:
	var alive := 0
	for number in floats:
		if number["age"] < 1.0:
			alive += 1
	return alive


## Something you cannot see: point at it from the rim of the screen.
func _draw_rim_arrow(from_mid: Vector2, mid: Vector2, behind: bool) -> void:
	var direction := from_mid
	if behind:
		# Behind the camera the projection is mirrored. Without this flip the arrow
		# points at the exact opposite side of the screen.
		if guard:
			direction = -direction
		else:
			wrong_arrows += 1
	if direction.length() < 0.01:
		direction = Vector2.RIGHT
	direction = direction.normalized()
	var limit := Vector2(mid.x - edge, mid.y - edge)
	var reach := minf(
			limit.x / maxf(absf(direction.x), 0.0001),
			limit.y / maxf(absf(direction.y), 0.0001))
	var at := mid + direction * reach
	var side := Vector2(-direction.y, direction.x)
	arrows_now += 1
	draw_colored_polygon(
			PackedVector2Array([
				at + direction * 13.0,
				at - direction * 7.0 + side * 8.0,
				at - direction * 7.0 - side * 8.0,
			]),
			Color(1.0, 0.55, 0.4, 0.9))
