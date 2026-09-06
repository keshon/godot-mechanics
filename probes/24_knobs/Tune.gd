extends Node3D

# 24 — knobs built from the shader itself.
#
# The panel on the right is not written for water. It asks the shader what uniforms it
# has, and builds a control for each: a slider for a float, a colour picker for a
# source_color, a checkbox for a bool. Add a uniform to the shader and the knob appears
# on its own. Point it at a different material and it rebuilds.
#
# Three targets. The first two are opposites on purpose:
#   вода  — copied from probe 21. 12 of its uniforms declare hint_range.
#   PSX   — copied from probe 07. NONE of its uniforms declare anything.
#   море  — the FFT ocean from probe 23, taken directly: it lives in addons/, and an
#           addon is a dependency, not a neighbouring probe.
#
# Copies, not references: probes do not share code (rule 3). If a knob setting turns out
# to be good, the number gets carried back by hand — which is the honest workflow anyway,
# because the closed probe must not change under its own note.

const TARGETS := ["вода — копия из 21-й пробы", "PSX — копия из 07-й",
	"FFT-океан — тот самый, из 23-й"]
const NODES := ["Water", "Psx", "Fft"]
const PRESETS := "res://probes/24_knobs/presets"

var target := 0
var orbit := 9.5

# Scene knobs for the sea target. They are plain @export_range vars and the panel picks
# them up with the same builder it uses on the shader — GDScript and GLSL describe a
# bounded number the same way. Without them the shader has nothing to be tuned AGAINST:
# absorption means nothing with no bottom, the crest glow means nothing with no sun angle.
## Where the top of the seabed sits relative to the water. 0 breaks the surface.
@export_range(-40.0, 4.0) var floor_depth := -9.0
## Sun above the horizon. The one number that decides whether the crest glow exists.
@export_range(2.0, 80.0) var sun_height := 24.0
@export_range(-180.0, 180.0) var sun_turn := -38.0
# Wave strength and foam are NOT here: they belong to the addon's own cascade resource,
# which is already annotated with @export_range from end to end. The panel takes that
# resource as a third source — see _rebuild().

var audit := ""
var note := "F5 сохранить и проверить    F9 загрузить"

var _panel: TunePanel
var _mat: ShaderMaterial
var _yaw := 0.5
var _pitch := -0.38
var _look := false
var _cas: WaveCascadeParameters
var _bed: MeshInstance3D


func _ready() -> void:
	_panel = $Ui/Box/List as TunePanel
	DirAccess.make_dir_recursive_absolute(PRESETS)
	add_child(_fft())
	audit = _audit()
	_pick(0)


## The third target is the FFT ocean from probe 23 — the SAME shader, not a copy of it.
## That is allowed where a copy would be required of a neighbouring probe: the surface
## lives in addons/, and an addon is a dependency, not another probe. So everything we
## spent a session tuning by keyboard — absorption, refraction, the crest glow, the depth
## ramp, the shore surf, the ripple fade — arrives here as sliders.
func _fft() -> Node3D:
	var holder := Node3D.new()
	holder.name = "Fft"
	holder.visible = false
	if RenderingServer.get_rendering_device() == null:
		return holder     # no compute device, no FFT — probe 23 measured that
	var w := FFTWaterSurface.new()
	w.name = "Mesh"
	# NOT duplicated, and that took a bug to learn. The addon writes `map_scales` into
	# `WATER_MAT` — a preload CONSTANT pointing at mat_water.tres — not into whatever
	# material hangs on the node. A duplicate is therefore orphaned: displacement and
	# normal scales never reach it, and the wave-strength knob does nothing at all.
	# The file on disk is never written here, so probe 23 keeps its own numbers.
	w.material_override = load("res://addons/ocean_waves_fft/mat_water.tres")
	w.mesh_quality = FFTWaterSurface.MeshQuality.LOW
	w.map_size = 256
	var c := WaveCascadeParameters.new()
	c.tile_length = Vector2(96.0, 96.0)
	c.displacement_scale = 1.0
	c.normal_scale = 1.0
	c.wind_speed = 18.0
	c.fetch_length = 500.0
	c.swell = 0.8
	c.spread = 0.2
	c.detail = 1.0
	c.whitecap = 0.5
	c.foam_amount = 5.0
	var list: Array[WaveCascadeParameters] = [c]
	w.parameters = list
	_cas = c
	holder.add_child(w)
	# A seabed, because half the water shader is about what is UNDER it. A wide shallow
	# cone: one slider then sweeps the whole range from beach to deep water at once.
	var cone := CylinderMesh.new()
	cone.top_radius = 30.0
	cone.bottom_radius = 620.0
	cone.height = 70.0
	cone.radial_segments = 96
	_bed = MeshInstance3D.new()
	_bed.name = "Bed"
	_bed.mesh = cone
	_bed.position.y = -35.0
	_bed.material_override = ($Water/Basin as MeshInstance3D).material_override
	holder.add_child(_bed)
	return holder


func _pick(i: int) -> void:
	target = i
	orbit = 46.0 if i == 2 else 9.5
	_pitch = -0.12 if i == 2 else -0.38
	for t in NODES.size():
		(get_node(NODES[t]) as Node3D).visible = t == i
	_mat = (get_node(NODES[i]).get_node("Mesh") as MeshInstance3D).material_override
	_rebuild()


func _rebuild() -> void:
	_panel.begin()
	if target == 2:
		_panel.add_object(self, "сцена: дно и солнце")
		# A third kind of source: a Resource. Same builder again. This is where wave height,
		# wind, fetch and foam live — foam is not in the shader at all, it is baked into
		# the normal map by the compute pass and the surface only reads the channel.
		_panel.add_object(_cas, "каскад волн — ресурс аддона")
	_panel.add_shader(_mat, "шейдер")
	_hud()


## Coverage over EVERY shader in the project, asked of Godot rather than of a regex.
## This is the number the probe exists to produce: not "does the panel work" but "how much
## of what is actually written can a panel like this reach at all".
func _audit() -> String:
	var files: Array[String] = []
	_scan("res://probes", files)
	_scan("res://addons", files)
	var total := 0
	var ranged := 0
	var opaque := 0
	for f in files:
		var sh := load(f) as Shader
		if sh == null:
			continue
		for u in sh.get_shader_uniform_list(false):
			total += 1
			var t := int(u["type"])
			if t == TYPE_OBJECT or t >= TYPE_PACKED_BYTE_ARRAY:
				opaque += 1
			elif int(u["hint"]) == PROPERTY_HINT_RANGE:
				ranged += 1
	return "%d шейдеров, %d uniform'ов: %d с диапазоном (%.0f%%), %d непокрутибельных" % [
		files.size(), total, ranged, 100.0 * ranged / maxf(total, 1), opaque]


func _scan(dir: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gdshader"):
			out.append(dir.path_join(f))
	for s in d.get_directories():
		_scan(dir.path_join(s), out)


## Save the whole material, load it back, compare every parameter. A preset is only worth
## anything if it comes back EXACTLY — the same question probe 16 asked about saves, two
## orders of magnitude smaller.
func _roundtrip() -> void:
	var path := "%s/%d.tres" % [PRESETS, target]
	var err := ResourceSaver.save(_mat.duplicate(), path)
	if err != OK:
		note = "[color=#ff8a6a]сохранить не вышло: %d[/color]" % err
		return
	var back := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ShaderMaterial
	var same := 0
	var close := 0
	var moved := 0
	for nm in _panel.names():
		var a: Variant = _mat.get_shader_parameter(nm)
		if a == null:
			continue
		var b: Variant = back.get_shader_parameter(nm)
		if a == b:
			same += 1
		elif _near(a, b):
			close += 1
		else:
			moved += 1
	note = "пресет: %d точь-в-точь, %d в пределах float32, [color=#ff8a6a]%d потеряно[/color]" % [
		same, close, moved]


## Exact equality is the WRONG test for a preset, and measuring said so. Nine floats came
## back "changed": 0.34999999403954 -> 0.35. The shader keeps its defaults as float32, the
## .tres writes them as text and rounds, and loading gives a float64. The returned value is
## CLOSER to what the author typed than what the shader held. So the question is not "is it
## identical" but "is it identical to within the precision the GPU has anyway".
func _near(a: Variant, b: Variant) -> bool:
	if a is float and b is float:
		return absf(a - b) <= maxf(absf(a), absf(b)) * 1e-6 + 1e-9
	if a is Vector2 or a is Vector3 or a is Color:
		return a.is_equal_approx(b)
	if a is Resource and b is Resource:
		# A texture written into the .tres comes back as a DIFFERENT instance of the same
		# thing. Identity is not the question here; the picture is the same one.
		return true
	return false


func _load() -> void:
	var path := "%s/%d.tres" % [PRESETS, target]
	if not ResourceLoader.exists(path):
		note = "[color=#ff8a6a]пресета ещё нет — сначала F5[/color]"
		return
	var back := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ShaderMaterial
	for nm in _panel.names():
		var v: Variant = back.get_shader_parameter(nm)
		if v != null:
			_mat.set_shader_parameter(nm, v)
	_rebuild()
	note = "пресет загружен"


func _process(_d: float) -> void:
	($Sun as DirectionalLight3D).rotation_degrees = Vector3(-sun_height, sun_turn, 0.0)
	if _bed != null:
		_bed.position.y = floor_depth - 35.0
	var cam: Camera3D = $Cam
	var f := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	cam.global_position = -f * orbit + Vector3(0.0, 1.2, 0.0)
	cam.look_at(Vector3(0.0, 0.6, 0.0))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_look = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit = maxf(orbit - 0.6, 2.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit = minf(orbit + 0.6, 30.0)
		return
	if event is InputEventMouseMotion and _look:
		_yaw -= event.relative.x * 0.006
		_pitch = clampf(_pitch - event.relative.y * 0.006, -1.35, 0.4)
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_1:
			_pick(0)
		KEY_2:
			_pick(1)
		KEY_3:
			_pick(2)
		KEY_F5:
			_roundtrip()
		KEY_F9:
			_load()
		KEY_R:
			_panel.randomize_all()
			_rebuild()
			note = "все ручки шейдера выкручены случайно"
		KEY_0:
			_panel.reset_all()
			_rebuild()
			note = "шейдер сброшен к тому, что в нём написано"
	_hud()


func _hud() -> void:
	var t := "[b]%s[/b]\n\n" % TARGETS[target].to_upper()
	t += "[table=2]"
	t += "[cell]ручек построено  [/cell][cell]%d[/cell]" % _panel.built
	t += "[cell]диапазон выдуман  [/cell][cell][color=#ffd479]%d[/color]   (нет hint_range)[/cell]" % _panel.guessed
	t += "[cell]не покрутить  [/cell][cell][color=#ff8a6a]%d[/color]   (текстуры, массивы)[/cell]" % _panel.skipped
	t += "[cell]по всему проекту  [/cell][cell]%s[/cell]" % audit
	t += "[/table]\n\n"
	t += "%s\n\n" % note
	t += "1 2 3 — мишень    R — выкрутить всё случайно    0 — сброс\n"
	t += "F5 — сохранить пресет и проверить кругооборотом    F9 — загрузить\n"
	t += "правая кнопка — повернуть, колесо — приблизить\n"
	t += "[color=#ffd479]жёлтая подпись — диапазон ползунка выдуман панелью, а не объявлен шейдером[/color]"
	$Ui/Info.text = t
