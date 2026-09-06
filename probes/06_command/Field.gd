class_name Field
extends Node3D
## The commander. For the first time in this project the player is not a body
## standing somewhere — he is a hand above the world, and everything about the
## input changes because of it.
##
## Three things live here, and none of them existed in probes 01 to 05:
##
## 1. Turning a mouse position into a place in the world. Two different ways,
##    because the two jobs want different tools — see _ground_at and _unit_at.
## 2. Selecting many things at once, which is the projection run backwards.
## 3. Stopping time without stopping the game.
##
## This node's process_mode is ALWAYS, set in the scene. That is why the camera
## still pans and orders still register while the world is frozen. The units
## live under World, which is left on the default, so they stop. The pause is
## not a variable anyone checks; it is a property of the tree.

@export var unit_scene: PackedScene
@export_range(1, 2000, 1) var unit_count := 40
@export var units_parent: NodePath = ^"../World/Units"

@export_group("Camera")
@export_range(5.0, 80.0, 1.0) var pan_speed := 26.0
@export_range(6.0, 60.0, 0.5) var height := 22.0
@export_range(4.0, 80.0, 1.0) var min_height := 8.0
@export_range(4.0, 120.0, 1.0) var max_height := 60.0

@onready var _cam: Camera3D = $CamPivot/Camera3D
@onready var _pivot: Node3D = $CamPivot
@onready var _units_root: Node3D = get_node(units_parent)

## Where the drag started, in screen pixels. Read by the HUD to draw the box.
var drag_from := Vector2.ZERO
var dragging := false
var selected: Array[Unit] = []
## Ticks up on every fresh order. Everything told to move by one click carries
## the same number, which is what lets the HUD draw one thread instead of two
## thousand.
var _next_order := 0


func _ready() -> void:
	var side := int(ceil(sqrt(float(unit_count))))
	for i in unit_count:
		var u: Unit = unit_scene.instantiate()
		_units_root.add_child(u)
		u.global_position = Vector3(
			(i % side) * 2.2 - side * 1.1, 0.0, (i / side) * 2.2 - side * 1.1)
	_apply_height()


func units() -> Array:
	return _units_root.get_children()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		match key.keycode:
			KEY_SPACE:
				# One flag, whole tree. Everything under World stops; this node
				# and the HUD carry on because their process_mode says ALWAYS.
				get_tree().paused = not get_tree().paused
			KEY_1: Engine.time_scale = 1.0
			KEY_2: Engine.time_scale = 2.0
			KEY_3: Engine.time_scale = 4.0
		return

	var mb := event as InputEventMouseButton
	if mb == null:
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		height = clampf(height / 1.12, min_height, max_height)
		_apply_height()
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		height = clampf(height * 1.12, min_height, max_height)
		_apply_height()
	elif mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			drag_from = mb.position
			dragging = true
		else:
			dragging = false
			_finish_select(drag_from, mb.position, mb.shift_pressed)
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		var at := _ground_at(mb.position)
		if not mb.shift_pressed:
			_next_order += 1
		for u in selected:
			u.order(at, mb.shift_pressed, _next_order)


func _process(delta: float) -> void:
	var move := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	# The camera pans on the ground plane whatever its pitch, so the pan uses a
	# flattened basis. Skip that and panning would drive you into the floor.
	var f := -_pivot.global_basis.z
	var r := _pivot.global_basis.x
	f.y = 0.0
	r.y = 0.0
	_pivot.global_position += (r.normalized() * move.x + f.normalized() * -move.y) \
		* pan_speed * delta * (height / 22.0)


## A place on the ground under the cursor.
##
## No physics, no collider, no raycast. The ground is the plane y = 0, and
## where a line crosses a plane is four lines of arithmetic. Worth knowing
## before reaching for the physics server: half the picking a strategy game
## does is against a flat world, and a flat world needs no collision at all.
func _ground_at(screen: Vector2) -> Vector3:
	var from := _cam.project_ray_origin(screen)
	var dir := _cam.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return Vector3.ZERO
	return from + dir * (-from.y / dir.y)


## The unit under the cursor, if any.
##
## THIS one wants a raycast, because "what is under this pixel" is exactly the
## question a ray answers, and it answers it with the nearest hit, which is
## what you want when things overlap.
func _unit_at(screen: Vector2) -> Unit:
	var from := _cam.project_ray_origin(screen)
	var q := PhysicsRayQueryParameters3D.create(from, from + _cam.project_ray_normal(screen) * 500.0)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.get("collider") as Unit if not hit.is_empty() else null


## Everything inside a screen rectangle.
##
## And here the ray is useless: a rectangle is not a line. So the projection is
## run the other way — every unit's world position is turned INTO a pixel, and
## the pixel is tested against the box. One ray for one thing, one projection
## per thing for many things. Same camera, opposite directions.
func _finish_select(a: Vector2, b: Vector2, add: bool) -> void:
	if not add:
		for u in selected:
			u.selected = false
		selected.clear()

	var box := Rect2(a, b - a).abs()
	if box.size.length() < 6.0:
		# Barely moved: treat it as a click, not a drag.
		var one := _unit_at(b)
		if one and not selected.has(one):
			one.selected = true
			selected.append(one)
		return

	for u in units():
		if selected.has(u) or _cam.is_position_behind(u.global_position):
			continue
		if box.has_point(_cam.unproject_position(u.global_position)):
			u.selected = true
			selected.append(u)


func _apply_height() -> void:
	_cam.position = Vector3(0.0, height, height * 0.72)
	_cam.look_at(_pivot.global_position, Vector3.UP)
