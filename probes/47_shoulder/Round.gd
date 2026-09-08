extends Node3D
class_name ShoulderRound

## THE ROUND, IN TWO KINDS FROM ONE TUBE.
##
## Unguided, it is a thrown thing: boost, then gravity and drag, and everything about whether
## it hits was decided before the trigger. Beam-riding, it chases a LINE rather than a target —
## the line a hand is holding — and everything about whether it hits is decided during the
## flight, by that hand.
##
## The forty-fifth probe steered at the target and needed nothing but the target. This one is
## the opposite arrangement: the round knows only where the sight is pointing and has never
## heard of a target. That is what a wire down the tail actually carries.
##
## Reads no keys. The sight arrives in `beam_from` and `beam_dir`, written by whoever is
## holding it.

signal finished(miss: float, hit: bool, reason: String)

enum Kind {
	DUMB,   ## no guidance at all: a boost, then a parabola
	BEAM,   ## steers onto the line of sight and rides it in
}

@export var kind := Kind.BEAM
@export_range(20.0, 400.0, 5.0) var speed := 115.0
## Ceiling on lateral acceleration. Beam riding asks for most of it at the moment the round
## gathers onto the line, which is why a shot taken while swinging the sight misses.
@export_range(2.0, 40.0, 0.5) var limit := 9.0
## How hard the round pulls back towards the line, per metre it is off it. Too little and it
## never gathers; too much and it weaves across the line all the way out.
@export_range(0.05, 3.0, 0.05) var beam_gain := 0.55
@export_range(0.0, 6.0, 0.1) var beam_damp := 1.6
## THE FUSE IS NOT ARMED AT THE MUZZLE. Below this range the warhead is a lump of metal, and
## that is why a launcher has a minimum range as well as a maximum one.
@export_range(0.0, 120.0, 1.0) var arming := 25.0
@export_range(1.0, 30.0, 0.5) var life := 12.0
@export_range(0.5, 12.0, 0.5) var kill := 2.5
@export_range(0.0, 20.0, 0.1) var gravity := 9.81
## Only the unguided round admits to air. The beam rider is fighting a line, and drag on it
## reads as the line being wrong.
@export_range(0.0, 0.02, 0.0005) var drag := 0.004

## Written from outside every tick: where the sight is and which way it looks.
var beam_from := Vector3.ZERO
var beam_dir := Vector3.FORWARD

var flying := false
var clock := 0.0
var armed := false
var off_beam := 0.0     ## metres from the line of sight
var pulled := 0.0       ## g being used this tick
var travelled := 0.0

var _v := Vector3.ZERO
var _target: ShoulderTarget = null
var _closest := INF
var _was_rel := Vector3.ZERO

@onready var _trail: Node3D = $Trail


func launch(from: Transform3D, at: ShoulderTarget) -> void:
	global_transform = from
	_v = -from.basis.z * speed
	_target = at
	_closest = INF
	_was_rel = at.global_position - from.origin if at != null else Vector3.ZERO
	clock = 0.0
	travelled = 0.0
	armed = false
	off_beam = 0.0
	flying = true
	visible = true


func _physics_process(delta: float) -> void:
	if not flying:
		return
	clock += delta
	travelled += _v.length() * delta
	armed = travelled >= arming

	if kind == Kind.BEAM:
		_ride(delta)
	else:
		_v += Vector3.DOWN * gravity * delta
		_v -= _v * _v.length() * drag * delta

	global_position += _v * delta
	if _v.length_squared() > 1.0:
		look_at(global_position + _v, Vector3.UP)
	if _trail != null:
		_trail.visible = clock < 0.6

	_score(delta)


## BEAM RIDING. The round measures how far it is from the line and pulls back towards it —
## nothing more. It never asks where the target is, and it cannot: all it has is the line.
##
## Hence the one thing that separates this from every guidance law in the forty-fifth probe.
## A missile that chases a target forgives a shaky hand. A missile that chases a line IS the
## hand: the line moves, the round goes there, and there is nothing between the two.
func _ride(delta: float) -> void:
	var along := global_position - beam_from
	var down_range := along.dot(beam_dir)
	var offset := along - beam_dir * down_range
	off_beam = offset.length()
	if down_range < 1.0:
		return
	# Proportional on the offset, minus the rate at which the offset is already closing.
	var closing := _v - beam_dir * _v.dot(beam_dir)
	var want := -offset * beam_gain - closing * beam_damp
	var asked := want.length() / 9.81
	if asked > limit:
		want = want.normalized() * limit * 9.81
	pulled = want.length() / 9.81
	_v = (_v + want * delta).normalized() * speed


func _score(delta: float) -> void:
	if _target == null:
		return
	var rel := _target.global_position - global_position
	var gap := rel.length()
	# Closest approach inside the tick, the way the forty-fifth probe learned to do it: at a
	# hundred metres per second one step is two metres and the kill radius is two and a half.
	var seg := rel - _was_rel
	var t := 0.0 if seg.length_squared() < 1e-9 else clampf(
		-_was_rel.dot(seg) / seg.length_squared(), 0.0, 1.0)
	var pass_gap := (_was_rel + seg * t).length()
	_was_rel = rel
	_closest = minf(_closest, pass_gap)

	if pass_gap < kill:
		if armed:
			_stop(pass_gap, true, "попадание")
		else:
			_stop(pass_gap, false, "не взвелась")
	elif gap > _closest and _closest < 60.0:
		_stop(_closest, false, "промах")
	elif global_position.y < 0.0:
		_stop(_closest, false, "в землю")
	elif clock > life:
		_stop(_closest, false, "вышло время")


func _stop(gap: float, hit: bool, reason: String) -> void:
	flying = false
	visible = false
	finished.emit(gap, hit, reason)
