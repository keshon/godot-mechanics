extends Node3D

# 17 — what you see, what you remember, what you have never met.
#
# Three states per cell and they are all different things:
#
#   VISIBLE     lit now. monsters are drawn.
#   REMEMBERED  you have been here. terrain is drawn dim; monsters are NOT, because
#               you do not remember where something walked off to.
#   UNKNOWN     not drawn at all.
#
# The second one is the mechanic. Without memory the map is a torch in a void; with
# it, walking becomes scouting.

const W := 61
const H := 41

@export_range(3, 16) var radius := 8
@export_range(0.03, 0.3) var hold_repeat := 0.11
@export_range(4, 40) var monsters := 18

var mode: SightFov.Mode = SightFov.Mode.SHADOW
var seed_value := 4
var steps := 0
var us := 0.0
var wide := false
var one_way := 0
var lit_now := 0

var _fov := SightFov.new()
var _solid := PackedByteArray()
var _known := PackedByteArray()
var _foes: Array[Vector2i] = []
var _at := Vector2i.ZERO
var _rng := RandomNumberGenerator.new()
var _held := Vector2i.ZERO
var _repeat := 0.0
var _eye := Vector3.ZERO


func _ready() -> void:
	_build()


func _process(delta: float) -> void:
	_walk(delta)
	_camera(delta)
	_hud()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_1:
			mode = SightFov.Mode.CIRCLE
			_look()
		KEY_2:
			mode = SightFov.Mode.RAYS
			_look()
		KEY_3:
			mode = SightFov.Mode.SHADOW
			_look()
		KEY_M:
			wide = not wide
		KEY_SPACE:
			seed_value = randi() & 0xFFFF
			_build()
		KEY_R:
			_build()
		KEY_Q:
			radius = maxi(radius - 1, 3)
			_look()
		KEY_E:
			radius = mini(radius + 1, 16)
			_look()


# --- world --------------------------------------------------------------------

func _build() -> void:
	_rng.seed = seed_value
	_solid = PackedByteArray()
	_solid.resize(W * H)
	_solid.fill(1)
	_known = PackedByteArray()
	_known.resize(W * H)
	var rooms: Array[Rect2i] = []
	for _i in 140:
		var rw := _rng.randi_range(5, 11)
		var rh := _rng.randi_range(4, 8)
		var r := Rect2i(_rng.randi_range(1, W - rw - 2), _rng.randi_range(1, H - rh - 2), rw, rh)
		var ok := true
		for o in rooms:
			if r.grow(1).intersects(o):
				ok = false
				break
		if not ok:
			continue
		rooms.append(r)
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				_solid[y * W + x] = 0
	for i in range(1, rooms.size()):
		var a := rooms[i - 1].get_center()
		var b := rooms[i].get_center()
		for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
			_solid[a.y * W + x] = 0
		for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
			_solid[y * W + b.x] = 0

	var open: Array[Vector2i] = []
	for i in W * H:
		if _solid[i] == 0:
			open.append(Vector2i(i % W, i / W))
	_at = open[_rng.randi_range(0, open.size() - 1)]
	_foes.clear()
	for _k in monsters:
		_foes.append(open[_rng.randi_range(0, open.size() - 1)])
	_fov.setup(W, H, _solid)
	steps = 0
	_eye = Vector3(_at.x, 0.0, _at.y)
	_look()


func _look() -> void:
	var t0 := Time.get_ticks_usec()
	_fov.look(mode, _at.x, _at.y, radius)
	us = float(Time.get_ticks_usec() - t0)
	lit_now = _fov.seen  # looking back from each monster overwrites this later
	for i in W * H:
		if _fov.lit[i] == 1:
			_known[i] = 1
	_draw()


func _walk(delta: float) -> void:
	var step := Vector2i(
		int(Input.is_action_pressed("move_right")) - int(Input.is_action_pressed("move_left")),
		int(Input.is_action_pressed("move_back")) - int(Input.is_action_pressed("move_forward")))
	if step == Vector2i.ZERO:
		_repeat = 0.0
		_held = Vector2i.ZERO
		return
	if step != _held:
		_repeat = 0.0
		_held = step
	_repeat -= delta
	if _repeat > 0.0:
		return
	_repeat = hold_repeat
	var to := _at + step
	if to.x < 0 or to.y < 0 or to.x >= W or to.y >= H or _solid[to.y * W + to.x] == 1:
		return
	_at = to
	steps += 1
	_stir()
	_look()


func _stir() -> void:
	# monsters wander while you are away. that is what makes memory a memory and
	# not a screenshot.
	for i in _foes.size():
		if _rng.randf() > 0.5:
			continue
		var d: Vector2i = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)][_rng.randi() % 4]
		var to: Vector2i = _foes[i] + d
		if to.x >= 0 and to.y >= 0 and to.x < W and to.y < H and _solid[to.y * W + to.x] == 0:
			_foes[i] = to


# --- drawing ------------------------------------------------------------------

func _draw() -> void:
	var floor_at: Array[Vector3] = []
	var floor_col: Array[Color] = []
	var wall_at: Array[Vector3] = []
	var wall_col: Array[Color] = []
	for i in W * H:
		if _known[i] == 0:
			continue
		var x := i % W
		var y := i / W
		var bright: bool = _fov.lit[i] == 1
		if _solid[i] == 0:
			floor_at.append(Vector3(x, -0.05, y))
			floor_col.append(Color(0.74, 0.71, 0.63) if bright else Color(0.2, 0.23, 0.3))
		else:
			var touches := false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx >= 0 and ny >= 0 and nx < W and ny < H and _solid[ny * W + nx] == 0:
					touches = true
			if not touches:
				continue
			wall_at.append(Vector3(x, 0.3, y))
			wall_col.append(Color(0.98, 0.96, 0.9) if bright else Color(0.28, 0.31, 0.4))
	_fill($Floor.multimesh, floor_at, floor_col)
	_fill($Walls.multimesh, wall_at, wall_col)

	# Monsters only exist while you are looking at them. And for each one, look BACK
	# from where it stands: sight is not always mutual, and a blue monster is one you
	# can see that cannot see you.
	var foe_at: Array[Vector3] = []
	var foe_col: Array[Color] = []
	var mine := _fov.lit.duplicate()
	one_way = 0
	for f in _foes:
		if mine[f.y * W + f.x] != 1:
			continue
		_fov.look(mode, f.x, f.y, radius)
		var mutual: bool = _fov.visible(_at.x, _at.y)
		if not mutual:
			one_way += 1
		foe_at.append(Vector3(f.x, 0.6, f.y))
		foe_col.append(Color(1.0, 0.42, 0.34) if mutual else Color(0.4, 0.7, 1.0))
	_fov.lit = mine
	_fill($Foes.multimesh, foe_at, foe_col)
	$Hero.position = Vector3(_at.x, 0.6, _at.y)


func _fill(mm: MultiMesh, at: Array[Vector3], col: Array[Color]) -> void:
	mm.instance_count = at.size()
	for i in at.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, at[i]))
		mm.set_instance_color(i, col[i])


func _camera(delta: float) -> void:
	var want := Vector3(W * 0.5, 0.0, H * 0.5) if wide else Vector3(_at.x, 0.0, _at.y)
	_eye = want + (_eye - want) * exp(-9.0 * delta)
	var cam: Camera3D = $Camera
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = lerpf(cam.size, 46.0 if wide else 22.0, 1.0 - exp(-7.0 * delta))
	cam.position = _eye + Vector3(1.0, 1.0, 1.0).normalized() * 90.0
	cam.look_at(_eye, Vector3.UP)


func _hud() -> void:
	var names := ["no walls at all", "a line to every rim cell", "recursive shadowcasting"]
	var found := 0
	for f in _foes:
		if _fov.visible(f.x, f.y):
			found += 1
	var known := 0
	for b in _known:
		known += b
	$Ui/Hud/Big.text = "%d  cells lit" % lit_now
	var t := "[b]%d  %s[/b]\n\n[table=2]" % [int(mode) + 1, names[int(mode)]]
	t += "[cell]radius  [/cell][cell]%d   (Q E)[/cell]" % radius
	t += "[cell]cost  [/cell][cell]%.0f us[/cell]" % us
	t += "[cell]monsters in sight  [/cell][cell]%d of %d[/cell]" % [found, _foes.size()]
	t += "[cell]of those, blind to you  [/cell][cell]%d[/cell]" % one_way
	t += "[cell]map you have met  [/cell][cell]%d cells, %d steps[/cell]" % [known, steps]
	t += "[/table]\n\n"
	t += "bright = seen now      dim = remembered\n"
	t += "[color=#ff6a57]red[/color] sees you back    [color=#66b3ff]blue[/color] cannot — sight is not always mutual"
	$Ui/Hud/Detail.text = t
