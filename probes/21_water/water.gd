class_name WaterBench
extends Node3D
## 21 — water, taken apart.
##
## One shader, six switches, four presets. The presets are nothing but numbers: the
## same code is the ocean, the river and the pool, and the biggest single difference
## between them is `absorb` — how far light gets through the water before it gives up.
##
## The second half of the probe is the part MGS2 taught: what makes water convincing
## is often not the water. Dive under and the motes and the wobble do more than the
## surface shader ever did.

const PRESETS := {
	"ocean": {
		"absorb": 7.0, "wave_amp": 0.45, "wave_len": 12.0, "wave_speed": 1.0,
		"wave_steep": 0.7, "wave_n": 4, "ripple_scale": 0.22, "ripple_strength": 0.55,
		"ripple_speed": 0.05, "flow": Vector2.ZERO, "foam_depth": 0.7,
		"refract_amount": 0.35, "water_rough": 0.03, "murk": 0.55,
		"fog_col": Color(0.05, 0.24, 0.34),
		"foam_crest": 0.9, "motes": 260, "vol": 0.0, "at": Vector3(0, 3.2, 18),
		"shallow_col": Color(0.16, 0.55, 0.60), "deep_col": Color(0.01, 0.06, 0.16),
	},
	"river": {
		"absorb": 1.6, "wave_amp": 0.07, "wave_len": 3.0, "wave_speed": 1.6,
		"wave_steep": 0.4, "wave_n": 3, "ripple_scale": 0.7, "ripple_strength": 1.1,
		"ripple_speed": 0.16, "flow": Vector2(0.10, 0.0), "foam_depth": 1.1,
		"refract_amount": 0.6, "water_rough": 0.09, "murk": 0.8,
		"fog_col": Color(0.14, 0.22, 0.12),
		"foam_crest": 0.35, "motes": 260, "vol": 0.0, "at": Vector3(0, 2.0, 14),
		"shallow_col": Color(0.30, 0.42, 0.28), "deep_col": Color(0.08, 0.14, 0.11),
	},
	"pool": {
		"absorb": 26.0, "wave_amp": 0.02, "wave_len": 2.2, "wave_speed": 0.6,
		"wave_steep": 0.2, "wave_n": 2, "ripple_scale": 0.5, "ripple_strength": 0.35,
		"ripple_speed": 0.03, "flow": Vector2.ZERO, "foam_depth": 0.12,
		"refract_amount": 0.9, "water_rough": 0.01, "murk": 0.18,
		"fog_col": Color(0.22, 0.55, 0.66),
		"foam_crest": 0.0, "motes": 90, "vol": 0.0, "at": Vector3(0, 3.2, 18),
		"shallow_col": Color(0.42, 0.80, 0.86), "deep_col": Color(0.10, 0.45, 0.62),
	},
	# The one the screenshots were actually of: water in a room. Nothing here is an
	# ocean setting turned down — you see three metres, the muck is at your face,
	# and the light comes in a column through the hole you fell in by.
	"flooded": {
		"absorb": 2.4, "wave_amp": 0.05, "wave_len": 2.0, "wave_speed": 0.5,
		"wave_steep": 0.2, "wave_n": 2, "ripple_scale": 0.9, "ripple_strength": 0.8,
		"ripple_speed": 0.04, "flow": Vector2(0.004, 0.002), "foam_depth": 0.25,
		"refract_amount": 0.5, "water_rough": 0.05, "murk": 0.9,
		"fog_col": Color(0.09, 0.30, 0.30),
		"shallow_col": Color(0.16, 0.42, 0.40), "deep_col": Color(0.04, 0.13, 0.14),
		"foam_crest": 0.0, "motes": 900, "vol": 0.16, "at": Vector3(-70, -3.1, 9.6),
	},
}

## Preset keys that belong to the SCENE, not to the surface shader.
const SCENE_KEYS := ["murk", "fog_col", "motes", "vol", "at"]

const LAYERS := [
	"use_waves",
	"use_ripple",
	"use_depth",
	"use_fresnel",
	"use_refract",
	"use_foam",
]
const LAYER_KEYS := ["4", "5", "6", "7", "8", "9"]

@export var fly_speed := 9.0

var preset := "ocean"
var layers_on := [true, true, true, true, true, true]
## How much of the lens is still covered in drops, 0..1.
var lens_wet := 0.0
var under := false
var show_depth := false

var _fog_colour := Color(0.08, 0.28, 0.36)
var _fog_density := 0.06
var _volumetric := 0.0
var _yaw := 0.0
var _pitch := -0.12
var _looking := false

@onready var _camera: Camera3D = $Camera
@onready var _motes: GPUParticles3D = $Particles
@onready var _world: WorldEnvironment = $WorldEnvironment
@onready var _info: RichTextLabel = $Ui/Info
@onready var _surface_mesh: MeshInstance3D = $Surface
@onready var _lens_rect: ColorRect = $Ui/Wet
@onready var _surface := _surface_mesh.material_override as ShaderMaterial
@onready var _lens := _lens_rect.material as ShaderMaterial


func _ready() -> void:
	apply_preset("ocean")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _process(delta: float) -> void:
	_fly(delta)
	var was_under := under
	under = _camera.global_position.y < 0.0
	if was_under and not under:
		# Just surfaced: the lens is covered.
		lens_wet = 1.0
	lens_wet = maxf(lens_wet - delta * 0.28, 0.0)
	_lens.set_shader_parameter("submerged", 1.0 if under else 0.0)
	_lens.set_shader_parameter("drops", lens_wet)
	_soak()
	_place_motes()
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
		KEY_1:
			apply_preset("ocean")
		KEY_2:
			apply_preset("river")
		KEY_3:
			apply_preset("pool")
		KEY_F:
			apply_preset("flooded")
		KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			# NOT near WASD. The first version put a layer on W and ate every step.
			var layer: int = event.keycode - KEY_4
			layers_on[layer] = not layers_on[layer]
			_push_layers()
		KEY_0:
			var any := false
			for on in layers_on:
				any = any or on
			for i in layers_on.size():
				layers_on[i] = not any
			_push_layers()
		KEY_U:
			show_depth = not show_depth
			_surface.set_shader_parameter("show_depth", 1.0 if show_depth else 0.0)


func apply_preset(key: String) -> void:
	preset = key
	var values: Dictionary = PRESETS[key]
	for field in values:
		if not SCENE_KEYS.has(field):
			_surface.set_shader_parameter(field, values[field])
	_lens.set_shader_parameter("murk", float(values["murk"]) * 0.45)
	_fog_density = 0.012 + 0.085 * float(values["murk"])
	_fog_colour = values["fog_col"]
	_motes.amount = int(values["motes"])
	_volumetric = float(values["vol"])
	_camera.global_position = values["at"]
	_yaw = 0.0
	_pitch = 0.08 if key == "flooded" else -0.12
	_push_layers()


func _push_layers() -> void:
	for i in LAYERS.size():
		_surface.set_shader_parameter(LAYERS[i], 1.0 if layers_on[i] else 0.0)


## Distance under water is done by the ENVIRONMENT, not by a screen shader: a
## canvas_item pass has no depth, so it can only tint everything equally.
func _soak() -> void:
	var environment: Environment = _world.environment
	environment.fog_enabled = under
	# Volumetric fog is what turns a spotlight into a shaft of light in the water. It
	# is not a water effect at all, and it does more for the room than the shader.
	environment.volumetric_fog_enabled = under and _volumetric > 0.0
	if not under:
		return
	environment.fog_light_color = _fog_colour
	environment.fog_density = _fog_density
	environment.volumetric_fog_density = _volumetric
	environment.volumetric_fog_albedo = _fog_colour.lightened(0.45)
	environment.volumetric_fog_length = 40.0


func _place_motes() -> void:
	# The motes box used to sit ON the camera, so half of them spawned inside the near
	# plane, and a 5 cm quad 3 cm from the lens is a screen-filling square. Put the box
	# AHEAD of where you look and nothing can get between you and the near plane.
	_motes.visible = under
	_motes.emitting = under
	var ahead: Vector3 = _camera.global_transform.basis * Vector3(0.0, 0.0, -7.0)
	_motes.global_position = Vector3(
			_camera.global_position.x + ahead.x,
			clampf(_camera.global_position.y + ahead.y, -12.0, -1.0),
			_camera.global_position.z + ahead.z)


func _fly(delta: float) -> void:
	var wanted := Vector3(
			Input.get_action_strength(&"move_right")
			- Input.get_action_strength(&"move_left"),
			0.0,
			Input.get_action_strength(&"move_back")
			- Input.get_action_strength(&"move_forward"))
	if Input.is_key_pressed(KEY_SPACE):
		wanted.y += 1.0
	if Input.is_key_pressed(KEY_SHIFT):
		wanted.y -= 1.0
	if wanted != Vector3.ZERO:
		_camera.global_position += (
				_camera.global_transform.basis * wanted.normalized() * fly_speed * delta)
	_camera.rotation = Vector3(_pitch, _yaw, 0.0)


func _draw_hud() -> void:
	var text := "[b]%s[/b]    1 ocean   2 river   3 pool   F flooded room\n" % preset.to_upper()
	text += "absorb %.1f m — how far light gets before the water gives up\n\n" % float(
			PRESETS[preset]["absorb"])
	for i in LAYERS.size():
		var layer := str(LAYERS[i]).replace("use_", "")
		text += "%s  %-9s %s\n" % [
			LAYER_KEYS[i],
			layer,
			"[color=#7fe08a]on[/color]" if layers_on[i] else "[color=#666666]off[/color]"]
	text += "\n0 all on or off    U show the water column%s\n" % (
			"   [color=#ffd479](on)[/color]" if show_depth else "")
	text += "camera y %+.1f   %s\n" % [
		_camera.global_position.y,
		"[color=#66ccff]under water[/color]" if under else "above"]
	if lens_wet > 0.0:
		text += "[color=#ffd479]drops on the lens %.0f%%[/color]\n" % (lens_wet * 100.0)
	text += "\nWASD fly   SPACE up   SHIFT down   RIGHT MOUSE look\n"
	text += "swim down past y=0 and look up"
	_info.text = text
