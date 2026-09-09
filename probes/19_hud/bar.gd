class_name HudBar
extends Control
## The action bar. What makes it different from the bag in probe 18 is that it is a
## clock: sweeps turn, charges refill, the global cooldown darkens everything at once,
## a cast fills up and can be broken.
##
## The one rule that matters:
##
##   a cooldown is a MOMENT IT ENDS, not a number of seconds left.
##
## Counting down with `left -= delta` looks identical while the bar is on screen. The
## difference is WHO OWNS THE CLOCK. A countdown lives in the widget, so it stops when
## the widget stops — a closed panel, a loading screen, a scene the bar is not part
## of. A moment-it-ends is measured against a clock the GAME owns, and the widget can
## come and go without the world noticing.

signal cast_done(slot: int)

## Seconds every ability locks every other one for. A domain term, spelled the way
## the domain spells it.
const GCD := 0.9

const ABILITIES: Array[Dictionary] = [
	{"name": "Strike", "key": "1", "cooldown": 2.0, "cost": 8.0, "cast": 0.0,
		"charges": 1, "damage": 16.0, "aoe": false, "colour": Color(0.95, 0.75, 0.35)},
	{"name": "Cleave", "key": "2", "cooldown": 6.0, "cost": 22.0, "cast": 0.0,
		"charges": 1, "damage": 11.0, "aoe": true, "colour": Color(0.95, 0.45, 0.3)},
	{"name": "Bolt", "key": "3", "cooldown": 0.0, "cost": 14.0, "cast": 1.2,
		"charges": 1, "damage": 30.0, "aoe": false, "colour": Color(0.5, 0.7, 1.0)},
	{"name": "Dash", "key": "4", "cooldown": 7.0, "cost": 0.0, "cast": 0.0,
		"charges": 2, "damage": 0.0, "aoe": false, "colour": Color(0.6, 0.95, 0.7)},
	{"name": "Mend", "key": "5", "cooldown": 9.0, "cost": 28.0, "cast": 1.8,
		"charges": 1, "damage": 0.0, "aoe": false, "colour": Color(0.5, 0.95, 0.55)},
	{"name": "Nova", "key": "6", "cooldown": 16.0, "cost": 44.0, "cast": 0.0,
		"charges": 1, "damage": 26.0, "aoe": true, "colour": Color(0.8, 0.5, 1.0)},
]

@export var slot_size := 62
@export var padding := 8
## The trap, on a switch: count down instead of remembering when it ends.
@export var countdown_mode := false
## For the bench: force every cooldown to this. 0 = use the value in ABILITIES.
@export var cooldown_override := 0.0

## Game time, seconds. Handed in by `tick`, never read off a clock of our own.
var now := 0.0
var mana := 100.0
var mana_max := 100.0
var gcd_until := 0.0
## The right way: the moment the next charge of each ability lands.
var recharge_at := PackedFloat64Array()
## The wrong way, kept so the difference can be felt and counted.
var left := PackedFloat64Array()
var charges := PackedInt32Array()
var casting := -1
var cast_from := 0.0
var cast_until := 0.0
var fired := 0
var refused := 0


func _ready() -> void:
	var count := ABILITIES.size()
	recharge_at.resize(count)
	left.resize(count)
	charges.resize(count)
	for i in count:
		charges[i] = ABILITIES[i]["charges"]
	custom_minimum_size = Vector2(
			count * (slot_size + padding) - padding,
			slot_size + 26)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var font := get_theme_default_font()
	for i in ABILITIES.size():
		var ability: Dictionary = ABILITIES[i]
		var box := Rect2(i * (slot_size + padding), 20, slot_size, slot_size)
		var dim: bool = mana < ability["cost"] or charges[i] == 0
		draw_rect(box, Color(0.1, 0.11, 0.14, 0.9))
		var colour: Color = ability["colour"]
		draw_rect(box.grow(-4), colour.darkened(0.55) if dim else colour)
		draw_rect(box, Color(1, 1, 1, 0.18), false, 1.0)

		var remaining := cooldown_left(i)
		if remaining > 0.0:
			_draw_sweep(
					box,
					clampf(remaining / maxf(cooldown_of(i), 0.001), 0.0, 1.0),
					Color(0, 0, 0, 0.62))
			draw_string(
					font,
					box.position + Vector2(6, box.size.y - 8),
					"%.1f" % remaining,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.9))

		# The global cooldown darkens everything at once, and it is a different bar.
		var global_left := maxf(gcd_until - now, 0.0)
		if global_left > 0.0:
			draw_rect(
					Rect2(
							box.position.x,
							box.end.y - 4,
							box.size.x * (global_left / GCD),
							4),
					Color(1, 1, 1, 0.5))

		draw_string(
				font, box.position + Vector2(5, 14), ability["key"],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.75))
		if int(ability["charges"]) > 1:
			draw_string(
					font, Vector2(box.end.x - 14, box.end.y - 7), str(charges[i]),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.95))
		draw_string(
				font, Vector2(box.position.x, 14), ability["name"],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.45))

	var width := size.x
	draw_rect(Rect2(0, slot_size + 26, width, 6), Color(0.1, 0.12, 0.2, 0.9))
	draw_rect(
			Rect2(0, slot_size + 26, width * (mana / mana_max), 6),
			Color(0.35, 0.55, 0.95))

	if casting >= 0:
		var done := clampf(
				(now - cast_from) / maxf(cast_until - cast_from, 0.001), 0.0, 1.0)
		var box := Rect2(0, slot_size + 40, width, 16)
		draw_rect(box, Color(0.08, 0.09, 0.12, 0.95))
		draw_rect(
				Rect2(box.position, Vector2(box.size.x * done, box.size.y)),
				Color(0.95, 0.85, 0.4))
		draw_string(
				font,
				box.position + Vector2(8, 13),
				"casting %s — move and it breaks" % ABILITIES[casting]["name"],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0, 0, 0, 0.8))


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
		var ability: Dictionary = ABILITIES[i]
		if countdown_mode:
			if left[i] > 0.0:
				left[i] -= delta
				if left[i] <= 0.0:
					left[i] = 0.0
					charges[i] = mini(charges[i] + 1, ability["charges"])
					if charges[i] < ability["charges"]:
						left[i] = cooldown_of(i)
		elif charges[i] < ability["charges"] and now >= recharge_at[i]:
			charges[i] = mini(charges[i] + 1, ability["charges"])
			if charges[i] < ability["charges"]:
				recharge_at[i] = now + cooldown_of(i)
	if casting >= 0 and now >= cast_until:
		var slot := casting
		casting = -1
		_spend(slot)
	queue_redraw()


func cooldown_of(slot: int) -> float:
	if cooldown_override > 0.0:
		return cooldown_override
	return ABILITIES[slot]["cooldown"]


func cooldown_left(slot: int) -> float:
	if countdown_mode:
		return left[slot]
	return maxf(recharge_at[slot] - now, 0.0)


func can_cast(slot: int) -> bool:
	var ability: Dictionary = ABILITIES[slot]
	return (
			charges[slot] > 0
			and now >= gcd_until
			and casting < 0
			and mana >= ability["cost"]
	)


func press(slot: int) -> void:
	if not can_cast(slot):
		refused += 1
		return
	var ability: Dictionary = ABILITIES[slot]
	gcd_until = now + GCD
	if ability["cast"] > 0.0:
		casting = slot
		cast_from = now
		cast_until = now + ability["cast"]
		queue_redraw()
		return
	_spend(slot)


func break_cast() -> void:
	if casting >= 0:
		casting = -1
		queue_redraw()


func _spend(slot: int) -> void:
	var ability: Dictionary = ABILITIES[slot]
	mana -= ability["cost"]
	charges[slot] -= 1
	if countdown_mode:
		if left[slot] <= 0.0:
			left[slot] = cooldown_of(slot)
	elif charges[slot] < ability["charges"] and recharge_at[slot] <= now:
		recharge_at[slot] = now + cooldown_of(slot)
	fired += 1
	cast_done.emit(slot)
	queue_redraw()


func _draw_sweep(box: Rect2, fraction: float, colour: Color) -> void:
	# The fan has to reach the SQUARE border, not a circle. A circle of radius "long
	# enough" spills over the neighbouring slots, and there is nothing to clip it
	# against — Control does not clip its own drawing by default.
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
