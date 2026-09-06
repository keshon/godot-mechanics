class_name Director
extends Node3D
## Two ways to play the same world, and one camera between them.
##
## Probe 06 made you a hand above the map. Probes 01-03 made you a body inside
## it. This one is both, switchable, and the switch is the whole probe:
##
##   COMMAND    — high up, WASD pans the map, click selects, right-click orders
##   POSSESSED  — behind one unit, WASD drives it, mouse looks
##
## Three things had to be decided, and they are the same three every game with
## this feature decides:
##
## 1. What the camera does in between. Not a cut — a cut loses the player, who
##    has to work out where he ended up. A blend keeps the thread.
## 2. What the same keys mean in each mode. WASD pans in one and drives in the
##    other, and nothing announces the change except the picture.
## 3. What the rest of the world does while you are inside one of them. Here:
##    exactly what it was told to. Walk away from a marching column, possess a
##    straggler, and the column keeps marching.

enum Mode {COMMAND, POSSESSED}

@export var unit_scene: PackedScene
@export_range(1, 200, 1) var unit_count := 30

@export_group("Command view")
@export_range(5.0, 80.0, 1.0) var pan_speed := 24.0
@export var command_offset := Vector3(0.0, 26.0, 19.0)

@export_group("Possessed view")
@export var shoulder := Vector3(0.0, 2.3, 5.5)
@export_range(0.0005, 0.01, 0.0001) var mouse_sensitivity := 0.0025

@export_group("Transition")
## How long the camera takes to move between the two points of view.
##
## Zero is a cut, and a cut is genuinely worse: at 0.0 you arrive somewhere and
## have to work out where. Anything from 0.4 up and the eye follows the move
## and knows where it went. Try both.
@export_range(0.0, 2.0, 0.05) var blend_time := 0.55

@onready var _cam: Camera3D = $Camera
@onready var _units_root: Node3D = get_node(^"../World/Units")
@onready var _big: Label = get_node(^"../Ui/Hud/Big")
@onready var _detail: RichTextLabel = get_node(^"../Ui/Hud/Detail")

var mode: Mode = Mode.COMMAND
var selected: PossessUnit
var host: PossessUnit

var _pan := Vector3.ZERO
var _yaw := 0.0
var _pitch := -0.22
var _blend := 1.0
var _from := Transform3D.IDENTITY


func _ready() -> void:
	var side := int(ceil(sqrt(float(unit_count))))
	for i in unit_count:
		var u: PossessUnit = unit_scene.instantiate()
		_units_root.add_child(u)
		u.global_position = Vector3((i % side) * 2.4 - side * 1.2, 0.6,
			(i / side) * 2.4 - side * 1.2)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_cam.global_transform = _want()


func units() -> Array:
	return _units_root.get_children()


func busy() -> int:
	var n := 0
	for u in units():
		if u.has_order() and not u.possessed:
			n += 1
	return n


func _unhandled_input(event: InputEvent) -> void:
	if mode == Mode.POSSESSED and event is InputEventMouseMotion \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity,
			-deg_to_rad(50.0), deg_to_rad(25.0))
		return

	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		if key.keycode == KEY_E:
			_toggle()
		elif key.keycode == KEY_ESCAPE and mode == Mode.POSSESSED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mode == Mode.POSSESSED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		var u := _unit_at(mb.position)
		if selected:
			selected.selected = false
		selected = u
		if u:
			u.selected = true
	elif mb.button_index == MOUSE_BUTTON_RIGHT and selected:
		selected.order(_ground_at(mb.position))


## Getting in and out. Note what is NOT here: no camera code, no input
## remapping table, no state machine. Two flags and a blend start.
func _toggle() -> void:
	if mode == Mode.COMMAND:
		if selected == null:
			return
		host = selected
		host.possessed = true
		# Face the way it is already facing, so the view does not spin on entry.
		_yaw = host.get_node(^"Body").global_rotation.y
		mode = Mode.POSSESSED
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		# Leave the camera looking down at where you were standing, so you know
		# where you came out.
		_pan = host.global_position
		host.wish = Vector3.ZERO
		host.possessed = false
		host = null
		mode = Mode.COMMAND
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_from = _cam.global_transform
	_blend = 0.0


func _physics_process(delta: float) -> void:
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")

	if mode == Mode.POSSESSED and is_instance_valid(host):
		# The same two axes, read through the camera instead of the map.
		var f := -_cam.global_basis.z
		var r := _cam.global_basis.x
		f.y = 0.0
		r.y = 0.0
		host.wish = (r.normalized() * input.x + f.normalized() * -input.y).normalized() \
			if input != Vector2.ZERO else Vector3.ZERO
	else:
		_pan += (Vector3(input.x, 0.0, input.y)) * pan_speed * delta

	var want := _want()
	if _blend < 1.0:
		_blend = minf(_blend + delta / maxf(blend_time, 0.0001), 1.0)
		# interpolate_with lerps the position and SLERPS the rotation. Doing it
		# by hand on the two separately is the usual way to get a camera that
		# rolls halfway through a turn.
		_cam.global_transform = _from.interpolate_with(want, _ease(_blend))
	else:
		_cam.global_transform = want
	_hud()


func _hud() -> void:
	var possessed := mode == Mode.POSSESSED
	_big.text = "INSIDE" if possessed else "ABOVE"
	_detail.text = "
".join([
		"point of view    [color=#8ecbff]%s[/color]" % ("blending %.0f%%" % (_blend * 100.0)
			if _blend < 1.0 else "settled"),
		"",
		"WASD    %s" % ("[b]drives this unit[/b]" if possessed else "[b]pans the map[/b]"),
		"mouse   %s" % ("looks around" if possessed else "selects and orders"),
		"E       %s" % ("step back out" if possessed else "get inside the selected one"),
		"",
		"units    %d" % units().size(),
		"still carrying out orders    [b]%d[/b]" % busy(),
		"selected    %s" % ("yes" if selected else "[color=#7a7f88]none[/color]"),
	])


## Where the camera belongs right now, for whichever mode is running.
func _want() -> Transform3D:
	if mode == Mode.POSSESSED and is_instance_valid(host):
		var basis := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)
		return Transform3D(basis, host.global_position + basis * shoulder + Vector3.UP * 0.4)
	var eye := _pan + command_offset
	return Transform3D(Basis.looking_at(_pan + Vector3.UP * 0.5 - eye, Vector3.UP), eye)


func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


func _unit_at(screen: Vector2) -> PossessUnit:
	var from := _cam.project_ray_origin(screen)
	var q := PhysicsRayQueryParameters3D.create(from,
		from + _cam.project_ray_normal(screen) * 400.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.get("collider") as PossessUnit if not hit.is_empty() else null


func _ground_at(screen: Vector2) -> Vector3:
	var from := _cam.project_ray_origin(screen)
	var dir := _cam.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return _pan
	return from + dir * (-from.y / dir.y)
