class_name SplitBridge
extends AnimatableBody3D
## A BRIDGE THAT EXISTS IN ONE WORLD AND IS RAISED FROM THE OTHER.
##
## Seen only by its own world's camera and solid only on its own world's physics layer: a hero of
## the other world looks straight through it and falls straight through it. The switch that
## raises it lives in the OTHER world — so whoever pulls it sees nothing happen on their own half
## of the screen, and the only way to know it worked is to look across the divider.
##
## An `AnimatableBody3D` rather than a static body moved by hand: a hero standing on it while it
## moves is carried, instead of being left in the air or pushed through the deck.

@export var world := SplitDual.World.SCIFI
## How far below its working height the bridge waits, m. Deep enough to vanish into the fog.
@export_range(1.0, 30.0, 0.5) var depth := 9.0
## Seconds to rise or to sink all the way.
@export_range(0.1, 5.0, 0.05) var travel := 1.6
@export var raised := false

var _home := Vector3.ZERO
## Where the bridge is between down (0) and up (1).
var _height := 0.0

@onready var _scifi_look: Node3D = $ScifiLook
@onready var _fantasy_look: Node3D = $FantasyLook


func _ready() -> void:
	_home = position
	_height = 1.0 if raised else 0.0
	collision_layer = SplitDual.bits(world)
	collision_mask = 0
	_scifi_look.visible = world == SplitDual.World.SCIFI
	_fantasy_look.visible = world == SplitDual.World.FANTASY
	SplitDual.paint(self, SplitDual.bits(world))
	_place()


func _physics_process(delta: float) -> void:
	var goal := 1.0 if raised else 0.0
	if is_equal_approx(_height, goal):
		return
	_height = move_toward(_height, goal, delta / travel)
	_place()


func toggle() -> void:
	raised = not raised


func _place() -> void:
	position = _home + Vector3.DOWN * depth * (1.0 - smoothstep(0.0, 1.0, _height))
