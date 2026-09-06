extends Node3D

# 25 — a map is not one thing. There are two answers, and they are not interchangeable.
#
#   ЖИВАЯ    a second Camera3D inside a SubViewport, looking straight down, its texture
#            shown in the corner. The map is a RENDER OF THE WORLD. Free to author —
#            everything in the scene appears on it without a line of code — and always
#            correct, because it IS the world.
#
#   РИСОВАННАЯ  one Control._draw over the world's data. The map is a DRAWING OF WHAT THE
#            PLAYER KNOWS. Costs a line per feature, but it can show what the world does
#            not have: fog, markers for things out of sight, an arrow at the screen edge.
#
# The whole probe is the gap between "what is there" and "what you know is there".
# Fog of war is nearly free on one and awkward on the other, and it is the reason
# every game with exploration draws its map instead of filming it.

const N := 96          ## world is N x N cells
const CELL := 1.0
const WATER := 0
const LAND := 1
const ROCK := 2
const SEED := 20260831

@export_range(6.0, 30.0) var walk := 12.0
@export_range(4.0, 40.0) var sight := 14.0
## 0 none, 1 explored only, 2 three states
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
## the world, a turning one saves you the translation from map to hands. Every game with a
## minimap offers the choice, and it is not decoration — the two are read differently.
@export var rotate_map := false

var kind := PackedByteArray()
var seen := PackedByteArray()   ## 0 unknown, 1 explored, 2 visible right now
var pois: Array[Vector2] = []
var ms_now := 0.0
var explored := 0

var _map: MapView
var _big := false
var _mini := 256
var _img: Image
var _fog: Image
var fog_tex: ImageTexture
var _dirty := false
var _last := Vector2.ZERO
var _lit := PackedInt32Array()
var heading := 0.0     ## where the player faces, radians, atan2(dz, dx)
var tex: ImageTexture


func _ready() -> void:
	_map = $Ui/Mini as MapView
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_generate()
	_build()
	_map.world = self
	($Ui/Big as MapView).world = self
	_bake_all()
	_apply()


func _generate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var n := FastNoiseLite.new()
	n.seed = SEED
	n.frequency = 0.028
	n.fractal_octaves = 4
	kind.resize(N * N)
	seen.resize(N * N)
	for y in N:
		for x in N:
			var h := n.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			# a rim of water so the island reads as an island, not as a cropped field
			var d := Vector2(float(x) - N * 0.5, float(y) - N * 0.5).length() / (N * 0.5)
			h -= smoothstep(0.62, 1.0, d) * 0.55
			kind[y * N + x] = WATER if h < 0.36 else (ROCK if h > 0.70 else LAND)
	for _i in 12:
		for _try in 64:
			var p := Vector2i(rng.randi_range(4, N - 5), rng.randi_range(4, N - 5))
			if kind[p.y * N + p.x] == LAND:
				pois.append(Vector2(p))
				break


## One MultiMesh for the whole board. 9216 boxes as separate nodes would be 9216 nodes;
## as instances it is one draw call, and probe 13 already paid for learning that.
func _build() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3(CELL, 1.0, CELL)
	mm.mesh = box
	mm.instance_count = N * N
	for i in N * N:
		var x := i % N
		var y := i / N
		var k := kind[i]
		var h := 0.2 if k == WATER else (0.6 if k == LAND else 1.5)
		mm.set_instance_transform(i, Transform3D(
			Basis.IDENTITY.scaled(Vector3(1.0, h, 1.0)),
			Vector3(float(x) * CELL, h * 0.5, float(y) * CELL)))
		mm.set_instance_color(i, tint(k))
	($Ground as MultiMeshInstance3D).multimesh = mm
	$Player.global_position = Vector3(N * 0.5, 1.0, N * 0.5)


## TWO images, not one. The ground never changes, so it is baked once and never touched
## again. Fog is its own layer over it — and that separation is the whole reason the edge
## of the seen circle can stop stepping by whole cells: a fog layer may be FILTERED, and
## ground may not (filtered ground turns crisp cells into mush).
func _bake_all() -> void:
	_img = Image.create_empty(N, N, false, Image.FORMAT_RGBA8)
	_fog = Image.create_empty(N, N, false, Image.FORMAT_RGBA8)
	for y in N:
		for x in N:
			_img.set_pixel(x, y, tint(kind[y * N + x]))
			_fog.set_pixel(x, y, veil(x, y))
	tex = ImageTexture.create_from_image(_img)
	fog_tex = ImageTexture.create_from_image(_fog)


## What covers a cell. Black and opaque where nothing is known, half-dark where it is only
## remembered, clear where it is seen right now.
func veil(x: int, y: int) -> Color:
	var s: int = seen[y * N + x]
	if fog_mode == 0:
		return Color(0, 0, 0, 0)
	if s == 0:
		return Color(0.05, 0.06, 0.08, 1.0)
	return Color(0.02, 0.03, 0.05, 0.55) if fog_mode == 2 and s == 1 else Color(0, 0, 0, 0)


## Colour of one cell for the per-cell path, fog folded in.
func shade(x: int, y: int) -> Color:
	var s: int = seen[y * N + x]
	if fog_mode > 0 and s == 0:
		return Color(0.05, 0.06, 0.08)
	var c := tint(kind[y * N + x])
	return c.darkened(0.55) if fog_mode == 2 and s == 1 else c


func tint(k: int) -> Color:
	if k == WATER:
		return Color(0.13, 0.31, 0.46)
	return Color(0.34, 0.46, 0.26) if k == LAND else Color(0.44, 0.42, 0.40)


func _apply() -> void:
	var sub: SubViewport = $Ui/Live/Sub
	# A SubViewportContainer with stretch on OWNS its viewport's size, so resolution is
	# changed by resizing the container, not the viewport.
	var vp := get_viewport().get_visible_rect().size
	($Ui/Live as SubViewportContainer).size = Vector2(_mini, _mini)
	$Ui/Live.position = Vector2(vp.x - _mini - 24.0, 24.0)
	($Ui/Mini as Control).size = Vector2(_mini, _mini)
	$Ui/Mini.position = Vector2(vp.x - _mini - 24.0, 24.0 + (_mini + 14.0 if live_map else 0.0))
	# THE lever on a live map, and the reason it is not free: a SubViewport set to ALWAYS
	# renders the whole world again every frame, whether or not anything moved.
	sub.render_target_update_mode = (SubViewport.UPDATE_ALWAYS if live_always
		else SubViewport.UPDATE_ONCE)
	$Ui/Live.visible = live_map and not _big
	$Ui/Mini.visible = drawn_map and not _big
	$Ui/Big.visible = _big


func _process(delta: float) -> void:
	_move(delta)
	_reveal()
	ms_now = lerpf(ms_now,
		RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()),
		0.05)
	# the top-down camera of the live map has to be told where to look; the drawn one is
	# told the same thing as a number, and that is the only difference in driving them
	# The .tscn writes a Basis by ROWS, not columns — I built the top-down matrix by hand
	# and got a camera pointing at the sky, which renders as a pale square with no error
	# anywhere. rotation_degrees says the same thing and cannot be misread.
	# The live map turns by turning its CAMERA; the drawn one turns by turning the DRAWING.
	# Same angle, two entirely different mechanisms, and both cost nothing.
	var eye: Camera3D = $Ui/Live/Sub/Eye
	eye.rotation = Vector3(-PI * 0.5, map_turn(), 0.0)
	eye.global_position = Vector3(
		$Player.global_position.x, 60.0, $Player.global_position.z)
	# UPDATE_ONCE means "draw once, then disable yourself". Setting it EVERY frame re-arms
	# it every frame, which is not a freeze at all — measured 1.63 ms against 1.39 for
	# honest per-frame updating, i.e. worse. A minimap does not need 200 fps: redraw it
	# when the player has actually gone somewhere.
	if not live_always:
		var here := Vector2($Player.global_position.x, $Player.global_position.z)
		if here.distance_to(_last) > 1.5:
			_last = here
			($Ui/Live/Sub as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
	if _dirty:
		fog_tex.update(_fog)      # only the veil moves; the ground was baked once
		_dirty = false
	_map.queue_redraw()
	if _big:
		($Ui/Big as MapView).queue_redraw()
	_hud()


## The one angle both maps need. Zero keeps north up; otherwise it is whatever turns the
## player's facing into "up on the screen", which is heading rotated back by a quarter turn.
func map_turn() -> float:
	return 0.0 if not rotate_map else -heading - PI * 0.5


func _move(delta: float) -> void:
	var v := Vector3(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		0.0,
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward"))
	if v != Vector3.ZERO:
		var p: Node3D = $Player
		# lerp_angle, not lerp: -3.1 and 3.1 are neighbours, and plain interpolation would
		# take the long way round every time the player crosses due north.
		heading = lerp_angle(heading, atan2(v.z, v.x), 1.0 - exp(-9.0 * delta))
		p.global_position += v.normalized() * walk * delta
		p.global_position.x = clampf(p.global_position.x, 0.0, float(N - 1))
		p.global_position.z = clampf(p.global_position.z, 0.0, float(N - 1))
	# the camera is a follower, not a parent: parenting it would inherit rotation too
	($Cam as Camera3D).global_position = $Player.global_position + Vector3(0.0, 26.0, 20.0)


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
	# Distance from the player's REAL position, not from the nearest cell centre. With
	# round() the whole disc teleported a cell at a time: measured 82% of frames with no
	# change at all, then a burst of up to 1226 cells — the old circle going out and the
	# new one coming on, together. Diagonally the two axes snap out of step, which is what
	# makes it read as stutter rather than as motion.
	var p := Vector2($Player.global_position.x, $Player.global_position.z)
	var r := int(ceil(sight)) + 1
	for y in range(maxi(int(p.y) - r, 0), mini(int(p.y) + r + 1, N)):
		for x in range(maxi(int(p.x) - r, 0), mini(int(p.x) + r + 1, N)):
			if Vector2(float(x) - p.x, float(y) - p.y).length() > sight:
				continue
			var i := y * N + x
			if seen[i] == 0:
				explored += 1
			_set_seen(i, 2)
			_lit.append(i)


func _set_seen(i: int, v: int) -> void:
	if seen[i] == v:
		return
	seen[i] = v
	if _fog != null:
		_fog.set_pixel(i % N, i / N, veil(i % N, i / N))
		_dirty = true


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		# NOT letters next to WASD — probe 21 and 23 both got caught by that.
		KEY_M:
			_big = not _big
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
			_bake_all()      # fog is baked in, so changing it means redoing the lot
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
			_mini = 128
			_apply()
		KEY_X:
			_mini = 256
			_apply()
		KEY_C:
			_mini = 512
			_apply()


func _hud() -> void:
	var t := "[b]КАРТА[/b]    %s\n\n" % ("[color=#7fe08a]большая[/color]" if _big
		else "мини: %s%s" % [
			"[color=#7fe08a]живая[/color] " if live_map else "",
			"[color=#ffd479]рисованная[/color]" if drawn_map else ""])
	t += "[table=2]"
	t += "[cell]мир  [/cell][cell]%d×%d клеток[/cell]" % [N, N]
	t += "[cell]исследовано  [/cell][cell]%d из %d  (%.0f%%)[/cell]" % [
		explored, N * N, 100.0 * explored / float(N * N)]
	t += "[cell]живая карта  [/cell][cell]%d×%d, обновление %s[/cell]" % [_mini, _mini,
		"[color=#ff8a6a]каждый кадр[/color]" if live_always else "[color=#7fe08a]замерла[/color]"]
	t += "[cell]миникарта  [/cell][cell]%s[/cell]" % (
		"[color=#7fe08a]вращается по взгляду[/color]" if rotate_map
		else "[color=#ffd479]север всегда вверх[/color]")
	t += "[cell]кромка видимости  [/cell][cell]%s[/cell]" % (
		"[color=#7fe08a]сглажена[/color]" if smooth_fog else "[color=#ffd479]ступеньками[/color]")
	t += "[cell]рисованная карта  [/cell][cell]%s[/cell]" % (
		"[color=#7fe08a]запечена: одна текстура[/color]" if baked
		else "[color=#ffd479]по клетке за раз[/color]")
	t += "[cell]туман  [/cell][cell]%s[/cell]" % ["нет", "только исследованное",
		"три состояния"][fog_mode]
	t += "[cell]кадр  [/cell][cell]%.2f мс на GPU[/cell]" % ms_now
	t += "[/table]\n\n"
	t += "WASD — ходить    M — большая карта    TAB — какая миникарта\n"
	t += "1 2 3 — туман    F — живая карта реже    B — запечь рисованную\n"
	t += "Z X C — 128 / 256 / 512    V — сгладить кромку    N — север/по взгляду\n"
	t += "[color=#66ccff]живая показывает, ЧТО ЕСТЬ. рисованная — что ты ЗНАЕШЬ.[/color]"
	$Ui/Info.text = t
