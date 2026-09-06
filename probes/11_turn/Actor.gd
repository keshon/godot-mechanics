class_name TurnActor
extends Node3D

# One thing that takes turns.
#
# `cell` is the truth. `position` is only a picture of that truth, and it is always
# a little behind. No rule in this probe ever reads `position` — that separation is
# the whole reason a turn-based game can still feel quick.

@export var speed := 100
@export var color := Color.WHITE

var kind := ""
var cell := Vector2i.ZERO
var energy := 0
var acted := 0
var hits := 0

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _t := 1.0
var _time := 0.12
var _nudge := Vector3.ZERO

@onready var _mesh: MeshInstance3D = $Mesh


static func world_of(c: Vector2i) -> Vector3:
	return Vector3(float(c.x), 0.0, float(c.y))


func setup(k: String, spd: int, col: Color, at: Vector2i) -> void:
	kind = k
	speed = spd
	color = col
	cell = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.55
	_mesh.material_override = mat
	position = world_of(cell)
	_from = position
	_to = position
	_t = 1.0


func slide_to(c: Vector2i, seconds: float) -> void:
	_time = maxf(seconds, 0.0001)
	_from = position
	_to = world_of(c)
	_t = 0.0


func bump(step: Vector2i, seconds: float) -> void:
	# a shove is a turn too: lean into it and come back
	_time = maxf(seconds, 0.0001)
	_from = position
	_to = world_of(cell)
	_nudge = Vector3(float(step.x), 0.0, float(step.y)) * 0.4
	_t = 0.0


func settled() -> bool:
	return _t >= 1.0


func _process(delta: float) -> void:
	if _t >= 1.0 and _nudge == Vector3.ZERO:
		return
	_t = minf(_t + delta / _time, 1.0)
	var e := _t * _t * (3.0 - 2.0 * _t)
	position = _from.lerp(_to, e)
	if _nudge != Vector3.ZERO:
		position += _nudge * sin(_t * PI)
		if _t >= 1.0:
			_nudge = Vector3.ZERO
