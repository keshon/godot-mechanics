class_name SpecBench
extends Node3D
## 20 — the bench. Play the spec by hand, or hand it to the robot and watch.
##
## The point of the probe is the button marked S. It runs the same fight four times
## with four priority lists, headless, in a few milliseconds, and prints how much
## damage each one did. That is theorycrafting, and it is the tool you need to balance
## any RPG — not just this one.
##
## P prints the other table: one clean hit per ability, the numbers to hold against a
## published one.

const HP := 600_000.0

var sim := SpecSim.new()
var autopilot := false
var list_name := "aimed on cooldown"
var report := ""
## Damage of the last ability fired by hand, so a press has an answer on screen.
var last_hit := 0.0

var _list_names: Array[String] = []
## Time owed to the simulation but not yet stepped, seconds.
var _leftover := 0.0

@onready var _dummy: MeshInstance3D = $Dummy
@onready var _bar: SpecBar = $Ui/Bar
@onready var _info: RichTextLabel = $Ui/Info


func _ready() -> void:
	for key in SpecSim.PRIORITIES:
		_list_names.append(key)
	sim.reset(HP)
	_bar.setup(sim)
	_run_report()


func _process(delta: float) -> void:
	# The sim ticks at a fixed 10 ms. Keep the leftover, or it runs slow: at 60 fps
	# int(delta / 0.01) is 1 instead of 1.67 and the rotation plays at 0.6x speed.
	_leftover += delta
	var guard := 0
	while _leftover >= SpecSim.TICK and guard < 200:
		guard += 1
		_leftover -= SpecSim.TICK
		if autopilot:
			sim.auto(SpecSim.PRIORITIES[list_name])
		sim.step()
	if sim.target_hp <= 0.0:
		sim.reset(HP)
	_dummy.scale = Vector3.ONE * (0.45 + 0.55 * sim.target_hp / sim.target_max)
	_bar.queue_redraw()
	_draw_hud()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode >= KEY_1 and event.keycode <= KEY_7:
		var slot: int = event.keycode - KEY_1
		var before := sim.damage
		sim.use(slot)
		if sim.damage > before:
			last_hit = sim.damage - before
		return
	match event.keycode:
		KEY_A:
			autopilot = not autopilot
		KEY_T:
			var next := (_list_names.find(list_name) + 1) % _list_names.size()
			list_name = _list_names[next]
		KEY_S:
			_run_report()
		KEY_P:
			_run_check()
		KEY_R:
			sim.reset(HP)


## The whole reason the probe exists: four ten-minute fights, headless, on one press.
func _run_report() -> void:
	var started := Time.get_ticks_usec()
	var rows: Array[String] = []
	var base := 0.0
	for key in SpecSim.PRIORITIES:
		var bot := SpecSim.new()
		var result := bot.run(key, HP)
		if base == 0.0:
			base = result["dps"]
		rows.append(
				"[cell]%s  [/cell][cell]%.0f  [/cell][cell]%.0f s  [/cell]"
				% [key, result["dps"], result["time"]]
				+ "[cell]%d  [/cell][cell]%+.1f%%[/cell]"
				% [result["wasted"], 100.0 * (result["dps"] / base - 1.0)])
	var elapsed_ms := (Time.get_ticks_usec() - started) / 1000.0
	report = "[table=5][cell][b]priority list[/b]  [/cell][cell][b]dps[/b]  [/cell]"
	report += "[cell][b]kill time[/b]  [/cell][cell][b]procs wasted[/b]  [/cell]"
	report += "[cell][b]vs first[/b][/cell]"
	for row in rows:
		report += row
	report += "[/table]\n[color=#888888]four ten-minute fights simulated in %.0f ms" % (
			elapsed_ms)
	report += "[/color]"


## One clean hit per ability. This is the table to check the model against a source.
func _run_check() -> void:
	report = "[table=2][cell][b]one clean hit[/b]  [/cell][cell][b]damage[/b][/cell]"
	for i in SpecSim.ABILITIES.size():
		if float(SpecSim.ABILITIES[i]["coef"]) <= 0.0:
			continue
		report += "[cell]%s  [/cell][cell]%.0f[/cell]" % [
			SpecSim.ABILITIES[i]["name"], sim.plain(i)]
	report += "[/table]\n[color=#888888]no procs, no execute window, no crit[/color]"


func _draw_hud() -> void:
	var text := "[b]Marksmanship, Shadowlands.[/b]  AP %.0f, vers %.0f%%, mastery %.0f%%\n" % [
		sim.attack_power, sim.versatility * 100.0, sim.mastery * 100.0]
	text += "target %.0f%%   focus %.0f/100   last hit %.0f\n\n" % [
		100.0 * sim.target_hp / sim.target_max, sim.focus, last_hit]
	var held := ""
	for buff in sim.buffs:
		var count: int = sim.stacks(buff)
		if count > 0:
			held += "[color=#ffd479]%s x%d[/color]   " % [buff, count]
	text += "buffs: %s\n\n" % ("none" if held == "" else held)
	text += report + "\n\n"
	text += "1..7 fire    A robot plays: %s    T list: [color=#ffd479]%s[/color]\n" % [
		"ON" if autopilot else "off", list_name]
	text += "S the four fights    P one clean hit each    R reset the dummy"
	_info.text = text
