class_name DuoSpark
extends Area3D
## A CHARGE FOR THE BUILDER, lying where only the runner can go.
##
## The other half of the dependency: the builder's clicks are paid for with sparks, and sparks are
## picked up by walking into them. Who takes it does not matter to the spark — it reports the take
## and lets the rig decide what a charge is worth.

signal taken

## Seconds before a taken spark lights up again.
@export_range(1.0, 60.0, 0.5) var regrow := 10.0

var ready_in := 0.0

@onready var _gem: Node3D = $Gem


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_gem.rotate_y(delta * 1.8)
	if ready_in <= 0.0:
		return
	ready_in -= delta
	if ready_in <= 0.0:
		_gem.visible = true


func reset() -> void:
	ready_in = 0.0
	_gem.visible = true


func _on_body_entered(body: Node3D) -> void:
	if ready_in > 0.0 or not body.is_in_group(&"duo_runner"):
		return
	ready_in = regrow
	_gem.visible = false
	taken.emit()
