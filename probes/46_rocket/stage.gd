class_name RocketStage
extends Node3D
## ONE STAGE, AND A STAGE IS A SCENE.
##
## Engines, tanks and the empty structure that holds them. It burns, it gets lighter, and
## at some point it becomes a passenger — that moment is what staging exists to end.
##
## A stage knows nothing about the rocket it belongs to. It reports its mass and, when
## asked and while it has anything left, its thrust. Who asks is not its business.
##
## THRUST IS A COUNT TIMES A CHAMBER, and the count is also what you see: the ring of bells
## under the block is built from that same number. An RD-107 is one engine with four chambers,
## which is why a Soyuz has four bells under each carrot — change `engines` and both the
## number and the thrust follow, because they are the same fact written once. The ring is the
## one thing here built by code, and the rules name that case outright: many of a thing,
## arranged by a rule, not touched by hand.

## Below this throttle setting an engine counts as shut.
const MIN_THROTTLE := 0.01

@export_range(0.0, 40000.0, 10.0) var dry_mass := 2200.0
@export_range(0.0, 200000.0, 100.0) var propellant := 18000.0

@export_group("Engines")
## Combustion chambers on this block. Four is an RD-107; one is a small upper stage.
@export_range(1, 8, 1) var engines := 4
## Sea-level thrust of ONE chamber, newtons.
@export_range(0.0, 1000000.0, 250.0) var chamber := 98750.0
## Radius of the circle the bells sit on, metres.
@export_range(0.0, 4.0, 0.01) var ring := 0.62
## Exhaust speed, m/s. Divided by the surface gravity it is the specific impulse in seconds,
## and it is the only thing that decides how far a given tank of fuel can throw a given mass.
@export_range(500.0, 5000.0, 10.0) var exhaust := 2600.0
## How far the engines can swivel, degrees. Below the atmosphere this is the only control
## there is.
@export_range(0.0, 12.0, 0.1) var gimbal := 5.0
## Seconds an engine needs to come up to pressure. On a large liquid engine this is not an
## instant: the chamber takes one to three seconds, and the rocket is still on the table for
## all of it.
@export_range(0.0, 8.0, 0.1) var spool := 2.2
## One bell with its plume. A scene, so the shape of an engine is drawn and not written.
@export var nozzle_scene: PackedScene

## Which group separates together. Four side blocks share a number and leave as one event.
@export_range(0, 4, 1) var group := 0
## Lit on the pad, whatever group it belongs to. This is what an R-7 is: the core burns with
## the boosters from the first second and keeps burning after they leave. A flag rather than
## an assumption — most rockets are not built that way, and the difference is the vehicle.
@export var starts_lit := false
## How much more this engine gives with no air on the nozzle. An RD-107A goes from 838 kN at
## sea level to 1021 kN in vacuum — a fifth again, for free, and specific impulse rises by
## the same factor, so the mass flow does not change at all.
@export_range(1.0, 1.6, 0.01) var vacuum_gain := 1.22

var fuel := 1.0
var lit := false
var spent := false
var since_light := 0.0

var _flames: Array[Node3D] = []

@onready var _mount: Node3D = $Nozzles


func _ready() -> void:
	_build()


func thrust() -> float:
	return float(engines) * chamber


func mass() -> float:
	return dry_mass + propellant * fuel


## WHERE THE NOZZLES ARE, along the stack's own axis: thrust is applied there, and the distance
## to the centre of mass is the entire lever the gimbal works with. Taken from the mount node,
## so moving the engines in the editor moves the rocket's authority over itself.
func nozzle() -> float:
	return position.z + (_mount.position.z * scale.z if _mount != null else 0.0)


## WHERE THE PLUMES POINT. The body writes it and the nodes turn, so the gimbal stops being a
## number in the readout — and below the atmosphere it is the only control there is.
func aim(tilt: Basis) -> void:
	for flame in _flames:
		flame.basis = tilt


## Burn for one tick at the given throttle. Returns the thrust actually produced; asking a
## dry stage for thrust is not an error, it simply gives nothing.
## `air` is one at sea level and zero above the atmosphere.
func burn(throttle: float, delta: float, air: float) -> float:
	var ramp := 1.0 if spool <= 0.0 else clampf(since_light / spool, 0.0, 1.0)
	var alight := lit and fuel > 0.0 and throttle > MIN_THROTTLE
	for flame in _flames:
		flame.visible = alight
		flame.scale = Vector3.ONE * (0.35 + 0.65 * ramp)
	if not alight:
		return 0.0
	since_light += delta
	# Coming up to pressure. While it lasts there IS thrust, and there is not enough of it —
	# the rocket stands on the table with the engines running.
	ramp = 1.0 if spool <= 0.0 else clampf(since_light / spool, 0.0, 1.0)
	var gain := lerpf(vacuum_gain, 1.0, clampf(air, 0.0, 1.0))
	var push := thrust() * gain * throttle * ramp
	# Mass flow is thrust over exhaust speed. Everything else about rocket performance is a
	# consequence of this one line — including the fact that height buys thrust for nothing:
	# the gain multiplies thrust and exhaust speed alike, so it cancels here and the pumps
	# keep pushing the same kilograms per second.
	var flow := push / (exhaust * gain)
	var used := flow * delta / maxf(propellant, 0.001)
	if fuel - used <= 0.0:
		var part := fuel / maxf(used, 1e-9)
		fuel = 0.0
		spent = true
		return push * part
	fuel -= used
	return push


## The ring of chambers. Angle zero points at +X and the first bell goes there, so a block
## turned in the editor turns its engines with it.
func _build() -> void:
	if nozzle_scene == null or _mount == null:
		return
	for index in engines:
		var one := nozzle_scene.instantiate() as Node3D
		var angle := TAU * float(index) / float(engines)
		one.position = Vector3(cos(angle), sin(angle), 0.0) * (ring if engines > 1 else 0.0)
		_mount.add_child(one)
		var flame := one.get_node_or_null("Flame") as Node3D
		if flame != null:
			flame.visible = false
			_flames.append(flame)
