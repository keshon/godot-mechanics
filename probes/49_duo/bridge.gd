class_name DuoBridge
extends AnimatableBody3D
## A FOLDING BRIDGE hinged at the far edge of a pit: hanging down into it, it is nothing; swung up
## level, it is the way across for the one who cannot swing.
##
## It folds DOWN rather than standing up. A deck standing on the far edge would be a wall across the
## very air the swinger has to fly through; hanging below the edge it is out of everyone's way.
##
## THE BODY ITSELF IS THE HINGE AND TURNS; the deck's shape and mesh are laid out towards the near
## side inside it. A hinge node turning an `AnimatableBody3D` child does not work: measured, the
## child's body stays in the physics server where it was created and writes that back over its own
## node every tick — the deck is drawn standing up and walked on lying flat.

## Seconds from hanging to level.
@export_range(0.1, 5.0, 0.05) var travel := 1.2

var laid := false

## 0 hanging, 1 level.
var _open := 0.0


func _ready() -> void:
	_place()


func _physics_process(delta: float) -> void:
	var goal := 1.0 if laid else 0.0
	if is_equal_approx(_open, goal):
		return
	_open = move_toward(_open, goal, delta / travel)
	_place()


func lay() -> void:
	laid = true


func fold() -> void:
	laid = false


func _place() -> void:
	# The deck lies towards −X of the hinge. Turned +90° about Z it hangs straight down.
	rotation.z = deg_to_rad(90.0) * (1.0 - smoothstep(0.0, 1.0, _open))
