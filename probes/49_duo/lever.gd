class_name DuoLever
extends Area3D
## A LEVER ON THE FAR SIDE OF A PIT, pulled by walking into it — and only a swinger ever gets there
## first, because the other side has no way across until the lever is pulled.
##
## It is told nothing about the bridge it lowers: the scene wires `pulled` to it.

signal pulled

var down := false

@onready var _handle: Node3D = $Handle


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	reset()


func reset() -> void:
	down = false
	_handle.rotation.z = deg_to_rad(35.0)


func _on_body_entered(body: Node3D) -> void:
	if down or not body.is_in_group(&"duo_swinger"):
		return
	down = true
	_handle.rotation.z = deg_to_rad(-35.0)
	pulled.emit()
