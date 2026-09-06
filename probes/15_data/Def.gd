class_name DataDef
extends Resource

# A definition. One .tres file each, and the folder is the game's content.
#
# Note that a sword and a werewolf are the SAME type here. Both are a title, some
# numbers and a list of effects. The resolver in Bench.gd never asks which is which
# beyond `kind`, and it never asks for a name.

enum Kind { ITEM, FOE }

@export var title := ""
@export var kind: Kind = Kind.ITEM
@export var colour := Color.WHITE

@export_group("Foe only")
@export var hp := 0.0
@export var armour := 0.0

@export_group("Both")
@export var effects: Array[Resource] = []
