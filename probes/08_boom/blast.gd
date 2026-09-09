class_name BoomBlast
extends Node3D
## One explosion, built out of five layers that know nothing about each other.
##
## This is the part worth taking away before any of the Godot detail: an
## explosion is not an effect, it is a STACK of effects on different clocks.
## The flash is over in a tenth of a second, the fireball in half, the smoke
## outlives both by four times, the sparks fall while the rest rises. Every one
## of them can be switched off here, and switching them off one at a time is
## how you find out which one you were actually seeing.
##
## And the timing matters more than any texture. A white circle on the right
## curve reads as a blast; a photographed fireball on the wrong one does not.

enum Style {
	PHOTO,
	STYLISED,
}

## Built once for the whole game rather than once per explosion. A `static var`
## survives between instances, which is exactly what a shared texture wants.
static var _soft: ImageTexture
static var _hard: ImageTexture

@export var style: Style = Style.PHOTO

@export_group("Layers")
@export var flash_enabled := true
@export var fireball_enabled := true
@export var smoke_enabled := true
@export var sparks_enabled := true
@export var ring_enabled := true

@export_group("Timing")
## Each layer's own clock, in seconds. The spread between them IS the effect.
@export_range(0.02, 1.0, 0.01) var flash_life := 0.12
@export_range(0.05, 3.0, 0.05) var fireball_life := 0.55
@export_range(0.2, 8.0, 0.1) var smoke_life := 2.6
@export_range(0.1, 5.0, 0.1) var sparks_life := 1.4
@export_range(0.05, 3.0, 0.05) var ring_life := 0.5

## Seconds since this explosion was born.
var age := 0.0

@onready var _light: OmniLight3D = $Flash
@onready var _fire: GPUParticles3D = $Fireball
@onready var _smoke: GPUParticles3D = $Smoke
@onready var _sparks: GPUParticles3D = $Sparks
@onready var _ring: MeshInstance3D = $Ring


## A round blob. `hard` is where the edge falls: 0 fades from the centre, 0.8
## keeps it solid almost to the rim and then cuts.
static func _disc(size: int, hard: float) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var middle := float(size - 1) * 0.5
	for y in size:
		for x in size:
			var radius := Vector2(x - middle, y - middle).length() / middle
			var alpha := 1.0 - smoothstep(hard, 1.0, radius)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)


func _ready() -> void:
	if _soft == null:
		_soft = _disc(64, 0.0)  # a soft round smudge
		_hard = _disc(64, 0.82)  # a disc with an edge you can see
	_build()


func _process(delta: float) -> void:
	age += delta
	# Nothing here is told to stop; each layer simply runs out. The node goes
	# when the longest of them has finished.
	if age > maxf(smoke_life, sparks_life) + 0.6:
		queue_free()


## Which layers are alive right now. Read by the HUD, and the reason the probe
## is worth slowing down: at one tenth speed they stop overlapping.
func alive() -> Array[String]:
	var running: Array[String] = []
	if flash_enabled and age < flash_life:
		running.append("flash")
	if ring_enabled and age < ring_life:
		running.append("ring")
	if fireball_enabled and age < fireball_life:
		running.append("fire")
	if sparks_enabled and age < sparks_life:
		running.append("sparks")
	if smoke_enabled and age < smoke_life:
		running.append("smoke")
	return running


func _build() -> void:
	var stylised := style == Style.STYLISED
	var texture := _hard if stylised else _soft

	_light.visible = flash_enabled
	if flash_enabled:
		_light.light_energy = 14.0 if stylised else 9.0
		_light.light_color = Color(1.0, 0.72, 0.4)
		# A light is the cheapest layer and the one people never think of. It
		# is also the only one that touches the rest of the scene.
		var tween := create_tween()
		tween.tween_property(_light, "light_energy", 0.0, flash_life).set_trans(
				Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	_layer(_fire, fireball_enabled, {
		"tex": texture,
		"life": fireball_life,
		"amount": 14 if stylised else 90,
		"speed": Vector2(5.0, 9.0) if stylised else Vector2(3.0, 11.0),
		"scale": Vector2(1.6, 2.6) if stylised else Vector2(0.7, 1.7),
		"grow": 3.2 if stylised else 2.2,
		"gravity": Vector3(0.0, 1.5, 0.0),
		"add": true,
		# Never start an additive layer at white.
		#
		# Ninety soft discs piled on top of each other with additive blending
		# sum to well over 1.0 wherever they overlap, and everything above 1.0
		# is the same white. The first version began this ramp at (1, 0.97,
		# 0.85) and the result was a featureless white blob — the orange and the
		# red existed in the gradient and never once appeared on screen.
		#
		# Start warm and dim instead. Let the bright core come from the OVERLAP,
		# which is also where it comes from in a real fire.
		"ramp": ([
			Color(1.0, 0.78, 0.3, 0.85),
			Color(1.0, 0.42, 0.1, 0.7),
			Color(0.45, 0.09, 0.04, 0.0),
		] if stylised else [
			Color(1.0, 0.72, 0.34, 0.55),
			Color(1.0, 0.44, 0.14, 0.45),
			Color(0.55, 0.14, 0.05, 0.25),
			Color(0.1, 0.04, 0.03, 0.0),
		]),
	})

	_layer(_smoke, smoke_enabled, {
		"tex": texture,
		"life": smoke_life,
		"amount": 10 if stylised else 60,
		"speed": Vector2(1.2, 3.0),
		"scale": Vector2(2.6, 4.4) if stylised else Vector2(1.4, 3.2),
		"grow": 2.6,
		"gravity": Vector3(0.0, 1.1, 0.0),
		"add": false,
		"ramp": ([
			Color(0.2, 0.19, 0.19, 0.95),
			Color(0.14, 0.13, 0.14, 0.0),
		] if stylised else [
			Color(0.34, 0.28, 0.24, 0.0),
			Color(0.19, 0.18, 0.17, 0.75),
			Color(0.12, 0.12, 0.12, 0.0),
		]),
	})

	_layer(_sparks, sparks_enabled, {
		"tex": texture,
		"life": sparks_life,
		"amount": 12 if stylised else 50,
		"speed": Vector2(7.0, 16.0),
		"scale": Vector2(0.22, 0.4) if stylised else Vector2(0.08, 0.22),
		"grow": 0.4,
		# The only layer pulled DOWN. Everything else in an explosion rises;
		# sparks are the debris, and debris falls. That contrast is most of
		# what makes the whole thing look like it obeys physics.
		"gravity": Vector3(0.0, -14.0, 0.0),
		"add": true,
		"ramp": [
			Color(1.0, 0.88, 0.55, 0.9),
			Color(1.0, 0.5, 0.15, 0.7),
			Color(0.6, 0.12, 0.04, 0.0),
		],
	})

	_ring.visible = ring_enabled
	if ring_enabled:
		var material := _ring.material_override as ShaderMaterial
		material.set_shader_parameter("softness", 0.35 if stylised else 1.0)
		material.set_shader_parameter("thickness", 0.1 if stylised else 0.16)
		material.set_shader_parameter("refract", 0.06 if stylised else 0.03)
		material.set_shader_parameter("t", 0.0)
		var tween := create_tween()
		tween.tween_method(
				func(value: float) -> void: material.set_shader_parameter("t", value),
				0.0,
				1.0,
				ring_life).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


## Build one particle layer. Everything a layer is, is in this dictionary —
## which is the honest shape of the thing: a handful of numbers and two curves.
func _layer(node: GPUParticles3D, enabled: bool, config: Dictionary) -> void:
	node.emitting = false
	node.visible = enabled
	if not enabled:
		return

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.4
	process.spread = 180.0
	process.initial_velocity_min = config.speed.x
	process.initial_velocity_max = config.speed.y
	process.gravity = config.gravity
	process.damping_min = 1.5
	process.damping_max = 4.0
	process.scale_min = config.scale.x
	process.scale_max = config.scale.y
	process.angle_min = -180.0
	process.angle_max = 180.0
	# Size over life and colour over life. These two curves are where an
	# explosion actually lives; the texture is almost incidental next to them.
	process.scale_curve = _grow_curve(config.grow)
	process.color_ramp = _ramp(config.ramp)
	node.process_material = process

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = (
			BaseMaterial3D.BLEND_MODE_ADD if config.add
			else BaseMaterial3D.BLEND_MODE_MIX
	)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_texture = config.tex
	# Without this the colour ramp above is computed and thrown away.
	material.vertex_color_use_as_albedo = true
	material.disable_receive_shadows = true

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = material
	node.draw_pass_1 = quad

	node.amount = config.amount
	node.lifetime = config.life
	node.one_shot = true
	node.explosiveness = 1.0
	node.emitting = true


func _grow_curve(peak: float) -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.25))
	curve.add_point(Vector2(0.25, peak))
	curve.add_point(Vector2(1.0, peak * 0.75))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


func _ramp(colours: Array) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array()
	gradient.colors = PackedColorArray()
	for i in colours.size():
		gradient.add_point(float(i) / float(colours.size() - 1), colours[i])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture
