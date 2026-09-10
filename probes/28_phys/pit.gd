class_name PhysPit
extends Node3D
## 28 — bodies, joints, and the three questions you only ask once you have them.
##
##   СТОИТ ЛИ?     a tower is the classic quality test of a solver. Nothing pushes it,
##                 so any movement at all is error accumulating.
##   СПИТ ЛИ?      a body at rest should cost nothing. Sleeping is the single biggest
##                 lever in a physics scene, the same shape as UPDATE_ONCE in probe 25.
##   ОДИНАКОВО ЛИ? run the same thing twice from the same state. Rule 4 says tests come
##                 back for the deterministic step, so this is the probe that finds out
##                 whether there IS one.
##
## Bodies are real RigidBody3D nodes, not a homegrown integrator: rule 5. What the engine
## does not promise is exactly what gets measured.

enum Scene {
	TOWER,
	RAIN,
	BRIDGE,
}

const SCENES := ["башня", "ливень", "мост"]

@export_range(0, 2) var kind := 0
@export var bodies := 240
@export var sleeping := true

var check := PhysCheck.new()
## Smoothed physics step, milliseconds.
var physics_ms := 0.0
var awake := 0
var engine_name := ""

var _boxes: Array[RigidBody3D] = []
## Everything spawned, joints and anchors included, so a rebuild can take it all away.
var _spawned: Array[Node] = []
var _yaw := 0.5
var _pitch := -0.35
var _distance := 34.0
var _looking := false
var _mesh := BoxMesh.new()
var _material := StandardMaterial3D.new()

@onready var _camera: Camera3D = $Camera
@onready var _info: RichTextLabel = $Ui/Info


func _ready() -> void:
	engine_name = str(
			ProjectSettings.get_setting("physics/3d/physics_engine", "DEFAULT"))
	_mesh.size = Vector3.ONE
	_material.albedo_color = Color(0.72, 0.6, 0.42)
	_material.roughness = 0.85
	_build()


func _process(_delta: float) -> void:
	physics_ms = lerpf(
			physics_ms,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			0.08)
	var forward := Vector3(
			sin(_yaw) * cos(_pitch),
			sin(_pitch),
			cos(_yaw) * cos(_pitch))
	_camera.global_position = -forward * _distance + Vector3(0.0, 6.0, 0.0)
	_camera.look_at(Vector3(0.0, 5.0, 0.0))
	_draw_hud()


func _physics_process(_delta: float) -> void:
	awake = 0
	for body in _boxes:
		if not body.sleeping:
			awake += 1
	check.tick(_boxes)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_looking = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(_distance - 2.0, 8.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(_distance + 2.0, 90.0)
		return
	if event is InputEventMouseMotion and _looking:
		_yaw -= event.relative.x * 0.005
		_pitch = clampf(_pitch - event.relative.y * 0.005, -1.4, 0.5)
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_1, KEY_2, KEY_3:
			kind = event.keycode - KEY_1
			_build()
		KEY_Z:
			bodies = 60
			_build()
		KEY_X:
			bodies = 240
			_build()
		KEY_C:
			bodies = 600
			_build()
		KEY_V:
			sleeping = not sleeping
			for body in _boxes:
				body.can_sleep = sleeping
				if not sleeping:
					body.sleeping = false
		KEY_G:
			# Честный повтор: сцена собирается заново.
			check.start(true, _build)
		KEY_H:
			# Дешёвый: вернуть тела на места.
			check.start(false)
		KEY_R:
			_build()


## Everything spawned is remembered and taken away again — joints and anchors included.
## The first version freed only the bodies, so every rebuild left its joints behind and
## the bridge quietly accumulated dead constraints.
##
## And remove_child BEFORE queue_free: queue_free only takes the node away at the end of
## the frame, so the old pile is still in the physics world while the new one spawns
## inside it. One frame of ghosts is enough to make two runs differ.
func _build() -> void:
	for node in _spawned:
		remove_child(node)
		node.queue_free()
	_spawned.clear()
	_boxes.clear()
	check.reset()
	match kind:
		Scene.TOWER:
			_tower()
		Scene.RAIN:
			_rain()
		Scene.BRIDGE:
			_bridge()


func _add_box(at: Vector3, size := Vector3.ONE, mass := 1.0) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.mass = mass
	body.can_sleep = sleeping
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	var visual := MeshInstance3D.new()
	visual.mesh = _mesh
	visual.scale = size
	visual.material_override = _material
	body.add_child(visual)
	add_child(body)
	body.global_position = at
	_boxes.append(body)
	_spawned.append(body)
	return body


## A tower nobody touches. Every millimetre it moves is the solver failing to hold still,
## and that is why it is the standard test: the right answer is exactly zero.
func _tower() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 20260903
	# Fourteen, not twenty-four: a metre-wide tower twenty-four storeys tall topples in
	# any solver, and "it fell" is not a measurement of anything. Fourteen is tall enough
	# to show error accumulating and short enough that standing still is right.
	for i in 14:
		# A hair of jitter, because a perfectly aligned tower never happens.
		_add_box(Vector3(
				random.randf_range(-0.004, 0.004),
				0.5 + float(i) * 1.02,
				random.randf_range(-0.004, 0.004)))


func _rain() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 20260903
	for i in bodies:
		_add_box(Vector3(
				random.randf_range(-7.0, 7.0),
				2.0 + float(i / 24) * 1.6,
				random.randf_range(-7.0, 7.0)))


## A chain hung between two anchors. Joints are where a solver stops being convincing:
## every link is a constraint, and the solver only gets so many passes to satisfy them.
func _bridge() -> void:
	var links := 18
	var previous: PhysicsBody3D = _anchor(Vector3(-links * 0.5 - 0.5, 8.0, 0.0))
	for i in links:
		var link := _add_box(
				Vector3(-links * 0.5 + float(i), 8.0, 0.0),
				Vector3(0.9, 0.3, 2.4),
				0.6)
		var joint := PinJoint3D.new()
		add_child(joint)
		_spawned.append(joint)
		joint.global_position = link.global_position - Vector3(0.5, 0.0, 0.0)
		joint.node_a = previous.get_path()
		joint.node_b = link.get_path()
		previous = link
	var far := _anchor(Vector3(links * 0.5 - 0.5, 8.0, 0.0))
	var last := PinJoint3D.new()
	add_child(last)
	_spawned.append(last)
	last.global_position = far.global_position - Vector3(0.5, 0.0, 0.0)
	last.node_a = previous.get_path()
	last.node_b = far.get_path()


func _anchor(at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 0.6, 2.4)
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
	_spawned.append(body)
	body.global_position = at
	return body


func _draw_hud() -> void:
	var text := "[b]ФИЗИКА[/b]    [color=#7fe08a]%s[/color]\n\n[table=2]" % (
			SCENES[kind].to_upper())
	text += "[cell]движок  [/cell][cell]%s[/cell]" % engine_name
	text += "[cell]тел  [/cell][cell]%d, из них не спят %d[/cell]" % [
		_boxes.size(), awake]
	text += "[cell]засыпание (V)  [/cell][cell]%s[/cell]" % (
			"[color=#7fe08a]включено[/color]" if sleeping
			else "[color=#ff8a6a]выключено[/color]")
	text += "[cell]физический шаг  [/cell][cell][b]%.2f мс[/b][/cell]" % physics_ms
	if kind == Scene.TOWER:
		text += "[cell]увод башни  [/cell][cell]%s%.4f м[/color]   за %.0f с[/cell]" % [
			"[color=#ff8a6a]" if check.drift > 0.05 else "[color=#7fe08a]",
			check.drift, check.age]
	elif kind == Scene.BRIDGE:
		text += "[cell]провис моста  [/cell][cell]%.3f м ниже опор[/cell]" % check.sag
	text += "[cell]повтор (G)  [/cell][cell]%s[/cell]" % check.verdict
	text += "[/table]\n\n"
	text += "1 2 3 — башня / ливень / мост    Z X C — 60 / 240 / 600 тел\n"
	text += "V — засыпание    G — повтор с пересборкой    H — повтор возвратом\n"
	text += "R — заново    правая кнопка — осмотреться, колесо — приблизить"
	_info.text = text
