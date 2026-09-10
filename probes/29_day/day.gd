class_name DayBench
extends Node3D
## 29 — the sky, and what it costs to have one that moves.
##
## Two skies over the same hour:
##   ВСТРОЕННОЕ  ProceduralSkyMaterial — three colours and a blur. Free, and it cannot
##               make a sunset, because a sunset is not a colour.
##   СВОЁ        single scattering computed per pixel. Every colour comes from geometry.
##
## And the lever nobody finds until the frame drops: a sky that CHANGES has to re-bake its
## radiance map, because the sky is not a backdrop — it is the ambient light of the scene
## and its reflections. That bake is the same shape as UPDATE_ALWAYS in probe 25.

const SPEEDS := [0.0, 0.6, 4.0]
## The real lever, and it is not the radiance size: REALTIME pins that to 256 whatever you
## ask for ("Realtime Skies can only use a radiance size of 256"). What you actually
## choose is HOW OFTEN the sky is turned back into light.
const MODES := [
	Sky.PROCESS_MODE_REALTIME,
	Sky.PROCESS_MODE_INCREMENTAL,
	Sky.PROCESS_MODE_QUALITY,
]
const MODE_NAMES := [
	"каждый кадр (REALTIME)",
	"по кусочкам (INCREMENTAL)",
	"полный пересчёт (QUALITY)",
]
const SKY_NAMES := [
	"встроенное: три цвета",
	"рассеяние: посчитано",
	"Пришем: подгонка к измеренным небесам",
	"градиент: как в играх",
]

## 0 built-in, then three models inside one shader. Four answers to the same hour.
@export_range(0, 3) var sky_kind := 1
@export_range(0.0, 24.0) var hour := 17.6
@export_range(0, 2) var speed := 1
@export var fog := true
## Sky as a light source. Turning it off is how you find out how much of the picture is
## the sky rather than the sun. Measured: 22 % at noon, 31 % once the sun is down —
## against a flat ambient colour, which is what a game would fall back to.
@export var sky_lights := true
@export_range(0, 2) var sky_mode := 0
## POST. Not part of the sky at all, and that is the point: a fixed exposure plus no grade
## is not how any shipped game looks. The eye adapts, and the picture is graded
## afterwards. Toggling this is how you find out how much of "AAA" is the sky model and
## how much is the two hundred lines of post nobody talks about.
@export var post := true

var cycle := DayCycle.new()
## Smoothed GPU frame time, milliseconds.
var frame_ms := 0.0

var _environment: Environment
var _own_sky: ShaderMaterial
var _stock_sky: ProceduralSkyMaterial
# Pointed roughly along the sun azimuth and tilted up: the subject of this probe is the
# sky, and a camera aimed at the ground shows none of it.
var _yaw := -0.61
var _pitch := 0.26
var _looking := false

@onready var _camera: Camera3D = $Camera
@onready var _sun: DirectionalLight3D = $Sun
@onready var _moon: DirectionalLight3D = $Moon
@onready var _world: WorldEnvironment = $WorldEnvironment
@onready var _info: RichTextLabel = $Ui/Info


func _ready() -> void:
	RenderingServer.viewport_set_measure_render_time(
			get_viewport().get_viewport_rid(), true)
	_environment = _world.environment
	_own_sky = load("res://probes/29_day/sky_mat.tres")
	_stock_sky = ProceduralSkyMaterial.new()
	_stock_sky.sky_horizon_color = Color(0.72, 0.76, 0.82)
	_stock_sky.ground_horizon_color = Color(0.72, 0.76, 0.82)
	_apply()


func _process(delta: float) -> void:
	hour = fposmod(hour + SPEEDS[speed] * delta, 24.0)
	cycle.step(hour)

	# Both bodies are always in the scene; what changes is which one has any energy left.
	# A moon that switches off at dawn instead of fading gives the hour away.
	_sun.global_transform.basis = Basis.looking_at(cycle.sun_dir)
	_moon.global_transform.basis = Basis.looking_at(cycle.moon_dir)
	_sun.light_energy = cycle.sun_energy
	_sun.light_color = cycle.sun_colour
	_moon.light_energy = 0.10 * (1.0 - smoothstep(-0.05, 0.20, -cycle.sun_dir.y))
	_moon.light_color = Color(0.62, 0.70, 0.95)

	_environment.ambient_light_energy = cycle.ambient
	_environment.fog_light_color = cycle.fog_colour
	_environment.fog_density = cycle.fog_density
	if sky_kind > 0:
		_own_sky.set_shader_parameter("moon_dir", cycle.moon_dir)

	# The camera stands at a fixed height and aims; it does not orbit. Orbiting put it
	# UNDERGROUND — with the eye placed at -forward * distance, raising the pitch lowers
	# the eye, which is the opposite of what the hand expects.
	var flat := Vector3(sin(_yaw), 0.0, cos(_yaw))
	_camera.global_position = -flat * 26.0 + Vector3(0.0, 5.0, 0.0)
	_camera.look_at(Vector3(0.0, 5.0 + _pitch * 26.0, 0.0))
	frame_ms = lerpf(
			frame_ms,
			RenderingServer.viewport_get_measured_render_time_gpu(
					get_viewport().get_viewport_rid()),
			0.05)
	_draw_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_looking = event.pressed
		return
	if event is InputEventMouseMotion and _looking:
		_yaw -= event.relative.x * 0.005
		_pitch = clampf(_pitch - event.relative.y * 0.004, -0.45, 0.95)
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_TAB:
			sky_kind = (sky_kind + 1) % SKY_NAMES.size()
			_apply()
		KEY_1, KEY_2, KEY_3:
			speed = event.keycode - KEY_1
		KEY_BRACKETLEFT:
			# Stepping by hand stops the clock: otherwise it runs the half-hour back.
			speed = 0
			hour = fposmod(hour - 0.5, 24.0)
		KEY_BRACKETRIGHT:
			speed = 0
			hour = fposmod(hour + 0.5, 24.0)
		KEY_F:
			fog = not fog
			_apply()
		KEY_G:
			sky_lights = not sky_lights
			_apply()
		KEY_P:
			post = not post
			_apply()
		KEY_Z:
			sky_mode = 0
			_apply()
		KEY_X:
			sky_mode = 1
			_apply()
		KEY_C:
			sky_mode = 2
			_apply()


func _apply() -> void:
	_environment.sky.sky_material = _stock_sky if sky_kind == 0 else _own_sky
	if sky_kind > 0:
		_own_sky.set_shader_parameter("model", sky_kind - 1)
	_environment.sky.radiance_size = Sky.RADIANCE_SIZE_256
	_environment.sky.process_mode = MODES[sky_mode]
	_environment.ambient_light_source = (
			Environment.AMBIENT_SOURCE_SKY if sky_lights
			else Environment.AMBIENT_SOURCE_COLOR)
	_environment.reflected_light_source = (
			Environment.REFLECTION_SOURCE_SKY if sky_lights
			else Environment.REFLECTION_SOURCE_DISABLED)
	_environment.fog_enabled = fog
	# fog_sky_affect defaults to 1.0, and that means distance fog REPAINTS THE SKY. The
	# whole gradient, the sun, the twilight band — all replaced by one flat fog colour,
	# and the sky shader looks broken while being perfectly correct. Distance fog has no
	# business on the sky anyway: the sky already carries its own aerial perspective.
	_environment.fog_sky_affect = 0.25
	# THREE exposures stack in this scene and only one of them should be the exposure: the
	# sky shader has a gain, the lights have energies, and the tonemapper has this. Tuning
	# the first two to fix brightness destroys the RATIO between sun and sky, which is
	# what "sunny" and "overcast" actually are. Fix the level here, keep the ratio there.
	_environment.tonemap_exposure = 0.42
	# AUTO-EXPOSURE: walk from shade into sun and the picture settles, the way an eye
	# does. Without it a scene is correct at one hour and wrong at the other twenty-three.
	var attributes: CameraAttributesPractical = _camera.attributes
	if attributes != null:
		attributes.auto_exposure_enabled = post
	# GRADING is the cheapest big lever in rendering and the least discussed: contrast and
	# saturation over the finished frame. A physically perfect render with no grade looks
	# flat, and a modest render with one looks like a game.
	_environment.adjustment_enabled = post
	_environment.adjustment_contrast = 1.18
	_environment.adjustment_saturation = 1.22
	_environment.glow_intensity = 0.9 if post else 0.35


func _draw_hud() -> void:
	var named := "[color=#7fe08a]%s[/color]" % SKY_NAMES[sky_kind]
	if sky_kind == 0:
		named = "[color=#ffd479]%s[/color]" % SKY_NAMES[sky_kind]
	var text := "[b]%02d:%02d[/b]    %s    %s\n\n[table=2]" % [
		int(hour), int(fposmod(hour, 1.0) * 60.0), cycle.label.to_upper(), named]
	text += "[cell]солнце  [/cell]"
	text += "[cell]%.0f° над горизонтом, азимут %.0f°, сила %.2f[/cell]" % [
		rad_to_deg(asin(-cycle.sun_dir.y)),
		rad_to_deg(atan2(-cycle.sun_dir.x, -cycle.sun_dir.z)),
		cycle.sun_energy]
	text += "[cell]цвет солнца  [/cell][cell]%.2f %.2f %.2f[/cell]" % [
		cycle.sun_colour.r, cycle.sun_colour.g, cycle.sun_colour.b]
	text += "[cell]толща воздуха  [/cell]"
	text += "[cell]%.1f× зенитной   (10° = 5.6×, 0° = 38×)[/cell]" % (
			DayCycle.air_mass(rad_to_deg(asin(-cycle.sun_dir.y))))
	text += "[cell]рассеянный свет  [/cell][cell]%.2f[/cell]" % cycle.ambient
	text += "[cell]туман (F)  [/cell][cell]%s, плотность %.4f[/cell]" % [
		"есть" if fog else "нет", cycle.fog_density]
	text += "[cell]небо как свет (G)  [/cell][cell]%s[/cell]" % (
			"[color=#7fe08a]светит и отражается[/color]" if sky_lights
			else "[color=#ff8a6a]выключено — видно, сколько от него[/color]")
	text += "[cell]пост (P)  [/cell][cell]%s[/cell]" % (
			"[color=#7fe08a]адаптация глаза + грейд[/color]" if post
			else "[color=#ff8a6a]выключен — голый рендер[/color]")
	text += "[cell]небо в свет (Z X C)  [/cell][cell]%s[/cell]" % MODE_NAMES[sky_mode]
	text += "[cell]кадр  [/cell][cell]%.2f мс на GPU[/cell]" % frame_ms
	text += "[/table]\n\n"
	text += "TAB — четыре неба по кругу    1 2 3 — время стоит / идёт / бежит\n"
	text += "[ ] — час назад / вперёд    F — туман    G — небо как свет    P — пост\n"
	text += "Z X C — небо в свет: каждый кадр / по кусочкам / полный    ПКМ — осмотреться\n\n"
	text += "[color=#66ccff]час — это не угол, а согласие полудюжины кривых, и все"
	text += " они обязаны меняться в один момент[/color]"
	_info.text = text
