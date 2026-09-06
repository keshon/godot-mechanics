extends Node3D

# 28 — bodies, joints, and the three questions you only ask once you have them.
#
#   СТОИТ ЛИ?     a tower is the classic quality test of a solver. Nothing pushes it, so
#                 any movement at all is error accumulating.
#   СПИТ ЛИ?      a body at rest should cost nothing. Sleeping is the single biggest lever
#                 in a physics scene, the same shape as UPDATE_ONCE in probe 25.
#   ОДИНАКОВО ЛИ? run the same thing twice from the same state. Rule 4 says tests come
#                 back for the deterministic step, so this is the probe that finds out
#                 whether there IS one.
#
# Bodies are real RigidBody3D nodes, not a homegrown integrator: rule 5. What the engine
# does not promise is exactly what gets measured.

const FLOOR := 30.0
const SCENES := ["башня", "ливень", "мост"]

@export_range(0, 2) var kind := 0
@export var bodies := 240
@export var sleeping := true

var check := PhysCheck.new()
var ms_phys := 0.0
var awake := 0
var engine_name := ""

var _boxes: Array[RigidBody3D] = []
var _made: Array[Node] = []
var _yaw := 0.5
var _pitch := -0.35
var _dist := 34.0
var _look := false
var _mesh := BoxMesh.new()
var _mat := StandardMaterial3D.new()


func _ready() -> void:
	engine_name = str(ProjectSettings.get_setting("physics/3d/physics_engine", "DEFAULT"))
	_mesh.size = Vector3.ONE
	_mat.albedo_color = Color(0.72, 0.6, 0.42)
	_mat.roughness = 0.85
	_build()


## Everything spawned is remembered and taken away again — joints and anchors included.
## The first version freed only the bodies, so every rebuild left its joints behind and
## the bridge quietly accumulated dead constraints.
##
## And remove_child BEFORE queue_free: queue_free only takes the node away at the end of
## the frame, so the old pile is still in the physics world while the new one spawns
## inside it. One frame of ghosts is enough to make two runs differ.
func _build() -> void:
	for n in _made:
		remove_child(n)
		n.queue_free()
	_made.clear()
	_boxes.clear()
	check.reset()
	match kind:
		0:
			_tower()
		1:
			_rain()
		2:
			_bridge()


func _box(at: Vector3, size := Vector3.ONE, mass := 1.0) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.mass = mass
	b.can_sleep = sleeping
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	b.add_child(col)
	var vis := MeshInstance3D.new()
	vis.mesh = _mesh
	vis.scale = size
	vis.material_override = _mat
	b.add_child(vis)
	add_child(b)
	b.global_position = at
	_boxes.append(b)
	_made.append(b)
	return b


## A tower nobody touches. Every millimetre it moves is the solver failing to hold still,
## and that is why it is the standard test: the right answer is exactly zero.
func _tower() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260903
	# Fourteen, not twenty-four: a metre-wide tower twenty-four storeys tall topples in any
	# solver, and "it fell" is not a measurement of anything. Fourteen is tall enough to
	# show error accumulating and short enough that standing still is the right answer.
	for i in 14:
		# a hair of jitter, because a perfectly aligned tower is a case that never happens
		_box(Vector3(rng.randf_range(-0.004, 0.004), 0.5 + float(i) * 1.02,
			rng.randf_range(-0.004, 0.004)))


func _rain() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260903
	for i in bodies:
		_box(Vector3(rng.randf_range(-7.0, 7.0), 2.0 + float(i / 24) * 1.6,
			rng.randf_range(-7.0, 7.0)))


## A chain hung between two anchors. Joints are where a solver stops being convincing:
## every link is a constraint, and the solver only gets so many passes to satisfy them all.
func _bridge() -> void:
	var links := 18
	var prev: PhysicsBody3D = _anchor(Vector3(-links * 0.5 - 0.5, 8.0, 0.0))
	for i in links:
		var b := _box(Vector3(-links * 0.5 + float(i), 8.0, 0.0), Vector3(0.9, 0.3, 2.4), 0.6)
		var j := PinJoint3D.new()
		add_child(j)
		_made.append(j)
		j.global_position = b.global_position - Vector3(0.5, 0.0, 0.0)
		j.node_a = prev.get_path()
		j.node_b = b.get_path()
		prev = b
	var far := _anchor(Vector3(links * 0.5 - 0.5, 8.0, 0.0))
	var last := PinJoint3D.new()
	add_child(last)
	_made.append(last)
	last.global_position = far.global_position - Vector3(0.5, 0.0, 0.0)
	last.node_a = prev.get_path()
	last.node_b = far.get_path()


func _anchor(at: Vector3) -> StaticBody3D:
	var s := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 0.6, 2.4)
	col.shape = shape
	s.add_child(col)
	add_child(s)
	_made.append(s)
	s.global_position = at
	return s


func _physics_process(_d: float) -> void:
	awake = 0
	for b in _boxes:
		if not b.sleeping:
			awake += 1
	check.tick(_boxes)


func _process(_d: float) -> void:
	ms_phys = lerpf(ms_phys,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.08)
	var cam: Camera3D = $Cam
	var fwd := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	cam.global_position = -fwd * _dist + Vector3(0.0, 6.0, 0.0)
	cam.look_at(Vector3(0.0, 5.0, 0.0))
	_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_look = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(_dist - 2.0, 8.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(_dist + 2.0, 90.0)
		return
	if event is InputEventMouseMotion and _look:
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
			for b in _boxes:
				b.can_sleep = sleeping
				if not sleeping:
					b.sleeping = false
		KEY_G:
			check.start(true, _build)     # честный повтор: сцена собирается заново
		KEY_H:
			check.start(false)            # дешёвый: вернуть тела на места
		KEY_R:
			_build()


func _hud() -> void:
	var t := "[b]ФИЗИКА[/b]    [color=#7fe08a]%s[/color]\n\n" % SCENES[kind].to_upper()
	t += "[table=2]"
	t += "[cell]движок  [/cell][cell]%s[/cell]" % engine_name
	t += "[cell]тел  [/cell][cell]%d, из них не спят %d[/cell]" % [_boxes.size(), awake]
	t += "[cell]засыпание (V)  [/cell][cell]%s[/cell]" % (
		"[color=#7fe08a]включено[/color]" if sleeping else "[color=#ff8a6a]выключено[/color]")
	t += "[cell]физический шаг  [/cell][cell][b]%.2f мс[/b][/cell]" % ms_phys
	if kind == 0:
		t += "[cell]увод башни  [/cell][cell]%s%.4f м[/color]   за %.0f с[/cell]" % [
			"[color=#ff8a6a]" if check.drift > 0.05 else "[color=#7fe08a]",
			check.drift, check.age]
	elif kind == 2:
		t += "[cell]провис моста  [/cell][cell]%.3f м ниже опор[/cell]" % check.sag
	t += "[cell]повтор (G)  [/cell][cell]%s[/cell]" % check.verdict
	t += "[/table]\n\n"
	t += "1 2 3 — башня / ливень / мост    Z X C — 60 / 240 / 600 тел\n"
	t += "V — засыпание    G — повтор с пересборкой    H — повтор возвратом    R — заново\n"
	t += "правая кнопка — осмотреться, колесо — приблизить"
	$Ui/Info.text = t
