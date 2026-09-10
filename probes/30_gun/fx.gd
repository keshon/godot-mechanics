class_name GunFx
extends Node3D
## Everything a shot leaves behind, and all of it POOLED. A rifle fires ten times a second
## and each shot spawns four things; at that rate the cost is not drawing them, it is
## CREATING them. Everything here is made once and handed out oldest-first.
##
## The pool size is not an optimisation, it is a DESIGN DECISION with a visible
## consequence: a wall holds as many holes as there are decals, and the oldest goes when
## the next comes.

const DECALS := 64
const SHELLS := 28
## Отдельный слой для латуни: см. комментарий в её создании.
const SHELL_LAYER := 1 << 4
const SPARKS := 10
## Поперечник дырки, метры, на глаз: настоящая пробоина мельче, но след от неё — с
## выкрошенным краем и копотью — читается примерно так.
const HOLE := 0.2
const TRACERS := 8
## A tracer is a BURNING ROUND IN FLIGHT, not a lit-up trajectory. The first version drew
## the whole path at once, and it read exactly as what it was: a fan of bright rods with
## its apex in the face of the player. A round crosses a fifteen-metre room in three
## frames, and three frames of a short segment is what the eye calls a streak.
const TRACER_SPEED := 150.0
const TRACER_LEN := 3.0
## Where the streak becomes visible, in metres from the muzzle. NOT zero, and this is the
## fix for "the tracers are crooked and you can see it when the camera moves": the muzzle
## sits twenty centimetres right of the eye, so a segment drawn AT the muzzle and aimed at
## a point on the crosshair axis is visibly skewed, and the skew swings with every turn of
## the head. Two metres out the parallax is gone and the round simply goes where it goes.
## You never see a real tracer at the muzzle anyway — it is inside the flash.
const TRACER_START := 2.0

var _decals: Array[Decal] = []
var _shells: Array[RigidBody3D] = []
var _sparks: Array[GPUParticles3D] = []
var _spark_materials: Array[ShaderMaterial] = []
var _tracers: Array[MeshInstance3D] = []
var _tracer_from := PackedVector3Array()
var _tracer_dir := PackedVector3Array()
## How far this tracer has to fly, metres.
var _tracer_far := PackedFloat32Array()
## When it left the muzzle, seconds on the local clock. -1 means the slot is free.
var _tracer_born := PackedFloat32Array()
var _decal_at := 0
var _shell_at := 0
var _spark_at := 0
var _tracer_at := 0
var _clock := 0.0


func _ready() -> void:
	var hole := _make_hole()
	for i in DECALS:
		var decal := Decal.new()
		decal.texture_albedo = hole
		# X and Z are the FOOTPRINT on the wall; Y is how deep the box reaches to find a
		# surface to project onto. Confusing the three is what made stripes.
		decal.size = Vector3(HOLE, 0.3, HOLE)
		decal.upper_fade = 0.4
		decal.lower_fade = 0.4
		decal.visible = false
		add_child(decal)
		_decals.append(decal)
	_make_shells()
	_make_sparks()
	_make_tracers()


func _process(delta: float) -> void:
	_clock += delta
	for i in TRACERS:
		# `visible` is NOT the liveness flag, and using it as one cost the whole feature.
		# In the first frame the round has flown less than TRACER_START, so there is
		# nothing to draw YET — and hiding it then made the loop skip that slot for good.
		# On a 60 Hz machine the round cleared two metres in the first frame and it
		# worked; on a 200 Hz one it never did. A state that means "not yet" must not
		# share a flag with one that means "done".
		if _tracer_born[i] < 0.0:
			continue
		var flown := (_clock - _tracer_born[i]) * TRACER_SPEED
		if flown - TRACER_LEN >= _tracer_far[i]:
			# Arrived: the slot is free again.
			_tracer_born[i] = -1.0
			_tracers[i].visible = false
			continue
		var head: float = minf(flown, _tracer_far[i])
		var tail: float = maxf(
				maxf(flown - TRACER_LEN, 0.0), minf(TRACER_START, _tracer_far[i]))
		if head <= tail:
			# Not yet out of the muzzle glow — still alive.
			_tracers[i].visible = false
			continue
		_tracers[i].visible = true
		var back := _tracer_from[i] + _tracer_dir[i] * tail
		var front := _tracer_from[i] + _tracer_dir[i] * head
		# BUILT BY COLUMNS, not by `looking_at().scaled()`. Basis.scaled() multiplies the
		# basis ROWS, which means it scales along the axes of the PARENT, not along the
		# local ones: asking for "longer in Z" stretched the streak along world Z whatever
		# way it was pointing. Aim down the world Z and it looks right; turn the head and
		# the streak lies down across the shot. Same trap as any "scale in local space"
		# mistake, and it only shows up once something is not axis-aligned.
		var along := _tracer_dir[i]
		var up := Vector3.UP if absf(along.y) < 0.95 else Vector3.RIGHT
		var side := up.cross(along).normalized()
		_tracers[i].global_transform = Transform3D(
				Basis(side, along.cross(side), along * (head - tail)),
				(back + front) * 0.5)


## A hole on the surface, and the orientation is the whole trick.
##
## A Decal in Godot projects along its own **Y** axis, downwards — it is a box, and the
## picture is pressed onto whatever the box contains, from above. The first version built
## the basis with `looking_at`, which aims **-Z** at the surface: every decal was
## projecting SIDEWAYS, and what landed on the wall was the edge of the box — a stripe,
## never a circle. Nothing in the picture said "wrong axis"; it said "the holes are
## streaks".
##
## So: +Y along the normal, X and Z are the footprint, and the random spin is about Y.
func add_hole(at: Vector3, normal: Vector3, incoming: Vector3, tint: Color) -> void:
	var decal := _decals[_decal_at]
	_decal_at = (_decal_at + 1) % DECALS
	decal.visible = true
	decal.modulate = tint
	var head_on := clampf(-incoming.dot(normal), 0.0, 1.0)
	# A round arriving square punches a round hole. One arriving at a graze SMEARS: it
	# ploughs along the surface, and the mark it leaves is stretched by one over the
	# cosine of the angle. Circles at every angle is what gave the wall its rubber-stamp
	# look.
	var stretch := clampf(1.0 / maxf(head_on, 0.22), 1.0, 4.5)
	# The direction of the smear is the incoming ray flattened onto the surface.
	var along := incoming - normal * incoming.dot(normal)
	if along.length() < 0.01:
		along = (Vector3.UP if absf(normal.y) < 0.95 else Vector3.RIGHT).cross(normal)
	along = along.normalized()
	# РАСТЯЖЕНИЕ ИДЁТ В size, А НЕ В БАЗИС. Масштаб в трансформе Decal просто не смотрит:
	# я записал туда scale (2.45, 1, 1), прочитал обратно — он там лежит нетронутый, — а
	# на стене остался ровный кружок. Проектор строится по `size`, базис берётся только
	# как ориентация. Опять картинка без единой ошибки в консоли.
	decal.size = Vector3(HOLE * stretch, 0.3, HOLE)
	decal.global_transform = Transform3D(
			Basis(along, normal, along.cross(normal)), at + normal * 0.06)
	# Spinning is only right for a round hole; a smear already has a direction.
	if head_on > 0.9:
		decal.rotate_object_local(Vector3.UP, randf() * TAU)


## THE physics of an impact spray, and it is one line of it. A round arriving head-on
## throws fragments back at the shooter in a wide cone; a round arriving at a graze
## RICOCHETS, and the spray becomes a narrow fan along the reflected direction. Same wall,
## same weapon, two completely different pictures — and that difference is most of what
## reads as real.
##
## Direction from the angle, everything else from the SURFACE. Steel throws a shower of
## fast white-hot fragments; wood throws a handful of dull embers and mostly dust. Using
## one spray for every material is what makes a shooting range feel like a cardboard set.
func add_sparks(
		at: Vector3,
		normal: Vector3,
		incoming: Vector3,
		surface: Dictionary) -> void:
	var emitter := _sparks[_spark_at]
	var material := _spark_materials[_spark_at]
	_spark_at = (_spark_at + 1) % SPARKS
	var head_on := clampf(-incoming.dot(normal), 0.0, 1.0)
	var bounced := incoming - normal * (2.0 * incoming.dot(normal))
	material.set_shader_parameter(
			"emit_dir", bounced.lerp(normal, head_on * 0.6).normalized())
	material.set_shader_parameter("cone", lerpf(0.30, 1.15, head_on))
	material.set_shader_parameter("speed_min", float(surface["speed"]) * 0.25)
	material.set_shader_parameter(
			"speed_max", float(surface["speed"]) * lerpf(1.5, 1.0, head_on))
	material.set_shader_parameter("streak", float(surface["streak"]))
	material.set_shader_parameter("tint", surface["hot"])
	emitter.amount = int(surface["count"])
	emitter.lifetime = float(surface["life"])
	emitter.global_position = at + normal * 0.02
	emitter.restart()
	emitter.emitting = true


func add_shell(at: Vector3, right: Vector3, up: Vector3) -> void:
	var body := _shells[_shell_at]
	_shell_at = (_shell_at + 1) % SHELLS
	body.visible = true
	body.freeze = false
	# The server owns a body during the step, so the reset goes through it — probe 28 lost
	# a day to assigning global_transform instead.
	var rid := body.get_rid()
	PhysicsServer3D.body_set_state(
			rid,
			PhysicsServer3D.BODY_STATE_TRANSFORM,
			Transform3D(Basis.IDENTITY, at))
	PhysicsServer3D.body_set_state(
			rid,
			PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY,
			right * randf_range(2.2, 3.6) + up * randf_range(1.4, 2.4))
	PhysicsServer3D.body_set_state(
			rid,
			PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY,
			Vector3(randf_range(-22, 22), randf_range(-22, 22), randf_range(-22, 22)))
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_SLEEPING, false)


func add_tracer(from: Vector3, to: Vector3) -> void:
	var along := to - from
	_tracer_from[_tracer_at] = from
	_tracer_dir[_tracer_at] = along.normalized()
	_tracer_far[_tracer_at] = along.length()
	_tracer_born[_tracer_at] = _clock
	_tracers[_tracer_at].visible = false
	_tracer_at = (_tracer_at + 1) % TRACERS


func clear_all() -> void:
	for decal in _decals:
		decal.visible = false
	for body in _shells:
		body.visible = false
		body.freeze = true
	for tracer in _tracers:
		tracer.visible = false
	_tracer_born.fill(-1.0)


## A bullet hole drawn, not loaded: dark core, a bright rim of crushed material, ragged
## edge. Twelve lines instead of an asset, and the probe stays self-contained.
func _make_hole() -> ImageTexture:
	var side := 96
	var image := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	var random := RandomNumberGenerator.new()
	random.seed = 7717
	for y in side:
		for x in side:
			var at := Vector2(float(x) - side * 0.5, float(y) - side * 0.5) / (side * 0.5)
			var radius := at.length() * (
					1.0 + 0.22 * sin(at.angle() * 7.0 + random.randf() * 0.2))
			var core := 1.0 - smoothstep(0.16, 0.34, radius)
			var rim := smoothstep(0.30, 0.42, radius) * (
					1.0 - smoothstep(0.42, 0.62, radius))
			var colour := Color(0.04, 0.04, 0.05).lerp(Color(0.66, 0.61, 0.54), rim)
			image.set_pixel(x, y, Color(
					colour.r, colour.g, colour.b, clampf(core + rim * 0.55, 0.0, 1.0)))
	return ImageTexture.create_from_image(image)


func _make_shells() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.019, 0.052, 0.019)
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.86, 0.66, 0.24)
	brass.metallic = 0.95
	brass.roughness = 0.22
	for i in SHELLS:
		var body := RigidBody3D.new()
		body.mass = 0.012
		# ГИЛЬЗА ЛЕЖИТ НА СВОЁМ СЛОЕ и никого не толкает. Здесь стрелок бесплотен —
		# камера просто летает, — и слой был неважен. В мультипробе, где у игрока
		# появилась капсула, гильза стала вылетать у самого лица, и `move_and_slide`
		# честно принимал латунь за препятствие: двадцать пять выстрелов на месте
		# сносили стрелка на 3.13 м вбок.
		#
		# Это дефект пробы, а не стык: «гильза не должна толкать того, в кого попала»
		# формулируется без всякой второй пробы. Маска остаётся первой — падать на пол
		# и звенеть по нему латунь продолжает.
		body.collision_layer = SHELL_LAYER
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = mesh.size
		collider.shape = shape
		body.add_child(collider)
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.material_override = brass
		body.add_child(visual)
		body.freeze = true
		body.visible = false
		add_child(body)
		_shells.append(body)


## Each emitter gets its OWN process material: direction and cone are set per impact, and
## a shared material would make every spark on screen point the same way.
func _make_sparks() -> void:
	var process := load("res://probes/30_gun/sparks.gdshader") as Shader
	var streak := BoxMesh.new()
	streak.size = Vector3(1.0, 1.0, 1.0)
	var draw := ShaderMaterial.new()
	draw.shader = load("res://probes/30_gun/fx.gdshader")
	draw.set_shader_parameter("mode", 1)
	draw.set_shader_parameter("gain", 3.2)
	for i in SPARKS:
		var emitter := GPUParticles3D.new()
		emitter.amount = 22
		emitter.lifetime = 0.65
		emitter.one_shot = true
		emitter.explosiveness = 1.0
		emitter.emitting = false
		emitter.local_coords = false
		var material := ShaderMaterial.new()
		material.shader = process
		emitter.process_material = material
		emitter.draw_pass_1 = streak
		emitter.material_override = draw
		add_child(emitter)
		_sparks.append(emitter)
		_spark_materials.append(material)


func _make_tracers() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.022, 0.022, 1.0)
	# UNSHADED ИГНОРИРУЕТ EMISSION. Это стоило мне бледных трассеров: emission_energy 16
	# не делал ничего, потому что в unshaded-режиме на экран идёт ровно albedo. Свечение
	# задаётся HDR-цветом самого albedo — компоненты больше единицы, их подхватывает glow
	# по порогу 0.85. Ошибки нет, предупреждения нет, просто пыльная полоска вместо пули.
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(6.0, 3.4, 1.1)
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_tracer_from.resize(TRACERS)
	_tracer_dir.resize(TRACERS)
	_tracer_far.resize(TRACERS)
	_tracer_born.resize(TRACERS)
	_tracer_born.fill(-1.0)
	for i in TRACERS:
		var streak := MeshInstance3D.new()
		streak.mesh = mesh
		streak.material_override = glow
		streak.visible = false
		add_child(streak)
		_tracers.append(streak)
