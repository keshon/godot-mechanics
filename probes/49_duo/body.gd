class_name DuoBody
extends CharacterBody3D
## ONE BODY FOR BOTH PLAYERS: walks, jumps, and — if allowed — hangs from a point and swings.
##
## The course is seen from the side, so a body lives on the plane z = 0 and is put back on it every
## tick. Nothing here reads input or knows about nails: the rig writes `move` and `jumping`, and
## hands the swinger an anchor point with `grab`. Whether the point is a nail is the rig's business.
##
## THE SWING IS A PENDULUM, integrated by angle rather than left to the physics engine: a rope in
## Jolt would be a joint between two bodies, and a body hanging off a point that is not a body has
## nothing to join to. The angle is measured from straight down; the body is then driven towards
## where the angle puts it with `move_and_slide`, so a beam or a wall in the way still stops it.

signal respawned

## Height of the hands above the feet, m. The rope hangs from here.
const HAND_HEIGHT := 1.9

@export var can_swing := false
## Top speed on foot, m/s.
@export_range(1.0, 12.0, 0.1) var speed := 6.0
## Reaching that speed on the ground, m/s². In the air a quarter of it.
@export_range(5.0, 80.0, 1.0) var acceleration := 40.0
## Take-off speed, m/s. Six gives an apex of 1.84 m.
@export_range(1.0, 12.0, 0.1) var jump := 6.0
## How far from the hands a point may be and still be caught, m.
@export_range(1.0, 8.0, 0.1) var reach := 3.0
## The rope is never shorter or longer than this, whatever the distance at the moment of the grab.
@export_range(0.5, 4.0, 0.1) var rope_shortest := 1.5
@export_range(1.0, 8.0, 0.1) var rope_longest := 3.2
## Tangential acceleration a full stick adds to the swing, m/s². This is the pumping.
@export_range(0.0, 30.0, 0.5) var pump := 4.0
## How far from straight down the swing may go, degrees. Measured by a sweep over nail spots, pumps
## and release angles on 14 m pits: at 55° and above one nail crosses every pit; at 45° with a pump
## of 4 m/s² one nail crosses none of them and two nails cross all three.
@export_range(20.0, 90.0, 1.0) var swing_limit := 45.0
## Fraction of the swing lost per second.
@export_range(0.0, 2.0, 0.01) var swing_damping := 0.08
## Upward speed added on letting go, m/s: without it a release at the top of the arc only falls.
@export_range(0.0, 8.0, 0.1) var release_lift := 0.8
## Below this height, m, the body has fallen and is put back where it last stood.
@export_range(-40.0, -1.0, 0.5) var floor_of_the_world := -10.0

## Intent along the course, -1..1.
var move := 0.0
var jumping := false
var hanging := false
var anchor := Vector3.ZERO

var _angle := 0.0
## Angular speed of the swing, rad/s.
var _spin := 0.0
var _rope := 2.0
var _jumping_before := false
var _start := Vector3.ZERO
var _safe := Vector3.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var _body: Node3D = $Body
@onready var _thrower_suit: Node3D = $Body/ThrowerSuit
@onready var _swinger_suit: Node3D = $Body/SwingerSuit
@onready var _rope_mesh: MeshInstance3D = $Rope


func _ready() -> void:
	if can_swing:
		add_to_group(&"duo_swinger")
	_thrower_suit.visible = not can_swing
	_swinger_suit.visible = can_swing
	_start = global_position
	_safe = _start


func _physics_process(delta: float) -> void:
	if global_position.y < floor_of_the_world:
		respawn()
	elif hanging:
		_swing(delta)
	else:
		_walk(delta)
	global_position.z = 0.0
	velocity.z = 0.0
	_jumping_before = jumping
	_draw_rope()


func hand() -> Vector3:
	return global_position + Vector3.UP * HAND_HEIGHT


## Hangs from `point`. The rope takes the distance it finds, within its limits, and the swing keeps
## whatever part of the body's velocity runs along the arc — catching a point mid-jump carries the
## jump into the swing instead of stopping dead under it.
func grab(point: Vector3) -> void:
	var from_anchor := hand() - point
	anchor = point
	hanging = true
	_rope = clampf(from_anchor.length(), rope_shortest, rope_longest)
	_angle = atan2(from_anchor.x, -from_anchor.y)
	_spin = velocity.dot(_tangent()) / _rope


func release() -> void:
	if not hanging:
		return
	hanging = false
	velocity = _tangent() * _spin * _rope + Vector3.UP * release_lift


func respawn() -> void:
	hanging = false
	global_position = _safe + Vector3.UP * 0.2
	velocity = Vector3.ZERO
	respawned.emit()


## Back to where the body stood at the start, not to the last safe ground.
func restart() -> void:
	_safe = _start
	respawn()


func _walk(delta: float) -> void:
	# Gravity every tick, grounded or not: without it `is_on_floor()` goes false on the next tick.
	velocity.y -= _gravity * delta
	if jumping and not _jumping_before and is_on_floor():
		velocity.y = jump
	var rate := acceleration if is_on_floor() else acceleration * 0.25
	velocity.x = move_toward(velocity.x, move * speed, rate * delta)
	move_and_slide()
	if is_on_floor():
		_safe = global_position
	if absf(velocity.x) > 0.5:
		_body.rotation.y = lerp_angle(_body.rotation.y, -signf(velocity.x) * PI * 0.5, 12.0 * delta)


func _swing(delta: float) -> void:
	if jumping and not _jumping_before:
		release()
		return
	# θ'' = −(g/L)·sin θ, plus the pump along the arc. The pump is scaled by the rope for the same
	# reason gravity is: it is an acceleration of the body, and the angle turns L times slower.
	_spin += (-_gravity * sin(_angle) + move * pump) / _rope * delta
	_spin *= 1.0 - swing_damping * delta
	_angle += _spin * delta
	var limit := deg_to_rad(swing_limit)
	if absf(_angle) > limit:
		# The top of the arc: the swing stops there and falls back, as it would at the end of a rope
		# that goes no further.
		_angle = signf(_angle) * limit
		_spin = 0.0
	var hands_at := anchor + Vector3(sin(_angle), -cos(_angle), 0.0) * _rope
	velocity = (hands_at - hand()) / delta
	move_and_slide()
	if get_slide_collision_count() > 0:
		# Something stopped the body short of the arc. The angle follows the body, not the other way
		# round, and the swing loses most of its speed against whatever it hit.
		var from_anchor := hand() - anchor
		_angle = atan2(from_anchor.x, -from_anchor.y)
		_spin *= 0.3


func _tangent() -> Vector3:
	return Vector3(cos(_angle), sin(_angle), 0.0)


func _draw_rope() -> void:
	_rope_mesh.visible = hanging
	if not hanging:
		return
	var from := hand()
	var span := anchor - from
	var along := span.normalized()
	_rope_mesh.global_position = from + span * 0.5
	# The rope mesh is one metre long on its own Y; the basis lays Y along the rope and stretches it
	# to length. Everything lives on z = 0, so the other two axes are simply across and into the
	# screen.
	_rope_mesh.global_basis = Basis(
			along.cross(Vector3.BACK),
			along * span.length(),
			Vector3.BACK)
