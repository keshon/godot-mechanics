class_name DataBench
extends Node3D
## Content as data.
##
## Every sword and every monster in this probe is a .tres file in content/. This
## script has never heard of a sword or a monster. It knows four verbs and a
## folder.
##
## The claim being tested: adding a THING costs zero lines of code, and only
## adding a KIND OF BEHAVIOUR costs code. If that holds, content scales and code
## does not.

const FOLDER := "res://probes/15_data/content/"
## Damage before a single piece of gear is worn.
const BASE_POWER := 10.0

@export_range(1.0, 40.0) var base_power := BASE_POWER

var items: Array[DataDef] = []
var foes: Array[DataDef] = []
var gear: Array[DataDef] = []

var pick := 0
var foe := 0

var _stage: Array[Node3D] = []

@onready var _gear_root: Node3D = $Gear
@onready var _proto: MeshInstance3D = $Proto/Bit
@onready var _foe_mesh: MeshInstance3D = $Foe
@onready var _hud: RichTextLabel = $Ui/Info
@onready var _items_label: RichTextLabel = $Ui/Items
@onready var _foes_label: RichTextLabel = $Ui/Foes
@onready var _trace_label: RichTextLabel = $Ui/Trace


func _ready() -> void:
	scan()


func _process(delta: float) -> void:
	_draw_hud()
	var seconds := float(Time.get_ticks_msec()) * 0.001
	for i in _stage.size():
		_stage[i].rotate_y(0.6 * delta)
		_stage[i].position.y = 1.6 + sin(seconds * 1.6 + i) * 0.12


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_LEFT:
			pick = posmod(pick - 1, maxi(items.size(), 1))
		KEY_RIGHT:
			pick = posmod(pick + 1, maxi(items.size(), 1))
		KEY_UP:
			foe = posmod(foe - 1, maxi(foes.size(), 1))
		KEY_DOWN:
			foe = posmod(foe + 1, maxi(foes.size(), 1))
		KEY_SPACE:
			if pick < items.size():
				var definition := items[pick]
				if gear.has(definition):
					gear.erase(definition)
				else:
					gear.append(definition)
				_build_stage()
		KEY_C:
			gear.clear()
			_build_stage()
		KEY_R:
			scan()


## The registry is a folder, not a list in code. Drop a .tres in, press R.
func scan() -> void:
	items.clear()
	foes.clear()
	gear.clear()
	var names := DirAccess.get_files_at(FOLDER)
	names.sort()
	for file in names:
		# .tres becomes .res once the project is exported. Accept both, always.
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var loaded := load(FOLDER + file)
		if loaded is DataDef:
			if (loaded as DataDef).kind == DataDef.Kind.ITEM:
				items.append(loaded)
			else:
				foes.append(loaded)
	pick = clampi(pick, 0, maxi(items.size() - 1, 0))
	foe = clampi(foe, 0, maxi(foes.size() - 1, 0))
	_build_stage()


## The whole combat system.
##
## Read it and notice what is MISSING. No item name. No monster name. No list of
## types. Twenty items times eight monsters is a hundred and sixty different
## answers, and none of the hundred and sixty is written down anywhere.
func resolve(held: Array[DataDef], target: DataDef) -> Dictionary:
	var trace: Array[String] = []
	var power := base_power
	var tags := {}
	trace.append("своя сила                         %6.1f" % power)

	for definition in held:
		for effect in definition.effects:
			if effect.verb == DataEffect.Verb.ADD and effect.stat == "power":
				power += effect.amount
				trace.append("%-22s %+6.1f  %6.1f" % [definition.title, effect.amount, power])
			elif effect.verb == DataEffect.Verb.TAG:
				tags[effect.tag] = true
				trace.append("%-22s  несёт метку [%s]" % [definition.title, effect.tag])

	# Every multiplier lands after every addition. An RPG rule, not a coding one:
	# interleave them and the same gear gives different numbers depending on the
	# order it happened to be picked up in.
	for definition in held:
		for effect in definition.effects:
			if effect.verb == DataEffect.Verb.MUL and effect.stat == "power":
				power *= effect.amount
				trace.append("%-22s  x%-5.2f %6.1f" % [definition.title, effect.amount, power])

	var damage := power
	for effect in target.effects:
		if effect.verb != DataEffect.Verb.VULN or not tags.has(effect.tag):
			continue
		damage *= effect.amount
		var word := "стойкий к"
		if effect.amount > 1.0:
			word = "уязвим к"
		elif effect.amount <= 0.0:
			word = "неуязвим к"
		trace.append("%-13s %-8s [%s]  x%-5.2f %6.1f" % [
			target.title, word, effect.tag, effect.amount, damage])

	# Two rules argued here: armour leaves you a chip of 1, immunity leaves
	# nothing. Immunity wins, or an immune monster quietly becomes killable.
	if target.armour > 0.0 and damage > 0.0:
		damage = maxf(damage - target.armour, 1.0)
		trace.append("%-22s броня %-2.0f  %6.1f" % [target.title, target.armour, damage])
	if damage <= 0.0:
		trace.append("%-22s не берёт вообще ничего" % target.title)

	return {
		"damage": damage,
		"swings": -1 if damage <= 0.0 else ceili(target.hp / damage),
		"trace": trace,
		"tags": tags.keys(),
	}


func _build_stage() -> void:
	for node in _gear_root.get_children():
		node.free()
	_stage.clear()
	for i in gear.size():
		var instance := MeshInstance3D.new()
		instance.mesh = _proto.mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = gear[i].colour
		material.emission_enabled = true
		material.emission = gear[i].colour * 0.4
		instance.material_override = material
		var angle := TAU * float(i) / maxf(gear.size(), 1.0)
		instance.position = Vector3(cos(angle) * 1.3, 1.6, sin(angle) * 1.3)
		_gear_root.add_child(instance)
		_stage.append(instance)
	if foe < foes.size():
		var definition := foes[foe]
		var material := StandardMaterial3D.new()
		material.albedo_color = definition.colour
		_foe_mesh.material_override = material
		_foe_mesh.scale = Vector3.ONE * (0.7 + definition.hp / 120.0)


func _draw_hud() -> void:
	if items.is_empty() or foes.is_empty():
		_hud.text = "[color=#ff8a6a]папка content/ пуста[/color]"
		return

	var result := resolve(gear, foes[foe])
	var swings: int = result["swings"]
	_hud.text = "\n".join(PackedStringArray([
		"урон [b]%.1f[/b]   %s   надето %d из %d предметов   врагов %d" % [
			result["damage"],
			"[color=#ff8a6a]не умирает никогда[/color]" if swings < 0
				else "ударов до смерти [b]%d[/b]" % swings,
			gear.size(), items.size(), foes.size()],
		"",
		"← → выбрать предмет   ПРОБЕЛ надеть или снять   C раздеться догола",
		"↑ ↓ выбрать врага   R перечитать папку",
		"каждый предмет и каждый враг — один .tres в content/: заголовок, цвет и список"
			+ " эффектов",
		"",
		"[color=#66ccff]закрытый набор из четырёх глаголов вместо if type ==:"
			+ " bench.gd не слышал слова «меч»[/color]",
	]))

	var left := "[b]предметы[/b]\n"
	for i in items.size():
		var mark := "x" if gear.has(items[i]) else " "
		var cursor := "[color=#ffd479]>[/color]" if i == pick else " "
		left += "%s [%s] %s\n" % [cursor, mark, items[i].title]
	_items_label.text = left

	var right := "[b]враги[/b]\n"
	for i in foes.size():
		var cursor := "[color=#ffd479]>[/color]" if i == foe else " "
		right += "%s %-15s жизни %-4.0f броня %.0f\n" % [
			cursor, foes[i].title, foes[i].hp, foes[i].armour]
	_foes_label.text = right

	var middle := "[b]как получилось это число[/b]\n"
	for line in result["trace"]:
		middle += line + "\n"
	_trace_label.text = middle

