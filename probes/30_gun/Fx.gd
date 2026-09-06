class_name GunFx
extends Node3D

## Everything a shot leaves behind, and all of it POOLED. A rifle fires ten times a second
## and each shot spawns four things; at that rate the cost is not drawing them, it is
## CREATING them. Everything here is made once and handed out oldest-first.
##
## The pool size is not an optimisation, it is a DESIGN DECISION with a visible consequence:
## a wall holds as many holes as there are decals, and the oldest goes when the next comes.

const DECALS := 64
const SHELLS := 28
## Отдельный слой для латуни: см. комментарий в её создании.
const SHELL_LAYER := 1 << 4
const SPARKS := 10
## Поперечник дырки. Метры, на глаз: настоящая пробоина мельче, но след от неё — с
## выкрошенным краем и копотью — читается примерно так.
const HOLE := 0.2
const TRACERS := 8
## A tracer is a BURNING ROUND IN FLIGHT, not a lit-up trajectory. The first version drew
## the whole path at once, and it read exactly as what it was: a fan of bright rods with its
## apex in the player's face. A round crosses a fifteen-metre room in three frames, and
## three frames of a short segment is what the eye calls a streak.
const TRACER_SPEED := 150.0
const TRACER_LEN := 3.0
## Where the streak becomes visible, in metres from the muzzle. NOT zero, and this is the
## fix for "the tracers are crooked and you can see it when the camera moves": the muzzle
## sits twenty centimetres right of the eye, so a segment drawn AT the muzzle and aimed at a
## point on the crosshair axis is visibly skewed, and the skew swings with every turn of the
## head. Two metres out the parallax is gone and the round is simply going where it goes.
## You never see a real tracer at the muzzle anyway — it is inside the flash.
const TRACER_START := 2.0

var _decals: Array[Decal] = []
var _shells: Array[RigidBody3D] = []
var _sparks: Array[GPUParticles3D] = []
var _spark_mats: Array[ShaderMaterial] = []
var _tracers: Array[MeshInstance3D] = []
var _tr_from := PackedVector3Array()
var _tr_dir := PackedVector3Array()
var _tr_far := PackedFloat32Array()
var _tr_t0 := PackedFloat32Array()
var _di := 0
var _si := 0
var _pi := 0
var _ti := 0

var _clock := 0.0


func _ready() -> void:
	var hole := _make_hole()
	for i in DECALS:
		var d := Decal.new()
		d.texture_albedo = hole
		# X and Z are the FOOTPRINT on the wall; Y is how deep the box reaches to find a
		# surface to project onto. Confusing the three is what made stripes.
		d.size = Vector3(HOLE, 0.3, HOLE)
		d.upper_fade = 0.4
		d.lower_fade = 0.4
		d.visible = false
		add_child(d)
		_decals.append(d)
	_make_shells()
	_make_sparks()
	_make_tracers()


## A bullet hole drawn, not loaded: dark core, a bright rim of crushed material, ragged
## edge. Twelve lines instead of an asset, and the probe stays self-contained.
func _make_hole() -> ImageTexture:
	var n := 96
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7717
	for y in n:
		for x in n:
			var p := Vector2(float(x) - n * 0.5, float(y) - n * 0.5) / (n * 0.5)
			var r := p.length() * (1.0 + 0.22 * sin(p.angle() * 7.0 + rng.randf() * 0.2))
			var core := 1.0 - smoothstep(0.16, 0.34, r)
			var rim := smoothstep(0.30, 0.42, r) * (1.0 - smoothstep(0.42, 0.62, r))
			var c := Color(0.04, 0.04, 0.05).lerp(Color(0.66, 0.61, 0.54), rim)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, clampf(core + rim * 0.55, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _make_shells() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.019, 0.052, 0.019)
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.86, 0.66, 0.24)
	brass.metallic = 0.95
	brass.roughness = 0.22
	for i in SHELLS:
		var b := RigidBody3D.new()
		b.mass = 0.012
		# ГИЛЬЗА ЛЕЖИТ НА СВОЁМ СЛОЕ и никого не толкает. Здесь стрелок бесплотен —
		# камера просто летает, — и слой был неважен. В мультипробе, где у игрока
		# появилась капсула, гильза стала вылетать у самого лица, и `move_and_slide`
		# честно принимал латунь за препятствие: двадцать пять выстрелов на месте
		# сносили стрелка на 3.13 м вбок.
		#
		# Это дефект пробы, а не стык: «гильза не должна толкать того, в кого попала»
		# формулируется без всякой второй пробы. Маска остаётся первой — падать на пол
		# и звенеть по нему латунь продолжает.
		b.collision_layer = SHELL_LAYER
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = mesh.size
		col.shape = shape
		b.add_child(col)
		var vis := MeshInstance3D.new()
		vis.mesh = mesh
		vis.material_override = brass
		b.add_child(vis)
		b.freeze = true
		b.visible = false
		add_child(b)
		_shells.append(b)


## Each emitter gets its OWN process material: direction and cone are set per impact, and a
## shared material would make every spark on screen point the same way.
func _make_sparks() -> void:
	var proc := load("res://probes/30_gun/sparks.gdshader") as Shader
	var streak := BoxMesh.new()
	streak.size = Vector3(1.0, 1.0, 1.0)
	var dm := ShaderMaterial.new()
	dm.shader = load("res://probes/30_gun/fx.gdshader")
	dm.set_shader_parameter("mode", 1)
	dm.set_shader_parameter("gain", 3.2)
	for i in SPARKS:
		var p := GPUParticles3D.new()
		p.amount = 22
		p.lifetime = 0.65
		p.one_shot = true
		p.explosiveness = 1.0
		p.emitting = false
		p.local_coords = false
		var m := ShaderMaterial.new()
		m.shader = proc
		p.process_material = m
		p.draw_pass_1 = streak
		p.material_override = dm
		add_child(p)
		_sparks.append(p)
		_spark_mats.append(m)


func _make_tracers() -> void:
	var tm := BoxMesh.new()
	tm.size = Vector3(0.022, 0.022, 1.0)
	# UNSHADED ИГНОРИРУЕТ EMISSION. Это стоило мне бледных трассеров: emission_energy 16
	# не делал ничего, потому что в unshaded-режиме на экран идёт ровно albedo. Свечение
	# задаётся HDR-цветом самого albedo — компоненты больше единицы, их подхватывает glow
	# по порогу 0.85. Ошибки нет, предупреждения нет, просто пыльная полоска вместо пули.
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(6.0, 3.4, 1.1)
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_tr_from.resize(TRACERS)
	_tr_dir.resize(TRACERS)
	_tr_far.resize(TRACERS)
	_tr_t0.resize(TRACERS)
	_tr_t0.fill(-1.0)
	for i in TRACERS:
		var t := MeshInstance3D.new()
		t.mesh = tm
		t.material_override = glow
		t.visible = false
		add_child(t)
		_tracers.append(t)


## A hole on the surface, and the orientation is the whole trick.
##
## A Decal in Godot projects along its own **Y** axis, downwards — it is a box, and the
## picture is pressed onto whatever the box contains, from above. The first version built
## the basis with `looking_at`, which aims **-Z** at the surface: every decal was projecting
## SIDEWAYS, and what landed on the wall was the edge of the box — a stripe, never a circle.
## Nothing in the picture said "wrong axis"; it said "the holes are streaks".
##
## So: +Y along the normal, X and Z are the footprint, and the random spin is about Y.
func hole(at: Vector3, normal: Vector3, incoming: Vector3, tint: Color) -> void:
	var d := _decals[_di]
	_di = (_di + 1) % DECALS
	d.visible = true
	d.modulate = tint
	var head_on := clampf(-incoming.dot(normal), 0.0, 1.0)
	# A round arriving square punches a round hole. One arriving at a graze SMEARS: it
	# ploughs along the surface, and the mark it leaves is stretched by one over the cosine
	# of the angle. Circles at every angle is what gave the wall its rubber-stamp look.
	var stretch := clampf(1.0 / maxf(head_on, 0.22), 1.0, 4.5)
	# the direction of the smear is the incoming ray flattened onto the surface
	var along := incoming - normal * incoming.dot(normal)
	if along.length() < 0.01:
		along = (Vector3.UP if absf(normal.y) < 0.95 else Vector3.RIGHT).cross(normal)
	along = along.normalized()
	# РАСТЯЖЕНИЕ ИДЁТ В size, А НЕ В БАЗИС. Масштаб в трансформе Decal просто не смотрит:
	# я записал туда scale (2.45, 1, 1), прочитал обратно — он там лежит нетронутый, — а на
	# стене остался ровный кружок. Проектор строится по `size`, базис берётся только как
	# ориентация. Опять картинка без единой ошибки в консоли.
	d.size = Vector3(HOLE * stretch, 0.3, HOLE)
	d.global_transform = Transform3D(
		Basis(along, normal, along.cross(normal)), at + normal * 0.06)
	# spinning is only right for a round hole; a smear already has a direction
	if head_on > 0.9:
		d.rotate_object_local(Vector3.UP, randf() * TAU)


## THE physics of an impact spray, and it is one line of it. A round arriving head-on throws
## fragments back at the shooter in a wide cone; a round arriving at a graze RICOCHETS, and
## the spray becomes a narrow fan along the reflected direction. Same wall, same weapon, two
## completely different pictures — and that difference is most of what reads as real.
## Direction from the angle, everything else from the SURFACE. Steel throws a shower of
## fast white-hot fragments; wood throws a handful of dull embers and mostly dust. Using one
## spray for every material is what makes a shooting range feel like a cardboard set.
func sparks(at: Vector3, normal: Vector3, incoming: Vector3, surf: Dictionary) -> void:
	var p := _sparks[_pi]
	var m := _spark_mats[_pi]
	_pi = (_pi + 1) % SPARKS
	var head_on := clampf(-incoming.dot(normal), 0.0, 1.0)
	var refl := incoming - normal * (2.0 * incoming.dot(normal))
	m.set_shader_parameter("emit_dir", refl.lerp(normal, head_on * 0.6).normalized())
	m.set_shader_parameter("cone", lerpf(0.30, 1.15, head_on))
	m.set_shader_parameter("speed_min", float(surf["speed"]) * 0.25)
	m.set_shader_parameter("speed_max", float(surf["speed"]) * lerpf(1.5, 1.0, head_on))
	m.set_shader_parameter("streak", float(surf["streak"]))
	m.set_shader_parameter("tint", surf["hot"])
	p.amount = int(surf["count"])
	p.lifetime = float(surf["life"])
	p.global_position = at + normal * 0.02
	p.restart()
	p.emitting = true


func shell(at: Vector3, right: Vector3, up: Vector3) -> void:
	var b := _shells[_si]
	_si = (_si + 1) % SHELLS
	b.visible = true
	b.freeze = false
	# The server owns a body during the step, so the reset goes through it — probe 28 lost
	# a day to assigning global_transform instead.
	var rid := b.get_rid()
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM,
		Transform3D(Basis.IDENTITY, at))
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY,
		right * randf_range(2.2, 3.6) + up * randf_range(1.4, 2.4))
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY,
		Vector3(randf_range(-22, 22), randf_range(-22, 22), randf_range(-22, 22)))
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_SLEEPING, false)


func tracer(from: Vector3, to: Vector3) -> void:
	var d := to - from
	_tr_from[_ti] = from
	_tr_dir[_ti] = d.normalized()
	_tr_far[_ti] = d.length()
	_tr_t0[_ti] = _clock
	_tracers[_ti].visible = false
	_ti = (_ti + 1) % TRACERS


func _process(delta: float) -> void:
	_clock += delta
	for i in TRACERS:
		# `visible` is NOT the liveness flag, and using it as one cost the whole feature.
		# In the first frame the round has flown less than TRACER_START, so there is nothing
		# to draw YET — and hiding it then made the loop skip that slot for good. On a
		# 60 Hz machine the round cleared two metres in the first frame and it worked; on a
		# 200 Hz one it never did. A state that means "not yet" must not share a flag with
		# one that means "done".
		if _tr_t0[i] < 0.0:
			continue
		var flown := (_clock - _tr_t0[i]) * TRACER_SPEED
		if flown - TRACER_LEN >= _tr_far[i]:
			_tr_t0[i] = -1.0                  # arrived: the slot is free again
			_tracers[i].visible = false
			continue
		var head: float = minf(flown, _tr_far[i])
		var tail: float = maxf(maxf(flown - TRACER_LEN, 0.0), minf(TRACER_START, _tr_far[i]))
		if head <= tail:
			_tracers[i].visible = false       # not yet out of the muzzle glow — still alive
			continue
		_tracers[i].visible = true
		var a := _tr_from[i] + _tr_dir[i] * tail
		var b := _tr_from[i] + _tr_dir[i] * head
		# BUILT BY COLUMNS, not by `looking_at().scaled()`. Basis.scaled() multiplies the
		# basis ROWS, which means it scales along the PARENT's axes, not along the local
		# ones: asking for "longer in Z" stretched the streak along world Z whatever way it
		# was pointing. Aim down the world Z and it looks right; turn the head and the
		# streak lies down across the shot. Same trap as any "scale in local space" mistake,
		# and it only shows up once something is not axis-aligned.
		var f := _tr_dir[i]
		var up := Vector3.UP if absf(f.y) < 0.95 else Vector3.RIGHT
		var rr := up.cross(f).normalized()
		_tracers[i].global_transform = Transform3D(
			Basis(rr, f.cross(rr), f * (head - tail)), (a + b) * 0.5)


func clear_all() -> void:
	for d in _decals:
		d.visible = false
	for b in _shells:
		b.visible = false
		b.freeze = true
	for t in _tracers:
		t.visible = false
	_tr_t0.fill(-1.0)
