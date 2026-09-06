class_name DayCycle
extends RefCounted

## A day is not "rotate the light". It is half a dozen curves that have to agree with each
## other, and the moment one disagrees the hour stops reading as an hour.
##
## Sun angle, sun colour, sun brightness, ambient level, fog colour, fog density, which
## body is the key light at all — every one of them is a function of the same number, and
## every one of them has to change at the same moment. Get the colour right and the
## brightness wrong and you get a lit night; get the fog wrong and the distance stops
## agreeing with the sky it fades into.

## Sun elevation at noon. Below the equator this flips, and at the poles the whole model
## stops making sense — which is a design decision, not a bug.
const NOON := 62.0
const AZIMUTH := -35.0

## Rayleigh optical depth at the zenith, per channel. Short wavelengths scatter as the
## fourth power of frequency, so blue is thinned three times harder than red even straight
## overhead. The small constant added to each is aerosol, which is nearly grey.
const TAU := Vector3(0.068 + 0.04, 0.103 + 0.04, 0.229 + 0.04)


## HOW MUCH AIR the beam actually crosses, in units of "straight up". This is the honest
## answer to "is density accounted for": a real atmosphere thins exponentially with height,
## and 1/sin(elevation) gets that badly wrong near the horizon. Kasten and Young fitted the
## real profile — one over the zenith, 5.6 at ten degrees, thirty-eight at the horizon.
##
## Thirty-eight is why the last degrees are dramatic; 5.6 is why the yellowing starts long
## before that, which the hand-drawn curve it replaced did not do.
static func air_mass(elev_deg: float) -> float:
	var h := maxf(elev_deg, -1.2)
	return 1.0 / (sin(deg_to_rad(h)) + 0.50572 * pow(h + 6.07995, -1.6364))

var hour := 9.0            ## 0..24
var sun_dir := Vector3.DOWN
var moon_dir := Vector3.UP
var sun_energy := 1.0
var sun_colour := Color.WHITE
var ambient := 1.0
var fog_colour := Color(0.5, 0.6, 0.7)
var fog_density := 0.002
var label := ""


## Sun pitch over the day: below the horizon at night, NOON degrees up at midday. A sine
## is not right — the real thing depends on latitude and season — but it is right in the
## one way that matters here: it crosses zero at the same two moments every day, and those
## two moments are what the eye reads as dawn and dusk.
func step(h: float) -> void:
	hour = fposmod(h, 24.0)
	var t := (hour - 6.0) / 12.0 * PI          # 6:00 sunrise, 18:00 sunset
	var pitch := sin(t) * NOON
	# AZIMUTH SWEEPS, and leaving it fixed was a real mistake, not a simplification.
	# Elevation alone is SYMMETRIC about noon: 11:30 and 12:30 give the same angle. With a
	# fixed bearing, morning and afternoon are pixel-identical, shadows never swing round,
	# and winding the clock BACK after noon looks exactly like winding it forward — which is
	# how the bug was found. Fifteen degrees an hour is the real rate: the sky turns once a
	# day, so ±90° between sunrise and sunset.
	var az := AZIMUTH + (hour - 12.0) * 15.0
	sun_dir = _dir(pitch, az)
	moon_dir = _dir(-pitch, az + 180.0)

	# above the horizon in degrees, and everything below hangs off it
	var up := sin(deg_to_rad(pitch))

	# COLOUR AND BRIGHTNESS FROM THE SAME TRANSMITTANCE, and this replaced a hand-drawn
	# curve that was wrong in a way a player caught: it only warmed in the last few degrees,
	# whereas real sunlight starts yellowing far higher up. The old curve was invented; this
	# one is what is LEFT of the beam after crossing `air_mass` atmospheres.
	var m := air_mass(pitch)
	var through := Vector3(exp(-TAU.x * m), exp(-TAU.y * m), exp(-TAU.z * m))
	# colour is the shape of what survives, brightness is how much of it survives: splitting
	# them means the light can redden without the scene also going dark by the same factor
	var peak: float = maxf(through.x, maxf(through.y, through.z))
	sun_colour = Color(through.x / peak, through.y / peak, through.z / peak)
	var lum := through.x * 0.21 + through.y * 0.72 + through.z * 0.07
	# 3.4, and the number matters more than it looks. On a clear day the sun is several
	# times brighter than the whole sky put together; with them equal the scene reads as
	# OVERCAST at noon — flat, blue, shadowless — while every individual value looks sane.
	# "Sunny" is not a brightness, it is a RATIO between the two lights.
	sun_energy = smoothstep(-0.10, 0.10, up) * lum * 3.4

	# AMBIENT is where games lie, and have to. Real night is a thousand times darker than
	# day; a night the player cannot see through is a night nobody plays. This floor is the
	# lie, and it is deliberate.
	# 0.65, not 1.0. The sky IS the ambient light, so its brightness and this number
	# multiply: a sky tuned to look right and an ambient of one together washed the whole
	# scene to white at noon, shadows and all. Two knobs, one exposure.
	ambient = maxf(smoothstep(-0.18, 0.30, up) * 0.65, 0.11)

	# FOG has to end up the colour of the sky it fades into, or the horizon comes apart.
	var day := Color(0.52, 0.63, 0.78)
	var dusk := Color(0.62, 0.40, 0.30)
	var night := Color(0.05, 0.07, 0.13)
	var duskness := clampf(1.0 - absf(up) * 6.0, 0.0, 1.0)
	fog_colour = night.lerp(day, smoothstep(-0.08, 0.30, up)).lerp(dusk, duskness * 0.75)
	# and thicker when the air is cold and still, which is the small hours
	fog_density = lerpf(0.0055, 0.0018, smoothstep(-0.05, 0.35, up))

	label = _name_of(hour)


func _dir(pitch_deg: float, yaw_deg: float) -> Vector3:
	var p := deg_to_rad(pitch_deg)
	var y := deg_to_rad(yaw_deg)
	# direction the light TRAVELS, i.e. from the body towards the ground
	return Vector3(-cos(p) * sin(y), -sin(p), -cos(p) * cos(y)).normalized()


func _name_of(h: float) -> String:
	if h < 4.5:
		return "глухая ночь"
	if h < 6.5:
		return "рассвет"
	if h < 9.0:
		return "утро"
	if h < 15.5:
		return "день"
	if h < 17.5:
		return "предвечерье"
	if h < 19.5:
		return "закат"
	if h < 21.5:
		return "сумерки"
	return "ночь"
