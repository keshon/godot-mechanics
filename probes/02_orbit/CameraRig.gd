class_name OrbitRig
extends Node3D
## Three nodes, three jobs: this one holds yaw, its `Pitch` child holds pitch,
## and the SpringArm3D under that holds distance.
##
## Splitting them means none of the three needs to know about the others, and
## "orbit" needs no orbit code at all — rotating this node rotates everything
## beneath it, so the camera swings around the player as a consequence of the
## node tree rather than as a calculation. That is the part worth taking away
## from this probe: in Godot the scene graph often IS the maths.
##
## The one thing the tree cannot give us is LAG. A child node follows its
## parent exactly, and exactness is what made the first version of this rig
## feel weightless. So this node opts out of its parent's transform entirely
## (`top_level`) and chases the body by hand — see _follow().

@export_range(0.0005, 0.01, 0.0001) var mouse_sensitivity := 0.0025
## Looking down. Steeper than looking up because you want to see the ground in
## front of the character, and almost never the sky behind him.
@export_range(-89.0, 0.0, 1.0) var pitch_min := -70.0
@export_range(0.0, 89.0, 1.0) var pitch_max := 35.0


@export_group("Follow")
## How fast the pivot catches up to the body on the ground plane, per second.
##
## THE weight knob. Set it to 0 and the rig is welded to the body: that is
## exactly how this probe shipped before, and why it read as weightless. 4 is
## a heavy handheld camera trailing behind. 30 is welded again in all but name.
@export_range(0.0, 40.0, 0.5) var follow_speed := 12.0
## The same, vertically — and deliberately a different number.
##
## Vertical lag is the one that makes people ill. Every jump would leave the
## camera hanging below and then heave it up after you. Keep this well above
## `follow_speed`; the asymmetry is not a hack, it is the standard answer.
@export_range(0.0, 60.0, 0.5) var follow_speed_vertical := 25.0
## How high above the body's origin the pivot sits.
@export_range(0.0, 3.0, 0.05) var pivot_height := 0.55


@export_group("Distance")
## How far back the camera sits normally.
@export_range(1.0, 10.0, 0.1) var free_length := 4.0
## ...and while aiming. Close plus off-centre is what sells "aiming" — the
## character stops being the subject of the shot and becomes its foreground.
@export_range(0.5, 6.0, 0.1) var aim_length := 1.6
## The over-the-shoulder offset while aiming.
##
## This lives on the CAMERA and must never be put on the SpringArm3D, which is
## where the first version of this probe put it. The arm casts its shape from
## its own origin, so offsetting the arm moves the START of the cast — 0.65 m
## is further than the player's own radius, so standing against a wall put the
## cast origin on the far side of it. From there the cast found nothing, parked
## the camera at full length behind the wall, and you looked at the wall's
## backface, which does not render. One line, three symptoms.
@export var aim_shoulder := Vector3(0.65, 0.15, 0.0)
@export_range(0.05, 1.0, 0.01) var blend_time := 0.18
## How far short of an obstacle the sideways shoulder step stops.
@export_range(0.0, 1.0, 0.01) var offset_pad := 0.2


@onready var _pitch: Node3D = $Pitch
@onready var _arm: SpringArm3D = $Pitch/SpringArm3D
@onready var _mount: Node3D = $Pitch/SpringArm3D/Mount
@onready var _cam: Camera3D = $Pitch/SpringArm3D/Mount/Camera3D
## The body this rig hangs off: what it chases, and what it must not collide
## with. Read through get_parent() because top_level severs everything else.
@onready var _owner_body: CollisionObject3D = get_parent() as CollisionObject3D

## Where the shoulder offset currently wants to be. Tweened, then faded by how
## squeezed the arm is — see _process.
var _shoulder := Vector3.ZERO

var _tween: Tween


func _ready() -> void:
	top_level = true
	_arm.spring_length = free_length
	snap()


## The follow runs on the PHYSICS step, in lockstep with the body it chases.
##
## The obvious place is _process, once per rendered frame, and that is what
## this probe did first. It shivers: the body only moves 60 times a second, so
## between ticks it stands still while a camera updating every frame slides
## past it. Measured, the capsule jumped 108 mm frame to frame.
##
## Godot's proper answer is physics interpolation, and it was tried here. It
## cannot be switched on from a script at runtime: doing so leaves every node
## already in the tree with an uninitialised transform, and static geometry —
## which never moves again — renders stacked at the world origin forever while
## its collision stays correctly placed. reset_physics_interpolation() does not
## undo it, and neither does switching the flag back off. Enabling it in the
## project settings would work, but that is project-wide and probe 01 is closed.
##
## So: step together instead. The camera now updates at the body's rate.
func _physics_process(delta: float) -> void:
	_follow(delta)


func _process(_delta: float) -> void:
	# Fade the shoulder out as the arm gets squeezed. At full length the camera
	# sits all the way over the shoulder; pinned against a wall it slides back
	# to centre — the one place the arm has already proved there is room.
	var room := clampf(_arm.get_hit_length() / maxf(_arm.spring_length, 0.01), 0.0, 1.0)
	_cam.position = _clear(_shoulder * room)


## Put the pivot exactly on the body, no easing. For spawns and teleports,
## where lag would sweep the camera across the whole level.
func snap() -> void:
	global_position = _target()


## Distance the pivot is currently trailing the body by. Read by the HUD: it is
## the lag made visible, and it is what "weight" actually costs you.
func lag() -> float:
	return global_position.distance_to(_target())


func _target() -> Vector3:
	return _owner_body.global_position + Vector3.UP * pivot_height


func _follow(delta: float) -> void:
	var to := _target()
	var p := global_position
	p.x = _damp(p.x, to.x, follow_speed, delta)
	p.z = _damp(p.z, to.z, follow_speed, delta)
	p.y = _damp(p.y, to.y, follow_speed_vertical, delta)
	global_position = p


## Exponential damping, and the exponent is the point. The obvious version,
## `lerp(from, to, speed * delta)`, is correct at exactly one frame rate: halve
## the rate and it visibly loosens, and the moment `speed * delta` exceeds 1 it
## overshoots and rings.
##
## This one can never overshoot, at any rate, and against a STATIONARY target
## it lands identically whatever dt is. Chasing a MOVING target it is better
## but still not perfect — measured trailing distance at 6 m/s came out 0.41 m
## at 30 fps, 0.45 at 60, 0.47 at 144, because the target advances a full step
## before we damp. The naive lerp spreads 0.30 to 0.46 across the same range.
## Better, not perfect, and worth knowing which of the two it is.
func _damp(from: float, to: float, speed: float, delta: float) -> float:
	if speed <= 0.0:
		return to
	return to + (from - to) * exp(-speed * delta)


## The arm proves the path BACKWARD is clear. It says nothing about the
## sideways step from where it parks the mount out to the shoulder — and that
## step is long enough to cross a pillar the arm was entitled to call clear.
## So cast the last leg too, and stop short of whatever is in the way.
func _clear(want: Vector3) -> Vector3:
	if want.is_zero_approx():
		return Vector3.ZERO
	var from := _mount.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + _mount.global_basis * want)
	q.exclude = [_owner_body.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return want
	var reach := from.distance_to(hit.position) - offset_pad
	return want.normalized() * reach if reach > 0.0 else Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion) or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	rotate_y(-event.relative.x * mouse_sensitivity)
	# Repeated small rotations accumulate floating-point drift and the basis
	# slowly stops being a rotation. One call per frame keeps it honest.
	orthonormalize()
	_pitch.rotation.x = clampf(
		_pitch.rotation.x - event.relative.y * mouse_sensitivity,
		deg_to_rad(pitch_min), deg_to_rad(pitch_max))


## Wired to the player's `mode_changed` signal in orbit.tscn, not in code.
func set_aiming(on: bool) -> void:
	if _tween:
		_tween.kill()
	# A Tween is Godot's answer to "move a property over time" with no node, no
	# timer and no lerp in _process. The TPS demo does this same job with an
	# AnimationPlayer, which is the better tool the moment you want to shape
	# the curve by eye instead of by naming an easing.
	_tween = create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "_shoulder", aim_shoulder if on else Vector3.ZERO, blend_time)
	_tween.tween_property(_arm, "spring_length", aim_length if on else free_length, blend_time)


## How far the camera actually sits right now. Differs from spring_length the
## moment something is in the way — that gap is the SpringArm doing its job.
func actual_length() -> float:
	return _arm.get_hit_length()


func wanted_length() -> float:
	return _arm.spring_length
