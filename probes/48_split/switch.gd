class_name SplitSwitch
extends StaticBody3D
## A LEVER THAT EXISTS IN ONE WORLD AND DOES ITS WORK IN THE OTHER.
##
## It says nothing about what it moves: the scene wires `used` to whatever should answer, and the
## answer is always across the divider. Only a hero of the same world can see it, bump into it or
## reach it.

signal used

@export var world := SplitDual.World.SCIFI
## What the readout calls it.
@export var title := "пульт"
## How close a hero's feet have to be, m.
@export_range(0.5, 5.0, 0.1) var reach := 2.2

var on := false

var _glow: StandardMaterial3D

@onready var _scifi_look: Node3D = $ScifiLook
@onready var _fantasy_look: Node3D = $FantasyLook


func _ready() -> void:
	add_to_group(&"split_switch")
	collision_layer = SplitDual.bits(world)
	collision_mask = 0
	var look := _scifi_look if world == SplitDual.World.SCIFI else _fantasy_look
	_scifi_look.visible = look == _scifi_look
	_fantasy_look.visible = look == _fantasy_look
	SplitDual.paint(self, SplitDual.bits(world))
	# DUPLICATED, because a material in a scene is one resource for every instance of it: dimming
	# this switch's glow would dim every other switch built from the same scene.
	var glow: MeshInstance3D = look.get_node("Glow")
	_glow = glow.material_override.duplicate()
	glow.material_override = _glow
	_light()


func can_reach(hero: SplitHero) -> bool:
	return hero.world == world and hero.global_position.distance_to(global_position) <= reach


func use() -> void:
	on = not on
	_light()
	used.emit()


func _light() -> void:
	_glow.emission_energy_multiplier = 4.0 if on else 0.7
