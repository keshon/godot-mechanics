class_name ShoulderTarget
extends Node3D
## THE THING BEING SHOT AT.
##
## Drives a straight line across the front at a fixed speed, because the question here is
## about the shooter and not about the driver. What it contributes is exactly one quantity:
## how far it moves while the round is in the air.
##
## That quantity is the whole difference between the two rounds. Against something standing
## still both hit and there is nothing to measure.

@export_range(0.0, 40.0, 0.5) var speed := 11.0
## How far it runs, in metres, before turning back. Kept short so the shot happens across the
## front and not away down the range.
@export_range(20.0, 400.0, 5.0) var run := 200.0
## What it looks like whole and what it looks like hit. A shot that lands and changes nothing
## on screen is a shot the eye has to take on trust from a line of text.
@export var calm: Material
@export var struck: Material
## Seconds a wreck stays red.
@export_range(0.2, 8.0, 0.1) var burn := 3.0

var velocity := Vector3.ZERO
var hit := false

var _home := Vector3.ZERO
## Which way along the run it is going: +1 or -1.
var _way := 1.0
var _burn_left := 0.0

@onready var _hull: Node3D = $Hull
@onready var _centre: Node3D = $Centre


func _ready() -> void:
	_home = position


func _physics_process(delta: float) -> void:
	if _burn_left > 0.0:
		_burn_left -= delta
		if _burn_left <= 0.0:
			_paint(calm)
	if hit or speed <= 0.0:
		velocity = Vector3.ZERO
		return
	velocity = global_basis.x * speed * _way
	position += (Vector3.RIGHT * speed * _way) * delta
	if absf(position.x - _home.x) > run * 0.5:
		_way = -_way
	if _hull != null:
		_hull.rotation.y = 0.0 if _way > 0.0 else PI


## WHAT IS AIMED AT AND WHAT IS SCORED AGAINST — the middle of the hull, not the patch of
## ground the node stands on. Aiming at the origin points the beam INTO the dirt: the round
## rides it down, grazes in short, and a shot that went through the side of the vehicle is
## already booked as a metre of miss before anything else has gone wrong.
func centre() -> Vector3:
	return _centre.global_position


## Moved to a new stand. The patrol runs from wherever it is PUT, so the range dial can walk the
## target down the field without it snapping back to where the scene left it on the next reset.
func place(where: Vector3) -> void:
	_home = where
	reset()


func reset() -> void:
	position = _home
	_way = 1.0
	hit = false
	_burn_left = 0.0
	_paint(calm)
	velocity = Vector3.ZERO
	if _hull != null:
		_hull.rotation.y = 0.0


## Struck. Stops where it stands and goes red for a few seconds: a wreck is a landmark, and
## the colour is the only thing that tells the eye the shot landed.
func wreck() -> void:
	hit = true
	velocity = Vector3.ZERO
	_burn_left = burn
	_paint(struck)


func _paint(what: Material) -> void:
	if _hull == null:
		return
	for child in _hull.get_children():
		var visual := child as MeshInstance3D
		if visual != null:
			visual.material_override = what
