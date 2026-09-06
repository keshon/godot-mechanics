class_name DataEffect
extends Resource

# One thing a definition does. Four verbs, and that is the closed set — the whole
# probe rests on it staying closed.
#
#   ADD   stat += amount
#   MUL   stat *= amount        (always after every ADD, never interleaved)
#   TAG   whoever holds this swings with `tag` on the blow
#   VULN  whoever holds this takes x amount from blows carrying `tag`
#
# A new ITEM costs nothing. A new VERB costs about fifteen lines, once. Real games
# have thousands of the first and dozens of the second.

enum Verb { ADD, MUL, TAG, VULN }

@export var verb: Verb = Verb.ADD
@export var stat := "power"
@export var tag := ""
@export var amount := 0.0
