class_name FftSines
extends RefCounted
## The sum-of-sines side of the comparison, cut down to only what this probe needs.
##
## Copied from probe 22 rather than imported: probes do not share code, and copying is
## the price of being able to change one without breaking the other. What is gone here
## is everything about physics — the iterative solve and the jacobian as a public
## answer — because this probe is not about where a ship floats. It is about what N
## components buy you.

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

var wave_len := 90.0
var wave_height := 3.0
var steepness := 0.6


func build(length: float, height: float, steep: float) -> void:
	wave_len = length
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
		var amplitude := pow(length_i / wave_len, 0.9)
		var spread := deg_to_rad(lerpf(18.0, 85.0, along))
		raw.append({
			"direction": Vector2.RIGHT.rotated(random.randf_range(-spread, spread)),
			"length": length_i,
			"amplitude": amplitude,
			"phase": random.randf_range(0.0, TAU),
		})
		energy += amplitude * amplitude
	var scale := wave_height / (2.0 * sqrt(2.0)) / sqrt(energy)
	for component in raw:
		var number: float = TAU / float(component["length"])
		directions.append(component["direction"])
		wave_numbers.append(number)
		amplitudes.append(float(component["amplitude"]) * scale)
		phases.append(float(component["phase"]))
		omegas.append(sqrt(GRAVITY * number))
		group_rate.append(random.randf_range(0.2, 0.6))
		group_phase.append(random.randf_range(0.0, TAU))


## Worst horizontal compression on a grid — the foam threshold has to be calibrated
## against it, as probe 22 measured.
func worst_squeeze(at_time: float) -> float:
	var worst := 1.0
	for grid_x in 10:
		for grid_z in 10:
			var at := Vector2(float(grid_x) * 8.7, float(grid_z) * 6.3)
			worst = minf(worst, _jacobian(at, at_time))
	return worst


func _jacobian(at: Vector2, at_time: float) -> float:
	var jxx := 0.0
	var jxz := 0.0
	var jzx := 0.0
	var jzz := 0.0
	for i in COMPONENTS:
		var direction := directions[i]
		var breath := sin(group_rate[i] * at_time + group_phase[i])
		var amplitude := amplitudes[i] * (0.72 + 0.28 * breath)
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
