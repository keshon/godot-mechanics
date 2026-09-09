class_name SpecBar
extends Control
## The bar, reading straight off the simulation. It owns no state of its own — the
## clock, the cooldowns and the buffs all live in SpecSim, and this only draws them.
## Probe 19 measured why that matters; here it is just the way it is built.

@export var slot_size := 66
@export var padding := 9

var _sim: SpecSim


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(
			SpecSim.ABILITIES.size() * (slot_size + padding),
			slot_size + 40)


func _draw() -> void:
	if _sim == null:
		return
	var font := get_theme_default_font()
	for i in SpecSim.ABILITIES.size():
		var ability: Dictionary = SpecSim.ABILITIES[i]
		var box := Rect2(i * (slot_size + padding), 22, slot_size, slot_size)
		var usable := _sim.can_use(i)
		draw_rect(box, Color(0.09, 0.1, 0.13, 0.92))
		var colour: Color = ability["colour"]
		draw_rect(box.grow(-4), colour if usable else colour.darkened(0.6))
		draw_rect(box, Color(1, 1, 1, 0.16), false, 1.0)

		var remaining := maxf(_sim.recharge_at[i] - _sim.now, 0.0)
		var recharging: bool = _sim.charges[i] < int(ability["charges"])
		if recharging or (remaining > 0.0 and _sim.charges[i] == 0):
			_draw_sweep(
					box,
					clampf(remaining / maxf(float(ability["cooldown"]), 0.001), 0.0, 1.0),
					Color(0, 0, 0, 0.6))
			draw_string(
					font,
					box.position + Vector2(6, box.size.y - 8),
					"%.1f" % remaining,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.9))
		draw_string(
				font, box.position + Vector2(5, 14), ability["key"],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.7))
		if int(ability["charges"]) > 1:
			draw_string(
					font, Vector2(box.end.x - 15, box.end.y - 7), str(_sim.charges[i]),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.95))
		draw_string(
				font,
				Vector2(box.position.x, 15),
				str(ability["name"]).substr(0, 11),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.45))

	var width := SpecSim.ABILITIES.size() * (slot_size + padding) - padding
	var global_left := maxf(_sim.gcd_until - _sim.now, 0.0)
	draw_rect(Rect2(0, slot_size + 26, width, 5), Color(0.12, 0.13, 0.18, 0.9))
	if global_left > 0.0:
		draw_rect(
				Rect2(0, slot_size + 26, width * (global_left / SpecSim.GCD), 5),
				Color(1, 1, 1, 0.55))
	draw_rect(Rect2(0, slot_size + 34, width, 7), Color(0.1, 0.12, 0.2, 0.9))
	draw_rect(
			Rect2(0, slot_size + 34, width * (_sim.focus / _sim.focus_max), 7),
			Color(0.4, 0.75, 0.45))

	if _sim.casting >= 0:
		var total := _sim.cast_time(_sim.casting)
		var done := clampf((_sim.now - _sim.cast_from) / maxf(total, 0.001), 0.0, 1.0)
		var box := Rect2(0, -24, width, 17)
		draw_rect(box, Color(0.08, 0.09, 0.12, 0.95))
		draw_rect(
				Rect2(box.position, Vector2(box.size.x * done, box.size.y)),
				Color(0.95, 0.85, 0.4))
		draw_string(
				font,
				box.position + Vector2(8, 13),
				str(SpecSim.ABILITIES[_sim.casting]["name"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0, 0, 0, 0.85))


## Handed the model by the scene that owns both of us. A widget that went looking for
## its own model up the tree would only work in one tree.
func setup(simulation: SpecSim) -> void:
	_sim = simulation


func _draw_sweep(box: Rect2, fraction: float, colour: Color) -> void:
	var mid := box.get_center()
	var half := box.size * 0.5
	var points := PackedVector2Array([mid])
	var steps := 32
	for i in steps + 1:
		var angle := -PI * 0.5 + TAU * fraction * (1.0 - float(i) / steps)
		var ray := Vector2(cos(angle), sin(angle))
		var reach := minf(
				half.x / maxf(absf(ray.x), 0.0001),
				half.y / maxf(absf(ray.y), 0.0001))
		points.append(mid + ray * reach)
	if points.size() > 2:
		draw_colored_polygon(points, colour)
