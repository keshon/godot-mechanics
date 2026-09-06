extends Node3D

# 26 — the way to the goal, and who pays for knowing it.
#
# Godot ships AStarGrid2D, so half of this probe is not written but TAKEN (rule 5). What
# the engine does not ship is everything around it, and that is the actual subject:
#
#   * a grid path is a staircase, and nothing straightens it for you;
#   * the goal moves, and now every agent needs a new answer;
#   * a thousand agents want the same answer, and asking a thousand times is a choice.
#
# Two mechanisms, one event. Move the goal and watch what each of them costs.

const SPEED := 5.5

@export var field_mode := false      ## false = one A* per agent, true = one sweep for all
@export var smoothing := true
@export var count := 300
@export var show_field := false

var f := PathField.new()
var goal := Vector2i(32, 32)
var pos := PackedVector2Array()
var cursor := PackedInt32Array()
var paths: Array = []

var ms_repath := 0.0
## Kept across a mode switch so the crossover can be MEASURED rather than guessed. The
## first version divided the sweep by one A* query and said 596 agents; the repath loop
## said 80. Both numbers were real, they just measured different things — a bare query is
## not what an agent costs.
var us_agent := 0.0
var ms_sweep := 0.0
var ms_frame := 0.0
var waypoints := 0
var raw_len := 0.0
var cut_len := 0.0
var world_seed := 20260901

var _yaw := 0.0
var _pitch := -1.05
var _dist := 78.0
var _look := false


func _ready() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_fresh()


func _fresh() -> void:
	f.build(world_seed)
	goal = f.open_cells[f.open_cells.size() / 2]
	_paint()
	_spawn()
	_repath()


func _spawn() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 7
	pos.resize(count)
	cursor.resize(count)
	paths.resize(count)
	for i in count:
		var c: Vector2i = f.open_cells[rng.randi_range(0, f.open_cells.size() - 1)]
		pos[i] = Vector2(c) + Vector2(rng.randf(), rng.randf()) - Vector2(0.5, 0.5)
		cursor[i] = 0
		paths[i] = [] as Array[Vector2i]
	($Agents as MultiMeshInstance3D).multimesh.instance_count = count


## THE measurement of the probe, and it is one event seen twice: the goal moved, so every
## agent's answer is stale. A* pays per agent; the sweep pays per grid and does not care
## how many agents there are — or whether there are any yet.
func _repath() -> void:
	var t0 := Time.get_ticks_usec()
	waypoints = 0
	raw_len = 0.0
	cut_len = 0.0
	if field_mode:
		f.sweep(goal)
	else:
		for i in count:
			var p := f.path(_cell(i), goal)
			raw_len += f.length_of(p)
			var q: Array[Vector2i] = f.smooth(p) if smoothing else p
			cut_len += f.length_of(q)
			waypoints += q.size()
			paths[i] = q
			cursor[i] = 0
	ms_repath = float(Time.get_ticks_usec() - t0) / 1000.0
	if field_mode:
		ms_sweep = ms_repath
	elif count > 0:
		us_agent = ms_repath * 1000.0 / float(count)
	if show_field:
		_paint()


func _cell(i: int) -> Vector2i:
	var c := Vector2i(roundi(pos[i].x), roundi(pos[i].y))
	if f.walkable(c.x, c.y):
		return c
	# an agent nudged into a wall would make A* return nothing at all, which reads as a
	# broken pathfinder rather than as a bad start cell
	for d in PathField.DIRS:
		if f.walkable(c.x + d.x, c.y + d.y):
			return c + d
	return goal


func _paint() -> void:
	var mm: MultiMesh = ($Ground as MultiMeshInstance3D).multimesh
	mm.instance_count = PathField.N * PathField.N
	var far := 1.0
	if show_field and f.reach.size() > 0:
		for v in f.reach:
			far = maxf(far, float(v))
	for i in PathField.N * PathField.N:
		var x := i % PathField.N
		var y := i / PathField.N
		var wall := f.solid[i] == 1
		var h := 2.2 if wall else 0.25
		mm.set_instance_transform(i, Transform3D(
			Basis.IDENTITY.scaled(Vector3(1.0, h, 1.0)),
			Vector3(float(x), h * 0.5, float(y))))
		var c := Color(0.30, 0.31, 0.36) if wall else Color(0.13, 0.15, 0.19)
		if not wall and show_field and f.reach.size() > 0 and f.reach[i] >= 0:
			# the wave, drawn: every cell the sweep touched, shaded by how far it got
			c = Color(0.10, 0.55, 0.85).lerp(Color(0.95, 0.85, 0.25), float(f.reach[i]) / far)
		mm.set_instance_color(i, c)


func _process(delta: float) -> void:
	_drive(delta)
	_place()
	var cam: Camera3D = $Cam
	var fwd := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	var mid := Vector3(PathField.N * 0.5, 0.0, PathField.N * 0.5)
	cam.global_position = mid - fwd * _dist
	cam.look_at(mid)
	$Goal.global_position = Vector3(goal.x, 1.2, goal.y)
	ms_frame = lerpf(ms_frame,
		RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()),
		0.05)
	_hud()


func _drive(delta: float) -> void:
	for i in count:
		var want := Vector2.ZERO
		if field_mode:
			var d := f.step(Vector2i(roundi(pos[i].x), roundi(pos[i].y)))
			want = Vector2(d)
		else:
			var p: Array = paths[i]
			while cursor[i] < p.size() and pos[i].distance_to(Vector2(p[cursor[i]])) < 0.35:
				cursor[i] += 1
			if cursor[i] < p.size():
				want = Vector2(p[cursor[i]]) - pos[i]
		if want.length_squared() > 0.0001:
			pos[i] += want.normalized() * SPEED * delta


func _place() -> void:
	var mm: MultiMesh = ($Agents as MultiMeshInstance3D).multimesh
	for i in count:
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY,
			Vector3(pos[i].x, 0.75, pos[i].y)))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_look = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(_dist - 4.0, 20.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(_dist + 4.0, 160.0)
		return
	if event is InputEventMouseMotion and _look:
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
			_fresh()


## Click on the floor moves the goal. A plane at y = 0 needs no physics: the ray from the
## camera meets it at exactly one parameter, and that is the whole intersection.
func _click(mouse: Vector2) -> void:
	var cam: Camera3D = $Cam
	var o := cam.project_ray_origin(mouse)
	var d := cam.project_ray_normal(mouse)
	if absf(d.y) < 0.0001:
		return
	var hit := o + d * (-o.y / d.y)
	var c := Vector2i(roundi(hit.x), roundi(hit.z))
	if f.walkable(c.x, c.y):
		goal = c
		_repath()


func _hud() -> void:
	var t := "[b]ПУТЬ[/b]    %s\n\n" % ("[color=#7fe08a]поле: одна развёртка на всех[/color]"
		if field_mode else "[color=#ffd479]A*: свой запрос каждому[/color]")
	t += "[table=2]"
	t += "[cell]сетка  [/cell][cell]%d×%d, проходимых %d[/cell]" % [
		PathField.N, PathField.N, f.open_cells.size()]
	t += "[cell]агентов  [/cell][cell]%d[/cell]" % count
	t += "[cell]перепрокладка всем  [/cell][cell][b]%.2f мс[/b][/cell]" % ms_repath
	if field_mode:
		t += "[cell]развёртка  [/cell][cell]%.0f мкс, задето клеток %d[/cell]" % [
			f.us_field, f.visited]
		if us_agent > 0.0:
			t += "[cell]окупается с  [/cell][cell][b]%d агентов[/b]   (по замеру обоих режимов)[/cell]" % int(
				ms_sweep * 1000.0 / us_agent)
	else:
		t += "[cell]один запрос  [/cell][cell]%.0f мкс   (на агента в цикле %.0f)[/cell]" % [
			f.us_path, us_agent]
		t += "[cell]сглаживание (V)  [/cell][cell]%s[/cell]" % (
			"[color=#7fe08a]есть[/color]" if smoothing else "[color=#ff8a6a]нет[/color]")
		t += "[cell]точек в путях  [/cell][cell]%d[/cell]" % waypoints
		t += "[cell]длина путей  [/cell][cell]%.0f → %.0f клеток[/cell]" % [raw_len, cut_len]
	t += "[cell]кадр  [/cell][cell]%.2f мс на GPU[/cell]" % ms_frame
	t += "[/table]\n\n"
	t += "щелчок — поставить цель    TAB — A* / поле    V — сглаживание\n"
	t += "Z X C — 60 / 300 / 1200 агентов    G — показать развёртку    R — новый мир\n"
	t += "правая кнопка — осмотреться, колесо — приблизить
"
	t += "[color=#66ccff]A* тут нативный, развёртка на GDScript — форма ответа честна, точка окупаемости нет[/color]"
	$Ui/Info.text = t
