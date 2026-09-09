class_name PathRun
extends Node3D
## 26 — the way to the goal, and who pays for knowing it.
##
## Godot ships AStarGrid2D, so half of this probe is not written but TAKEN (rule 5). What
## the engine does not ship is everything around it, and that is the actual subject:
##
##   * a grid path is a staircase, and nothing straightens it for you;
##   * the goal moves, and now every agent needs a new answer;
##   * a thousand agents want the same answer, and asking a thousand times is a choice.
##
## Two mechanisms, one event. Move the goal and watch what each of them costs.

const SPEED := 5.5

## False = one A* per agent, true = one sweep for all.
@export var field_mode := false
@export var smoothing := true
@export var count := 300
@export var show_field := false

var field := PathField.new()
var goal := Vector2i(32, 32)
## Where every agent stands, in cells but not snapped to them.
var spots := PackedVector2Array()
## Index of the waypoint each agent is walking towards.
var next_point := PackedInt32Array()
var routes: Array = []
var world_seed := 20260901

## Cost of answering every agent once, milliseconds.
var repath_ms := 0.0
## Kept across a mode switch so the crossover can be MEASURED rather than guessed. The
## first version divided the sweep by one A* query and said 596 agents; the repath loop
## said 80. Both numbers were real, they just measured different things — a bare query is
## not what an agent costs.
var agent_usec := 0.0
var sweep_ms := 0.0
var frame_ms := 0.0
var waypoints := 0
var raw_length := 0.0
var cut_length := 0.0

var _yaw := 0.0
var _pitch := -1.05
var _distance := 78.0
var _looking := false

@onready var _camera: Camera3D = $Camera
@onready var _ground: MultiMeshInstance3D = $Ground
@onready var _agents: MultiMeshInstance3D = $Agents
@onready var _goal_mesh: MeshInstance3D = $Goal
@onready var _info: RichTextLabel = $Ui/Info


func _ready() -> void:
	RenderingServer.viewport_set_measure_render_time(
			get_viewport().get_viewport_rid(), true)
	_regenerate()


func _process(delta: float) -> void:
	_drive(delta)
	_place()
	var forward := Vector3(
			sin(_yaw) * cos(_pitch),
			sin(_pitch),
			cos(_yaw) * cos(_pitch))
	var middle := Vector3(PathField.SIZE * 0.5, 0.0, PathField.SIZE * 0.5)
	_camera.global_position = middle - forward * _distance
	_camera.look_at(middle)
	_goal_mesh.global_position = Vector3(goal.x, 1.2, goal.y)
	frame_ms = lerpf(
			frame_ms,
			RenderingServer.viewport_get_measured_render_time_gpu(
					get_viewport().get_viewport_rid()),
			0.05)
	_draw_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_move_goal(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_looking = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(_distance - 4.0, 20.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(_distance + 4.0, 160.0)
		return
	if event is InputEventMouseMotion and _looking:
		_yaw -= event.relative.x * 0.005
		_pitch = clampf(_pitch - event.relative.y * 0.005, -1.45, -0.15)
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_TAB:
			field_mode = not field_mode
			_repath()
		KEY_V:
			smoothing = not smoothing
			_repath()
		KEY_G:
			show_field = not show_field
			_paint()
		KEY_Z:
			count = 60
			_spawn()
			_repath()
		KEY_X:
			count = 300
			_spawn()
			_repath()
		KEY_C:
			count = 1200
			_spawn()
			_repath()
		KEY_R:
			world_seed += 1
			_regenerate()


func _regenerate() -> void:
	field.build(world_seed)
	goal = field.open_cells[field.open_cells.size() / 2]
	_paint()
	_spawn()
	_repath()


func _spawn() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = world_seed + 7
	spots.resize(count)
	next_point.resize(count)
	routes.resize(count)
	for i in count:
		var cell: Vector2i = field.open_cells[
				random.randi_range(0, field.open_cells.size() - 1)]
		var jitter := Vector2(random.randf(), random.randf()) - Vector2(0.5, 0.5)
		spots[i] = Vector2(cell) + jitter
		next_point[i] = 0
		routes[i] = [] as Array[Vector2i]
	_agents.multimesh.instance_count = count


## THE measurement of the probe, and it is one event seen twice: the goal moved, so the
## answer every agent holds is stale. A* pays per agent; the sweep pays per grid and does
## not care how many agents there are — or whether there are any yet.
func _repath() -> void:
	var started := Time.get_ticks_usec()
	waypoints = 0
	raw_length = 0.0
	cut_length = 0.0
	if field_mode:
		field.sweep(goal)
	else:
		for i in count:
			var route := field.path(_cell_of(i), goal)
			raw_length += field.length_of(route)
			var cut: Array[Vector2i] = field.smoothed(route) if smoothing else route
			cut_length += field.length_of(cut)
			waypoints += cut.size()
			routes[i] = cut
			next_point[i] = 0
	repath_ms = float(Time.get_ticks_usec() - started) / 1000.0
	if field_mode:
		sweep_ms = repath_ms
	elif count > 0:
		agent_usec = repath_ms * 1000.0 / float(count)
	if show_field:
		_paint()


func _cell_of(agent: int) -> Vector2i:
	var cell := Vector2i(roundi(spots[agent].x), roundi(spots[agent].y))
	if field.is_walkable(cell.x, cell.y):
		return cell
	# An agent nudged into a wall would make A* return nothing at all, which reads as a
	# broken pathfinder rather than as a bad start cell.
	for step in PathField.DIRS:
		if field.is_walkable(cell.x + step.x, cell.y + step.y):
			return cell + step
	return goal


func _paint() -> void:
	var mesh: MultiMesh = _ground.multimesh
	mesh.instance_count = PathField.SIZE * PathField.SIZE
	var furthest := 1.0
	if show_field and field.reach.size() > 0:
		for steps in field.reach:
			furthest = maxf(furthest, float(steps))
	for i in PathField.SIZE * PathField.SIZE:
		var wall := field.solid[i] == 1
		var height := 2.2 if wall else 0.25
		mesh.set_instance_transform(i, Transform3D(
				Basis.IDENTITY.scaled(Vector3(1.0, height, 1.0)),
				Vector3(
						float(i % PathField.SIZE),
						height * 0.5,
						float(i / PathField.SIZE))))
		var colour := Color(0.30, 0.31, 0.36) if wall else Color(0.13, 0.15, 0.19)
		if not wall and show_field and field.reach.size() > 0 and field.reach[i] >= 0:
			# The wave, drawn: every cell the sweep touched, shaded by how far it got.
			colour = Color(0.10, 0.55, 0.85).lerp(
					Color(0.95, 0.85, 0.25), float(field.reach[i]) / furthest)
		mesh.set_instance_color(i, colour)


func _drive(delta: float) -> void:
	for i in count:
		var wanted := Vector2.ZERO
		if field_mode:
			var cell := Vector2i(roundi(spots[i].x), roundi(spots[i].y))
			wanted = Vector2(field.direction_at(cell))
		else:
			var route: Array = routes[i]
			while (
					next_point[i] < route.size()
					and spots[i].distance_to(Vector2(route[next_point[i]])) < 0.35
			):
				next_point[i] += 1
			if next_point[i] < route.size():
				wanted = Vector2(route[next_point[i]]) - spots[i]
		if wanted.length_squared() > 0.0001:
			spots[i] += wanted.normalized() * SPEED * delta


func _place() -> void:
	var mesh: MultiMesh = _agents.multimesh
	for i in count:
		mesh.set_instance_transform(i, Transform3D(
				Basis.IDENTITY, Vector3(spots[i].x, 0.75, spots[i].y)))


## Click on the floor moves the goal. A plane at y = 0 needs no physics: the ray from the
## camera meets it at exactly one parameter, and that is the whole intersection.
func _move_goal(mouse: Vector2) -> void:
	var origin := _camera.project_ray_origin(mouse)
	var along := _camera.project_ray_normal(mouse)
	if absf(along.y) < 0.0001:
		return
	var hit := origin + along * (-origin.y / along.y)
	var cell := Vector2i(roundi(hit.x), roundi(hit.z))
	if not field.is_walkable(cell.x, cell.y):
		return
	goal = cell
	_repath()


func _draw_hud() -> void:
	var mode := "[color=#ffd479]A*: свой запрос каждому[/color]"
	if field_mode:
		mode = "[color=#7fe08a]поле: одна развёртка на всех[/color]"
	var text := "[b]ПУТЬ[/b]    %s\n\n[table=2]" % mode
	text += "[cell]сетка  [/cell][cell]%d×%d, проходимых %d[/cell]" % [
		PathField.SIZE, PathField.SIZE, field.open_cells.size()]
	text += "[cell]агентов  [/cell][cell]%d[/cell]" % count
	text += "[cell]перепрокладка всем  [/cell][cell][b]%.2f мс[/b][/cell]" % repath_ms
	if field_mode:
		text += "[cell]развёртка  [/cell][cell]%.0f мкс, задето клеток %d[/cell]" % [
			field.sweep_usec, field.visited]
		if agent_usec > 0.0:
			text += "[cell]окупается с  [/cell]"
			text += "[cell][b]%d агентов[/b]   (по замеру обоих режимов)[/cell]" % int(
					sweep_ms * 1000.0 / agent_usec)
	else:
		text += "[cell]один запрос  [/cell][cell]%.0f мкс   (на агента в цикле %.0f)[/cell]" % [
			field.query_usec, agent_usec]
		text += "[cell]сглаживание (V)  [/cell][cell]%s[/cell]" % (
				"[color=#7fe08a]есть[/color]" if smoothing
				else "[color=#ff8a6a]нет[/color]")
		text += "[cell]точек в путях  [/cell][cell]%d[/cell]" % waypoints
		text += "[cell]длина путей  [/cell][cell]%.0f → %.0f клеток[/cell]" % [
			raw_length, cut_length]
	text += "[cell]кадр  [/cell][cell]%.2f мс на GPU[/cell]" % frame_ms
	text += "[/table]\n\n"
	text += "щелчок — поставить цель    TAB — A* / поле    V — сглаживание\n"
	text += "Z X C — 60 / 300 / 1200 агентов    G — показать развёртку    R — новый мир\n"
	text += "правая кнопка — осмотреться, колесо — приблизить\n"
	text += "[color=#66ccff]A* тут нативный, развёртка на GDScript — форма ответа честна, "
	text += "точка окупаемости нет[/color]"
	_info.text = text
