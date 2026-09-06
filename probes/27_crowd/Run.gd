extends Node3D

# 27 — the heap probe 26 left behind.
#
# Two streams cross in the open. Nothing here is about finding a way: every agent already
# knows where it is going. The only question is what happens when the way is occupied.
#
# The measurement is not the frame time. It is OVERLAP — how deep agents stand inside each
# other — because "they do not walk through each other" is otherwise an opinion. Cost is
# the second number, and throughput the third: avoidance that stops the crowd moving has
# solved nothing.

const MODES := ["никак — как в 26-й", "своё расталкивание", "RVO движка"]

@export_range(0, 2) var mode := 2
@export var count := 300

var sim := CrowdSim.new()
var ms_frame := 0.0
var per_sec := 0.0

var _yaw := 0.0
var _pitch := -0.95
var _dist := 62.0
var _look := false
var _clock := 0.0
var _was := 0


func _ready() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	sim.mode = mode
	sim.build(count)
	_pillars()


func _exit_tree() -> void:
	# RIDs are not nodes: nothing frees them when the scene goes. Probe 23 met the same
	# rule with the FFT textures, and it is the whole difference between a node and a RID.
	sim.release()


func _pillars() -> void:
	var mm: MultiMesh = ($Pillars as MultiMeshInstance3D).multimesh
	mm.instance_count = CrowdSim.PILLARS.size()
	for i in CrowdSim.PILLARS.size():
		var p: Vector2 = CrowdSim.PILLARS[i]
		mm.set_instance_transform(i, Transform3D(
			Basis.IDENTITY.scaled(Vector3(CrowdSim.PILLAR_R, 1.6, CrowdSim.PILLAR_R)),
			Vector3(p.x, 1.6, p.y)))


func _physics_process(delta: float) -> void:
	# In _physics_process, not _process: the avoidance callbacks fire when the navigation
	# map syncs, and that happens on the physics step. Driving the crowd anywhere else
	# means reading last-but-one frame's answer.
	sim.step(delta)
	_clock += delta
	if _clock >= 1.0:
		per_sec = float(sim.arrivals - _was) / _clock
		_was = sim.arrivals
		_clock = 0.0


func _process(_d: float) -> void:
	var mm: MultiMesh = ($Agents as MultiMeshInstance3D).multimesh
	if mm.instance_count != sim.count:
		mm.instance_count = sim.count
	for i in sim.count:
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY,
			Vector3(sim.pos[i].x, 0.55, sim.pos[i].y)))
		# colour by direction, so lanes are visible the moment they form
		mm.set_instance_color(i, Color(1.0, 0.55, 0.2) if sim.side[i] == 0
			else Color(0.35, 0.7, 1.0))
	var cam: Camera3D = $Cam
	var fwd := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	cam.global_position = -fwd * _dist + Vector3(0.0, 1.0, 0.0)
	cam.look_at(Vector3.ZERO)
	ms_frame = lerpf(ms_frame,
		RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()),
		0.05)
	_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_look = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(_dist - 3.0, 16.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(_dist + 3.0, 130.0)
		return
	if event is InputEventMouseMotion and _look:
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


func _hud() -> void:
	var t := "[b]ТОЛПА[/b]    [color=#7fe08a]%s[/color]\n\n" % MODES[mode].to_upper()
	t += "[table=2]"
	t += "[cell]агентов  [/cell][cell]%d[/cell]" % sim.count
	t += "[cell][b]наложение, среднее[/b]  [/cell][cell][b]%.3f м[/b]   (радиус %.2f)[/cell]" % [
		sim.overlap_avg, CrowdSim.R]
	t += "[cell]наложение, худшее  [/cell][cell]%s%.3f м[/color][/cell]" % [
		"[color=#ff8a6a]" if sim.overlap_max > CrowdSim.R else "[color=#7fe08a]",
		sim.overlap_max]
	t += "[cell]пар внахлёст  [/cell][cell]%d[/cell]" % sim.pairs
	t += "[cell]шаг толпы  [/cell][cell]%.0f мкс   (+%.0f на сам замер)[/cell]" % [
		sim.us_step, sim.us_measure]
	t += "[cell]пропускная способность  [/cell][cell]%.0f переходов в секунду[/cell]" % per_sec
	t += "[cell]кадр  [/cell][cell]%.2f мс на GPU[/cell]" % ms_frame
	t += "[/table]\n\n"
	t += "1 2 3 — никак / своё расталкивание / RVO движка    Z X C — 60 / 300 / 1200\n"
	t += "правая кнопка — осмотреться, колесо — приблизить\n"
	t += "[color=#66ccff]оранжевые идут вправо, синие влево. смотри, образуются ли полосы[/color]"
	$Ui/Info.text = t
