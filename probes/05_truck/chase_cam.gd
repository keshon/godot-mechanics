class_name TruckChaseCam
extends Camera3D
## Two views, and the second one is the point.
##
## CHASE sits behind the truck and is how you drive. SIDE tracks it dead
## abeam, level, at a fixed distance — which is the only way to actually SEE a
## suspension work. From behind, a wheel rising 40 cm looks like nothing. From
## the side it is unmistakable, and on a six-by-six you get to watch three
## axles take the same bump one after another.
##
## Press C.

enum View {
	CHASE,
	SIDE,
}

@export var target_path: NodePath = ^"../Truck"
@export var view: View = View.CHASE

@export_group("Chase")
## Where the camera sits relative to the truck, in the TRUCK's frame, m.
@export var chase_offset := Vector3(0.0, 3.2, 9.0)
## How fast it catches up, per second. Higher is stiffer.
@export_range(1.0, 30.0, 0.5) var chase_damp := 5.0

@export_group("Side")
## Where the camera sits relative to the truck, in the WORLD frame, m.
@export var side_offset := Vector3(11.0, 1.4, 0.0)
@export_range(1.0, 30.0, 0.5) var side_damp := 9.0

@onready var _target: Node3D = get_node(target_path)


func _physics_process(delta: float) -> void:
	var want := Vector3.ZERO
	var look := _target.global_position
	var damping := chase_damp
	if view == View.CHASE:
		# Behind the truck in ITS frame, so the camera swings round with it.
		want = _target.global_position + _target.global_basis * chase_offset
	else:
		# Beside it in the WORLD frame: the camera must not roll or pitch with
		# the truck, or the suspension travel would be hidden by the very
		# body movement you are trying to watch.
		want = _target.global_position + side_offset
		look = _target.global_position + Vector3(0.0, 0.4, 0.0)
		damping = side_damp
	global_position = want + (global_position - want) * exp(-damping * delta)
	look_at(look, Vector3.UP)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_C:
		view = View.SIDE if view == View.CHASE else View.CHASE
