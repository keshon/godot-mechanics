class_name TuneBench
extends Node3D
## 24 — knobs built from the shader itself.
##
## The panel on the right is not written for water. It asks the shader what uniforms it
## has and builds a control for each: a slider for a float, a colour picker for a
## source_color, a checkbox for a bool. Add a uniform to the shader and the knob
## appears on its own. Point it at a different material and it rebuilds.
##
## Three targets. The first two are opposites on purpose:
##   вода  — copied from probe 21. 12 of its uniforms declare hint_range.
##   PSX   — copied from probe 07. NONE of its uniforms declare anything.
##   море  — the FFT ocean from probe 23, taken directly: it lives in addons/, and an
##           addon is a dependency, not a neighbouring probe.
##
## Copies, not references: probes do not share code (rule 3). If a knob setting turns
## out to be good, the number gets carried back by hand — which is the honest workflow
## anyway, because a closed probe must not change under its own note.

const TARGETS := [
	"вода — копия из 21-й пробы",
	"PSX — копия из 07-й",
	"FFT-океан — тот самый, из 23-й",
]
const NODES := ["Water", "Psx", "Fft"]
const PRESETS := "res://probes/24_knobs/presets"

# Scene knobs for the sea target. They are plain @export_range vars and the panel picks
# them up with the same builder it uses on the shader — GDScript and GLSL describe a
# bounded number the same way. Without them the shader has nothing to be tuned AGAINST:
# absorption means nothing with no bottom, the crest glow nothing with no sun angle.
## Where the top of the seabed sits relative to the water. 0 breaks the surface.
@export_range(-40.0, 4.0) var floor_depth := -9.0
## Sun above the horizon, degrees. The one number that decides whether the crest glow
## exists at all.
@export_range(2.0, 80.0) var sun_height := 24.0
@export_range(-180.0, 180.0) var sun_turn := -38.0
# Wave strength and foam are NOT here: they belong to the cascade resource of the addon,
# which is already annotated with @export_range from end to end. The panel takes that
# resource as a third source — see _rebuild().

var target := 0
## Camera distance from the middle, metres.
var orbit := 9.5
## One line about every shader in the project, produced once at startup.
var audit := ""
var note := "F5 сохранить и проверить    F9 загрузить"

var _material: ShaderMaterial
var _cascade: WaveCascadeParameters
var _seabed: MeshInstance3D
var _yaw := 0.5
var _pitch := -0.38
var _looking := false

@onready var _panel: TunePanel = $Ui/Box/Panel
@onready var _camera: Camera3D = $Camera
@onready var _sun: DirectionalLight3D = $Sun
@onready var _info: RichTextLabel = $Ui/Info
@onready var _basin: MeshInstance3D = $Water/Basin


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(PRESETS)
	add_child(_build_fft())
	audit = _audit()
	_show_target(0)


func _process(_delta: float) -> void:
	_sun.rotation_degrees = Vector3(-sun_height, sun_turn, 0.0)
	if _seabed != null:
		_seabed.position.y = floor_depth - 35.0
	var forward := Vector3(
			sin(_yaw) * cos(_pitch),
			sin(_pitch),
			cos(_yaw) * cos(_pitch))
	_camera.global_position = -forward * orbit + Vector3(0.0, 1.2, 0.0)
	_camera.look_at(Vector3(0.0, 0.6, 0.0))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_looking = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit = maxf(orbit - 0.6, 2.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit = minf(orbit + 0.6, 30.0)
		return
	if event is InputEventMouseMotion and _looking:
		_yaw -= event.relative.x * 0.006
		_pitch = clampf(_pitch - event.relative.y * 0.006, -1.35, 0.4)
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_1:
			_show_target(0)
		KEY_2:
			_show_target(1)
		KEY_3:
			_show_target(2)
		KEY_F5:
			_roundtrip()
		KEY_F9:
			_load_preset()
		KEY_R:
			_panel.randomize_all()
			_rebuild()
			note = "все ручки шейдера выкручены случайно"
		KEY_0:
			_panel.reset_all()
			_rebuild()
			note = "шейдер сброшен к тому, что в нём написано"
	_draw_hud()


## The third target is the FFT ocean from probe 23 — the SAME shader, not a copy. That
## is allowed where a copy would be required of a neighbouring probe: the surface lives
## in addons/, and an addon is a dependency. So everything tuned by keyboard over a
## session — absorption, refraction, the crest glow, the depth ramp, the shore surf,
## the ripple fade — arrives here as sliders.
func _build_fft() -> Node3D:
	var holder := Node3D.new()
	holder.name = "Fft"
	holder.visible = false
	if RenderingServer.get_rendering_device() == null:
		# No compute device, no FFT — probe 23 measured that.
		return holder
	var surface := FFTWaterSurface.new()
	surface.name = "Mesh"
	# NOT duplicated, and that took a bug to learn. The addon writes `map_scales` into
	# WATER_MAT — a preload CONSTANT pointing at mat_water.tres — not into whatever
	# material hangs on the node. A duplicate is therefore orphaned: displacement and
	# normal scales never reach it, and the wave-strength knob does nothing at all.
	# The file on disk is never written here, so probe 23 keeps its own numbers.
	surface.material_override = load("res://addons/ocean_waves_fft/mat_water.tres")
	surface.mesh_quality = FFTWaterSurface.MeshQuality.LOW
	surface.map_size = 256
	var cascade := WaveCascadeParameters.new()
	cascade.tile_length = Vector2(96.0, 96.0)
	cascade.displacement_scale = 1.0
	cascade.normal_scale = 1.0
	cascade.wind_speed = 18.0
	cascade.fetch_length = 500.0
	cascade.swell = 0.8
	cascade.spread = 0.2
	cascade.detail = 1.0
	cascade.whitecap = 0.5
	cascade.foam_amount = 5.0
	var list: Array[WaveCascadeParameters] = [cascade]
	surface.parameters = list
	_cascade = cascade
	holder.add_child(surface)
	# A seabed, because half the water shader is about what is UNDER it. A wide shallow
	# cone: one slider then sweeps the whole range from beach to deep water at once.
	var cone := CylinderMesh.new()
	cone.top_radius = 30.0
	cone.bottom_radius = 620.0
	cone.height = 70.0
	cone.radial_segments = 96
	_seabed = MeshInstance3D.new()
	_seabed.name = "Bed"
	_seabed.mesh = cone
	_seabed.position.y = -35.0
	_seabed.material_override = _basin.material_override
	holder.add_child(_seabed)
	return holder


func _show_target(index: int) -> void:
	target = index
	orbit = 46.0 if index == 2 else 9.5
	_pitch = -0.12 if index == 2 else -0.38
	for i in NODES.size():
		var node: Node3D = get_node(NODES[i])
		node.visible = i == index
	var mesh: MeshInstance3D = get_node(NODES[index]).get_node("Mesh")
	_material = mesh.material_override as ShaderMaterial
	_rebuild()


func _rebuild() -> void:
	_panel.begin()
	if target == 2:
		_panel.add_object(self, "сцена: дно и солнце")
		# A third kind of source: a Resource. Same builder again. This is where wave
		# height, wind, fetch and foam live — foam is not in the shader at all, it is
		# baked into the normal map by the compute pass and the surface reads a channel.
		_panel.add_object(_cascade, "каскад волн — ресурс аддона")
	_panel.add_shader(_material, "шейдер")
	_draw_hud()


## Coverage over EVERY shader in the project, asked of Godot rather than of a regex.
## This is the number the probe exists to produce: not "does the panel work" but "how
## much of what is actually written can a panel like this reach at all".
func _audit() -> String:
	var files: Array[String] = []
	_scan("res://probes", files)
	_scan("res://addons", files)
	var total := 0
	var ranged := 0
	var opaque := 0
	for path in files:
		var shader := load(path) as Shader
		if shader == null:
			continue
		for uniform in shader.get_shader_uniform_list(false):
			total += 1
			var kind := int(uniform["type"])
			if kind == TYPE_OBJECT or kind >= TYPE_PACKED_BYTE_ARRAY:
				opaque += 1
			elif int(uniform["hint"]) == PROPERTY_HINT_RANGE:
				ranged += 1
	return "%d шейдеров, %d uniform-ов: %d с диапазоном (%.0f%%), %d непокрутибельных" % [
		files.size(), total, ranged, 100.0 * ranged / maxf(total, 1), opaque]


func _scan(directory: String, found: Array[String]) -> void:
	var access := DirAccess.open(directory)
	if access == null:
		return
	for file in access.get_files():
		if file.ends_with(".gdshader"):
			found.append(directory.path_join(file))
	for sub in access.get_directories():
		_scan(directory.path_join(sub), found)


## Save the whole material, load it back, compare every parameter. A preset is only
## worth anything if it comes back EXACTLY — the same question probe 16 asked about
## saves, two orders of magnitude smaller.
func _roundtrip() -> void:
	var path := "%s/%d.tres" % [PRESETS, target]
	var error := ResourceSaver.save(_material.duplicate(), path)
	if error != OK:
		note = "[color=#ff8a6a]сохранить не вышло: %d[/color]" % error
		return
	var back := ResourceLoader.load(
			path, "", ResourceLoader.CACHE_MODE_IGNORE) as ShaderMaterial
	var same := 0
	var close := 0
	var moved := 0
	for parameter in _panel.parameter_names():
		var before: Variant = _material.get_shader_parameter(parameter)
		if before == null:
			continue
		var after: Variant = back.get_shader_parameter(parameter)
		if before == after:
			same += 1
		elif _near_enough(before, after):
			close += 1
		else:
			moved += 1
	note = "пресет: %d точь-в-точь, %d в пределах float32, " % [same, close]
	note += "[color=#ff8a6a]%d потеряно[/color]" % moved


func _load_preset() -> void:
	var path := "%s/%d.tres" % [PRESETS, target]
	if not ResourceLoader.exists(path):
		note = "[color=#ff8a6a]пресета ещё нет — сначала F5[/color]"
		return
	var back := ResourceLoader.load(
			path, "", ResourceLoader.CACHE_MODE_IGNORE) as ShaderMaterial
	for parameter in _panel.parameter_names():
		var value: Variant = back.get_shader_parameter(parameter)
		if value != null:
			_material.set_shader_parameter(parameter, value)
	_rebuild()
	note = "пресет загружен"


## Exact equality is the WRONG test for a preset, and measuring said so. Nine floats
## came back "changed": 0.34999999403954 -> 0.35. The shader keeps its defaults as
## float32, the .tres writes them as text and rounds, and loading gives a float64. The
## returned value is CLOSER to what the author typed than what the shader held. So the
## question is not "is it identical" but "is it identical to within the precision the
## GPU has anyway".
func _near_enough(before: Variant, after: Variant) -> bool:
	if before is float and after is float:
		return absf(before - after) <= maxf(absf(before), absf(after)) * 1e-6 + 1e-9
	if before is Vector2 or before is Vector3 or before is Color:
		return before.is_equal_approx(after)
	if before is Resource and after is Resource:
		# A texture written into the .tres comes back as a DIFFERENT instance of the
		# same thing. Identity is not the question here; the picture is the same one.
		return true
	return false


func _draw_hud() -> void:
	var text := "[b]%s[/b]\n\n[table=2]" % TARGETS[target].to_upper()
	text += "[cell]ручек построено  [/cell][cell]%d[/cell]" % _panel.built
	text += "[cell]диапазон выдуман  [/cell]"
	text += "[cell][color=#ffd479]%d[/color]   (нет hint_range)[/cell]" % _panel.guessed
	text += "[cell]не покрутить  [/cell]"
	text += "[cell][color=#ff8a6a]%d[/color]   (текстуры, массивы)[/cell]" % _panel.skipped
	text += "[cell]по всему проекту  [/cell][cell]%s[/cell]" % audit
	text += "[/table]\n\n%s\n\n" % note
	text += "1 2 3 — мишень    R — выкрутить всё случайно    0 — сброс\n"
	text += "F5 — сохранить пресет и проверить кругооборотом    F9 — загрузить\n"
	text += "правая кнопка — повернуть, колесо — приблизить\n"
	text += "[color=#ffd479]жёлтая подпись — диапазон ползунка выдуман панелью, "
	text += "а не объявлен шейдером[/color]\n\n"
	text += "[color=#66ccff]панель не написана под воду: она спрашивает у"
	text += " источника, что он объявляет[/color]"
	_info.text = text
