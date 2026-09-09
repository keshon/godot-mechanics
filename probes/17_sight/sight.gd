class_name SightWorld
extends Node3D
## What you see, what you remember, what you have never met.
##
## Three states per cell, and they are all different things:
##
##   VISIBLE     lit now. Monsters are drawn.
##   REMEMBERED  you have been here. Terrain is drawn dim; monsters are NOT,
##               because you do not remember where something walked off to.
##   UNKNOWN     not drawn at all.
##
## The second one is the mechanic. Without memory the map is a torch in a void;
## with it, walking becomes scouting.

const WIDTH := 61
const HEIGHT := 41
const STEPS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

## How far the torch reaches, in cells.
@export_range(3, 16) var radius := 8
## How fast steps repeat while a direction is held, s.
@export_range(0.03, 0.3) var hold_repeat := 0.11
@export_range(4, 40) var monsters := 18

var mode: SightFov.Mode = SightFov.Mode.SHADOW
var seed_value := 4
var steps := 0
## How long the last `look()` took, microseconds.
var look_usec := 0.0
## Pulled back to show the whole map instead of following the hero.
var wide := false
## Monsters you can see that cannot see you back.
var one_way := 0
var lit_now := 0

var _fov := SightFov.new()
var _solid := PackedByteArray()
var _known := PackedByteArray()
var _foes: Array[Vector2i] = []
var _hero := Vector2i.ZERO
var _random := RandomNumberGenerator.new()
var _held := Vector2i.ZERO
var _repeat := 0.0
var _eye := Vector3.ZERO

@onready var _floor: MultiMeshInstance3D = $Floor
@onready var _walls: MultiMeshInstance3D = $Walls
@onready var _foe_mesh: MultiMeshInstance3D = $Foes
@onready var _hero_mesh: MeshInstance3D = $Hero
@onready var _camera: Camera3D = $Camera
@onready var _lit_label: Label = $Ui/Hud/Lit
@onready var _detail: RichTextLabel = $Ui/Hud/Detail


func _ready() -> void:
	_build()


func _process(delta: float) -> void:
	_walk(delta)
	_place_camera(delta)
	_draw_hud()


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


func _build() -> void:
	_random.seed = seed_value
	_solid = PackedByteArray()
	_solid.resize(WIDTH * HEIGHT)
	_solid.fill(1)
	_known = PackedByteArray()
	_known.resize(WIDTH * HEIGHT)

	var rooms: Array[Rect2i] = []
	for _try in 140:
		var room_width := _random.randi_range(5, 11)
		var room_height := _random.randi_range(4, 8)
		var room := Rect2i(
				_random.randi_range(1, WIDTH - room_width - 2),
				_random.randi_range(1, HEIGHT - room_height - 2),
				room_width,
				room_height)
		var clear := true
		for other in rooms:
			if room.grow(1).intersects(other):
				clear = false
				break
		if not clear:
			continue
		rooms.append(room)
		for y in range(room.position.y, room.end.y):
			for x in range(room.position.x, room.end.x):
				_solid[y * WIDTH + x] = 0
	for i in range(1, rooms.size()):
		var from := rooms[i - 1].get_center()
		var to := rooms[i].get_center()
		for x in range(mini(from.x, to.x), maxi(from.x, to.x) + 1):
			_solid[from.y * WIDTH + x] = 0
		for y in range(mini(from.y, to.y), maxi(from.y, to.y) + 1):
			_solid[y * WIDTH + to.x] = 0

	var open: Array[Vector2i] = []
	for i in WIDTH * HEIGHT:
		if _solid[i] == 0:
			open.append(Vector2i(i % WIDTH, i / WIDTH))
	_hero = open[_random.randi_range(0, open.size() - 1)]
	_foes.clear()
	for _each in monsters:
		_foes.append(open[_random.randi_range(0, open.size() - 1)])
	_fov.setup(WIDTH, HEIGHT, _solid)
	steps = 0
	_eye = Vector3(_hero.x, 0.0, _hero.y)
	_look()


func _look() -> void:
	var started := Time.get_ticks_usec()
	_fov.look(mode, _hero.x, _hero.y, radius)
	look_usec = float(Time.get_ticks_usec() - started)
	# Read before _draw(), because looking back from each monster overwrites the
	# field of view with theirs.
	lit_now = _fov.seen
	for i in WIDTH * HEIGHT:
		if _fov.lit[i] == 1:
			_known[i] = 1
	_draw()


func _walk(delta: float) -> void:
	var step := Vector2i(
			int(Input.is_action_pressed(&"move_right"))
					- int(Input.is_action_pressed(&"move_left")),
			int(Input.is_action_pressed(&"move_back"))
					- int(Input.is_action_pressed(&"move_forward")))
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
	var to := _hero + step
	if (
			to.x < 0 or to.y < 0 or to.x >= WIDTH or to.y >= HEIGHT
			or _solid[to.y * WIDTH + to.x] == 1
	):
		return
	_hero = to
	steps += 1
	_stir()
	_look()


## Monsters wander while you are away. That is what makes memory a memory and
## not a screenshot.
func _stir() -> void:
	for i in _foes.size():
		if _random.randf() > 0.5:
			continue
		var step: Vector2i = STEPS[_random.randi() % 4]
		var to: Vector2i = _foes[i] + step
		if (
				to.x >= 0 and to.y >= 0 and to.x < WIDTH and to.y < HEIGHT
				and _solid[to.y * WIDTH + to.x] == 0
		):
			_foes[i] = to


func _draw() -> void:
	var floor_places: Array[Vector3] = []
	var floor_colours: Array[Color] = []
	var wall_places: Array[Vector3] = []
	var wall_colours: Array[Color] = []
	for i in WIDTH * HEIGHT:
		if _known[i] == 0:
			continue
		var x := i % WIDTH
		var y := i / WIDTH
		var bright: bool = _fov.lit[i] == 1
		if _solid[i] == 0:
			floor_places.append(Vector3(x, -0.05, y))
			floor_colours.append(
					Color(0.74, 0.71, 0.63) if bright else Color(0.2, 0.23, 0.3))
			continue
		var touches := false
		for step in STEPS:
			var next_x: int = x + step.x
			var next_y: int = y + step.y
			if (
					next_x >= 0 and next_y >= 0 and next_x < WIDTH and next_y < HEIGHT
					and _solid[next_y * WIDTH + next_x] == 0
			):
				touches = true
		if not touches:
			continue
		wall_places.append(Vector3(x, 0.3, y))
		wall_colours.append(
				Color(0.98, 0.96, 0.9) if bright else Color(0.28, 0.31, 0.4))
	_fill(_floor.multimesh, floor_places, floor_colours)
	_fill(_walls.multimesh, wall_places, wall_colours)

	# Monsters only exist while you are looking at them. And for each one, look
	# BACK from where it stands: sight is not always mutual, and a blue monster
	# is one you can see that cannot see you.
	var foe_places: Array[Vector3] = []
	var foe_colours: Array[Color] = []
	var mine := _fov.lit.duplicate()
	one_way = 0
	for foe in _foes:
		if mine[foe.y * WIDTH + foe.x] != 1:
			continue
		_fov.look(mode, foe.x, foe.y, radius)
		var mutual: bool = _fov.is_visible(_hero.x, _hero.y)
		if not mutual:
			one_way += 1
		foe_places.append(Vector3(foe.x, 0.6, foe.y))
		foe_colours.append(Color(1.0, 0.42, 0.34) if mutual else Color(0.4, 0.7, 1.0))
	_fov.lit = mine
	_fill(_foe_mesh.multimesh, foe_places, foe_colours)
	_hero_mesh.position = Vector3(_hero.x, 0.6, _hero.y)


func _fill(multi_mesh: MultiMesh, places: Array[Vector3], colours: Array[Color]) -> void:
	multi_mesh.instance_count = places.size()
	for i in places.size():
		multi_mesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, places[i]))
		multi_mesh.set_instance_color(i, colours[i])


func _place_camera(delta: float) -> void:
	var want := (
			Vector3(WIDTH * 0.5, 0.0, HEIGHT * 0.5) if wide
			else Vector3(_hero.x, 0.0, _hero.y)
	)
	_eye = want + (_eye - want) * exp(-9.0 * delta)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = lerpf(_camera.size, 46.0 if wide else 22.0, 1.0 - exp(-7.0 * delta))
	_camera.position = _eye + Vector3(1.0, 1.0, 1.0).normalized() * 90.0
	_camera.look_at(_eye, Vector3.UP)


func _draw_hud() -> void:
	var names := ["no walls at all", "a line to every rim cell", "recursive shadowcasting"]
	var found := 0
	for foe in _foes:
		if _fov.is_visible(foe.x, foe.y):
			found += 1
	var known := 0
	for cell in _known:
		known += cell

	_lit_label.text = "%d  cells lit" % lit_now
	var text := "[b]%d  %s[/b]\n\n[table=2]" % [int(mode) + 1, names[int(mode)]]
	text += "[cell]radius  [/cell][cell]%d   (Q E)[/cell]" % radius
	text += "[cell]cost  [/cell][cell]%.0f us[/cell]" % look_usec
	text += "[cell]monsters in sight  [/cell][cell]%d of %d[/cell]" % [found, _foes.size()]
	text += "[cell]of those, blind to you  [/cell][cell]%d[/cell]" % one_way
	text += "[cell]map you have met  [/cell][cell]%d cells, %d steps[/cell]" % [known, steps]
	text += "[/table]\n\n"
	text += "bright = seen now      dim = remembered\n"
	text += "[color=#ff6a57]red[/color] sees you back    "
	text += "[color=#66b3ff]blue[/color] cannot — sight is not always mutual"
	_detail.text = text
