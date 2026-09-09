class_name DataEffect
extends Resource
## One thing a definition does. Four verbs, and that is the closed set — the
## whole probe rests on it staying closed.
##
##   ADD   stat += amount
##   MUL   stat *= amount        (always after every ADD, never interleaved)
##   TAG   whoever holds this swings with `tag` on the blow
##   VULN  whoever holds this takes x amount from blows carrying `tag`
##
## A new ITEM costs nothing. A new VERB costs about fifteen lines, once. Real
## games have thousands of the first and dozens of the second.

enum Verb {
	ADD,
	MUL,
	TAG,
	VULN,
}

@export var verb: Verb = Verb.ADD
## Which number the verb touches. Only "power" is read today; the string is here
## so a second stat costs no code in this file.
@export var stat := "power"
## The word ADD/MUL ignore, TAG stamps onto a blow and VULN reacts to.
@export var tag := ""
@export var amount := 0.0
