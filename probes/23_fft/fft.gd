class_name FftOcean
extends Node3D
## 23 — two oceans under one sky.
##
##   sines — 48 plane waves, summed per vertex.
##   FFT   — a spectrum filled in frequency space and inverse-transformed on compute
##           shaders into displacement and normal maps, map_size^2 components per
##           cascade.
##
## One camera, one sun, one clock. Press TAB and look at the same water twice.
##
## The addon is 2Retr0/GodotOceanWaves (MIT), vendored in addons/ocean_waves_fft with
## his own notes on what he changed. It is a DEPENDENCY, not probe code — the six-file
## rule counts what the probe writes, the same way probe 15 let content/ grow.

const SEAS: Array[Dictionary] = [
	{"name": "зыбь", "length": 70.0, "height": 1.4, "steep": 0.4, "storm": 0.15,
		"over": 0.006, "wind": 12.0, "fetch": 400.0, "whitecap": 0.35, "foam": 3.0},
	{"name": "рабочее море", "length": 90.0, "height": 3.0, "steep": 0.6, "storm": 0.45,
		"over": 0.012, "wind": 20.0, "fetch": 550.0, "whitecap": 0.5, "foam": 5.0},
	{"name": "шторм", "length": 130.0, "height": 8.0, "steep": 0.82, "storm": 1.0,
		"over": 0.024, "wind": 32.0, "fetch": 900.0, "whitecap": 0.75, "foam": 7.0},
]

## Tile lengths that do not share a period: one long swell, one sea, one chop, each
## its own transform, summed. That is the thing a single sine sum cannot do at any
## component count you can afford.
const TILES := [
	Vector2(456.0, 456.0),
	Vector2(97.0, 97.0),
	Vector2(19.0, 19.0),
]
const TILE_SCALES := [1.0, 0.75, 0.4]

@export var show_fft := true
@export_range(0, 2) var sea_state := 1
@export var map_size := 256
@export_range(1, 3) var cascades := 3
@export var fly_speed := 26.0
## His own transparency edit in the addon ships switched OFF ("0 -> как оригинал").
@export var transparent := true
## SUBSURFACE SCATTERING. The addon already has the term; the sines surface got one
## written to match. Both hang off the same switch so the comparison stays fair.
@export var sss := true
@export_range(0.0, 30.0) var sss_gain := 12.0
## Sun elevation, degrees, and it is not a decoration: this single number decides
## whether the effect exists at all. Light has to come THROUGH the crest, so the sun
## must be low enough to be behind one.
@export_range(-80.0, -2.0) var sun_pitch := -38.0
## Wave amplitude on top of the preset. The three sea states are points, and points
## are not enough to find the one place where a look works: that is between them.
@export_range(0.2, 3.0) var wave_scale := 1.0
## Тон воды в прямом свете аддона. 0 — как в оригинале (белый диффуз), отчего при
## высоком солнце поверхность белеет.
@export_range(0.0, 1.0) var diffuse_tint := 0.85
## Цвет воды по глубине и прибой у кромки. Оба в аддоне выключены по умолчанию.
@export var depth_color := true
@export_range(0.0, 6.0) var shore_foam := 1.8
## Солнечные пятна: мелкая рябь живёт дальше, блик уже. Три ручки одним переключателем.
@export var glitter := true

## Wave time, seconds.
var clock := 0.0
## Smoothed GPU frame time, milliseconds.
var frame_ms := 0.0
var fft: FFTWaterSurface
var sines := FftSines.new()

var _fft_material: ShaderMaterial
var _yaw := 0.35
var _pitch := -0.13
var _looking := false

@onready var _camera: Camera3D = $Camera
@onready var _sun: DirectionalLight3D = $Sun
@onready var _info: RichTextLabel = $Ui/Info
@onready var _sines_mesh: MeshInstance3D = $Sines
@onready var _sines_material := _sines_mesh.material_override as ShaderMaterial


func _ready() -> void:
	var viewport := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	# No RenderingDevice means no compute shaders, which means no FFT at all. That is
	# not a guard against a rare case: it is the whole headless mode. Probe 22 could
	# be measured with --headless; this one cannot, and neither can anything
	# downstream of it. A sum of sines runs anywhere; an FFT ocean needs a GPU.
	if RenderingServer.get_rendering_device() == null:
		show_fft = false
		_apply()
		return
	fft = FFTWaterSurface.new()
	fft.name = "Waves"
	fft.material_override = load("res://addons/ocean_waves_fft/mat_water.tres")
	fft.mesh_quality = FFTWaterSurface.MeshQuality.LOW
	_fft_material = fft.material_override as ShaderMaterial
	add_child(fft)
	_apply()


func _process(delta: float) -> void:
	_fly(delta)
	clock += delta
	_sines_material.set_shader_parameter("wave_time", clock)
	_sines_mesh.visible = not show_fft or fft == null
	_light()
	if fft != null:
		fft.visible = show_fft
		fft.set_process(show_fft)
		# The clipmap is a fixed patch: it has to follow the eye or you sail off it.
		fft.global_position = Vector3(
				_camera.global_position.x, 0.0, _camera.global_position.z)
	# Время GPU, а не delta. delta упирается в vsync: на мониторе 200 Гц она
	# показывала ровно 5.00 мс во всех режимах подряд — то есть меряла монитор.
	var measured := RenderingServer.viewport_get_measured_render_time_gpu(
			get_viewport().get_viewport_rid())
	frame_ms = lerpf(frame_ms, measured, 0.05)
	_draw_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_looking = event.pressed
			Input.set_mouse_mode(
					Input.MOUSE_MODE_CAPTURED if _looking else Input.MOUSE_MODE_VISIBLE)
		return
	if event is InputEventMouseMotion and _looking:
		_yaw -= event.relative.x * 0.0035
		_pitch = clampf(_pitch - event.relative.y * 0.0035, -1.4, 1.4)
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_G:
			transparent = not transparent
		KEY_B:
			sss = not sss
		KEY_N:
			diffuse_tint = 0.0 if diffuse_tint > 0.0 else 0.85
		KEY_M:
			depth_color = not depth_color
		KEY_K:
			glitter = not glitter
			_apply()
		KEY_EQUAL, KEY_KP_ADD:
			wave_scale = minf(wave_scale + 0.15, 3.0)
			_apply()
		KEY_MINUS, KEY_KP_SUBTRACT:
			wave_scale = maxf(wave_scale - 0.15, 0.2)
			_apply()
		KEY_BRACKETLEFT:
			sun_pitch = clampf(sun_pitch - 5.0, -80.0, -2.0)
		KEY_BRACKETRIGHT:
			sun_pitch = clampf(sun_pitch + 5.0, -80.0, -2.0)
		KEY_L:
			_face_sun()
		KEY_TAB:
			# NOT a letter next to WASD. This sat on S and F, and S is move_back:
			# stepping backwards switched the ocean. Second time in this project —
			# probe 21 had a layer on W. On any probe you can walk around in, the
			# toggles live away from the movement keys, full stop.
			if fft != null:
				show_fft = not show_fft
		KEY_1, KEY_2, KEY_3:
			sea_state = event.keycode - KEY_1
			_apply()
		KEY_Z:
			map_size = 128
			_apply()
		KEY_X:
			map_size = 256
			_apply()
		KEY_C:
			map_size = 512
			_apply()
		KEY_V:
			map_size = 1024
			_apply()
		KEY_Q:
			cascades = maxi(cascades - 1, 1)
			_apply()
		KEY_E:
			cascades = mini(cascades + 1, 3)
			_apply()


func _apply() -> void:
	var state: Dictionary = SEAS[sea_state]
	sines.build(
			float(state["length"]),
			float(state["height"]) * wave_scale,
			float(state["steep"]))
	_sines_material.set_shader_parameter("wn", FftSines.COMPONENTS)
	_sines_material.set_shader_parameter("steepness", sines.steepness)
	_sines_material.set_shader_parameter("storm", float(state["storm"]))
	_sines_material.set_shader_parameter("wdirs", sines.directions)
	_sines_material.set_shader_parameter("wks", sines.wave_numbers)
	_sines_material.set_shader_parameter("wamps", sines.amplitudes)
	_sines_material.set_shader_parameter("wphs", sines.phases)
	_sines_material.set_shader_parameter("womg", sines.omegas)
	_sines_material.set_shader_parameter("wmr", sines.group_rate)
	_sines_material.set_shader_parameter("wmp", sines.group_phase)
	_sines_material.set_shader_parameter(
			"fold", sines.worst_squeeze(clock) + float(state["over"]))
	if fft == null:
		return
	var list: Array[WaveCascadeParameters] = []
	for i in cascades:
		var cascade := WaveCascadeParameters.new()
		cascade.tile_length = TILES[i]
		cascade.displacement_scale = float(TILE_SCALES[i]) * wave_scale
		cascade.normal_scale = 1.0 if i < 2 else (0.85 if glitter else 0.35)
		cascade.wind_speed = float(state["wind"])
		cascade.wind_direction = 0.0
		cascade.fetch_length = float(state["fetch"])
		cascade.swell = 0.8
		cascade.spread = 0.2
		cascade.detail = 1.0
		cascade.whitecap = float(state["whitecap"])
		cascade.foam_amount = float(state["foam"])
		list.append(cascade)
	fft.map_size = map_size
	fft.parameters = list


## Sun into both shaders. The sines surface has no light() of its own, so it cannot
## ask the engine where the sun is — the direction has to be handed to it.
func _light() -> void:
	_sun.rotation_degrees.x = sun_pitch
	# The way the light travels, world space.
	var travel := -_sun.global_transform.basis.z
	_sines_material.set_shader_parameter("sun_dir", travel)
	_sines_material.set_shader_parameter("sun_energy", _sun.light_energy)
	_sines_material.set_shader_parameter("sss_on", 1.0 if sss else 0.0)
	_sines_material.set_shader_parameter("sss_gain", sss_gain)
	_sines_material.set_shader_parameter("wave_h", sines.wave_height)
	if _fft_material == null:
		return
	_fft_material.set_shader_parameter("transparency_on", 1.0 if transparent else 0.0)
	_fft_material.set_shader_parameter("sss_gain", sss_gain if sss else 0.0)
	_fft_material.set_shader_parameter("diffuse_tint", diffuse_tint)
	_fft_material.set_shader_parameter("depth_color_on", 1.0 if depth_color else 0.0)
	_fft_material.set_shader_parameter("shore_foam", shore_foam)
	_fft_material.set_shader_parameter("normal_fade", 0.006 if glitter else 0.0175)
	_fft_material.set_shader_parameter("roughness", 0.32 if glitter else 0.65)


## Turn to face the sun. Not a convenience: the glow lives where the water is BETWEEN
## the eye and the sun, and with the sun behind you there is nothing to see no matter
## how high the gain.
func _face_sun() -> void:
	var travel := -_sun.global_transform.basis.z
	_yaw = atan2(travel.x, travel.z)
	_pitch = -0.10


func _fly(delta: float) -> void:
	var wanted := Vector3(
			Input.get_action_strength(&"move_right")
			- Input.get_action_strength(&"move_left"),
			0.0,
			Input.get_action_strength(&"move_back")
			- Input.get_action_strength(&"move_forward"))
	if Input.is_key_pressed(KEY_SHIFT):
		wanted.y -= 1.0
	if Input.is_key_pressed(KEY_CTRL):
		wanted.y += 1.0
	if wanted != Vector3.ZERO:
		_camera.global_position += (
				_camera.global_transform.basis * wanted.normalized() * fly_speed * delta)
	# No floor on the camera: his own edits to the addon shader draw the underside of
	# the surface and the view through it, and you cannot see either from above.
	_camera.rotation = Vector3(_pitch, _yaw, 0.0)


func _draw_hud() -> void:
	var state: Dictionary = SEAS[sea_state]
	var text := "[b]%s[/b]    %s\n\n" % [
		str(state["name"]).to_upper(),
		"[color=#7fe08a]FFT[/color]" if show_fft
		else "[color=#ffd479]сумма синусов[/color]"]
	text += "[table=2]"
	if show_fft and fft != null:
		text += "[cell]компонент  [/cell][cell]%d = %d² × %d каскад(а)[/cell]" % [
			map_size * map_size * cascades, map_size, cascades]
		text += "[cell]карта  [/cell][cell]%d×%d[/cell]" % [map_size, map_size]
		text += "[cell]тайлы  [/cell][cell]456 / 97 / 19 м, периоды не кратны[/cell]"
		text += "[cell]пена  [/cell][cell]копится в буфере и тает[/cell]"
		text += "[cell]прозрачность (G)  [/cell][cell]%s[/cell]" % (
				"[color=#7fe08a]включена[/color]" if transparent
				else "[color=#ff8a6a]выключена — как в оригинале аддона[/color]")
	else:
		text += "[cell]компонент  [/cell][cell]48[/cell]"
		text += "[cell]период  [/cell][cell]тайла нет, но 48 направлений дают полосы[/cell]"
		text += "[cell]пена  [/cell][cell]без памяти: считается заново каждый кадр[/cell]"
	text += "[cell]кадр  [/cell][cell]%.2f мс на GPU (не delta: та упёрлась бы в vsync)[/cell]" % (
			frame_ms)
	text += "[cell]просвет гребней (B)  [/cell][cell]%s[/cell]" % (
			"[color=#7fe08a]есть, усиление %.1f[/color]" % sss_gain if sss
			else "[color=#ff8a6a]выключен[/color]")
	text += "[cell]солнечные пятна (K)  [/cell][cell]%s[/cell]" % (
			"[color=#7fe08a]рябь до 300 м, блик узкий[/color]" if glitter
			else "[color=#ff8a6a]как в оригинале: рябь гаснет к 100 м[/color]")
	text += "[cell]цвет по глубине (M)  [/cell][cell]%s[/cell]" % (
			"[color=#7fe08a]есть, прибой до %.1f м[/color]" % shore_foam if depth_color
			else "[color=#ff8a6a]выключен — как в оригинале[/color]")
	text += "[cell]тон воды в свету (N)  [/cell][cell]%s[/cell]" % (
			"[color=#7fe08a]%.2f[/color]" % diffuse_tint if diffuse_tint > 0.0
			else "[color=#ff8a6a]0 — как в оригинале, диффуз белый[/color]")
	text += "[cell]волны (+ −)  [/cell][cell]×%.2f от пресета[/cell]" % wave_scale
	text += "[cell]солнце над горизонтом  [/cell]"
	text += "[cell]%.0f°   (чем ниже, тем сильнее просвет)[/cell]" % -sun_pitch
	text += "[/table]\n\n"
	text += "TAB — переключить поверхность    1 2 3 — зыбь / рабочее море / шторм\n"
	text += "+ − — волны выше / ниже\n"
	text += "N — тон воды    M — цвет по глубине и прибой    K — солнечные пятна\n"
	text += "B — просвет гребней    [ ] — солнце выше / ниже    L — повернуться к солнцу\n"
	text += "Z X C V — карта 128 / 256 / 512 / 1024    Q E — каскадов меньше / больше\n"
	text += "WASD летать, CTRL/SHIFT вверх-вниз, правая кнопка — осмотреться\n"
	text += "[color=#66ccff]нырни ниже нуля — изнанка поверхности нарисована[/color]"
	_info.text = text
