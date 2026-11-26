class_name MovingProbePlatform
extends AnimatableBody3D
## Authoritative physics motion with a separately interpolated visible deck.

enum Motion {
	SHUTTLE,
	ROTOR,
	LIFT,
	DROP,
}
@export var motion: Motion = Motion.SHUTTLE
@export var rate := 1.0
@export var running := true
@export var shuttle_distance := 1.5
var clock := 0.0
var triggered := false
var _drop_clock := 0.0
var _home := Transform3D.IDENTITY
var _previous := Transform3D.IDENTITY
var _current := Transform3D.IDENTITY
@onready var visual: Node3D = $Visual


func _ready() -> void:
	process_physics_priority = -20
	process_priority = -20
	_home = transform
	_previous = global_transform
	_current = global_transform
	visual.top_level = true
	visual.global_transform = _current


func _physics_process(delta: float) -> void:
	_previous = _current
	if not running:
		return
	clock += delta * rate
	var pose: Transform3D = _home
	match motion:
		Motion.SHUTTLE:
			pose.origin.x += sin(clock * 0.8) * shuttle_distance
		Motion.ROTOR:
			pose.basis = _home.basis * Basis(Vector3.UP, clock * 0.6)
		Motion.LIFT:
			pose.origin.y += sin(clock) * 1.5
		Motion.DROP:
			if triggered:
				_drop_clock += delta
				var fall: float = maxf(_drop_clock - 0.6, 0.0)
				pose.origin.y -= minf(6.0 * fall * fall, 12.0)
	transform = pose
	_current = global_transform


func _process(_delta: float) -> void:
	visual.global_transform = _previous.interpolate_with(
			_current, Engine.get_physics_interpolation_fraction())


func trigger() -> void:
	if motion == Motion.DROP:
		triggered = true


func reset_motion() -> void:
	clock = 0.0
	_drop_clock = 0.0
	triggered = false
	transform = _home
	_current = global_transform
	_previous = _current
	visual.global_transform = _current
