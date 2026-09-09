class_name SwellSea
extends RefCounted
## 22 — one wave, two counters.
##
## Ported from worldbox-0: scripts/modules/water/WaterField.gd (_gen, height) and
## shaders/ocean_waves.gdshaderinc (wave_disp). The spectrum here is his, component
## for component, so the numbers are about his sea and not about a toy.
##
## The probe exists because two of his own comments disagree:
##
##   ocean_waves.gdshaderinc:  "поверхность на экране и поверхность под килем -
##                              ОДИН расчёт"
##   WaterField.height():      "по PHYS_COMPONENTS длинным волнам и без
##                              горизонтального сноса Герстнера ... ошибка порядка
##                              крутизны, на глаз незаметна"
##
## They are not one calculation. The physics reads 8 components of 48 and skips the
## horizontal part of Gerstner entirely. Both approximations are reasonable and both
## are unmeasured. This file makes the third thing — the surface you actually SEE —
## so the other two can be compared against it.

const COMPONENTS := 48
const GRAVITY := 9.81
const SEED := 20240517

var directions := PackedVector2Array()
## Wave numbers, radians per metre.
var wave_numbers := PackedFloat32Array()
var amplitudes := PackedFloat32Array()
var phases := PackedFloat32Array()
## Angular frequencies, radians per second.
var omegas := PackedFloat32Array()
## Group breathing: how fast and where in the cycle each packet swells and dies.
var group_rate := PackedFloat32Array()
var group_phase := PackedFloat32Array()

var wave_len := 60.0
var wave_height := 2.4
var steepness := 0.4
var wind := Vector2(1.0, 0.0)


func build(length: float, height: float, steep: float) -> void:
	wave_len = length
	# Below the breaking limit with room to spare: at the limit the whole surface is
	# foam.
	wave_height = minf(height, length / 9.5)
	steepness = steep
	var random := RandomNumberGenerator.new()
	random.seed = SEED
	directions = PackedVector2Array()
	wave_numbers = PackedFloat32Array()
	amplitudes = PackedFloat32Array()
	phases = PackedFloat32Array()
	omegas = PackedFloat32Array()
	group_rate = PackedFloat32Array()
	group_phase = PackedFloat32Array()
	var raw: Array[Dictionary] = []
	var energy := 0.0
	var shortest: float = maxf(0.6, wave_len / 22.0)
	for i in COMPONENTS:
		var along := float(i) / float(COMPONENTS - 1)
		var length_i: float = wave_len * pow(shortest / wave_len, along)
		# Longer is taller: the slope of the spectrum.
		var amplitude := pow(length_i / wave_len, 0.9)
		# Swell holds the course of the wind, chop is nearly isotropic. One narrow fan
		# for everything drew a single diagonal stripe across the whole sea.
		var spread := deg_to_rad(lerpf(18.0, 85.0, along))
		var direction := wind.normalized().rotated(random.randf_range(-spread, spread))
		raw.append({
			"direction": direction,
			"length": length_i,
			"amplitude": amplitude,
			"phase": random.randf_range(0.0, TAU),
		})
		energy += amplitude * amplitude
	# Normalised by ENERGY: sqrt(sum a^2) = H / 2sqrt2, so sigma = H/4.
	var scale := wave_height / (2.0 * sqrt(2.0)) / sqrt(energy)
	for component in raw:
		var number: float = TAU / float(component["length"])
		directions.append(component["direction"])
		wave_numbers.append(number)
		amplitudes.append(float(component["amplitude"]) * scale)
		phases.append(float(component["phase"]))
		omegas.append(sqrt(GRAVITY * number))
		# A wave packet swells and dies away over 10-30 s.
		group_rate.append(random.randf_range(0.2, 0.6))
		group_phase.append(random.randf_range(0.0, TAU))


func amplitude_at(index: int, at_time: float) -> float:
	var breath := sin(group_rate[index] * at_time + group_phase[index])
	return amplitudes[index] * (0.72 + 0.28 * breath)


## What the physics does today: `count` components, a plain sum of sines, no
## horizontal displacement at all. Cheap, and called several times per ship per frame.
func felt_height(x: float, z: float, at_time: float, count: int) -> float:
	var height := 0.0
	for i in mini(count, COMPONENTS):
		var direction := directions[i]
		var phase := (
				wave_numbers[i] * (direction.x * x + direction.y * z)
				- omegas[i] * at_time + phases[i]
		)
		height += amplitude_at(i, at_time) * sin(phase)
	return height


## The displacement the SHADER applies: a Gerstner sum. Points move sideways as well
## as up, which is what sharpens the crests.
func displacement(at: Vector2, at_time: float, count: int) -> Vector3:
	var total := Vector3.ZERO
	var used := mini(count, COMPONENTS)
	for i in used:
		var direction := directions[i]
		var amplitude := amplitude_at(i, at_time)
		var pinch := 0.0
		if amplitude > 0.0:
			pinch = steepness / (wave_numbers[i] * amplitude * float(used))
		var phase := (
				wave_numbers[i] * (direction.x * at.x + direction.y * at.y)
				- omegas[i] * at_time + phases[i]
		)
		total.x += pinch * amplitude * direction.x * cos(phase)
		total.z += pinch * amplitude * direction.y * cos(phase)
		total.y += amplitude * sin(phase)
	return total


## The height you actually SEE at world (x, z).
##
## Gerstner moves points sideways, so the vertex that ends up over (x, z) did not
## start there. Finding it is a fixed-point solve: guess that it started at (x, z),
## see where that lands, step back by the error, repeat. Four rounds is plenty below
## the breaking limit. This is the "решается итерацией" his comment refuses to pay for.
func seen_height(x: float, z: float, at_time: float, rounds := 4) -> float:
	var start := Vector2(x, z)
	for _round in rounds:
		var moved := displacement(start, at_time, COMPONENTS)
		start = Vector2(x - moved.x, z - moved.z)
	return displacement(start, at_time, COMPONENTS).y


## How close the surface is to folding over. The smallest horizontal jacobian anywhere
## is what decides whether a crest breaks, so the foam threshold is calibrated against
## this number rather than chosen.
func worst_squeeze(at_time: float) -> float:
	var worst := 1.0
	for grid_x in 12:
		for grid_z in 12:
			var at := Vector2(float(grid_x) * 7.3, float(grid_z) * 5.9)
			worst = minf(worst, jacobian(at, at_time))
	return worst


func jacobian(at: Vector2, at_time: float) -> float:
	var jxx := 0.0
	var jxz := 0.0
	var jzx := 0.0
	var jzz := 0.0
	for i in COMPONENTS:
		var direction := directions[i]
		var amplitude := amplitude_at(i, at_time)
		if amplitude <= 0.0:
			continue
		var pinch := steepness / (wave_numbers[i] * amplitude * float(COMPONENTS))
		var phase := (
				wave_numbers[i] * (direction.x * at.x + direction.y * at.y)
				- omegas[i] * at_time + phases[i]
		)
		var factor := pinch * amplitude * wave_numbers[i] * sin(phase)
		jxx -= factor * direction.x * direction.x
		jxz -= factor * direction.x * direction.y
		jzx -= factor * direction.y * direction.x
		jzz -= factor * direction.y * direction.y
	return (1.0 + jxx) * (1.0 + jzz) - jxz * jzx
