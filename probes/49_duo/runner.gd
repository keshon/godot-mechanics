class_name DuoRunner
extends CharacterBody3D
## THE ONE WITH A BODY: runs, jumps and carries the light the builder works by.
##
## Nothing here knows who is holding it. The rig writes `move` and `jumping`; a stick, four keys or
## a script produce the same body. What the runner offers the other player is not a method but a
## fact about the world — a circle of light — and that is the whole of the dependency in one
## direction.

## Take-off speed, m/s. 5.5 gives an apex of 1.54 m: a 1.2 m platform is a hop, the 2.4 m ledge
## is not — it needs a platform under it, and the 1.8 m step to the top needs one on the ledge.
@export_range(1.0, 12.0, 0.1) var jump := 5.5
## Top speed, m/s.
@export_range(1.0, 12.0, 0.1) var speed := 5.0
## Reaching that speed on the ground, m/s². In the air a fifth of it.
@export_range(5.0, 80.0, 1.0) var acceleration := 35.0
## Reach of the lamp, m. The builder may only build inside it, when that rule is on.
@export_range(1.0, 12.0, 0.1) var light_radius := 4.5
## Below this height, m, the runner has fallen off the world.
@export_range(-40.0, -1.0, 0.5) var floor_of_the_world := -10.0

## Intent, world-flat: x along world X, y along world -Z. The rig turns a stick into this, because
## the rig owns the camera and "up on the stick" means "away from the camera".
var move := Vector2.ZERO
var jumping := false

var _start := Transform3D.IDENTITY
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var _body: Node3D = $Body
@onready var _lamp: OmniLight3D = $Lamp


func _ready() -> void:
	add_to_group(&"duo_runner")
	_start = global_transform
	_lamp.omni_range = light_radius


func _physics_process(delta: float) -> void:
	if global_position.y < floor_of_the_world:
		respawn()
		return

	# Gravity every tick, grounded or not: without it `is_on_floor()` goes false on the next tick.
	velocity.y -= _gravity * delta
	if jumping and is_on_floor():
		velocity.y = jump

	var wanted := Vector3(move.x, 0.0, -move.y) * speed
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


## Whether a point is inside the lamp, measured flat: a platform raised on a ledge above the
## runner's head is still in the light if it is near the runner on the map.
func lights(point: Vector3) -> bool:
	var offset := point - global_position
	return Vector2(offset.x, offset.z).length() <= light_radius
