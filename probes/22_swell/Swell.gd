class_name Swell
extends RefCounted

# 22 — one wave, two counters.
#
# Ported from worldbox-0: scripts/modules/water/WaterField.gd (_gen, height) and
# shaders/ocean_waves.gdshaderinc (wave_disp). The spectrum here is his, component for
# component, so the numbers below are about his sea and not about a toy.
#
# The probe exists because two of his own comments disagree:
#
#   ocean_waves.gdshaderinc:  "поверхность на экране и поверхность под килем -
#                              ОДИН расчёт"
#   WaterField.height():      "по PHYS_COMPONENTS длинным волнам и без горизонтального
#                              сноса Герстнера ... ошибка порядка крутизны,
#                              на глаз незаметна"
#
# They are not one calculation. The physics reads 8 components of 48 and skips the
# horizontal part of Gerstner entirely. Both approximations are reasonable and both
# are unmeasured. This file makes the third thing — the surface you actually SEE —
# so the other two can be compared against it.

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

var wave_len := 60.0
var wave_height := 2.4
var steepness := 0.4
var wind := Vector2(1.0, 0.0)


func build(len_m: float, height_m: float, steep: float) -> void:
	wave_len = len_m
	# below the breaking limit with room to spare: at the limit the whole surface is foam
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
		var a := pow(l / wave_len, 0.9)              # longer is taller: the spectrum slope
		# swell holds the wind's course, chop is nearly isotropic. one narrow fan for
		# everything drew a single diagonal stripe across the whole sea.
		var spread := deg_to_rad(lerpf(18.0, 85.0, t))
		var d := wind.normalized().rotated(rng.randf_range(-spread, spread))
		raw.append({"d": d, "l": l, "a": a, "ph": rng.randf_range(0.0, TAU)})
		energy += a * a
	# normalised by ENERGY: sqrt(sum a^2) = H / 2sqrt2, so sigma = H/4
	var scale := wave_height / (2.0 * sqrt(2.0)) / sqrt(energy)
	for c in raw:
		var k: float = TAU / float(c["l"])
		dirs.append(c["d"])
		ks.append(k)
		amps.append(float(c["a"]) * scale)
		phases.append(float(c["ph"]))
		omegas.append(sqrt(G * k))
		# group breathing: a wave packet swells and dies away over 10-30 s
		mrate.append(rng.randf_range(0.2, 0.6))
		mphase.append(rng.randf_range(0.0, TAU))


func amp_at(i: int, t: float) -> float:
	return amps[i] * (0.72 + 0.28 * sin(mrate[i] * t + mphase[i]))


# --- the three answers --------------------------------------------------------

## What the physics does today: n components, a plain sum of sines, no horizontal
## displacement at all. Cheap, and called several times per ship per frame.
func phys(x: float, z: float, t: float, n: int) -> float:
	var h := 0.0
	for i in mini(n, N):
		var d := dirs[i]
		h += amp_at(i, t) * sin(ks[i] * (d.x * x + d.y * z) - omegas[i] * t + phases[i])
	return h


## The displacement the SHADER applies: a Gerstner sum. Points move sideways as well
## as up, which is what sharpens the crests.
func disp(p: Vector2, t: float, n: int) -> Vector3:
	var out := Vector3.ZERO
	var m := mini(n, N)
	for i in m:
		var d := dirs[i]
		var a := amp_at(i, t)
		var q: float = steepness / (ks[i] * a * float(m)) if a > 0.0 else 0.0
		var ph: float = ks[i] * (d.x * p.x + d.y * p.y) - omegas[i] * t + phases[i]
		out.x += q * a * d.x * cos(ph)
		out.z += q * a * d.y * cos(ph)
		out.y += a * sin(ph)
	return out


## The height you actually SEE at world (x, z).
##
## Gerstner moves points sideways, so the vertex that ends up over (x, z) did not
## start there. Finding it is a fixed-point solve: guess that it started at (x, z),
## see where that lands, step back by the error, repeat. Four rounds is plenty below
## the breaking limit. This is the "решается итерацией" his comment refuses to pay for.
func truth(x: float, z: float, t: float, rounds := 4) -> float:
	var u := Vector2(x, z)
	for _r in rounds:
		var d := disp(u, t, N)
		u = Vector2(x - d.x, z - d.z)
	return disp(u, t, N).y


func steep_of(t: float) -> float:
	# how close the surface is to folding over: the smallest horizontal jacobian
	# anywhere is what decides whether a crest breaks
	var worst := 1.0
	for gx in 12:
		for gz in 12:
			var p := Vector2(float(gx) * 7.3, float(gz) * 5.9)
			worst = minf(worst, jacobian(p, t))
	return worst


func jacobian(p: Vector2, t: float) -> float:
	var jxx := 0.0
	var jxz := 0.0
	var jzx := 0.0
	var jzz := 0.0
	for i in N:
		var d := dirs[i]
		var a := amp_at(i, t)
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
