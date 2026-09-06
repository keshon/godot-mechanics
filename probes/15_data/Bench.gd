extends Node3D

# 15 — content as data.
#
# Every sword and every monster in this probe is a .tres file in content/. This script
# has never heard of a sword or a monster. It knows four verbs and a folder.
#
# The claim being tested: adding a THING costs zero lines of code, and only adding a
# KIND OF BEHAVIOUR costs code. If that holds, content scales and code does not.

const FOLDER := "res://probes/15_data/content/"
const BASE_POWER := 10.0

@export_range(1.0, 40.0) var base_power := BASE_POWER

var items: Array[DataDef] = []
var foes: Array[DataDef] = []
var gear: Array[DataDef] = []

var pick := 0
var foe := 0

var _stage: Array[Node3D] = []


func _ready() -> void:
	scan()


# --- the registry: a folder, not a list in code -------------------------------

func scan() -> void:
	items.clear()
	foes.clear()
	gear.clear()
	var names := DirAccess.get_files_at(FOLDER)
	names.sort()
	for f in names:
		# .tres becomes .res once the project is exported. accept both, always.
		if not (f.ends_with(".tres") or f.ends_with(".res")):
			continue
		var d := load(FOLDER + f)
		if d is DataDef:
			if (d as DataDef).kind == DataDef.Kind.ITEM:
				items.append(d)
			else:
				foes.append(d)
	pick = clampi(pick, 0, maxi(items.size() - 1, 0))
	foe = clampi(foe, 0, maxi(foes.size() - 1, 0))
	_build_stage()


# --- the resolver: the whole combat system ------------------------------------
#
# Read it and notice what is missing. No item name. No monster name. No list of
# types. Twenty items times eight monsters is a hundred and sixty different answers,
# and none of the hundred and sixty is written down anywhere.

func resolve(held: Array[DataDef], target: DataDef) -> Dictionary:
	var trace: Array[String] = []
	var power := base_power
	var tags := {}
	trace.append("base power                        %6.1f" % power)

	for d in held:
		for e in d.effects:
			var fx := e as DataEffect
			if fx == null:
				continue
			if fx.verb == DataEffect.Verb.ADD and fx.stat == "power":
				power += fx.amount
				trace.append("%-22s %+6.1f  %6.1f" % [d.title, fx.amount, power])
			elif fx.verb == DataEffect.Verb.TAG:
				tags[fx.tag] = true
				trace.append("%-22s  carries [%s]" % [d.title, fx.tag])

	# every multiplier lands after every addition. an RPG rule, not a coding one:
	# interleave them and the same gear gives different numbers depending on order.
	for d in held:
		for e in d.effects:
			var fx := e as DataEffect
			if fx != null and fx.verb == DataEffect.Verb.MUL and fx.stat == "power":
				power *= fx.amount
				trace.append("%-22s  x%-5.2f %6.1f" % [d.title, fx.amount, power])

	var dmg := power
	for e in target.effects:
		var fx := e as DataEffect
		if fx == null or fx.verb != DataEffect.Verb.VULN or not tags.has(fx.tag):
			continue
		dmg *= fx.amount
		var word := "weak to" if fx.amount > 1.0 else ("immune to" if fx.amount <= 0.0 else "resists")
		trace.append("%-13s %-8s [%s]  x%-5.2f %6.1f" % [target.title, word, fx.tag, fx.amount, dmg])

	# two rules argued here: armour leaves you a chip of 1, immunity leaves nothing.
	# immunity wins, or an immune monster quietly becomes killable.
	if target.armour > 0.0 and dmg > 0.0:
		dmg = maxf(dmg - target.armour, 1.0)
		trace.append("%-22s armour %-2.0f %6.1f" % [target.title, target.armour, dmg])
	if dmg <= 0.0:
		trace.append("%-22s takes nothing at all" % target.title)

	return {
		"damage": dmg,
		"swings": -1 if dmg <= 0.0 else ceili(target.hp / dmg),
		"trace": trace,
		"tags": tags.keys(),
	}


# --- hands --------------------------------------------------------------------

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
				var d := items[pick]
				if gear.has(d):
					gear.erase(d)
				else:
					gear.append(d)
				_build_stage()
		KEY_C:
			gear.clear()
			_build_stage()
		KEY_R:
			scan()


func _process(_delta: float) -> void:
	_hud()
	var t := float(Time.get_ticks_msec()) * 0.001
	for i in _stage.size():
		_stage[i].rotate_y(0.6 * get_process_delta_time())
		_stage[i].position.y = 1.6 + sin(t * 1.6 + i) * 0.12


func _build_stage() -> void:
	for n in $Gear.get_children():
		n.free()
	_stage.clear()
	for i in gear.size():
		var m := MeshInstance3D.new()
		m.mesh = $Proto/Bit.mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = gear[i].colour
		mat.emission_enabled = true
		mat.emission = gear[i].colour * 0.4
		m.material_override = mat
		var a := TAU * float(i) / maxf(gear.size(), 1.0)
		m.position = Vector3(cos(a) * 1.3, 1.6, sin(a) * 1.3)
		$Gear.add_child(m)
		_stage.append(m)
	if foe < foes.size():
		var d := foes[foe]
		var mat2 := StandardMaterial3D.new()
		mat2.albedo_color = d.colour
		$Foe.material_override = mat2
		$Foe.scale = Vector3.ONE * (0.7 + d.hp / 120.0)


func _hud() -> void:
	if items.is_empty() or foes.is_empty():
		$Ui/Hud/Big.text = "content/ is empty"
		return
	var r := resolve(gear, foes[foe])
	var sw: int = r["swings"]
	$Ui/Hud/Big.text = "%.1f  dmg      %s" % [r["damage"],
		"never dies" if sw < 0 else "%d swings" % sw]

	var left := "[b]items[/b]  %d files\n" % items.size()
	for i in items.size():
		var mark := "x" if gear.has(items[i]) else " "
		var cur := "[color=#ffd479]>[/color]" if i == pick else " "
		left += "%s [%s] %s\n" % [cur, mark, items[i].title]
	$Ui/Hud/Items.text = left

	var right := "[b]foes[/b]  %d files\n" % foes.size()
	for i in foes.size():
		var cur := "[color=#ffd479]>[/color]" if i == foe else " "
		right += "%s %-15s hp %-4.0f arm %.0f\n" % [cur, foes[i].title, foes[i].hp, foes[i].armour]
	$Ui/Hud/Foes.text = right

	var mid := "[b]how that number was reached[/b]\n"
	for line in r["trace"]:
		mid += line + "\n"
	$Ui/Hud/Trace.text = mid
