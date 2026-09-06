class_name HudBar
extends Control

# The action bar. The thing that makes it different from the bag in probe 18 is that
# it is a clock: sweeps turn, charges refill, the global cooldown darkens everything
# at once, a cast fills up and can be broken.
#
# The one rule that matters:
#
#   a cooldown is a MOMENT IT ENDS, not a number of seconds left.
#
# Counting down with `left -= delta` looks identical while the bar is on screen. The
# difference is WHO OWNS THE CLOCK. A countdown lives in the widget, so it stops when
# the widget stops — a closed panel, a loading screen, a scene the bar is not part of.
# A moment-it-ends is measured against a clock the GAME owns, and the widget can come
# and go without the world noticing.

signal cast_done(slot: int)
signal cast_started(slot: int)

const GCD := 0.9

const ABILITIES := [
	{"name": "Strike", "key": "1", "cd": 2.0, "cost": 8.0, "cast": 0.0, "charges": 1,
		"dmg": 16.0, "aoe": false, "col": Color(0.95, 0.75, 0.35)},
	{"name": "Cleave", "key": "2", "cd": 6.0, "cost": 22.0, "cast": 0.0, "charges": 1,
		"dmg": 11.0, "aoe": true, "col": Color(0.95, 0.45, 0.3)},
	{"name": "Bolt", "key": "3", "cd": 0.0, "cost": 14.0, "cast": 1.2, "charges": 1,
		"dmg": 30.0, "aoe": false, "col": Color(0.5, 0.7, 1.0)},
	{"name": "Dash", "key": "4", "cd": 7.0, "cost": 0.0, "cast": 0.0, "charges": 2,
		"dmg": 0.0, "aoe": false, "col": Color(0.6, 0.95, 0.7)},
	{"name": "Mend", "key": "5", "cd": 9.0, "cost": 28.0, "cast": 1.8, "charges": 1,
		"dmg": 0.0, "aoe": false, "col": Color(0.5, 0.95, 0.55)},
	{"name": "Nova", "key": "6", "cd": 16.0, "cost": 44.0, "cast": 0.0, "charges": 1,
		"dmg": 26.0, "aoe": true, "col": Color(0.8, 0.5, 1.0)},
]

@export var slot := 62
@export var pad := 8
## the trap, on a switch: count down instead of remembering when it ends
@export var countdown_mode := false
## for the bench: force every cooldown to this. 0 = use each ability's own.
@export var cd_override := 0.0

var now := 0.0
var mana := 100.0
var mana_max := 100.0
var gcd_until := 0.0

var ready_at := PackedFloat64Array()
var charges := PackedInt32Array()
var recharge_at := PackedFloat64Array()
var left := PackedFloat64Array()      # only used by the wrong way
var casting := -1
var cast_from := 0.0
var cast_until := 0.0
var fired := 0
var refused := 0


func _ready() -> void:
	var n := ABILITIES.size()
	ready_at.resize(n)
	recharge_at.resize(n)
	left.resize(n)
	charges.resize(n)
	for i in n:
		charges[i] = ABILITIES[i]["charges"]
	custom_minimum_size = Vector2(n * (slot + pad) - pad, slot + 26)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## `game_now` comes from outside: the game owns the clock, not the bar.
## `awake` false = the bar exists but is not being updated (a closed panel).
func tick(game_now: float, awake := true) -> void:
	var delta := maxf(game_now - now, 0.0)
	now = game_now
	if not awake:
		queue_redraw()
		return
	mana = minf(mana + 9.0 * delta, mana_max)
	for i in ABILITIES.size():
		var a: Dictionary = ABILITIES[i]
		if countdown_mode:
			# the wrong way, kept so the difference can be felt and counted
			if left[i] > 0.0:
				left[i] -= delta
				if left[i] <= 0.0:
					left[i] = 0.0
					charges[i] = mini(charges[i] + 1, a["charges"])
					if charges[i] < a["charges"]:
						left[i] = cd_of(i)
		elif charges[i] < a["charges"] and now >= recharge_at[i]:
			charges[i] = mini(charges[i] + 1, a["charges"])
			if charges[i] < a["charges"]:
				recharge_at[i] = now + cd_of(i)
	if casting >= 0 and now >= cast_until:
		var s := casting
		casting = -1
		_spend(s)
	queue_redraw()


func cd_of(i: int) -> float:
	return cd_override if cd_override > 0.0 else float(ABILITIES[i]["cd"])


func remaining(i: int) -> float:
	if countdown_mode:
		return left[i]
	return maxf(recharge_at[i] - now, 0.0)


func can_cast(i: int) -> bool:
	var a: Dictionary = ABILITIES[i]
	return charges[i] > 0 and now >= gcd_until and casting < 0 and mana >= a["cost"]


func press(i: int) -> void:
	if not can_cast(i):
		refused += 1
		return
	var a: Dictionary = ABILITIES[i]
	gcd_until = now + GCD
	if a["cast"] > 0.0:
		casting = i
		cast_from = now
		cast_until = now + a["cast"]
		cast_started.emit(i)
		queue_redraw()
		return
	_spend(i)


func break_cast() -> void:
	if casting >= 0:
		casting = -1
		queue_redraw()


func _spend(i: int) -> void:
	var a: Dictionary = ABILITIES[i]
	mana -= a["cost"]
	charges[i] -= 1
	if countdown_mode:
		if left[i] <= 0.0:
			left[i] = cd_of(i)
	elif charges[i] < a["charges"] and recharge_at[i] <= now:
		recharge_at[i] = now + cd_of(i)
	fired += 1
	cast_done.emit(i)
	queue_redraw()


# --- drawing ------------------------------------------------------------------

func _draw() -> void:
	var font := get_theme_default_font()
	for i in ABILITIES.size():
		var a: Dictionary = ABILITIES[i]
		var r := Rect2(i * (slot + pad), 20, slot, slot)
		var dim: bool = mana < a["cost"] or charges[i] == 0
		draw_rect(r, Color(0.1, 0.11, 0.14, 0.9))
		var c: Color = a["col"]
		draw_rect(r.grow(-4), c.darkened(0.55) if dim else c)
		draw_rect(r, Color(1, 1, 1, 0.18), false, 1.0)

		# the sweep: a fan of triangles covering what is still left
		var rem := remaining(i)
		if rem > 0.0:
			_sweep(r, clampf(rem / maxf(cd_of(i), 0.001), 0.0, 1.0), Color(0, 0, 0, 0.62))
			draw_string(font, r.position + Vector2(6, r.size.y - 8),
				"%.1f" % rem, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.9))
		# the global cooldown darkens everything at once, and it is a different bar
		var g := maxf(gcd_until - now, 0.0)
		if g > 0.0:
			draw_rect(Rect2(r.position.x, r.end.y - 4, r.size.x * (g / GCD), 4),
				Color(1, 1, 1, 0.5))

		draw_string(font, r.position + Vector2(5, 14), a["key"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.75))
		if int(a["charges"]) > 1:
			draw_string(font, Vector2(r.end.x - 14, r.end.y - 7), str(charges[i]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.95))
		draw_string(font, Vector2(r.position.x, 14), a["name"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.45))

	var w := size.x
	draw_rect(Rect2(0, slot + 26, w, 6), Color(0.1, 0.12, 0.2, 0.9))
	draw_rect(Rect2(0, slot + 26, w * (mana / mana_max), 6), Color(0.35, 0.55, 0.95))

	if casting >= 0:
		var t := clampf((now - cast_from) / maxf(cast_until - cast_from, 0.001), 0.0, 1.0)
		var cr := Rect2(0, slot + 40, w, 16)
		draw_rect(cr, Color(0.08, 0.09, 0.12, 0.95))
		draw_rect(Rect2(cr.position, Vector2(cr.size.x * t, cr.size.y)), Color(0.95, 0.85, 0.4))
		draw_string(font, cr.position + Vector2(8, 13), "casting %s — move and it breaks"
			% ABILITIES[casting]["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0, 0, 0, 0.8))


func _sweep(r: Rect2, frac: float, col: Color) -> void:
	# The fan has to reach the SQUARE's border, not a circle's. A circle of radius
	# "long enough" spills over the neighbouring slots, and there is nothing to clip
	# it against — Control does not clip its own drawing by default.
	var mid := r.get_center()
	var half := r.size * 0.5
	var pts := PackedVector2Array([mid])
	var steps := 32
	for i in steps + 1:
		var ang := -PI * 0.5 + TAU * frac * (1.0 - float(i) / steps)
		var d := Vector2(cos(ang), sin(ang))
		var t: float = minf(half.x / maxf(absf(d.x), 0.0001), half.y / maxf(absf(d.y), 0.0001))
		pts.append(mid + d * t)
	if pts.size() > 2:
		draw_colored_polygon(pts, col)
