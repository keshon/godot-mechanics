class_name SeekerPrey
extends Node3D
## THE TARGET, AND THE ONLY THING WORTH FLYING BY HAND HERE.
##
## Same shape as the missile — a point at fixed speed with a ceiling on how hard it can
## bend — because the question is about the two laws, not about who has the better wing.
## Its ceiling is much lower, which is the whole reason a missile can catch an aeroplane.
##
## Reads no keys. Intent arrives in `pitch_input` and `yaw_input`, and who writes them is
## not its business.

## Gravity, m/s2. The only thing that turns a load in g into an acceleration.
const GRAVITY := 9.81

@export_range(50.0, 600.0, 5.0) var speed := 250.0
## Ceiling on lateral acceleration, g.
@export_range(1.0, 20.0, 0.5) var limit := 9.0
## A floor, so that diving away is an escape and not a way to leave the probe. Metres.
@export_range(50.0, 4000.0, 10.0) var floor_height := 150.0

var pitch_input := 0.0
var yaw_input := 0.0
var velocity := Vector3.ZERO


func _ready() -> void:
	velocity = -global_basis.z * speed


func _physics_process(delta: float) -> void:
	var up := global_basis.y
	var right := global_basis.x
	var want := (up * pitch_input + right * yaw_input) * limit * GRAVITY
	if want.length() > limit * GRAVITY:
		want = want.normalized() * limit * GRAVITY
	velocity = (velocity + want * delta).normalized() * speed
	global_position += velocity * delta
	if global_position.y < floor_height:
		global_position.y = floor_height
		velocity.y = maxf(velocity.y, 0.0)
		velocity = velocity.normalized() * speed
	look_at(global_position + velocity, Vector3.UP)


func reset(at: Transform3D) -> void:
	global_transform = at
	velocity = -at.basis.z * speed
	pitch_input = 0.0
	yaw_input = 0.0
