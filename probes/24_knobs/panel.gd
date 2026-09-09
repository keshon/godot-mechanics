class_name TunePanel
extends VBoxContainer
## One control per declared parameter, built by ASKING THE SOURCE what it has.
##
## Nothing here knows about water, or PSX, or any particular shader. It knows four
## things: what types can be declared, what hints those can carry, which Godot control
## fits each, and where to read the current value from.
##
## Two kinds of source, and the reason both work is that Godot describes them
## IDENTICALLY: `Shader.get_shader_uniform_list()` and `Object.get_property_list()`
## return dictionaries with the same keys, and `@export_range(0, 2)` in GDScript
## produces the same PROPERTY_HINT_RANGE as `hint_range(0, 2)` in GLSL. So the builder
## does not care whether it is looking at a shader or at a script.

## A float with no declared range gets bounds invented from its default. That guess is
## the weak spot of the whole idea, so it is counted separately and painted.
const GUESS_SPAN := 4.0

var built := 0
var guessed := 0
var skipped := 0

var _material: ShaderMaterial


func begin() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	built = 0
	guessed = 0
	skipped = 0


func add_shader(material: ShaderMaterial, title: String) -> void:
	_material = material
	_add_title(title)
	# `true` asks for group markers too: `group_uniforms` comes back as an entry with
	# PROPERTY_USAGE_GROUP and no type of its own.
	for uniform in material.shader.get_shader_uniform_list(true):
		_add_row(material, uniform)


func add_object(source: Object, title: String) -> void:
	_add_title(title)
	for uniform in source.get_property_list():
		# Only @export vars: a plain script variable carries SCRIPT_VARIABLE but not
		# EDITOR, which is exactly the line between "the author offered this knob" and
		# "this is internal bookkeeping".
		var usage := int(uniform["usage"])
		if not (usage & PROPERTY_USAGE_EDITOR):
			continue
		if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		_add_row(source, uniform)


func parameter_names() -> PackedStringArray:
	var found := PackedStringArray()
	for uniform in _material.shader.get_shader_uniform_list(false):
		found.append(uniform["name"])
	return found


func reset_all() -> void:
	for parameter in parameter_names():
		_material.set_shader_parameter(
				parameter,
				RenderingServer.shader_get_parameter_default(
						_material.shader.get_rid(), parameter))


func randomize_all() -> void:
	for uniform in _material.shader.get_shader_uniform_list(false):
		var parameter: String = uniform["name"]
		match int(uniform["type"]):
			TYPE_BOOL:
				_material.set_shader_parameter(parameter, randf() < 0.5)
			TYPE_COLOR:
				_material.set_shader_parameter(
						parameter, Color(randf(), randf(), randf()))
			TYPE_FLOAT:
				var span := _range(_material, uniform)
				_material.set_shader_parameter(parameter, randf_range(span.x, span.y))
			TYPE_INT:
				var span := _range(_material, uniform)
				_material.set_shader_parameter(
						parameter, randi_range(int(span.x), int(span.y)))


## Current value. Not as simple as it looks for a material: it stores only what somebody
## OVERRODE and returns null for everything untouched — the default lives in the shader.
##
## Which is also why this probe cannot be checked with --headless: without a rendering
## device `shader_get_parameter_default` gives back null for everything, and every
## slider is built on a null. Probe 23 hit the same wall from the other side.
func _read(source: Object, parameter: String) -> Variant:
	if not (source is ShaderMaterial):
		return source.get(parameter)
	var material := source as ShaderMaterial
	var value: Variant = material.get_shader_parameter(parameter)
	if value != null:
		return value
	return RenderingServer.shader_get_parameter_default(
			material.shader.get_rid(), parameter)


func _write(source: Object, parameter: String, value: Variant) -> void:
	if source is ShaderMaterial:
		(source as ShaderMaterial).set_shader_parameter(parameter, value)
	else:
		source.set(parameter, value)


## Bounds, and the one honest admission of the probe: declared if the author declared
## them, invented from the magnitude of the default otherwise.
func _range(source: Object, uniform: Dictionary) -> Vector2:
	if int(uniform["hint"]) == PROPERTY_HINT_RANGE:
		var parts: PackedStringArray = str(uniform["hint_string"]).split(",")
		return Vector2(float(parts[0]), float(parts[1]))
	var current := float(_read(source, uniform["name"]))
	var high := maxf(absf(current) * GUESS_SPAN, 1.0)
	return Vector2(-high if current < 0.0 else 0.0, high)


func _add_title(text: String) -> void:
	var label := Label.new()
	label.text = "  %s" % text.to_upper()
	label.modulate = Color(0.55, 0.78, 1.0)
	add_child(label)


func _add_row(source: Object, uniform: Dictionary) -> void:
	var parameter: String = uniform["name"]
	var usage := int(uniform["usage"])
	if usage & PROPERTY_USAGE_GROUP or usage & PROPERTY_USAGE_SUBGROUP:
		_add_title(parameter)
		return
	var control := _control(source, uniform)
	if control == null:
		skipped += 1
		var missing := Label.new()
		missing.text = "%s — %s, ручкой не покрутишь" % [
			parameter, _type_name(uniform)]
		missing.modulate = Color(1.0, 0.55, 0.42)
		add_child(missing)
		return
	built += 1
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = parameter
	label.custom_minimum_size.x = 148
	# Orange label = the range under this slider was invented, not declared.
	var kind := int(uniform["type"])
	if (
			int(uniform["hint"]) != PROPERTY_HINT_RANGE
			and kind != TYPE_BOOL
			and kind != TYPE_COLOR
	):
		label.modulate = Color(1.0, 0.83, 0.47)
	row.add_child(label)
	row.add_child(control)
	add_child(row)


func _control(source: Object, uniform: Dictionary) -> Control:
	var parameter: String = uniform["name"]
	var hint := int(uniform["hint"])
	match int(uniform["type"]):
		TYPE_BOOL:
			var check := CheckBox.new()
			check.button_pressed = bool(_read(source, parameter))
			check.toggled.connect(
					func(on: bool) -> void: _write(source, parameter, on))
			return check
		TYPE_COLOR:
			var picker := ColorPickerButton.new()
			picker.custom_minimum_size = Vector2(150, 20)
			picker.color = _read(source, parameter)
			picker.edit_alpha = false
			picker.color_changed.connect(
					func(picked: Color) -> void: _write(source, parameter, picked))
			return picker
		TYPE_INT:
			if hint == PROPERTY_HINT_ENUM:
				var options := OptionButton.new()
				for item in str(uniform["hint_string"]).split(","):
					options.add_item(item)
				options.selected = int(_read(source, parameter))
				options.item_selected.connect(
						func(item: int) -> void: _write(source, parameter, item))
				return options
			var span := _range(source, uniform)
			if hint != PROPERTY_HINT_RANGE:
				guessed += 1
			return _slider(
					source, parameter, span.x, span.y, 1.0,
					float(_read(source, parameter)), true, -1)
		TYPE_FLOAT:
			var span := _range(source, uniform)
			var step := 0.001
			if hint == PROPERTY_HINT_RANGE:
				var parts: PackedStringArray = str(uniform["hint_string"]).split(",")
				if parts.size() > 2:
					step = float(parts[2])
			else:
				guessed += 1
			return _slider(
					source, parameter, span.x, span.y, step,
					float(_read(source, parameter)), false, -1)
		TYPE_VECTOR2, TYPE_VECTOR3:
			guessed += 1
			var axes := 2 if int(uniform["type"]) == TYPE_VECTOR2 else 3
			var column := VBoxContainer.new()
			for axis in axes:
				var current := float(_read(source, parameter)[axis])
				var high := maxf(absf(current) * GUESS_SPAN, 1.0)
				column.add_child(_slider(
						source, parameter, -high, high, 0.001, current, false, axis))
			return column
	return null


## One slider plus its readout. `axis` >= 0 means it drives a single component of a
## vector: the setter rebuilds the whole vector with that one place replaced, because a
## parameter can only be written whole.
func _slider(
		source: Object,
		parameter: String,
		low: float,
		high: float,
		step: float,
		value: float,
		whole: bool,
		axis: int) -> Control:
	var row := HBoxContainer.new()
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = clampf(value, low, high)
	slider.custom_minimum_size = Vector2(150, 16)
	var readout := Label.new()
	readout.custom_minimum_size.x = 56
	readout.text = ("%d" % value) if whole else ("%.3f" % value)
	slider.value_changed.connect(func(moved: float) -> void:
		readout.text = ("%d" % moved) if whole else ("%.3f" % moved)
		if axis < 0:
			_write(source, parameter, int(moved) if whole else moved)
		else:
			var current: Variant = _read(source, parameter)
			current[axis] = moved
			_write(source, parameter, current))
	row.add_child(slider)
	row.add_child(readout)
	return row


func _type_name(uniform: Dictionary) -> String:
	if int(uniform["type"]) == TYPE_OBJECT:
		return "текстура"
	return type_string(int(uniform["type"]))
