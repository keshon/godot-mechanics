extends Node3D
class_name RocketPlanet

## THE WORLD UNDER THE ROCKET.
##
## Small on purpose. A real Earth means eight kilometres per second and nine minutes of
## ascent, and the probe would be a waiting simulator; a hundred and twenty kilometres of
## radius means orbit at eleven hundred metres per second and two minutes of work. The scale
## is a knob, not a claim.
##
## Everything the flight cares about lives here and nowhere else: which way is down, how
## thick the air is, and how fast one has to go around to stop falling.

## Distance from the centre to the pad. Orbital speed goes as its square root, so this one
## number sets the pace of the whole probe.
@export_range(20000.0, 1000000.0, 1000.0) var radius := 120000.0
@export_range(1.0, 30.0, 0.01) var surface_gravity := 9.81

@export_group("Air")
@export_range(0.0, 3.0, 0.001) var sea_density := 1.225
## Height over which the air thins by a factor of e. Everything about a gravity turn is
## decided by this number against the burn time.
@export_range(500.0, 20000.0, 100.0) var scale_height := 6000.0
## Above this there is nothing left to fly through and nothing left to burn up in.
@export_range(1000.0, 200000.0, 500.0) var edge := 45000.0

## Centre of the world, in world coordinates. Moves with the floating origin, and that is
## the only reason it is a variable rather than a constant.
var centre := Vector3.ZERO


func _ready() -> void:
	centre = global_position


## Height over the surface. Negative means the rocket is in the ground.
func altitude(at: Vector3) -> float:
	return at.distance_to(centre) - radius


## Down, and it is not the same down everywhere: that is the entire reason a gravity turn
## works. Tilt once at the bottom and the planet does the rest of the turning for free.
func down(at: Vector3) -> Vector3:
	var d := centre - at
	return d.normalized() if d.length_squared() > 0.0 else Vector3.DOWN


func gravity(at: Vector3) -> Vector3:
	var r := maxf(at.distance_to(centre), 1.0)
	# Inverse square, normalised so that the surface reads exactly the stated number.
	return down(at) * surface_gravity * (radius * radius) / (r * r)


func density(at: Vector3) -> float:
	var h := altitude(at)
	if h >= edge:
		return 0.0
	return sea_density * exp(-maxf(h, 0.0) / scale_height)


## What it takes to stop falling at a given height. The bar the whole flight is aimed at.
func orbital_speed(height: float) -> float:
	var r := radius + maxf(height, 0.0)
	return sqrt(surface_gravity * radius * radius / r)
