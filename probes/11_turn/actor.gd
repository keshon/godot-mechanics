class_name TurnActor
extends Node3D
## One thing that takes turns.
##
## `cell` is the truth. `position` is only a picture of that truth, and it is
## always a little behind. No rule in this probe ever reads `position` — that
## separation is the whole reason a turn-based game can still feel quick.

## What it is called on the readout: you, fast, normal, slow.
var kind := ""
## Energy gained every tick. At a cost of 100 per action, 200 acts twice a tick
## and 50 once every second tick. Called speed because that is the roguelike
## word for it, not because it is metres per second.
var speed := 100
var tint := Color.WHITE
## Where it actually is. The rules read this and nothing else.
var cell := Vector2i.ZERO
var energy := 0
var acted := 0
var hits := 0

var _from := Vector3.ZERO
var _to := Vector3.ZERO
## 0 at the start of the slide, 1 when the picture has caught up.
var _blend := 1.0
var _duration := 0.12
var _nudge := Vector3.ZERO

@onready var _mesh: MeshInstance3D = $Mesh


## Where a cell sits in the world. The one place the two coordinate systems meet.
static func world_of(at: Vector2i) -> Vector3:
	return Vector3(float(at.x), 0.0, float(at.y))


func _process(delta: float) -> void:
	if _blend >= 1.0 and _nudge == Vector3.ZERO:
		return
	_blend = minf(_blend + delta / _duration, 1.0)
	position = _from.lerp(_to, smoothstep(0.0, 1.0, _blend))
	if _nudge != Vector3.ZERO:
		position += _nudge * sin(_blend * PI)
		if _blend >= 1.0:
			_nudge = Vector3.ZERO


func setup(kind_name: String, tick_energy: int, colour: Color, at: Vector2i) -> void:
	kind = kind_name
	speed = tick_energy
	tint = colour
	cell = at
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.55
	_mesh.material_override = material
	position = world_of(cell)
	_from = position
	_to = position
	_blend = 1.0


func slide_to(at: Vector2i, seconds: float) -> void:
	_duration = maxf(seconds, 0.0001)
	_from = position
	_to = world_of(at)
	_blend = 0.0


## A shove is a turn too: lean into it and come back.
func bump(step: Vector2i, seconds: float) -> void:
	_duration = maxf(seconds, 0.0001)
	_from = position
	_to = world_of(cell)
	_nudge = Vector3(float(step.x), 0.0, float(step.y)) * 0.4
	_blend = 0.0


func is_settled() -> bool:
	return _blend >= 1.0
