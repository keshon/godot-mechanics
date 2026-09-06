extends Control

# The bar, reading straight off the simulation. It owns no state of its own — the
# clock, the cooldowns and the buffs all live in SpecSim, and this only draws them.
# Probe 19 measured why that matters; here it is just the way it is built.

@export var slot := 66
@export var pad := 9

var sim: SpecSim


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(7 * (slot + pad), slot + 40)


func _draw() -> void:
	if sim == null:
		sim = (get_parent().get_parent() as Node).sim
	if sim == null:
		return
	var font := get_theme_default_font()
	for i in SpecSim.ABILITIES.size():
		var a: Dictionary = SpecSim.ABILITIES[i]
		var r := Rect2(i * (slot + pad), 22, slot, slot)
		var ready: bool = sim.can_use(i)
		draw_rect(r, Color(0.09, 0.1, 0.13, 0.92))
		var c: Color = a["col"]
		draw_rect(r.grow(-4), c if ready else c.darkened(0.6))
		draw_rect(r, Color(1, 1, 1, 0.16), false, 1.0)

		var rem: float = maxf(sim.recharge_at[i] - sim.now, 0.0)
		if sim.charges[i] < int(a["charges"]) or (rem > 0.0 and sim.charges[i] == 0):
			_sweep(r, clampf(rem / maxf(float(a["cd"]), 0.001), 0.0, 1.0), Color(0, 0, 0, 0.6))
			draw_string(font, r.position + Vector2(6, r.size.y - 8), "%.1f" % rem,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.9))
		draw_string(font, r.position + Vector2(5, 14), a["key"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.7))
		if int(a["charges"]) > 1:
			draw_string(font, Vector2(r.end.x - 15, r.end.y - 7), str(sim.charges[i]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.95))
		draw_string(font, Vector2(r.position.x, 15), str(a["name"]).substr(0, 11),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.45))

	var w := 7.0 * (slot + pad) - pad
	var g: float = maxf(sim.gcd_until - sim.now, 0.0)
	draw_rect(Rect2(0, slot + 26, w, 5), Color(0.12, 0.13, 0.18, 0.9))
	if g > 0.0:
		draw_rect(Rect2(0, slot + 26, w * (g / SpecSim.GCD), 5), Color(1, 1, 1, 0.55))
	draw_rect(Rect2(0, slot + 34, w, 7), Color(0.1, 0.12, 0.2, 0.9))
	draw_rect(Rect2(0, slot + 34, w * (sim.focus / sim.focus_max), 7), Color(0.4, 0.75, 0.45))

	if sim.casting >= 0:
		var total: float = sim.cast_time(sim.casting)
		var done: float = clampf((sim.now - sim.cast_from) / maxf(total, 0.001), 0.0, 1.0)
		var cr := Rect2(0, -24, w, 17)
		draw_rect(cr, Color(0.08, 0.09, 0.12, 0.95))
		draw_rect(Rect2(cr.position, Vector2(cr.size.x * done, cr.size.y)), Color(0.95, 0.85, 0.4))
		draw_string(font, cr.position + Vector2(8, 13),
			str(SpecSim.ABILITIES[sim.casting]["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(0, 0, 0, 0.85))


func _sweep(r: Rect2, frac: float, col: Color) -> void:
	var mid := r.get_center()
	var half := r.size * 0.5
	var pts := PackedVector2Array([mid])
	for i in 33:
		var ang := -PI * 0.5 + TAU * frac * (1.0 - float(i) / 32.0)
		var d := Vector2(cos(ang), sin(ang))
		var t: float = minf(half.x / maxf(absf(d.x), 0.0001), half.y / maxf(absf(d.y), 0.0001))
		pts.append(mid + d * t)
	if pts.size() > 2:
		draw_colored_polygon(pts, col)
