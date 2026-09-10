class_name MissileFin
extends Node3D
## ONE CONTROL SURFACE.
##
## A fin is a node with a position, and that is the whole point: the force it makes is
## applied AT that position, so pitching moment, roll coupling and weathercock stability
## all fall out of the geometry instead of being written down. Move the fin forward of the
## centre of mass in the editor and the missile becomes unstable — no code knows about it.
##
## The fin only reports its force. Deciding how far to deflect belongs to the body, which
## is the thing that has a command to obey.
##
## The blade TURNS, and that is not decoration. The probe's whole claim is that the hand
## moves fins and not the missile; a fin that answers only in a readout leaves the claim
## unproven on screen. Writing `deflect` rotates the node, so the actuator is a moving part.

## Below this airspeed, in metres per second, there is nothing for a fin to bite on.
const MIN_FLOW := 1.0

## Area of the blade, in square metres, on which every force it makes is scaled.
@export_range(0.0, 0.2, 0.0005) var area := 0.022
## Lift per radian of angle. Thin plates sit near 2*PI in theory and well under it in air.
@export_range(0.5, 8.0, 0.1) var lift_slope := 3.4
## Past this angle, in radians, the flow separates and the fin stops paying. This is the
## real reason a missile cannot simply be told to turn harder.
@export_range(0.05, 0.6, 0.005) var stall := 0.28
## Mechanical travel of the actuator, radians.
@export_range(0.05, 0.6, 0.005) var max_deflect := 0.30

## Commanded deflection in radians, written by the body every tick. The setter turns the
## blade about its own span, which is where a control surface hinges.
var deflect := 0.0:
	set(value):
		deflect = value
		if _blade != null:
			_blade.rotation.x = value

## Last force this fin produced, newtons, for the readout.
var last_force := 0.0

@onready var _blade: Node3D = $Blade


## Lift direction in the airframe's own frame: the fin's +Y after its roll rotation. A fin
## turned 90 degrees lifts sideways, and that is what makes a cruciform missile steer in yaw.
func axis() -> Vector3:
	return basis.y.normalized()


## Force in world space. `flow` is the air coming at the missile in world coordinates,
## `pressure` the dynamic pressure. The fin sees the flow projected onto its own lift plane,
## adds the actuator angle on top, and stalls when the sum runs out of room.
##
## The angle is taken from the MOUNT and not from the blade: turning the blade is what the
## eye is for, and adding it to the mount frame as well would count the same deflection
## twice.
func force(flow: Vector3, pressure: float) -> Vector3:
	var lift_dir := (global_basis * Vector3.UP).normalized()
	var along := -flow.normalized()
	if flow.length_squared() < MIN_FLOW:
		last_force = 0.0
		return Vector3.ZERO
	# Angle the fin already meets before the actuator moves: the airframe's own attitude.
	var incidence := asin(clampf(-along.dot(lift_dir), -1.0, 1.0))
	var total := clampf(incidence + deflect, -stall, stall)
	var lift := pressure * area * lift_slope * total
	last_force = lift
	return lift_dir * lift
