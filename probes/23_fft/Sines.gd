class_name FftSines
extends RefCounted

# The sum-of-sines side of the comparison, cut down to only what this probe needs.
#
# Copied from probe 22 rather than imported: probes do not share code, and copying is
# the price of being able to change one without breaking the other. What is gone here
# is everything about physics — the iterative solve and the jacobian — because this
# probe is not about where a ship floats. It is about what N components buy you.

const N := 48
const G := 9.81
const SEED := 20240517

var dirs := PackedVector2Array()
var ks := PackedFloat32Array()
var amps := PackedFloat32Array()
var phases := PackedFloat32Array()
var omegas := PackedFloat32Array()
var mrate := PackedFloat32Array()
var mphase := PackedFloat32Array()

var wave_len := 90.0
var wave_height := 3.0
var steepness := 0.6


func build(len_m: float, height_m: float, steep: float) -> void:
	wave_len = len_m
	wave_height = minf(height_m, len_m / 9.5)
	steepness = steep
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	dirs = PackedVector2Array()
	ks = PackedFloat32Array()
	amps = PackedFloat32Array()
	phases = PackedFloat32Array()
	omegas = PackedFloat32Array()
	mrate = PackedFloat32Array()
	mphase = PackedFloat32Array()
	var raw: Array = []
	var energy := 0.0
	var l_min: float = maxf(0.6, wave_len / 22.0)
	for i in N:
		var t := float(i) / float(N - 1)
		var l: float = wave_len * pow(l_min / wave_len, t)
		var a := pow(l / wave_len, 0.9)
		var spread := deg_to_rad(lerpf(18.0, 85.0, t))
		var d := Vector2.RIGHT.rotated(rng.randf_range(-spread, spread))
		raw.append({"d": d, "l": l, "a": a, "ph": rng.randf_range(0.0, TAU)})
		energy += a * a
	var scale := wave_height / (2.0 * sqrt(2.0)) / sqrt(energy)
	for c in raw:
		var k: float = TAU / float(c["l"])
		dirs.append(c["d"])
		ks.append(k)
		amps.append(float(c["a"]) * scale)
		phases.append(float(c["ph"]))
		omegas.append(sqrt(G * k))
		mrate.append(rng.randf_range(0.2, 0.6))
		mphase.append(rng.randf_range(0.0, TAU))


## Worst horizontal compression on a grid — the foam threshold has to be calibrated
## against it, as probe 22 measured.
func worst_fold(t: float) -> float:
	var worst := 1.0
	for gx in 10:
		for gz in 10:
			worst = minf(worst, _jac(Vector2(float(gx) * 8.7, float(gz) * 6.3), t))
	return worst


func _jac(p: Vector2, t: float) -> float:
	var jxx := 0.0
	var jxz := 0.0
	var jzx := 0.0
	var jzz := 0.0
	for i in N:
		var d := dirs[i]
		var a: float = amps[i] * (0.72 + 0.28 * sin(mrate[i] * t + mphase[i]))
		if a <= 0.0:
			continue
		var q: float = steepness / (ks[i] * a * float(N))
		var ph: float = ks[i] * (d.x * p.x + d.y * p.y) - omegas[i] * t + phases[i]
		var qka: float = q * a * ks[i] * sin(ph)
		jxx -= qka * d.x * d.x
		jxz -= qka * d.x * d.y
		jzx -= qka * d.y * d.x
		jzz -= qka * d.y * d.y
	return (1.0 + jxx) * (1.0 + jzz) - jxz * jzx
