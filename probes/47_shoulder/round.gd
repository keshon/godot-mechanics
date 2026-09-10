class_name ShoulderRound
extends Node3D
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
	## No guidance at all: a boost, then a parabola.
	DUMB,
	## Steers onto the line of sight and rides it in.
	BEAM,
}

## Step for the paper flight the sight is cut against, seconds. Coarser than the physics tick
## on purpose: a firing table is not a simulation, it only has to put the marks in the right
## place.
const STEP := 0.02
## Standard gravity, m/s2. Loads are quoted in g, so it is divided out here.
const GRAVITY := 9.81
## Beyond this gap, in metres, a range that stopped shrinking means the round is wandering,
## not that it has gone past.
const PASS_GAP := 60.0

@export var kind := Kind.BEAM
## Off the rail slowly, because the tube sits on a shoulder and cannot afford the kick.
@export_range(20.0, 400.0, 5.0) var speed := 117.0
## What the sustainer works each kind up to. THE UNGUIDED ROUND IS THE FAST ONE, and that is the
## opposite of the guess: a thrown round is pushed as hard as the tube allows, because speed is
## the only thing keeping it flat, while a ridden one is held DOWN to a speed a hand can follow.
## Real numbers, and they are not close: PG-7VL leaves at 117 and burns up to 294; 9M113 Konkurs
## cruises near 200 and takes eleven seconds to reach two kilometres.
##
## Games cut both, always downwards — Battlefield flies a rocket near 100 and a tank shell near
## 200 against a real 1600. The reason is the same one that makes a real wire-guided round slow:
## below some speed a flight becomes something a person can watch and steer, and above it the
## shot is over before the eye has found it. Here the prototype numbers are kept and the RANGE
## is opened up instead, because that is what the real weapons do with them.
@export_range(20.0, 500.0, 5.0) var thrown := 294.0
@export_range(20.0, 500.0, 5.0) var ridden := 200.0
## Seconds the sustainer burns.
@export_range(0.0, 3.0, 0.05) var boost := 0.8
## Ceiling on lateral acceleration, g. Beam riding asks for most of it at the moment the round
## gathers onto the line, which is why a shot taken while swinging the sight misses.
@export_range(2.0, 40.0, 0.5) var limit := 9.0
## How hard the round pulls back towards the line, per metre it is off it, and how hard it brakes
## the closing. The pair is a spring: sqrt(gain) is how fast it gathers and damp/2*sqrt(gain) is
## whether it overshoots. THE GATHER HAS TO FIT INSIDE THE FLIGHT — at 0.55 and 1.6 it needs
## five seconds to settle and the round arrives still crossing the line.
@export_range(0.05, 20.0, 0.05) var beam_gain := 8.0
@export_range(0.0, 12.0, 0.1) var beam_damp := 5.0
## THE FUSE IS NOT ARMED AT THE MUZZLE. Below this range, in metres, the warhead is a lump of
## metal, and that is why a launcher has a minimum range as well as a maximum one.
@export_range(0.0, 120.0, 1.0) var arming := 25.0
## Seconds before the flight is called a timeout.
@export_range(1.0, 40.0, 0.5) var life := 18.0
## Kill radius, metres.
@export_range(0.5, 12.0, 0.5) var kill := 2.5
@export_range(0.0, 20.0, 0.1) var gravity := 9.81
## Only the unguided round admits to air. The beam rider is fighting a line, and drag on it
## reads as the line being wrong.
##
## The number is decel divided by v squared, and it has to be worked out rather than dialled:
## half rho v^2 Cd A over m for a 2.6 kg grenade of 85 mm at Cd 0.4 gives 46 m/s^2 at 294 m/s,
## so 0.0006. A 0.004 in this slot brakes the round at twelve g.
@export_range(0.0, 0.02, 0.0001) var drag := 0.0006

## Written from outside every tick: where the sight is and which way it looks.
var beam_from := Vector3.ZERO
var beam_dir := Vector3.FORWARD

var flying := false
var clock := 0.0
var armed := false
## Metres from the line of sight.
var off_beam := 0.0
## The load being used this tick, g.
var pulled := 0.0
var travelled := 0.0

var _velocity := Vector3.ZERO
var _target: ShoulderTarget = null
var _closest := INF
var _last_offset := Vector3.ZERO
var _last_off_beam := Vector3.ZERO
var _has_last_off_beam := false

@onready var _trail: Node3D = $Trail


func _physics_process(delta: float) -> void:
	if not flying:
		return
	clock += delta
	travelled += _velocity.length() * delta
	armed = travelled >= arming

	var top := thrown if kind == Kind.DUMB else ridden
	if clock < boost and _velocity.length() < top:
		_velocity += _velocity.normalized() * (top - speed) / maxf(boost, 0.01) * delta
	if kind == Kind.BEAM:
		_ride(delta)
	else:
		_velocity += Vector3.DOWN * gravity * delta
		_velocity -= _velocity * _velocity.length() * drag * delta

	global_position += _velocity * delta
	if _velocity.length_squared() > 1.0:
		look_at(global_position + _velocity, Vector3.UP)
	if _trail != null:
		_trail.visible = clock < 0.6

	_score()


func launch(from: Transform3D, at: ShoulderTarget) -> void:
	global_transform = from
	_velocity = -from.basis.z * speed
	_target = at
	_closest = INF
	_last_offset = at.centre() - from.origin if at != null else Vector3.ZERO
	clock = 0.0
	travelled = 0.0
	armed = false
	off_beam = 0.0
	_last_off_beam = Vector3.ZERO
	_has_last_off_beam = false
	flying = true
	visible = true


## WHAT ANGLE PUTS THE ROUND THERE — asked of the round, because the ballistics belong to it.
## `dist` is the horizontal distance and `drop` how far the target sits above the muzzle, which
## is negative when firing downhill. Returns the angle ABOVE THE LINE OF SIGHT, which is what a
## range scale is marked in.
##
## Integrated rather than solved. There is no closed form once the round spends eight tenths of a
## second working up to speed and then bleeds to drag — and the closed form, the flat-fire
## half-arcsine, has NO TERM FOR SHOOTING DOWNHILL at all. On the level it is a metre low across
## the middle of its own range; the moment the shooter stands on a rise it puts every round into
## the dirt in front of the target. Bisection over the round's own motion is not a clever
## substitute for the formula, it is what a firing table has always been.
func angle_for(dist: float, drop: float) -> float:
	var low := -0.6
	var high := 0.6
	for _step in 24:
		var mid := (low + high) * 0.5
		if _reach(dist, mid) < drop:
			low = mid
		else:
			high = mid
	return (low + high) * 0.5 - atan2(drop, dist)


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
		_last_off_beam = offset
		return
	# THE DAMPER MEASURES DRIFT OFF THE LINE, not sideways speed in the world. The two are the
	# same only while the line is still, and a beam rider exists for the case where it is not:
	# tracking a crosser at eleven metres per second, the round MUST carry lateral speed just to
	# stay on the beam, and a damper that reads world speed fights exactly that. It settles ten
	# metres out at every range — a constant offset large enough to overpower the damper — which
	# is what a steady-state error from a mis-framed feedback term looks like.
	var drift := ((offset - _last_off_beam) / maxf(delta, 1e-5)
			if _has_last_off_beam else Vector3.ZERO)
	_last_off_beam = offset
	_has_last_off_beam = true
	var want := -offset * beam_gain - drift * beam_damp
	var asked := want.length() / GRAVITY
	if asked > limit:
		want = want.normalized() * limit * GRAVITY
	pulled = want.length() / GRAVITY
	var was := _velocity.length()
	_velocity = (_velocity + want * delta).normalized() * was


func _score() -> void:
	if _target == null:
		return
	var offset := _target.centre() - global_position
	var gap := offset.length()
	# Closest approach inside the tick, the way the forty-fifth probe learned to do it: at a
	# hundred metres per second one step is two metres and the kill radius is two and a half.
	var step := offset - _last_offset
	var along := (0.0 if step.length_squared() < 1e-9
			else clampf(-_last_offset.dot(step) / step.length_squared(), 0.0, 1.0))
	var pass_gap := (_last_offset + step * along).length()
	_last_offset = offset
	_closest = minf(_closest, pass_gap)

	if pass_gap < kill:
		_stop(pass_gap, armed, "попадание" if armed else "не взвелась")
	elif gap > _closest and _closest < PASS_GAP:
		_stop(_closest, false, "промах")
	elif global_position.y < 0.0:
		_stop(_closest, false, "в землю")
	elif clock > life:
		_stop(_closest, false, "вышло время")


## Height above the muzzle once the round has covered `dist` horizontally, launched at `angle`.
## The round's own boost, gravity and drag, run forward on paper.
func _reach(dist: float, angle: float) -> float:
	var velocity := Vector2(cos(angle), sin(angle)) * speed
	var at := Vector2.ZERO
	var clock_on_paper := 0.0
	var top := thrown if kind == Kind.DUMB else ridden
	while at.x < dist and clock_on_paper < life:
		if clock_on_paper < boost and velocity.length() < top:
			velocity += velocity.normalized() * (top - speed) / maxf(boost, 0.01) * STEP
		velocity.y -= gravity * STEP
		velocity -= velocity * velocity.length() * drag * STEP
		at += velocity * STEP
		clock_on_paper += STEP
	return at.y


func _stop(gap: float, hit: bool, reason: String) -> void:
	flying = false
	visible = false
	finished.emit(gap, hit, reason)
