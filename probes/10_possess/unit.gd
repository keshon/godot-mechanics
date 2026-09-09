class_name PossessUnit
extends CharacterBody3D
## A unit that can be told what to do, or taken over and driven.
##
## The interesting part is how little difference there is between the two. Both
## paths end at the same three lines of movement; only the source of the wish
## changes — a stored waypoint, or a key being held. Everything downstream is
## identical, which is why possession is cheap to add and why it should be
## designed in from the start rather than bolted on.

## How fast it walks when carrying out an order, m/s.
@export_range(1.0, 20.0, 0.5) var order_speed := 5.0
## How fast it walks when a player is driving it, m/s. Deliberately quicker: a
## unit under the hand should feel more responsive than one under orders.
@export_range(1.0, 20.0, 0.5) var drive_speed := 9.0
## How fast velocity climbs toward the wish, m/s².
@export_range(1.0, 200.0, 1.0) var acceleration := 40.0
## How fast the body swings to face where it is going, rad/s.
@export_range(1.0, 30.0, 0.5) var turn_speed := 9.0
## How close counts as arrived, m.
@export_range(0.1, 3.0, 0.05) var arrive_radius := 0.8
## Local gravity, m/s².
@export_range(1.0, 60.0, 0.5) var gravity := 20.0

var selected := false:
	set(value):
		selected = value
		if _ring:
			_ring.visible = value and not possessed

## While true this unit ignores its orders and listens to `wish` instead.
var possessed := false:
	set(value):
		possessed = value
		if _ring:
			_ring.visible = selected and not value

## Set from outside every physics tick while possessed. Nothing else writes it.
var wish := Vector3.ZERO

## Where it was told to go. `Vector3.INF` means "nowhere" — a sentinel rather
## than a second boolean, so there is exactly one place the answer lives.
var _target := Vector3.INF

@onready var _ring: MeshInstance3D = $Ring
@onready var _body: Node3D = $Body


func _ready() -> void:
	_ring.visible = false


func _physics_process(delta: float) -> void:
	velocity.y -= gravity * delta

	# The only branch in the whole class. Above it, two different worlds; below
	# it, one.
	var want := Vector3.ZERO
	var speed := drive_speed
	if possessed:
		want = wish
	elif has_order():
		var to_target := _target - global_position
		to_target.y = 0.0
		if to_target.length() < arrive_radius:
			_target = Vector3.INF
		else:
			want = to_target.normalized()
		speed = order_speed

	var planar := Vector3(velocity.x, 0.0, velocity.z)
	planar = planar.move_toward(want * speed, acceleration * delta)
	velocity.x = planar.x
	velocity.z = planar.z
	move_and_slide()

	var facing := Vector3(velocity.x, 0.0, velocity.z)
	if facing.length() > 0.3:
		var to_face := Basis.looking_at(facing.normalized(), Vector3.UP)
		_body.global_basis = Basis(_body.global_basis.get_rotation_quaternion().slerp(
				to_face.get_rotation_quaternion(),
				clampf(turn_speed * delta, 0.0, 1.0)))


func order(point: Vector3) -> void:
	_target = point


func has_order() -> bool:
	return _target != Vector3.INF
