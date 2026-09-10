class_name SeekerThreat
extends Control
## THE THREAT RING.
##
## Numbers on the screen do not answer "where is it now". Direction is a quantity the eye
## reads and the mind does not, and it has to be drawn as a circle rather than a line of text.
##
## The circle works like this: the centre is dead ahead, the rim is dead astern, halfway
## between them is the beam. The dot crawls from centre to rim as the missile comes round
## behind, and it is the one thing on screen that shows the manoeuvre without turning round.
##
## Drawn through `_draw`, because this is precisely the case it exists for: a figure that
## depends on two numbers and changes every frame.

const RADIUS := 92.0
const MARGIN := 16.0
## Closing speed, m/s, past which the ring goes from warm to hot.
const HOT_CLOSING := 200.0

## The backing is not optional. A thin light line on a light sky does not read at all, and
## an indicator without it looks like the absence of an indicator.
@export var backing := Color(0.05, 0.07, 0.09, 0.42)
@export var cold := Color(0.78, 0.84, 0.9)
@export var warm := Color(0.95, 0.62, 0.22)
@export var hot := Color(1.0, 0.32, 0.24)

## Written by the rig every frame: direction to the missile, in the target's own axes.
var bearing := Vector3.ZERO
var closing := 0.0
var locked := false
## Empty means there is no missile in the air.
var live := false


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var mid := Vector2(RADIUS + MARGIN, RADIUS + MARGIN)
	draw_circle(mid, RADIUS + 8.0, backing)
	draw_arc(mid, RADIUS, 0.0, TAU, 64, cold * Color(1, 1, 1, 0.85), 2.0, true)
	draw_arc(mid, RADIUS * 0.5, 0.0, TAU, 48, cold * Color(1, 1, 1, 0.4), 1.5, true)
	# Nose cross: the centre of the circle is "straight in front of me".
	draw_line(mid + Vector2(-10, 0), mid + Vector2(10, 0), cold * Color(1, 1, 1, 0.9), 1.5)
	draw_line(mid + Vector2(0, -10), mid + Vector2(0, 10), cold * Color(1, 1, 1, 0.9), 1.5)
	if not live:
		return

	var direction := bearing.normalized()
	# The angle off the nose decides how far from the centre the dot sits; the direction of
	# the offset decides which way. Screen "up" is world +Y, so the vertical sign is inverted.
	var away := Vector3.FORWARD.angle_to(direction) / PI
	var flat := Vector2(direction.x, -direction.y)
	if flat.length_squared() < 1e-6:
		flat = Vector2(0.0, -1.0)
	var at := mid + flat.normalized() * away * RADIUS

	var tint := cold
	if locked:
		tint = hot if closing > HOT_CLOSING else warm
	# A ray from the centre reads faster than a dot: it shows the side even in peripheral view.
	draw_line(mid, at, tint * Color(1, 1, 1, 0.55), 2.0)
	draw_circle(at, 7.0, tint)
	draw_arc(at, 13.0, 0.0, TAU, 24, tint * Color(1, 1, 1, 0.85), 2.0, true)
