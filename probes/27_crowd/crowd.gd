class_name CrowdRun
extends Node3D
## 27 — the heap probe 26 left behind.
##
## Two streams cross in the open. Nothing here is about finding a way: every agent
## already knows where it is going. The only question is what happens when the way is
## occupied.
##
## The measurement is not the frame time. It is OVERLAP — how deep agents stand inside
## each other — because "they do not walk through each other" is otherwise an opinion.
## Cost is the second number, and throughput the third: avoidance that stops the crowd
## moving has solved nothing.

const MODES := [
	"никак — как в 26-й",
	"своё расталкивание",
	"RVO движка",
]

@export_range(0, 2) var mode := 2
@export var count := 300

var sim := CrowdSim.new()
var frame_ms := 0.0
## Crossings finished per second: avoidance that stops the crowd has solved nothing.
var arrivals_per_second := 0.0

var _yaw := 0.0
var _pitch := -0.95
var _distance := 62.0
var _looking := false
var _clock := 0.0
var _last_arrivals := 0

@onready var _camera: Camera3D = $Camera
@onready var _pillars: MultiMeshInstance3D = $Pillars
@onready var _agents: MultiMeshInstance3D = $Agents
@onready var _info: RichTextLabel = $Ui/Info


func _ready() -> void:
	RenderingServer.viewport_set_measure_render_time(
			get_viewport().get_viewport_rid(), true)
	sim.mode = mode
	sim.build(count)
	_place_pillars()


func _exit_tree() -> void:
	# RIDs are not nodes: nothing frees them when the scene goes. Probe 23 met the same
	# rule with the FFT textures, and it is the whole difference between a node and a RID.
	sim.release()


func _process(_delta: float) -> void:
	var mesh: MultiMesh = _agents.multimesh
	if mesh.instance_count != sim.count:
		mesh.instance_count = sim.count
	for i in sim.count:
		mesh.set_instance_transform(i, Transform3D(
				Basis.IDENTITY, Vector3(sim.spots[i].x, 0.55, sim.spots[i].y)))
		# Colour by direction, so lanes are visible the moment they form.
		mesh.set_instance_color(
				i,
				Color(1.0, 0.55, 0.2) if sim.side[i] == 0 else Color(0.35, 0.7, 1.0))
	var forward := Vector3(
			sin(_yaw) * cos(_pitch),
			sin(_pitch),
			cos(_yaw) * cos(_pitch))
	_camera.global_position = -forward * _distance + Vector3(0.0, 1.0, 0.0)
	_camera.look_at(Vector3.ZERO)
	frame_ms = lerpf(
			frame_ms,
			RenderingServer.viewport_get_measured_render_time_gpu(
					get_viewport().get_viewport_rid()),
			0.05)
	_draw_hud()


func _physics_process(delta: float) -> void:
	# In _physics_process, not _process: the avoidance callbacks fire when the navigation
	# map syncs, and that happens on the physics step. Driving the crowd anywhere else
	# means reading the answer of the frame before last.
	sim.step(delta)
	_clock += delta
	if _clock >= 1.0:
		arrivals_per_second = float(sim.arrivals - _last_arrivals) / _clock
		_last_arrivals = sim.arrivals
		_clock = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_looking = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(_distance - 3.0, 16.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(_distance + 3.0, 130.0)
		return
	if event is InputEventMouseMotion and _looking:
		_yaw -= event.relative.x * 0.005
		_pitch = clampf(_pitch - event.relative.y * 0.005, -1.5, -0.1)
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_1, KEY_2, KEY_3:
			mode = event.keycode - KEY_1
			sim.set_mode(mode)
		KEY_Z:
			count = 60
			sim.build(count)
		KEY_X:
			count = 300
			sim.build(count)
		KEY_C:
			count = 1200
			sim.build(count)


func _place_pillars() -> void:
	var mesh: MultiMesh = _pillars.multimesh
	mesh.instance_count = CrowdSim.PILLARS.size()
	for i in CrowdSim.PILLARS.size():
		var at: Vector2 = CrowdSim.PILLARS[i]
		mesh.set_instance_transform(i, Transform3D(
				Basis.IDENTITY.scaled(
						Vector3(CrowdSim.PILLAR_RADIUS, 1.6, CrowdSim.PILLAR_RADIUS)),
				Vector3(at.x, 1.6, at.y)))


func _draw_hud() -> void:
	var text := "[b]ТОЛПА[/b]    [color=#7fe08a]%s[/color]\n\n[table=2]" % (
			MODES[mode].to_upper())
	text += "[cell]агентов  [/cell][cell]%d[/cell]" % sim.count
	text += "[cell][b]наложение, среднее[/b]  [/cell]"
	text += "[cell][b]%.3f м[/b]   (радиус %.2f)[/cell]" % [
		sim.overlap_avg, CrowdSim.RADIUS]
	text += "[cell]наложение, худшее  [/cell][cell]%s%.3f м[/color][/cell]" % [
		"[color=#ff8a6a]" if sim.overlap_max > CrowdSim.RADIUS else "[color=#7fe08a]",
		sim.overlap_max]
	text += "[cell]пар внахлёст  [/cell][cell]%d[/cell]" % sim.pairs
	text += "[cell]шаг толпы  [/cell][cell]%.0f мкс   (+%.0f на сам замер)[/cell]" % [
		sim.step_usec, sim.measure_usec]
	text += "[cell]пропускная способность  [/cell]"
	text += "[cell]%.0f переходов в секунду[/cell]" % arrivals_per_second
	text += "[cell]кадр  [/cell][cell]%.2f мс на GPU[/cell]" % frame_ms
	text += "[/table]\n\n"
	text += "1 2 3 — никак / своё расталкивание / RVO движка    Z X C — 60 / 300 / 1200\n"
	text += "правая кнопка — осмотреться, колесо — приблизить\n"
	text += "[color=#66ccff]оранжевые идут вправо, синие влево. "
	text += "смотри, образуются ли полосы[/color]"
	_info.text = text
