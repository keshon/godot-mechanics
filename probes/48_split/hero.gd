class_name SplitHero
extends CharacterBody3D
## A HERO WHO LIVES IN ONE OF TWO WORLDS laid over the same ground.
##
## The ground, the walls and the pit are shared; what differs is what each hero can see and
## what each can stand on. Seeing is split by the camera — that is the rig's business, and the
## hero only says which world it belongs to. Standing is split HERE, by the collision mask, and
## nothing splits it for free: one physics world serves both heroes, and whatever is solid is
## solid for everyone who is allowed to touch its layer.
##
## Reads no keys. The rig writes `move`, `yaw` and `jumping`, and the same body works for a hand
## on a keyboard, a hand on a stick, or nobody at all.

## Physics layer every hero body sits on. Heroes do not collide with each other: they share a
## room but not a body, and pushing a partner off a ledge is a different probe.
const HERO_LAYER := 8

@export var world := SplitDual.World.SCIFI
## Top speed on foot, m/s.
@export_range(1.0, 12.0, 0.1) var speed := 5.0
## How fast the body reaches that speed on the ground, m/s². In the air a fifth of it.
@export_range(5.0, 80.0, 1.0) var acceleration := 30.0
## Take-off speed of a jump, m/s. Five gives a hop of about 1.3 m and a flight of about 1 s, so
## at full run a hero covers five metres in the air — and the pit is eight.
@export_range(1.0, 12.0, 0.1) var jump := 5.0
## Below this height, m, a hero has fallen into the pit and is put back at the start.
@export_range(-60.0, -2.0, 0.5) var floor_of_the_pit := -14.0

## Intent, written by whoever holds this hero: x is strafe, y is forward, both -1..1.
var move := Vector2.ZERO
## Where the hero is facing, radians about the vertical. Movement is relative to it.
var yaw := 0.0
var jumping := false
## Whether this hero also collides with the OTHER world's solids. Off, each world is its own;
## on, a hero walks on bridges it cannot see and stops against consoles that are not there.
var touches_other_world := false:
	set(value):
		touches_other_world = value
		_apply_mask()

var _start := Transform3D.IDENTITY
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var _body: Node3D = $Body
@onready var _scifi_suit: Node3D = $Body/ScifiSuit
@onready var _fantasy_suit: Node3D = $Body/FantasySuit


func _ready() -> void:
	_start = global_transform
	yaw = global_rotation.y
	collision_layer = HERO_LAYER
	_scifi_suit.visible = world == SplitDual.World.SCIFI
	_fantasy_suit.visible = world == SplitDual.World.FANTASY
	_apply_mask()


func _physics_process(delta: float) -> void:
	if global_position.y < floor_of_the_pit:
		respawn()
		return

	# Gravity is applied every tick, grounded or not: without it `is_on_floor()` stops being
	# true on the next tick and the body starts sliding off its own platform.
	velocity.y -= _gravity * delta
	if jumping and is_on_floor():
		velocity.y = jump

	var heading := Basis(Vector3.UP, yaw)
	var wanted := heading * Vector3(move.x, 0.0, -move.y) * speed
	var rate := acceleration if is_on_floor() else acceleration * 0.2
	var flat := Vector3(velocity.x, 0.0, velocity.z).move_toward(wanted, rate * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	move_and_slide()

	if flat.length_squared() > 0.25:
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(-flat.x, -flat.z), 12.0 * delta)


func respawn() -> void:
	global_transform = _start
	velocity = Vector3.ZERO
	yaw = _start.basis.get_euler().y


func _apply_mask() -> void:
	var other := (SplitDual.World.FANTASY if world == SplitDual.World.SCIFI
			else SplitDual.World.SCIFI)
	collision_mask = 1 | SplitDual.bits(world)
	if touches_other_world:
		collision_mask |= SplitDual.bits(other)
