extends Node3D

# 23 — two oceans under one sky.
#
#   S — sum of sines: 48 plane waves, summed per vertex.
#   F — FFT: a spectrum filled in frequency space and inverse-transformed on compute
#       shaders into displacement and normal maps. map_size^2 components per cascade.
#
# One camera, one sun, one clock. Press S and F and look at the same water twice.
#
# The addon is 2Retr0/GodotOceanWaves (MIT), vendored in addons/ocean_waves_fft with
# his own notes on what he changed. It is a DEPENDENCY, not probe code — the six-file
# rule counts what the probe writes, the same way probe 15 let content/ grow.

const SEAS := [
	{"name": "зыбь", "len": 70.0, "h": 1.4, "steep": 0.4, "storm": 0.15, "over": 0.006,
		"wind": 12.0, "fetch": 400.0, "whitecap": 0.35, "foam": 3.0},
	{"name": "рабочее море", "len": 90.0, "h": 3.0, "steep": 0.6, "storm": 0.45, "over": 0.012,
		"wind": 20.0, "fetch": 550.0, "whitecap": 0.5, "foam": 5.0},
	{"name": "шторм", "len": 130.0, "h": 8.0, "steep": 0.82, "storm": 1.0, "over": 0.024,
		"wind": 32.0, "fetch": 900.0, "whitecap": 0.75, "foam": 7.0},
]

@export var show_fft := true
@export_range(0, 2) var sea_state := 1
@export var map_size := 256
@export_range(1, 3) var cascades := 3
@export var fly_speed := 26.0
## his own transparency edit in the addon ships switched OFF ("0 -> как оригинал")
@export var transparent := true
## SUBSURFACE SCATTERING. The addon already has the term; the sines surface got one
## written to match. Both hang off the same switch so the comparison stays fair.
@export var sss := true
@export_range(0.0, 30.0) var sss_gain := 12.0
## Sun elevation, and it is not a decoration: this single number decides whether the
## effect exists at all. Light has to come THROUGH the crest, so it must be low enough
## to be behind one.
@export_range(-80.0, -2.0) var sun_pitch := -38.0
## Wave amplitude on top of the preset. The three sea states are points, and points are
## not enough to find the one place where a look works: that is always between them.
@export_range(0.2, 3.0) var wave_scale := 1.0
## Тон воды в прямом свете аддона. 0 — как в оригинале (белый диффуз), отчего при
## высоком солнце поверхность белеет.
@export_range(0.0, 1.0) var diffuse_tint := 0.85
## Цвет воды по глубине и прибой у кромки. Оба в аддоне выключены по умолчанию.
@export var depth_color := true
@export_range(0.0, 6.0) var shore_foam := 1.8
## Солнечные пятна: мелкая рябь живёт дальше, блик уже. Три ручки одним переключателем.
@export var glitter := true

var clock := 0.0
var ms_now := 0.0
var fft: FFTWaterSurface
var sines := FftSines.new()

var _mat: ShaderMaterial
var _water: ShaderMaterial
var _yaw := 0.35
var _pitch := -0.13
var _look := false


func _ready() -> void:
	_mat = ($Sines as MeshInstance3D).material_override
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	# No RenderingDevice means no compute shaders, which means no FFT at all. That is
	# not a guard against a rare case: it is the whole headless mode. Probe 22 could be
	# measured with --headless; this one cannot, and neither can anything downstream of
	# it. A sum of sines runs anywhere; an FFT ocean needs a GPU in the room.
	if RenderingServer.get_rendering_device() == null:
		show_fft = false
		_apply()
		return
	fft = FFTWaterSurface.new()
	fft.name = "Fft"
	fft.material_override = load("res://addons/ocean_waves_fft/mat_water.tres")
	fft.mesh_quality = FFTWaterSurface.MeshQuality.LOW
	_water = fft.material_override as ShaderMaterial
	add_child(fft)
	_apply()


func _apply() -> void:
	var st: Dictionary = SEAS[sea_state]
	sines.build(float(st["len"]), float(st["h"]) * wave_scale, float(st["steep"]))
	_mat.set_shader_parameter("wn", FftSines.N)
	_mat.set_shader_parameter("steepness", sines.steepness)
	_mat.set_shader_parameter("storm", float(st["storm"]))
	_mat.set_shader_parameter("wdirs", sines.dirs)
	_mat.set_shader_parameter("wks", sines.ks)
	_mat.set_shader_parameter("wamps", sines.amps)
	_mat.set_shader_parameter("wphs", sines.phases)
	_mat.set_shader_parameter("womg", sines.omegas)
	_mat.set_shader_parameter("wmr", sines.mrate)
	_mat.set_shader_parameter("wmp", sines.mphase)
	_mat.set_shader_parameter("fold", sines.worst_fold(clock) + float(st["over"]))

	# Cascades: tile lengths that do not share a period. One 456 m swell, one 97 m sea,
	# one 19 m chop, each its own transform, summed. That is the thing a single sine
	# sum cannot do at any component count you can afford.
	var tiles := [Vector2(456.0, 456.0), Vector2(97.0, 97.0), Vector2(19.0, 19.0)]
	var dsc := [1.0, 0.75, 0.4]
	var list: Array[WaveCascadeParameters] = []
	for i in cascades:
		var c := WaveCascadeParameters.new()
		c.tile_length = tiles[i]
		c.displacement_scale = dsc[i] * wave_scale
		c.normal_scale = 1.0 if i < 2 else (0.85 if glitter else 0.35)
		c.wind_speed = float(st["wind"])
		c.wind_direction = 0.0
		c.fetch_length = float(st["fetch"])
		c.swell = 0.8
		c.spread = 0.2
		c.detail = 1.0
		c.whitecap = float(st["whitecap"])
		c.foam_amount = float(st["foam"])
		list.append(c)
	if fft == null:
		return
	fft.map_size = map_size
	fft.parameters = list


func _process(delta: float) -> void:
	_fly(delta)
	clock += delta
	_mat.set_shader_parameter("wave_time", clock)
	($Sines as MeshInstance3D).visible = not show_fft or fft == null
	if _water != null:
		_water.set_shader_parameter("transparency_on", 1.0 if transparent else 0.0)
	_light()
	if fft != null:
		fft.visible = show_fft
		fft.set_process(show_fft)
	# Время GPU, а не delta. delta упирается в vsync: на мониторе 200 Гц она показывала
	# ровно 5.00 мс во всех режимах подряд — то есть меряла монитор, а не воду.
	ms_now = lerpf(ms_now,
		RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()),
		0.05)
	if fft != null:
		# the clipmap is a fixed patch: it has to follow the eye or you sail off it
		fft.global_position = Vector3($Cam.global_position.x, 0.0, $Cam.global_position.z)
	_hud()


## Sun into both shaders. The sines surface has no light() of its own, so it cannot ask
## the engine where the sun is — the direction has to be handed to it.
func _light() -> void:
	var sun: DirectionalLight3D = $Sun
	sun.rotation_degrees.x = sun_pitch
	var d := -sun.global_transform.basis.z   # the way the light travels, world space
	_mat.set_shader_parameter("sun_dir", d)
	_mat.set_shader_parameter("sun_energy", sun.light_energy)
	_mat.set_shader_parameter("sss_on", 1.0 if sss else 0.0)
	_mat.set_shader_parameter("sss_gain", sss_gain)
	_mat.set_shader_parameter("wave_h", sines.wave_height)
	if _water != null:
		_water.set_shader_parameter("sss_gain", sss_gain if sss else 0.0)
		_water.set_shader_parameter("diffuse_tint", diffuse_tint)
		_water.set_shader_parameter("depth_color_on", 1.0 if depth_color else 0.0)
		_water.set_shader_parameter("shore_foam", shore_foam)
		_water.set_shader_parameter("normal_fade", 0.006 if glitter else 0.0175)
		_water.set_shader_parameter("roughness", 0.32 if glitter else 0.65)


func _fly(delta: float) -> void:
	var cam: Camera3D = $Cam
	var v := Vector3(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		0.0,
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward"))
	if Input.is_key_pressed(KEY_SHIFT):
		v.y -= 1.0
	if Input.is_key_pressed(KEY_CTRL):
		v.y += 1.0
	if v != Vector3.ZERO:
		cam.global_position += cam.global_transform.basis * v.normalized() * fly_speed * delta
	# no floor on the camera: his own edits to the addon shader draw the underside of
	# the surface and the view through it, and you cannot see either from above.
	cam.rotation = Vector3(_pitch, _yaw, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_look = event.pressed
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if _look else Input.MOUSE_MODE_VISIBLE)
		return
	if event is InputEventMouseMotion and _look:
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
			# Turn to face the sun. Not a convenience: the glow lives where the water is
			# BETWEEN the eye and the sun, and with the sun behind you there is nothing
			# to see no matter how high the gain.
			var sd := -($Sun as DirectionalLight3D).global_transform.basis.z
			_yaw = atan2(sd.x, sd.z)
			_pitch = -0.10
		KEY_TAB:
			# NOT a letter next to WASD. This sat on S and F, and S is move_back:
			# stepping backwards switched the ocean. Second time in this project —
			# probe 21 had a layer on W. On any probe you can walk around in, the
			# toggles live away from the movement keys, full stop.
			show_fft = not show_fft and fft != null
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


func _hud() -> void:
	var st: Dictionary = SEAS[sea_state]
	var comps := map_size * map_size * cascades
	var t := "[b]%s[/b]    %s\n\n" % [str(st["name"]).to_upper(),
		"[color=#7fe08a]FFT[/color]" if show_fft else "[color=#ffd479]сумма синусов[/color]"]
	t += "[table=2]"
	if show_fft and fft != null:
		t += "[cell]компонент  [/cell][cell]%d = %d² × %d каскад(а)[/cell]" % [
			comps, map_size, cascades]
		t += "[cell]карта  [/cell][cell]%d×%d[/cell]" % [map_size, map_size]
		t += "[cell]тайлы  [/cell][cell]456 / 97 / 19 м, периоды не кратны[/cell]"
		t += "[cell]пена  [/cell][cell]копится в буфере и тает[/cell]"
		t += "[cell]прозрачность (G)  [/cell][cell]%s[/cell]" % (
			"[color=#7fe08a]включена[/color]" if transparent
			else "[color=#ff8a6a]выключена — как в оригинале аддона[/color]")
	else:
		t += "[cell]компонент  [/cell][cell]48[/cell]"
		t += "[cell]период  [/cell][cell]тайла нет, но 48 направлений дают полосы[/cell]"
		t += "[cell]пена  [/cell][cell]без памяти: считается заново каждый кадр[/cell]"
	t += "[cell]кадр  [/cell][cell]%.2f мс на GPU (не delta: та упёрлась бы в vsync)[/cell]" % ms_now
	t += "[cell]просвет гребней (B)  [/cell][cell]%s[/cell]" % (
		"[color=#7fe08a]есть, усиление %.1f[/color]" % sss_gain if sss
		else "[color=#ff8a6a]выключен[/color]")
	t += "[cell]солнечные пятна (K)  [/cell][cell]%s[/cell]" % (
		"[color=#7fe08a]рябь до 300 м, блик узкий[/color]" if glitter
		else "[color=#ff8a6a]как в оригинале: рябь гаснет к 100 м[/color]")
	t += "[cell]цвет по глубине (M)  [/cell][cell]%s[/cell]" % (
		"[color=#7fe08a]есть, прибой до %.1f м[/color]" % shore_foam if depth_color
		else "[color=#ff8a6a]выключен — как в оригинале[/color]")
	t += "[cell]тон воды в свету (N)  [/cell][cell]%s[/cell]" % (
		"[color=#7fe08a]%.2f[/color]" % diffuse_tint if diffuse_tint > 0.0
		else "[color=#ff8a6a]0 — как в оригинале, диффуз белый[/color]")
	t += "[cell]волны (+ −)  [/cell][cell]×%.2f от пресета[/cell]" % wave_scale
	t += "[cell]солнце над горизонтом  [/cell][cell]%.0f°   (чем ниже, тем сильнее просвет)[/cell]" % -sun_pitch
	t += "[/table]\n\n"
	t += "TAB — переключить поверхность    1 2 3 — зыбь / рабочее море / шторм\n"
	t += "+ − — волны выше / ниже
"
	t += "N — тон воды    M — цвет по глубине и прибой    K — солнечные пятна
"
	t += "B — просвет гребней    [ ] — солнце выше / ниже    L — повернуться к солнцу\n"
	t += "Z X C V — карта 128 / 256 / 512 / 1024    Q E — каскадов меньше / больше\n"
	t += "WASD летать, CTRL/SHIFT вверх-вниз, правая кнопка — осмотреться
"
	t += "[color=#66ccff]нырни ниже нуля — изнанка поверхности нарисована[/color]"
	$Ui/Info.text = t
