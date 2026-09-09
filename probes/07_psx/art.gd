class_name PsxArt
extends RefCounted
## TEXTURES AND PROPS OF THE ERA.
##
## The first version of this probe made do with a single checkerboard. As a
## test surface that is honest — perspective correction is invisible on flat
## colour and unmissable on a grid — but a player does not read it as a scene:
## "hard to take as PSX-era graphics, there were at least SOME objects with
## their own pixel textures". Fair, and not a complaint about the props:
## HALF OF WHAT MAKES THE ERA RECOGNISABLE LIVES IN THE TEXTURES, not in the
## artefacts of the rasteriser.
##
## What is imitated here, besides size:
##
## PALETTE. PSX textures were paletted: 4 bits gave sixteen colours, 8 bits two
## hundred and fifty six. That is not a detail. A narrow palette forces the
## artist to draw with CONTRAST rather than with shades, and that is where the
## poster-like look comes from.
##
## SIZE. 64x64 was the working size of the era and 256x256 the ceiling, while
## the texture was stretched across a whole wall — so the texel was large and
## you could see it. That is what "pixel texture" means: not a style, but a
## consequence of a megabyte of video memory.

## Every texture is this many pixels square.
const SIZE := 64
## Colours per channel. Four bits is what a PSX palette held.
const PALETTE := 16


## BRICK. Courses offset every other row, mortar between them, and a spread of
## tone per brick — without the spread a wall reads as wallpaper, because real
## masonry is never one colour.
static func brick(random: RandomNumberGenerator) -> ImageTexture:
	var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var course := 8
	var mortar := Color(0.42, 0.40, 0.37)
	for y in SIZE:
		var row := y / course
		var shift := 0 if row % 2 == 0 else 8
		for x in SIZE:
			var brick_x := (x + shift) % 16
			var colour := mortar
			if y % course >= 1 and brick_x >= 1:
				var shade := random.randf_range(-0.09, 0.09)
				colour = Color(
						0.52 + shade,
						0.30 + shade * 0.8,
						0.24 + shade * 0.7)
			image.set_pixel(x, y, _quantise(colour))
	return _texture(image)


## PLANKS. Vertical, with a dark seam and a lengthwise grain. A crate made of
## this reads as a crate even in twelve triangles — the silhouette does half
## the work and the texture the other half.
static func planks(random: RandomNumberGenerator) -> ImageTexture:
	var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for x in SIZE:
		var plank := x / 16
		var base := 0.40 + plank * 0.025 + random.randf_range(-0.02, 0.02)
		for y in SIZE:
			var colour := Color(0.16, 0.10, 0.06)
			if x % 16 >= 1:
				var grain := sin(float(y) * 0.9 + plank * 3.0) * 0.045
				grain += random.randf_range(-0.025, 0.025)
				# Wood is brown, not orange. At sixteen levels a saturated tone
				# drifts into pure orange and the crate stops being tellable
				# from the brick: a narrow palette forgives contrast but never
				# forgives saturation.
				var shade := base + grain
				colour = Color(shade, shade * 0.74, shade * 0.52)
			image.set_pixel(x, y, _quantise(colour))
	return _texture(image)


## CONCRETE. Blotches and a crack. The blotches are low-frequency noise, the
## crack a broken line: one noticeable feature per texture breaks the sense of
## repetition harder than many small ones.
static func concrete(random: RandomNumberGenerator, crack: bool = true) -> ImageTexture:
	var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = random.randi()
	noise.frequency = 0.09
	for y in SIZE:
		for x in SIZE:
			var blotch := noise.get_noise_2d(x, y) * 0.09
			var shade := 0.44 + blotch + random.randf_range(-0.015, 0.015)
			image.set_pixel(x, y, _quantise(Color(shade, shade * 0.99, shade * 0.95)))
	# No crack on the floor. That tile repeats dozens of times, and one
	# noticeable feature multiplied by a grid stops reading as a crack and
	# starts reading as wallpaper: a trick that works on a single wall turns on
	# itself across a large plane.
	if crack:
		var crack_x := random.randi_range(10, SIZE - 10)
		for y in SIZE:
			crack_x = clampi(crack_x + random.randi_range(-1, 1), 1, SIZE - 2)
			for offset in range(-1, 1):
				image.set_pixel(crack_x + offset, y, _quantise(Color(0.24, 0.24, 0.23)))
	return _texture(image)


## METAL. A panel with rivets at the corners and a band across the middle. The
## rivets are that large texel made visible: three pixels each, and on a wall
## they come out the size of a fist.
static func metal(random: RandomNumberGenerator) -> ImageTexture:
	var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y in SIZE:
		for x in SIZE:
			var shade := 0.30 + random.randf_range(-0.02, 0.02)
			if absi(y - SIZE / 2) < 3:
				shade = 0.22
			image.set_pixel(x, y, _quantise(Color(shade, shade * 1.02, shade * 1.08)))
	var corners := [
		Vector2i(6, 6),
		Vector2i(SIZE - 7, 6),
		Vector2i(6, SIZE - 7),
		Vector2i(SIZE - 7, SIZE - 7),
	]
	for corner in corners:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var lit := dx + dy < 0
				var colour := Color(0.52, 0.54, 0.58) if lit else Color(0.18, 0.19, 0.21)
				image.set_pixel(corner.x + dx, corner.y + dy, _quantise(colour))
	return _texture(image)


## THE SCENE. Not an endless plane with pillars but a corner of somewhere: an
## arch, a stack of crates, barrels, rubble. The point is not decoration — the
## props give the eye SCALE, without which it can judge neither the size of a
## texel nor the strength of the vertex wobble.
static func populate(world: Node3D, shader: Shader) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 19941203  # the console's Japanese release date
	var brick_material := _material(shader, brick(random), Vector2(4.0, 2.0))
	var wood_material := _material(shader, planks(random), Vector2(1.0, 1.0))
	var concrete_material := _material(shader, concrete(random), Vector2(1.0, 1.0))
	var metal_material := _material(shader, metal(random), Vector2(1.0, 1.0))

	# An arch in the gap.
	_box(world, brick_material, Vector3(-6.0, 1.6, -9.0), Vector3(0.9, 3.2, 0.9))
	_box(world, brick_material, Vector3(-2.4, 1.6, -9.0), Vector3(0.9, 3.2, 0.9))
	_box(world, brick_material, Vector3(-4.2, 3.5, -9.0), Vector3(4.5, 0.7, 0.9))

	# A stack of crates.
	_box(world, wood_material, Vector3(3.0, 0.55, -5.5), Vector3(1.1, 1.1, 1.1), 0.2)
	_box(world, wood_material, Vector3(4.2, 0.55, -5.2), Vector3(1.1, 1.1, 1.1), -0.35)
	_box(world, wood_material, Vector3(3.4, 1.65, -5.4), Vector3(1.1, 1.1, 1.1), 0.55)
	_box(world, wood_material, Vector3(6.4, 0.55, -7.4), Vector3(1.1, 1.1, 1.1), 0.9)

	# Barrels.
	_barrel(world, metal_material, Vector3(1.2, 0.0, -7.6), 0.3)
	_barrel(world, metal_material, Vector3(2.0, 0.0, -8.3), 1.1)
	_barrel(world, metal_material, Vector3(-7.6, 0.0, -4.2), 2.2)

	# A low wall and rubble.
	_box(world, concrete_material, Vector3(7.5, 0.6, -1.0), Vector3(0.6, 1.2, 7.0))
	for i in 9:
		var angle := random.randf_range(0.0, TAU)
		var radius := random.randf_range(2.0, 11.0)
		var size := random.randf_range(0.22, 0.55)
		_box(
				world,
				concrete_material,
				Vector3(cos(angle) * radius, size * 0.5, sin(angle) * radius - 4.0),
				Vector3(size, size * 0.7, size * 1.3),
				random.randf_range(0.0, TAU),
				random.randf_range(-0.3, 0.3))


## Snap a colour onto the palette. This is the whole of "paletted" for our
## purposes: the count of distinct values per channel, not an actual lookup
## table.
static func _quantise(colour: Color) -> Color:
	var span := float(PALETTE - 1)
	return Color(
			round(colour.r * span) / span,
			round(colour.g * span) / span,
			round(colour.b * span) / span)


static func _texture(image: Image) -> ImageTexture:
	return ImageTexture.create_from_image(image)


static func _material(shader: Shader, texture: ImageTexture, scale: Vector2) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("albedo_tex", texture)
	material.set_shader_parameter("albedo_smooth", texture)
	material.set_shader_parameter("uv_scale", scale)
	material.set_shader_parameter("tint", Color(1.0, 1.0, 1.0, 1.0))
	return material


static func _box(
		world: Node3D,
		material: ShaderMaterial,
		at: Vector3,
		size: Vector3,
		yaw: float = 0.0,
		pitch: float = 0.0) -> void:
	var box := BoxMesh.new()
	box.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = box
	instance.material_override = material
	instance.transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), at)
	world.add_child(instance)


static func _barrel(world: Node3D, material: ShaderMaterial, at: Vector3, yaw: float) -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.42
	cylinder.bottom_radius = 0.42
	cylinder.height = 1.15
	# Eight facets, not thirty: the console had no triangles to spare on round
	# sides, and a faceted barrel is not a simplification for speed — it is
	# literally what stood there.
	cylinder.radial_segments = 8
	cylinder.rings = 1
	var instance := MeshInstance3D.new()
	instance.mesh = cylinder
	instance.material_override = material
	instance.transform = Transform3D(
			Basis.from_euler(Vector3(0.0, yaw, 0.0)),
			at + Vector3(0.0, 0.575, 0.0))
	world.add_child(instance)
