class_name HudOverlay
extends Control

# World to screen. One Control draws every health bar, every damage number and every
# off-screen arrow — two hundred of them cost one _draw, not two hundred nodes.
#
# The trap lives in one line. `Camera3D.unproject_position` happily returns a point
# for something BEHIND the camera, and that point is mirrored: a monster at your back
# grows a health bar on the far side of the screen. `is_position_behind` is the guard,
# and press U to take it away and watch.

## off: no is_position_behind check. bars for things behind you appear mirrored.
@export var guard := true
@export var edge := 46.0

var arena: Node3D
var cam: Camera3D

var floats: Array[Dictionary] = []
var behind_now := 0
var arrows_now := 0

var draw_us := 0.0
var bad_arrows := 0

var _pool := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func pop(at: Vector3, text: String, col: Color) -> void:
	# reuse a dead slot instead of appending forever. same trick as the effect pool
	# in probe 09, and here it matters because numbers appear several times a second.
	for f in floats:
		if f["t"] >= 1.0:
			f["at"] = at
			f["text"] = text
			f["col"] = col
			f["t"] = 0.0
			f["drift"] = randf_range(-26.0, 26.0)
			return
	floats.append({"at": at, "text": text, "col": col, "t": 0.0,
		"drift": randf_range(-26.0, 26.0)})
	_pool = floats.size()


func tick(delta: float) -> void:
	for f in floats:
		if f["t"] < 1.0:
			f["t"] = minf(f["t"] + delta / 1.1, 1.0)
	queue_redraw()


func _draw() -> void:
	if cam == null or arena == null:
		return
	var t0 := Time.get_ticks_usec()
	var font := get_theme_default_font()
	var mid := size * 0.5
	behind_now = 0
	arrows_now = 0
	bad_arrows = 0

	for e in arena.enemies:
		if e["hp"] <= 0.0:
			continue
		var head: Vector3 = e["pos"] + Vector3(0, 1.5, 0)
		var back := cam.is_position_behind(head)
		if back:
			behind_now += 1
		var p := cam.unproject_position(head)
		var on := not back and p.x > 0.0 and p.y > 0.0 and p.x < size.x and p.y < size.y

		if on or not guard:
			var w := 54.0
			var r := Rect2(p.x - w * 0.5, p.y - 6.0, w, 7.0)
			draw_rect(r.grow(1.0), Color(0, 0, 0, 0.6))
			var frac: float = clampf(e["hp"] / e["max"], 0.0, 1.0)
			draw_rect(Rect2(r.position, Vector2(r.size.x * frac, r.size.y)),
				Color(0.95, 0.35, 0.3).lerp(Color(0.4, 0.9, 0.45), frac))
		if not on:
			# something you cannot see: point at it from the rim of the screen
			var dir := (p - mid)
			if back:
				# behind the camera the projection is mirrored. without this flip the
				# arrow points at the exact opposite side of the screen.
				if guard:
					dir = -dir
				else:
					bad_arrows += 1
			if dir.length() < 0.01:
				dir = Vector2.RIGHT
			dir = dir.normalized()
			var lim := Vector2(mid.x - edge, mid.y - edge)
			var k: float = minf(lim.x / maxf(absf(dir.x), 0.0001), lim.y / maxf(absf(dir.y), 0.0001))
			var a := mid + dir * k
			arrows_now += 1
			_arrow(a, dir, Color(1.0, 0.55, 0.4, 0.9))

	for f in floats:
		if f["t"] >= 1.0:
			continue
		var t: float = f["t"]
		var pos: Vector3 = f["at"]
		if cam.is_position_behind(pos):
			continue
		var p := cam.unproject_position(pos)
		p.y -= t * 54.0
		p.x += f["drift"] * t
		var c: Color = f["col"]
		c.a = 1.0 - t * t
		draw_string(font, p + Vector2(1, 1), f["text"], HORIZONTAL_ALIGNMENT_CENTER, 60,
			18 + int((1.0 - t) * 6), Color(0, 0, 0, c.a * 0.7))
		draw_string(font, p, f["text"], HORIZONTAL_ALIGNMENT_CENTER, 60,
			18 + int((1.0 - t) * 6), c)
	_finish_timer(t0)


func _finish_timer(t0: int) -> void:
	draw_us = float(Time.get_ticks_usec() - t0)


func _arrow(at: Vector2, dir: Vector2, col: Color) -> void:
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([
		at + dir * 13.0, at - dir * 7.0 + side * 8.0, at - dir * 7.0 - side * 8.0]), col)


func live() -> int:
	var n := 0
	for f in floats:
		if f["t"] < 1.0:
			n += 1
	return n
