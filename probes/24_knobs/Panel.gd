class_name TunePanel
extends VBoxContainer

## One control per declared parameter, built by ASKING THE SOURCE what it has.
##
## Nothing here knows about water, or PSX, or any particular shader. It knows four things:
## what types can be declared, what hints those can carry, which Godot control fits each,
## and where to read the current value from.
##
## Two kinds of source, and the reason both work is that Godot describes them IDENTICALLY:
## `Shader.get_shader_uniform_list()` and `Object.get_property_list()` return dictionaries
## with the same keys, and `@export_range(0, 2)` in GDScript produces the same
## PROPERTY_HINT_RANGE as `hint_range(0, 2)` in GLSL. So the builder does not care whether
## it is looking at a shader or at a script.

signal changed

## A float with no declared range gets bounds invented from its default. That guess is the
## weak spot of the whole idea, so it is counted separately and painted.
const GUESS_SPAN := 4.0

var built := 0
var guessed := 0
var skipped := 0

var _mat: ShaderMaterial


func begin() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	built = 0
	guessed = 0
	skipped = 0


func add_shader(mat: ShaderMaterial, title: String) -> void:
	_mat = mat
	_title(title)
	# `true` asks for group markers too: `group_uniforms` comes back as an entry with
	# PROPERTY_USAGE_GROUP and no type of its own.
	for u in mat.shader.get_shader_uniform_list(true):
		_row(mat, u)


func add_object(obj: Object, title: String) -> void:
	_title(title)
	for u in obj.get_property_list():
		# Only @export vars: a plain script variable carries SCRIPT_VARIABLE but not
		# EDITOR, which is exactly the line between "the author offered this knob" and
		# "this is internal bookkeeping".
		if not (int(u["usage"]) & PROPERTY_USAGE_EDITOR):
			continue
		if not (int(u["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		_row(obj, u)


func names() -> PackedStringArray:
	var out := PackedStringArray()
	for u in _mat.shader.get_shader_uniform_list(false):
		out.append(u["name"])
	return out


func reset_all() -> void:
	for nm in names():
		_mat.set_shader_parameter(nm,
			RenderingServer.shader_get_parameter_default(_mat.shader.get_rid(), nm))
	changed.emit()


func randomize_all() -> void:
	for u in _mat.shader.get_shader_uniform_list(false):
		var nm: String = u["name"]
		match int(u["type"]):
			TYPE_BOOL:
				_mat.set_shader_parameter(nm, randf() < 0.5)
			TYPE_COLOR:
				_mat.set_shader_parameter(nm, Color(randf(), randf(), randf()))
			TYPE_FLOAT:
				var r := _range(_mat, u)
				_mat.set_shader_parameter(nm, randf_range(r.x, r.y))
			TYPE_INT:
				var ri := _range(_mat, u)
				_mat.set_shader_parameter(nm, randi_range(int(ri.x), int(ri.y)))
	changed.emit()


## Current value. Not as simple as it looks for a material: it stores only what somebody
## OVERRODE, and returns null for everything untouched — the default lives in the shader.
func _read(src: Object, nm: String) -> Variant:
	if src is ShaderMaterial:
		var v: Variant = (src as ShaderMaterial).get_shader_parameter(nm)
		if v != null:
			return v
		return RenderingServer.shader_get_parameter_default(
			(src as ShaderMaterial).shader.get_rid(), nm)
	return src.get(nm)


func _write(src: Object, nm: String, v: Variant) -> void:
	if src is ShaderMaterial:
		(src as ShaderMaterial).set_shader_parameter(nm, v)
	else:
		src.set(nm, v)
	changed.emit()


## Bounds, and the one honest admission of the probe: declared if the author declared them,
## invented from the default's magnitude otherwise.
func _range(src: Object, u: Dictionary) -> Vector2:
	if int(u["hint"]) == PROPERTY_HINT_RANGE:
		var p: PackedStringArray = str(u["hint_string"]).split(",")
		return Vector2(float(p[0]), float(p[1]))
	var cur := float(_read(src, u["name"]))
	var hi := maxf(absf(cur) * GUESS_SPAN, 1.0)
	return Vector2(-hi if cur < 0.0 else 0.0, hi)


func _title(text: String) -> void:
	var l := Label.new()
	l.text = "  %s" % text.to_upper()
	l.modulate = Color(0.55, 0.78, 1.0)
	add_child(l)


func _row(src: Object, u: Dictionary) -> void:
	var nm: String = u["name"]
	var usage := int(u["usage"])
	if usage & PROPERTY_USAGE_GROUP or usage & PROPERTY_USAGE_SUBGROUP:
		_title(nm)
		return
	var ctl := _control(src, u)
	if ctl == null:
		skipped += 1
		var s := Label.new()
		s.text = "%s — %s, ручкой не покрутишь" % [nm, _kind(u)]
		s.modulate = Color(1.0, 0.55, 0.42)
		add_child(s)
		return
	built += 1
	var box := HBoxContainer.new()
	var lab := Label.new()
	lab.text = nm
	lab.custom_minimum_size.x = 148
	# Orange label = the range under this slider was invented, not declared.
	if int(u["hint"]) != PROPERTY_HINT_RANGE and int(u["type"]) != TYPE_BOOL \
			and int(u["type"]) != TYPE_COLOR:
		lab.modulate = Color(1.0, 0.83, 0.47)
	box.add_child(lab)
	box.add_child(ctl)
	add_child(box)


func _control(src: Object, u: Dictionary) -> Control:
	var nm: String = u["name"]
	match int(u["type"]):
		TYPE_BOOL:
			var cb := CheckBox.new()
			cb.button_pressed = bool(_read(src, nm))
			cb.toggled.connect(func(on: bool) -> void: _write(src, nm, on))
			return cb
		TYPE_COLOR:
			var cp := ColorPickerButton.new()
			cp.custom_minimum_size = Vector2(150, 20)
			cp.color = _read(src, nm)
			cp.edit_alpha = false
			cp.color_changed.connect(func(c: Color) -> void: _write(src, nm, c))
			return cp
		TYPE_INT:
			if int(u["hint"]) == PROPERTY_HINT_ENUM:
				var ob := OptionButton.new()
				for s in str(u["hint_string"]).split(","):
					ob.add_item(s)
				ob.selected = int(_read(src, nm))
				ob.item_selected.connect(func(i: int) -> void: _write(src, nm, i))
				return ob
			var ri := _range(src, u)
			if int(u["hint"]) != PROPERTY_HINT_RANGE:
				guessed += 1
			return _slider(src, nm, ri.x, ri.y, 1.0, float(_read(src, nm)), true, -1)
		TYPE_FLOAT:
			var r := _range(src, u)
			var step := 0.001
			if int(u["hint"]) == PROPERTY_HINT_RANGE:
				var p: PackedStringArray = str(u["hint_string"]).split(",")
				if p.size() > 2:
					step = float(p[2])
			else:
				guessed += 1
			return _slider(src, nm, r.x, r.y, step, float(_read(src, nm)), false, -1)
		TYPE_VECTOR2, TYPE_VECTOR3:
			guessed += 1
			var n := 2 if int(u["type"]) == TYPE_VECTOR2 else 3
			var col := VBoxContainer.new()
			for i in n:
				var c := float(_read(src, nm)[i])
				var hi := maxf(absf(c) * GUESS_SPAN, 1.0)
				col.add_child(_slider(src, nm, -hi, hi, 0.001, c, false, i))
			return col
	return null


## One slider plus its readout. `comp` >= 0 means it drives a single component of a vector:
## the setter rebuilds the whole vector with that one place replaced, because a parameter
## can only be written whole.
func _slider(src: Object, nm: String, lo: float, hi: float, step: float, val: float,
		whole: bool, comp: int) -> Control:
	var box := HBoxContainer.new()
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = clampf(val, lo, hi)
	sl.custom_minimum_size = Vector2(150, 16)
	var out := Label.new()
	out.custom_minimum_size.x = 56
	out.text = ("%d" % val) if whole else ("%.3f" % val)
	sl.value_changed.connect(func(v: float) -> void:
		out.text = ("%d" % v) if whole else ("%.3f" % v)
		if comp < 0:
			_write(src, nm, int(v) if whole else v)
		else:
			var cur: Variant = _read(src, nm)
			cur[comp] = v
			_write(src, nm, cur))
	box.add_child(sl)
	box.add_child(out)
	return box


func _kind(u: Dictionary) -> String:
	if int(u["type"]) == TYPE_OBJECT:
		return "текстура"
	return type_string(int(u["type"]))
