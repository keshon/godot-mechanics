class_name AnimationProbePlayer
extends CharacterBody3D
## The controller owns motion and interruption rules; imported clips pose the skinned model.

## Tuned reference speeds, independent of the controller's adjustable speed limits.
const WALK_CLIP_SPEED := 2.5
const RUN_CLIP_SPEED := 6.0

@export var run_speed := 6.0
@export var walk_speed := 2.5
@export var turn_speed := 14.0
@export var blend_time := 0.12
@export var match_stride := true
## Semantic states map to native imported names. Reimporting the GLB does not rewrite this mapping.
@export var clips: Dictionary[StringName, StringName] = {
	&"idle": &"Idle", &"walk": &"Walk", &"run": &"Sprint", &"turn": &"Walk",
	&"takeoff": &"Jump_Start", &"rise": &"Jump", &"fall": &"Jump",
	&"land": &"Jump_Land", &"action": &"Interact",
}
var wish := Vector3.ZERO
var walking := false
var jump_pressed := false
var action_pressed := false
var turn_input := 0.0
var state: StringName = &"idle"
var interruptions: int = 0
var landings: int = 0
var ground_speed := 0.0
var _facing := 0.0
var _action := 0.0
var _landing := 0.0
var _takeoff := 0.0
var _previous := Transform3D.IDENTITY
var _current := Transform3D.IDENTITY
@onready var visual: Node3D = $Visual
@onready var animation: AnimationPlayer = $Visual/Model/Character/AnimationPlayer


func _ready() -> void:
	visual.top_level = true
	process_priority = -10
	reset_at(global_position)


func _process(_delta: float) -> void:
	visual.global_transform = _previous.interpolate_with(
			_current, Engine.get_physics_interpolation_fraction())
	var clip: StringName = clips[state]
	if animation.current_animation != clip:
		animation.play(clip, blend_time)
	var reference: float = WALK_CLIP_SPEED if state == &"walk" else RUN_CLIP_SPEED
	animation.speed_scale = clampf(ground_speed / reference, 0.25, 1.5) if (
			match_stride and state in [&"walk", &"run"]) else 1.0
	# Long authored anticipation/recovery clips must not delay collision response.
	if state in [&"takeoff", &"land"]:
		var window: float = 0.16 if state == &"takeoff" else 0.25
		animation.speed_scale = animation.get_animation(clip).length / window


func _physics_process(delta: float) -> void:
	_previous = _current
	var grounded: bool = is_on_floor()
	_action = maxf(_action - delta, 0.0)
	_landing = maxf(_landing - delta, 0.0)
	_takeoff = maxf(_takeoff - delta, 0.0)
	if action_pressed and grounded:
		_action = animation.get_animation(clips[&"action"]).length
	if wish.length_squared() > 0.01 or jump_pressed or absf(turn_input) > 0.1:
		if _action > 0.0:
			interruptions += 1
		_action = 0.0
		_landing = 0.0
	var speed: float = walk_speed if walking else run_speed
	var planar := Vector3(velocity.x, 0, velocity.z)
	planar = planar.move_toward(wish.limit_length() * speed, 35.0 * delta)
	velocity.x = planar.x
	velocity.z = planar.z
	velocity.y -= 24.0 * delta
	if jump_pressed and grounded:
		velocity.y = 8.0
		_takeoff = 0.16
	move_and_slide()
	ground_speed = Vector2(get_real_velocity().x, get_real_velocity().z).length()
	if is_on_floor() and not grounded:
		landings += 1
		_landing = 0.25
	if planar.length_squared() > 0.1:
		_facing = lerp_angle(_facing, atan2(-planar.x, -planar.z),
				1.0 - exp(-turn_speed * delta))
	else:
		_facing += turn_input * 2.5 * delta
	if not is_on_floor():
		state = &"takeoff" if _takeoff > 0.0 else (&"rise" if velocity.y > 0 else &"fall")
	elif _action > 0.0:
		state = &"action"
	elif ground_speed > 0.15:
		state = &"walk" if ground_speed < 3.2 else &"run"
	elif absf(turn_input) > 0.1:
		state = &"turn"
	elif _landing > 0.0:
		state = &"land"
	else:
		state = &"idle"
	_current = Transform3D(Basis(Vector3.UP, _facing), global_position)
	if position.y < -5:
		reset_at(Vector3(0, 0.05, 4))
	jump_pressed = false
	action_pressed = false


func reset_at(point: Vector3) -> void:
	global_position = point
	velocity = Vector3.ZERO
	wish = Vector3.ZERO
	_action = 0.0
	_landing = 0.0
	_takeoff = 0.0
	jump_pressed = false
	action_pressed = false
	state = &"idle"
	move_and_slide()
	_current = Transform3D(Basis(Vector3.UP, _facing), global_position)
	_previous = _current
	visual.global_transform = _current
	animation.play(clips[&"idle"], 0.0)
	animation.advance(0.0)
