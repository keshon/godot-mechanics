class_name DataDef
extends Resource
## A definition. One .tres file each, and the folder is the game's content.
##
## Note that a sword and a werewolf are the SAME type here. Both are a title, some
## numbers and a list of effects. The resolver in bench.gd never asks which is
## which beyond `kind`, and it never asks for a name.

enum Kind {
	ITEM,
	FOE,
}

@export var title := ""
@export var kind: Kind = Kind.ITEM
@export var colour := Color.WHITE

@export_group("Foe only")
## Hit points. Only read for a FOE.
@export var hp := 0.0
## Flat damage taken off every blow, after every multiplier.
@export var armour := 0.0

@export_group("Both")
## The effects this definition carries.
@export var effects: Array[DataEffect] = []
