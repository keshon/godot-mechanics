class_name MapWorld
extends Node3D
## 25 — a map is not one thing. There are two answers, and they are not interchangeable.
##
##   ЖИВАЯ    a second Camera3D inside a SubViewport, looking straight down, its texture
##            shown in the corner. The map is a RENDER OF THE WORLD. Free to author —
##            everything in the scene appears on it without a line of code — and always
##            correct, because it IS the world.
##
##   РИСОВАННАЯ  one Control._draw over the data of the world. The map is a DRAWING OF
##            WHAT THE PLAYER KNOWS. Costs a line per feature, but it can show what the
##            world does not have: fog, markers for things out of sight, an arrow at the
##            screen edge.
##
## The whole probe is the gap between "what is there" and "what you know is there". Fog
## of war is nearly free on one and awkward on the other, and it is the reason every
## game with exploration draws its map instead of filming it.

enum Kind {
	WATER,
	LAND,
	ROCK,
}

## The world is SIZE x SIZE cells.
const SIZE := 96
const CELL := 1.0
const SEED := 20260831

@export_range(6.0, 30.0) var walk := 12.0
@export_range(4.0, 40.0) var sight := 14.0
## 0 none, 1 explored only, 2 three states.
@export_range(0, 2) var fog_mode := 2
@export var live_map := true
@export var drawn_map := true
## SubViewport update: ALWAYS costs a full render every frame, even when nothing moved.
@export var live_always := true
## Third answer: bake what is known into an Image, one texel per cell, and draw ONE
## textured rect. Costs a rebake whenever the RULES change, but nothing per cell.
@export var baked := false
## Filter the fog layer instead of stepping it. One texel is one cell, so nearest gives a
## staircase at the edge of sight; linear turns it into a gradient at no cost at all.
@export var smooth_fog := true
## North up, or forward up. Two different promises: a fixed map teaches you the shape of
## the world, a turning one saves you the translation from map to hands. Every game with
## a minimap offers the choice, and it is not decoration — the two are read differently.
@export var rotate_map := false

var kind := PackedByteArray()
## 0 unknown, 1 explored, 2 visible right now.
var seen := PackedByteArray()
var pois: Array[Vector2] = []
## Where the player faces, radians, atan2(dz, dx).
var heading := 0.0
var explored := 0
## Smoothed GPU frame time, milliseconds.
var frame_ms := 0.0
var ground_texture: ImageTexture
var fog_texture: ImageTexture

var _ground_image: Image
var _fog_image: Image
var _fog_moved := false
var _showing_full := false
var _mini_size := 256
var _last_here := Vector2.ZERO
## Cells lit right now. Remembered, because "visible" has to be taken back explicitly.
var _lit := PackedInt32Array()

@onready var _player: MeshInstance3D = $Player
@onready var _camera: Camera3D = $Camera
@onready var _ground: MultiMeshInstance3D = $Ground
@onready var _info: RichTextLabel = $Ui/Info
@onready var _live: SubViewportContainer = $Ui/Live
@onready var _sub: SubViewport = $Ui/Live/Sub
@onready var _eye: Camera3D = $Ui/Live/Sub/Eye
@onready var _mini: MapView = $Ui/Mini
@onready var _full: MapView = $Ui/Big


func _ready() -> void:
	RenderingServer.viewport_set_measure_render_time(
			get_viewport().get_viewport_rid(), true)
	_generate()
	_build()
	_mini.world = self
	_full.world = self
	_bake_all()
	_apply()


func _process(delta: float) -> void:
	_move(delta)
	_reveal()
	frame_ms = lerpf(
			frame_ms,
			RenderingServer.viewport_get_measured_render_time_gpu(
					get_viewport().get_viewport_rid()),
			0.05)
	# The top-down camera of the live map has to be told where to look; the drawn one is
	# told the same thing as a number, and that is the only difference in driving them.
	# The live map turns by turning its CAMERA, the drawn one by turning the DRAWING:
	# same angle, two entirely different mechanisms, and both cost nothing.
	#
	# The .tscn writes a Basis by ROWS, not columns — building the top-down matrix by
	# hand gave a camera pointing at the sky, which renders as a pale square with no
	# error anywhere. rotation_degrees says the same thing and cannot be misread.
	_eye.rotation = Vector3(-PI * 0.5, map_turn(), 0.0)
	_eye.global_position = Vector3(
			_player.global_position.x, 60.0, _player.global_position.z)
	# UPDATE_ONCE means "draw once, then disable yourself". Setting it EVERY frame
	# re-arms it every frame, which is not a freeze at all — measured 1.63 ms against
	# 1.39 for honest per-frame updating, i.e. worse. A minimap does not need 200 fps:
	# redraw it when the player has actually gone somewhere.
	if not live_always:
		var here := Vector2(_player.global_position.x, _player.global_position.z)
		if here.distance_to(_last_here) > 1.5:
			_last_here = here
			_sub.render_target_update_mode = SubViewport.UPDATE_ONCE
	if _fog_moved:
		# Only the veil moves; the ground was baked once.
		fog_texture.update(_fog_image)
		_fog_moved = false
	for view in [_mini, _full]:
		view.player = Vector2(_player.global_position.x, _player.global_position.z)
		view.heading = heading
	_mini.queue_redraw()
	if _showing_full:
		_full.queue_redraw()
	_draw_hud()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		# NOT letters next to WASD — probes 21 and 23 both got caught by that.
		KEY_M:
			_showing_full = not _showing_full
			_apply()
		KEY_TAB:
			if live_map and drawn_map:
				drawn_map = false
			elif live_map:
				live_map = false
				drawn_map = true
			else:
				live_map = true
			_apply()
		KEY_1, KEY_2, KEY_3:
			fog_mode = event.keycode - KEY_1
			# Fog is baked in, so changing it means redoing the lot.
			_bake_all()
		KEY_B:
			baked = not baked
		KEY_V:
			smooth_fog = not smooth_fog
		KEY_N:
			rotate_map = not rotate_map
		KEY_F:
			live_always = not live_always
			_apply()
		KEY_Z:
			_mini_size = 128
			_apply()
		KEY_X:
			_mini_size = 256
			_apply()
		KEY_C:
			_mini_size = 512
			_apply()


## The one angle both maps need. Zero keeps north up; otherwise it is whatever turns the
## facing of the player into "up on the screen", which is heading rotated back a quarter.
func map_turn() -> float:
	if not rotate_map:
		return 0.0
	return -heading - PI * 0.5


## What covers a cell. Black and opaque where nothing is known, half-dark where it is
## only remembered, clear where it is seen right now.
func veil(x: int, y: int) -> Color:
	var state: int = seen[y * SIZE + x]
	if fog_mode == 0:
		return Color(0, 0, 0, 0)
	if state == 0:
		return Color(0.05, 0.06, 0.08, 1.0)
	if fog_mode == 2 and state == 1:
		return Color(0.02, 0.03, 0.05, 0.55)
	return Color(0, 0, 0, 0)


func tint(cell: Kind) -> Color:
	match cell:
		Kind.WATER:
			return Color(0.13, 0.31, 0.46)
		Kind.LAND:
			return Color(0.34, 0.46, 0.26)
	return Color(0.44, 0.42, 0.40)


func _generate() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = SEED
	var noise := FastNoiseLite.new()
	noise.seed = SEED
	noise.frequency = 0.028
	noise.fractal_octaves = 4
	kind.resize(SIZE * SIZE)
	seen.resize(SIZE * SIZE)
	for y in SIZE:
		for x in SIZE:
			var height := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			# A rim of water so the island reads as an island, not as a cropped field.
			var from_middle := Vector2(
					float(x) - SIZE * 0.5, float(y) - SIZE * 0.5).length() / (SIZE * 0.5)
			height -= smoothstep(0.62, 1.0, from_middle) * 0.55
			if height < 0.36:
				kind[y * SIZE + x] = Kind.WATER
			elif height > 0.70:
				kind[y * SIZE + x] = Kind.ROCK
			else:
				kind[y * SIZE + x] = Kind.LAND
	for _i in 12:
		for _try in 64:
			var at := Vector2i(
					random.randi_range(4, SIZE - 5), random.randi_range(4, SIZE - 5))
			if kind[at.y * SIZE + at.x] == Kind.LAND:
				pois.append(Vector2(at))
				break


## One MultiMesh for the whole board. 9216 boxes as separate nodes would be 9216 nodes;
## as instances it is one draw call, and probe 13 already paid for learning that.
func _build() -> void:
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3(CELL, 1.0, CELL)
	mesh.mesh = box
	mesh.instance_count = SIZE * SIZE
	for i in SIZE * SIZE:
		var cell: Kind = kind[i]
		var height := 0.2 if cell == Kind.WATER else (0.6 if cell == Kind.LAND else 1.5)
		mesh.set_instance_transform(i, Transform3D(
				Basis.IDENTITY.scaled(Vector3(1.0, height, 1.0)),
				Vector3(float(i % SIZE) * CELL, height * 0.5, float(i / SIZE) * CELL)))
		mesh.set_instance_color(i, tint(cell))
	_ground.multimesh = mesh
	_player.global_position = Vector3(SIZE * 0.5, 1.0, SIZE * 0.5)


## TWO images, not one. The ground never changes, so it is baked once and never touched
## again. Fog is its own layer over it — and that separation is the whole reason the edge
## of the seen circle can stop stepping by whole cells: a fog layer may be FILTERED, and
## ground may not (filtered ground turns crisp cells into mush).
func _bake_all() -> void:
	_ground_image = Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	_fog_image = Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			_ground_image.set_pixel(x, y, tint(kind[y * SIZE + x]))
			_fog_image.set_pixel(x, y, veil(x, y))
	ground_texture = ImageTexture.create_from_image(_ground_image)
	fog_texture = ImageTexture.create_from_image(_fog_image)


func _apply() -> void:
	# A SubViewportContainer with stretch on OWNS the size of its viewport, so resolution
	# is changed by resizing the container, not the viewport.
	var screen := get_viewport().get_visible_rect().size
	_live.size = Vector2(_mini_size, _mini_size)
	_live.position = Vector2(screen.x - _mini_size - 24.0, 24.0)
	_mini.size = Vector2(_mini_size, _mini_size)
	_mini.position = Vector2(
			screen.x - _mini_size - 24.0,
			24.0 + (_mini_size + 14.0 if live_map else 0.0))
	# THE lever on a live map, and the reason it is not free: a SubViewport set to ALWAYS
	# renders the whole world again every frame, whether or not anything moved.
	_sub.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if live_always else SubViewport.UPDATE_ONCE)
	_live.visible = live_map and not _showing_full
	_mini.visible = drawn_map and not _showing_full
	_full.visible = _showing_full


func _move(delta: float) -> void:
	var wanted := Vector3(
			Input.get_action_strength(&"move_right")
			- Input.get_action_strength(&"move_left"),
			0.0,
			Input.get_action_strength(&"move_back")
			- Input.get_action_strength(&"move_forward"))
	if wanted != Vector3.ZERO:
		# lerp_angle, not lerp: -3.1 and 3.1 are neighbours, and plain interpolation
		# would take the long way round every time the player crosses due north.
		heading = lerp_angle(heading, atan2(wanted.z, wanted.x), 1.0 - exp(-9.0 * delta))
		_player.global_position += wanted.normalized() * walk * delta
		_player.global_position.x = clampf(_player.global_position.x, 0.0, SIZE - 1.0)
		_player.global_position.z = clampf(_player.global_position.z, 0.0, SIZE - 1.0)
	# The camera is a follower, not a parent: parenting it would inherit rotation too.
	_camera.global_position = _player.global_position + Vector3(0.0, 26.0, 20.0)


## Exploration. Only the disc around the player is touched — walking all 9216 cells every
## frame would cost more than everything else in this probe together.
##
## But demoting "visible" back to "explored" by rescanning a box around the player only
## works while the player moves slower than the box. Move faster once and a stripe of
## cells stays lit for good — which is exactly what the first screenshot showed. So the
## lit set is REMEMBERED and cleared explicitly. State that must be undone cannot be
## rediscovered from position alone.
func _reveal() -> void:
	for i in _lit:
		if seen[i] == 2:
			_set_seen(i, 1)
	_lit.clear()
	# Distance from the REAL position of the player, not from the nearest cell centre.
	# With round() the whole disc teleported a cell at a time: measured 82 % of frames
	# with no change at all, then a burst of up to 1226 cells — the old circle going out
	# and the new one coming on, together. Diagonally the two axes snap out of step,
	# which is what makes it read as stutter rather than as motion.
	var at := Vector2(_player.global_position.x, _player.global_position.z)
	var reach := int(ceil(sight)) + 1
	for y in range(maxi(int(at.y) - reach, 0), mini(int(at.y) + reach + 1, SIZE)):
		for x in range(maxi(int(at.x) - reach, 0), mini(int(at.x) + reach + 1, SIZE)):
			if Vector2(float(x) - at.x, float(y) - at.y).length() > sight:
				continue
			var i := y * SIZE + x
			if seen[i] == 0:
				explored += 1
			_set_seen(i, 2)
			_lit.append(i)


func _set_seen(index: int, state: int) -> void:
	if seen[index] == state:
		return
	seen[index] = state
	if _fog_image == null:
		return
	_fog_image.set_pixel(index % SIZE, index / SIZE, veil(index % SIZE, index / SIZE))
	_fog_moved = true


func _draw_hud() -> void:
	var which := "[color=#7fe08a]большая[/color]"
	if not _showing_full:
		which = "мини: %s%s" % [
			"[color=#7fe08a]живая[/color] " if live_map else "",
			"[color=#ffd479]рисованная[/color]" if drawn_map else ""]
	var text := "[b]КАРТА[/b]    %s\n\n[table=2]" % which
	text += "[cell]мир  [/cell][cell]%d×%d клеток[/cell]" % [SIZE, SIZE]
	text += "[cell]исследовано  [/cell][cell]%d из %d  (%.0f%%)[/cell]" % [
		explored, SIZE * SIZE, 100.0 * explored / float(SIZE * SIZE)]
	text += "[cell]живая карта  [/cell][cell]%d×%d, обновление %s[/cell]" % [
		_mini_size, _mini_size,
		"[color=#ff8a6a]каждый кадр[/color]" if live_always
		else "[color=#7fe08a]замерла[/color]"]
	text += "[cell]миникарта  [/cell][cell]%s[/cell]" % (
			"[color=#7fe08a]вращается по взгляду[/color]" if rotate_map
			else "[color=#ffd479]север всегда вверх[/color]")
	text += "[cell]кромка видимости  [/cell][cell]%s[/cell]" % (
			"[color=#7fe08a]сглажена[/color]" if smooth_fog
			else "[color=#ffd479]ступеньками[/color]")
	text += "[cell]рисованная карта  [/cell][cell]%s[/cell]" % (
			"[color=#7fe08a]запечена: одна текстура[/color]" if baked
			else "[color=#ffd479]по клетке за раз[/color]")
	text += "[cell]туман  [/cell][cell]%s[/cell]" % [
		"нет", "только исследованное", "три состояния"][fog_mode]
	text += "[cell]кадр  [/cell][cell]%.2f мс на GPU[/cell]" % frame_ms
	text += "[/table]\n\n"
	text += "WASD — ходить    M — большая карта    TAB — какая миникарта\n"
	text += "1 2 3 — туман    F — живая карта реже    B — запечь рисованную\n"
	text += "Z X C — 128 / 256 / 512    V — сгладить кромку    N — север/по взгляду\n"
	text += "[color=#66ccff]живая показывает, ЧТО ЕСТЬ. рисованная — что ты ЗНАЕШЬ.[/color]"
	_info.text = text
