class_name PsxLook
extends Node
## A style is a set of constraints, not a set of assets.
##
## Every switch below removes something a modern renderer gives you for free.
## Turn them all off and this is a plain, slightly ugly Godot scene. Turn them
## on one at a time and watch which one you were actually reacting to — that is
## the whole exercise, and it is worth doing in that order rather than looking
## at the finished thing and calling it "PSX".
##
## Nothing here is nostalgia. Each constraint is a different part of the
## pipeline: the viewport, the vertex stage, the interpolator, the post pass.

@export_group("Resolution")
## How many times smaller than the window the world is actually drawn, before
## being blown up again with no smoothing. The single biggest contributor to
## the look, and the cheapest thing in the entire probe.
##
## Godot does this with SubViewportContainer.stretch_shrink rather than a fixed
## pixel size: a divisor keeps the aspect ratio honest whatever the window does.
@export_range(1, 12, 1) var shrink := 4:
	set(value):
		shrink = value
		if is_inside_tree():
			_screen.stretch_shrink = value
			# The snap grid is measured in rendered pixels, so it moves too, and
			# the scanline period is in window pixels per rendered row.
			_push_geometry()
			_push_colour()

@export_group("Geometry")
@export var snap_vertices := true:
	set(value):
		snap_vertices = value
		_push_geometry()

## How coarse the vertex grid is, measured in rendered pixels.
##
## 1.0 is the honest setting: one step per pixel, which is all the precision
## the hardware had. That gives a wobble you notice but do not fight.
##
## The first version of this probe hard-coded the grid at 160x120 while the
## viewport was 250x140 — a step and a half per pixel, so about three times too
## much, and the floor under your feet boiled. Wrong, not stylised.
@export_range(0.25, 6.0, 0.05) var snap_coarseness := 1.0:
	set(value):
		snap_coarseness = value
		_push_geometry()

## How finely the floor is cut up, in pieces per side.
##
## Not decoration. Affine warping is proportional to how big a triangle is on
## screen, so a seventy-metre floor made of two triangles is the worst case
## there is. Games of the era chopped their geometry into small pieces
## precisely because of this — dense floors and sliced-up walls were the
## ARTISTS' answer to the hardware, and half of what the era looks like.
##
## Set this to 0 and the floor becomes two triangles again. That is what the
## first version of this probe shipped, and it is why the swim looked so much
## coarser than the console ever did.
@export_range(0, 60, 1) var floor_subdivide := 30:
	set(value):
		floor_subdivide = value
		if is_inside_tree():
			var plane := ($Screen/View/World/Floor as MeshInstance3D).mesh as PlaneMesh
			plane.subdivide_width = value
			plane.subdivide_depth = value

## Textures interpolated without perspective correction — the swim.
@export var affine_uv := true:
	set(value):
		affine_uv = value
		_push_geometry()

## Bilinear texture filtering: what a PS2 did when running a PS1 disc. Same
## geometry, same wobble, smooth textures. Immediately of the wrong decade.
@export var smooth_textures := false:
	set(value):
		smooth_textures = value
		_push_geometry()

@export_group("Colour")
## Distinct values per colour channel.
@export_range(2, 256, 1) var levels := 32:
	set(value):
		levels = value
		_push_colour()

@export var dither := true:
	set(value):
		dither = value
		_push_colour()

@export var scanlines := false:
	set(value):
		scanlines = value
		_push_colour()

@export_range(0.0, 0.6, 0.01) var scanline_strength := 0.18:
	set(value):
		scanline_strength = value
		_push_colour()

## THE FINAL PASS: vignette, a slight tube curve, colour smeared along the row.
## Not one of the three has anything to do with the console — all three were
## done by the SCREEN. But they are what pulls a set of separate tricks into one
## image: without them the frame looks like a list of artefacts, with them it
## looks like a television.
@export var crt := false:
	set(value):
		crt = value
		_push_colour()

@export var post_enabled := true:
	set(value):
		post_enabled = value
		if is_inside_tree():
			_post.visible = value

@export_group("Camera")
## How fast the free camera flies, m/s. Shift multiplies it by three.
@export_range(1.0, 40.0, 0.5) var fly_speed := 7.0
## Radians of rotation per pixel of mouse motion.
@export_range(0.0005, 0.01, 0.0001) var mouse_sensitivity := 0.0025

var _materials: Array[ShaderMaterial] = []
var _yaw := 0.0
var _pitch := 0.0

@onready var _screen: SubViewportContainer = $Screen
@onready var _view: SubViewport = $Screen/View
@onready var _post: ColorRect = $Screen/View/Post
## The display pass, outside the viewport and over the blown-up picture.
@onready var _display: ColorRect = $Scanlines
@onready var _camera: Camera3D = $Screen/View/World/Camera
@onready var _world: Node3D = $Screen/View/World


func _ready() -> void:
	_screen.stretch_shrink = shrink
	_dress_world()
	# Assigning a property to itself looks like a mistake and is not: the setter
	# above is what pushes the value into the floor mesh, and it could not run
	# during export because the tree was not up yet.
	floor_subdivide = floor_subdivide
	_yaw = _camera.rotation.y
	_pitch = _camera.rotation.x
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_push_geometry()
	_push_colour()
	_post.visible = post_enabled


func _process(delta: float) -> void:
	var input: Vector2 = Input.get_vector(
			&"move_left", &"move_right", &"move_forward", &"move_back")
	var lift := 1.0 if Input.is_action_pressed(&"jump") else 0.0
	var direction := _camera.global_basis * Vector3(input.x, 0.0, input.y) + Vector3.UP * lift
	var rush := 3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
	_camera.global_position += direction * fly_speed * rush * delta


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clampf(
				_pitch - event.relative.y * mouse_sensitivity,
				-deg_to_rad(89.0),
				deg_to_rad(89.0))
		_camera.rotation = Vector3(_pitch, _yaw, 0.0)
	elif event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1: snap_vertices = not snap_vertices
		KEY_2: affine_uv = not affine_uv
		KEY_3: post_enabled = not post_enabled
		KEY_4: dither = not dither
		KEY_5: shrink = 1 if shrink > 1 else 4
		KEY_6: smooth_textures = not smooth_textures
		KEY_7: scanlines = not scanlines
		KEY_8: floor_subdivide = 0 if floor_subdivide > 0 else 30
		KEY_9: crt = not crt


## The viewport the world is drawn into, before it is blown up. Handed out
## rather than found, so the HUD does not have to know this node's layout.
func viewport() -> SubViewport:
	return _view


## Textures and props, all of them from PsxArt.
##
## The checkerboard the probe started with was an honest test surface —
## perspective correction is invisible on flat colour and unmissable on a grid
## — but it does not read as a scene of the era. Half of what makes PSX
## recognisable lives in paletted textures and familiar objects, not in the
## artefacts of the rasteriser.
func _dress_world() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 4242
	var floor_texture := PsxArt.concrete(random, false)
	var wall_texture := PsxArt.brick(random)
	var prop_texture := PsxArt.metal(random)
	for mesh in _world.find_children("*", "MeshInstance3D"):
		var material := mesh.material_override as ShaderMaterial
		if material == null or _materials.has(material):
			continue
		var texture := prop_texture
		var scale := Vector2(3.0, 2.0)
		if mesh.name == "Floor":
			texture = floor_texture
			# Seventy metres across ten repeats: an eleven-centimetre texel,
			# exactly the coarse texel the console made you SEE.
			scale = Vector2(10.0, 10.0)
		elif mesh.name.begins_with("Wall"):
			texture = wall_texture
			# The wall is seventy metres by seven. Count from the brick rather
			# than from the wall: four bricks across a tile and eight rows down,
			# a brick half a metre, so a two-metre tile — 35 repeats along and
			# 3.5 up. It stood at 8 x 3, and the bricks came out two metres wide.
			scale = Vector2(35.0, 3.5)
		material.set_shader_parameter("albedo_tex", texture)
		material.set_shader_parameter("albedo_smooth", texture)
		material.set_shader_parameter("uv_scale", scale)
		_materials.append(material)

	# The props arrive with their own materials and have to obey the keys too.
	#
	# THE FOURTH ARGUMENT OF `find_children` IS `owned`, AND IT DEFAULTS TO
	# TRUE. Only nodes saved in the scene have an owner; anything added from
	# code through `add_child` has none and NEVER APPEARS in the result. The
	# walk above quietly returned the original walls and pillars only, the
	# materials of the arch, the crates and the barrels never reached
	# `_materials`, and the keys did nothing to them: the props stood with
	# default shader parameters and did not dim along with the scene.
	var shader: Shader = _materials[0].shader
	PsxArt.populate(_world, shader)
	for mesh in _world.find_children("*", "MeshInstance3D", true, false):
		var material := mesh.material_override as ShaderMaterial
		if material != null and not _materials.has(material):
			_materials.append(material)


## Everything in the Geometry group, into every world material.
func _push_geometry() -> void:
	if not is_inside_tree():
		return
	# One step of the grid lands on exactly one rendered pixel: normalised
	# device space runs -1..1 across `size` pixels, so the grid is size/2.
	var grid := Vector2(_view.size) * 0.5 / maxf(snap_coarseness, 0.01)
	for material in _materials:
		material.set_shader_parameter("snap_grid", grid)
		material.set_shader_parameter("snap_vertices", snap_vertices)
		material.set_shader_parameter("affine_uv", affine_uv)
		material.set_shader_parameter("smooth_textures", smooth_textures)


## Everything in the Colour group, into the two full-screen passes.
func _push_colour() -> void:
	if not is_inside_tree():
		return
	var post_material := _post.material as ShaderMaterial
	post_material.set_shader_parameter("levels", levels)
	post_material.set_shader_parameter("dither", dither)

	var display_material := _display.material as ShaderMaterial
	display_material.set_shader_parameter("scanlines", scanlines)
	display_material.set_shader_parameter("scanline_strength", scanline_strength)
	# The scanline period is in WINDOW pixels per RENDERED row, which is exactly
	# the shrink factor. It was a hard-coded 2, tied to the monitor pixel: at a
	# 900-row screen the pattern came out finer than the eye can separate and
	# read as nothing but a dimming.
	display_material.set_shader_parameter("scan_period", float(shrink))
	display_material.set_shader_parameter("crt", crt)
	# A full-screen pass that does nothing still copies every pixel. Hide it
	# rather than let it run as an expensive no-op.
	_display.visible = scanlines or crt
