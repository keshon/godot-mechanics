class_name WalkPlayer
extends CharacterBody3D
## First-person mover in the Quake 3 tradition, riding Godot's CharacterBody3D.
##
## Every number that decides how this feels is an @export. Run the scene, keep
## the editor open, select Player in the remote scene tree and drag the values
## while you play — the inspector writes straight into the running game. That
## is the whole point of this probe.

## Emitted the frame a jump takes off.
signal jumped

## Emitted the frame the feet touch down again. `speed_delta` is how much
## horizontal speed the jump gained (+) or lost (-), in m/s. Chained strafe
## jumps make this positive; a straight-line hop makes it negative.
signal landed(speed_delta: float)


@export_group("Look")
## Radians of rotation per pixel of mouse motion.
@export_range(0.0005, 0.01, 0.0001) var mouse_sensitivity := 0.0022
## How far the camera may tilt up or down, in degrees.
@export_range(50.0, 89.9, 0.1) var pitch_limit := 89.0


@export_group("Ground")
## Top speed the ground accelerator aims for, m/s.
@export_range(1.0, 20.0, 0.1) var max_speed := 9.0
## How hard the ground accelerator pushes toward max_speed, m/s².
@export_range(1.0, 40.0, 0.5) var acceleration := 12.0
## How hard the ground slows you down, m/s². 0 turns the floor into ice.
@export_range(0.0, 20.0, 0.1) var friction := 6.0
## Below this speed, friction is applied as if you were moving this fast, m/s.
## It is what makes the last metre of a stop crisp instead of a long slow crawl.
@export_range(0.0, 10.0, 0.1) var stop_speed := 2.0


@export_group("Air")
## THE strafe-jump number, in m/s, and the reason this probe exists. See
## _accelerate(): this is the speed cap the accelerator checks against while
## airborne, and it is deliberately tiny. Raise it to match max_speed and
## strafe jumping dies completely. Drop it to 0 and you lose all steering in
## the air.
@export_range(0.0, 20.0, 0.05) var air_max_speed := 1.0
## How hard the air accelerator pushes, within the cap above, m/s².
@export_range(0.0, 40.0, 0.5) var air_acceleration := 14.0


@export_group("Jump")
## Upward speed given at takeoff, m/s.
@export_range(1.0, 15.0, 0.1) var jump_velocity := 5.2
## Local gravity, m/s². Godot's project default is 9.8 — real, and far too
## floaty for this school of shooter. Heavier gravity buys a short arc and a
## hard landing.
##
## Not taken from physics. Solved from the SHAPE of the jump: pick the height
## and the time in the air, then g = 8h/t². For h 0.7 m and t 0.5 s that is
## exactly 20, and jump_velocity = g*t/2 = 5.2. Quake 3 runs at about 25.6,
## the same family.
@export_range(1.0, 60.0, 0.5) var gravity := 20.0
## Grace period after walking off an edge during which a jump still works, s.
@export_range(0.0, 0.3, 0.005) var coyote_time := 0.1
## How long a jump press is remembered if you hit it just before landing, s.
@export_range(0.0, 0.3, 0.005) var jump_buffer := 0.1
## Holding jump re-jumps the moment you land, so a chain needs no rhythm.
## Off by default, and the default is a deliberate choice: the jump frame skips
## the ground accelerator entirely (see _physics_process), so with this ON and
## the key held from a standstill you leave the ground before the ground can
## push you, and you crawl along at air_max_speed forever. Quake behaves the
## same way. Turn it on once you already have speed and want to keep it.
@export var auto_bhop_enabled := false

## Highest horizontal speed reached since the last respawn, m/s. Read by the HUD.
var peak_speed := 0.0

var _spawn: Transform3D
var _coyote_left := 0.0
var _buffer_left := 0.0
var _was_on_floor := true
var _takeoff_speed := 0.0

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	_spawn = global_transform
	_set_mouse_captured(true)


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed(&"respawn"):
		_respawn()
		return

	var on_floor := is_on_floor()
	_tick_timers(delta, on_floor)

	# Gravity is applied unconditionally, even while standing. The downward
	# nudge is what keeps is_on_floor() true and lets the body follow slopes
	# instead of stepping off them. A jump overwrites velocity.y right after,
	# so this costs the jump nothing.
	velocity.y -= gravity * delta

	var wish_direction := _wish_direction()
	var took_off := _try_jump(on_floor)

	if on_floor and not took_off:
		_apply_friction(delta)
		_accelerate(wish_direction, max_speed, acceleration, delta)
	else:
		_accelerate(wish_direction, air_max_speed, air_acceleration, delta)

	move_and_slide()

	peak_speed = maxf(peak_speed, speed())
	if is_on_floor() and not _was_on_floor:
		landed.emit(speed() - _takeoff_speed)
	_was_on_floor = is_on_floor()


func _unhandled_input(event: InputEvent) -> void:
	# Mouse look is the one thing that belongs here rather than in
	# _physics_process: motion events carry a `relative` delta that only makes
	# sense event by event, and polling would throw most of them away.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Yaw turns the whole body — that is what makes `global_basis` below a
		# valid frame for movement. Pitch turns the camera alone, so looking at
		# the sky never turns walking into flying.
		rotate_y(-event.relative.x * mouse_sensitivity)
		var limit := deg_to_rad(pitch_limit)
		_camera.rotation.x = clampf(
				_camera.rotation.x - event.relative.y * mouse_sensitivity,
				-limit,
				limit)
	elif event.is_action_pressed(&"ui_cancel"):
		_set_mouse_captured(false)
	elif event is InputEventMouseButton and event.pressed:
		_set_mouse_captured(true)


## Horizontal speed in m/s. Vertical motion is excluded on purpose: falling is
## not going fast, and mixing the two hides what the accelerators are doing.
func speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func _wish_direction() -> Vector3:
	# get_vector returns y = back - forward, and forward in Godot is -Z, so the
	# raw y drops into the Z slot with no sign flip. Multiplying by the body's
	# basis rotates that intent into the world using yaw only.
	var input: Vector2 = Input.get_vector(
			&"move_left", &"move_right", &"move_forward", &"move_back")
	var direction := global_basis * Vector3(input.x, 0.0, input.y)
	direction.y = 0.0
	return direction.normalized()


## Quake's accelerate. Four lines, and every one of them earns its place.
##
## The load-bearing trick is `current`: it is the projection of your velocity
## onto the direction you are ASKING for, not the length of your velocity. Ask
## for a direction roughly sideways to where you are already going, and that
## projection stays small — so the cap barely bites and you keep gaining speed
## well past `wish_speed`. That is strafe jumping. It was never designed; it
## fell out of this dot product, and it survived thirty years because it feels
## good.
func _accelerate(
		wish_direction: Vector3,
		wish_speed: float,
		rate: float,
		delta: float) -> void:
	var current := velocity.dot(wish_direction)
	var add := wish_speed - current
	if add <= 0.0:
		return
	velocity += wish_direction * minf(rate * wish_speed * delta, add)


## Friction scales horizontal velocity down, leaving its direction alone.
##
## Written as one scale factor rather than an early return, so the two lines
## that touch `velocity` are the last two and there is no path out of here with
## half the work done.
func _apply_friction(delta: float) -> void:
	var current := speed()
	var scale := 0.0
	if current >= 0.01:
		var drop := maxf(current, stop_speed) * friction * delta
		scale = maxf(current - drop, 0.0) / current
	velocity.x *= scale
	velocity.z *= scale


func _try_jump(on_floor: bool) -> bool:
	var can_jump := on_floor or _coyote_left > 0.0
	var wants_jump := (
			_buffer_left > 0.0
			or (auto_bhop_enabled and Input.is_action_pressed(&"jump"))
	)
	if not (can_jump and wants_jump):
		return false
	_takeoff_speed = speed()
	velocity.y = jump_velocity
	_coyote_left = 0.0
	_buffer_left = 0.0
	jumped.emit()
	return true


func _tick_timers(delta: float, on_floor: bool) -> void:
	_coyote_left = coyote_time if on_floor else _coyote_left - delta
	_buffer_left = (
			jump_buffer if Input.is_action_just_pressed(&"jump")
			else _buffer_left - delta
	)


func _respawn() -> void:
	global_transform = _spawn
	velocity = Vector3.ZERO
	peak_speed = 0.0
	_camera.rotation.x = 0.0


func _set_mouse_captured(captured: bool) -> void:
	Input.mouse_mode = (
			Input.MOUSE_MODE_CAPTURED if captured
			else Input.MOUSE_MODE_VISIBLE
	)
