class_name CommandField
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

## How far a drag has to travel, in pixels, before it counts as a box rather
## than a click.
const DRAG_THRESHOLD := 6.0
## How far the pick ray reaches, m.
const PICK_RANGE := 500.0

@export var unit_scene: PackedScene
@export_range(1, 2000, 1) var unit_count := 40
@export var units_parent: NodePath = ^"../World/Units"

@export_group("Camera")
## How fast the view pans, m/s at the default height.
@export_range(5.0, 80.0, 1.0) var pan_speed := 26.0
## How high the camera sits above the ground, m.
@export_range(6.0, 60.0, 0.5) var height := 22.0
@export_range(4.0, 80.0, 1.0) var min_height := 8.0
@export_range(4.0, 120.0, 1.0) var max_height := 60.0

## Where the drag started, in screen pixels. Read by the HUD to draw the box.
var drag_from := Vector2.ZERO
var dragging := false
var selected: Array[CommandUnit] = []

## Ticks up on every fresh order. Everything told to move by one click carries
## the same number, which is what lets the HUD draw one thread instead of two
## thousand.
var _next_order := 0

@onready var _camera: Camera3D = $CamPivot/Camera3D
@onready var _pivot: Node3D = $CamPivot
@onready var _units_root: Node3D = get_node(units_parent)


func _ready() -> void:
	var side := int(ceil(sqrt(float(unit_count))))
	for i in unit_count:
		var unit: CommandUnit = unit_scene.instantiate()
		_units_root.add_child(unit)
		unit.global_position = Vector3(
				(i % side) * 2.2 - side * 1.1,
				0.0,
				(i / side) * 2.2 - side * 1.1)
	_apply_height()


func _process(delta: float) -> void:
	var move: Vector2 = Input.get_vector(
			&"move_left", &"move_right", &"move_forward", &"move_back")
	# The camera pans on the ground plane whatever its pitch, so the pan uses a
	# flattened basis. Skip that and panning would drive you into the floor.
	var forward := -_pivot.global_basis.z
	var right := _pivot.global_basis.x
	forward.y = 0.0
	right.y = 0.0
	_pivot.global_position += (
			(right.normalized() * move.x + forward.normalized() * -move.y)
			* pan_speed * delta * (height / 22.0)
	)


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

	var button := event as InputEventMouseButton
	if button == null:
		return
	if button.button_index == MOUSE_BUTTON_WHEEL_UP:
		height = clampf(height / 1.12, min_height, max_height)
		_apply_height()
	elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		height = clampf(height * 1.12, min_height, max_height)
		_apply_height()
	elif button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			drag_from = button.position
			dragging = true
		else:
			dragging = false
			_finish_select(drag_from, button.position, button.shift_pressed)
	elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
		var at := _ground_at(button.position)
		if not button.shift_pressed:
			_next_order += 1
		for unit in selected:
			unit.order(at, button.shift_pressed, _next_order)


func units() -> Array:
	return _units_root.get_children()


## The camera the field looks through. Handed out rather than found: the HUD
## needs it to project world points onto the screen, and the alternative is the
## HUD knowing this node's internal layout by path.
func camera() -> Camera3D:
	return _camera


## A place on the ground under the cursor.
##
## No physics, no collider, no raycast. The ground is the plane y = 0, and
## where a line crosses a plane is four lines of arithmetic. Worth knowing
## before reaching for the physics server: half the picking a strategy game
## does is against a flat world, and a flat world needs no collision at all.
func _ground_at(screen: Vector2) -> Vector3:
	var from := _camera.project_ray_origin(screen)
	var direction := _camera.project_ray_normal(screen)
	if absf(direction.y) < 0.0001:
		return Vector3.ZERO
	return from + direction * (-from.y / direction.y)


## The unit under the cursor, if any.
##
## THIS one wants a raycast, because "what is under this pixel" is exactly the
## question a ray answers, and it answers it with the nearest hit, which is
## what you want when things overlap.
func _unit_at(screen: Vector2) -> CommandUnit:
	var from := _camera.project_ray_origin(screen)
	var to := from + _camera.project_ray_normal(screen) * PICK_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider: Object = hit.collider
	return collider as CommandUnit


## Everything inside a screen rectangle.
##
## And here the ray is useless: a rectangle is not a line. So the projection is
## run the other way — every unit's world position is turned INTO a pixel, and
## the pixel is tested against the box. One ray for one thing, one projection
## per thing for many things. Same camera, opposite directions.
func _finish_select(from: Vector2, to: Vector2, keep_existing: bool) -> void:
	if not keep_existing:
		for unit in selected:
			unit.selected = false
		selected.clear()

	var box := Rect2(from, to - from).abs()
	if box.size.length() < DRAG_THRESHOLD:
		# Barely moved: treat it as a click, not a drag.
		var one := _unit_at(to)
		if one and not selected.has(one):
			one.selected = true
			selected.append(one)
	else:
		for unit in units():
			if selected.has(unit) or _camera.is_position_behind(unit.global_position):
				continue
			if box.has_point(_camera.unproject_position(unit.global_position)):
				unit.selected = true
				selected.append(unit)


func _apply_height() -> void:
	_camera.position = Vector3(0.0, height, height * 0.72)
	_camera.look_at(_pivot.global_position, Vector3.UP)
