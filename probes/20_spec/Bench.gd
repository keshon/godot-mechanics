extends Node3D

# 20 — the bench. Play the spec by hand, or hand it to the robot and watch.
#
# The point of the probe is the button marked S. It runs the same fight four times
# with four priority lists, headless, in a few milliseconds, and prints how much
# damage each one did. That is theorycrafting, and it is the tool you need to balance
# any RPG — not just this one.

const HP := 600_000.0

var sim := SpecSim.new()
var autopilot := false
var list_name := "aimed on cooldown"
var report := ""
var floats: Array[Dictionary] = []

var _names: Array[String] = []
var _acc := 0.0


func _ready() -> void:
	for k in SpecSim.PRIORITIES:
		_names.append(k)
	sim.reset(HP)
	_run_report()


func _process(delta: float) -> void:
	# the sim ticks at a fixed 10 ms. keep the leftover, or it runs slow and you get
	# a rotation that quietly plays at 0.6x speed.
	_acc += delta
	var guard := 0
	while _acc >= SpecSim.TICK and guard < 200:
		guard += 1
		_acc -= SpecSim.TICK
		if autopilot:
			sim.auto(SpecSim.PRIORITIES[list_name])
		sim.step()
	if sim.target_hp <= 0.0:
		sim.reset(HP)
	for f in floats:
		f["t"] = minf(f["t"] + delta / 1.2, 1.0)
	$Dummy.scale = Vector3.ONE * (0.45 + 0.55 * sim.target_hp / sim.target_max)
	$Ui/Bar.queue_redraw()
	_hud()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode >= KEY_1 and event.keycode <= KEY_7:
		var i: int = event.keycode - KEY_1
		var before := sim.damage
		sim.use(i)
		if sim.damage > before:
			_pop(sim.damage - before, SpecSim.ABILITIES[i]["col"])
		return
	match event.keycode:
		KEY_A:
			autopilot = not autopilot
		KEY_T:
			list_name = _names[(_names.find(list_name) + 1) % _names.size()]
		KEY_S:
			_run_report()
		KEY_R:
			sim.reset(HP)


func _pop(dmg: float, col: Color) -> void:
	for f in floats:
		if f["t"] >= 1.0:
			f["text"] = str(roundi(dmg))
			f["col"] = col
			f["t"] = 0.0
			f["dx"] = randf_range(-40.0, 40.0)
			return
	floats.append({"text": str(roundi(dmg)), "col": col, "t": 0.0, "dx": randf_range(-40.0, 40.0)})


# --- the whole reason the probe exists ----------------------------------------

func _run_report() -> void:
	var t0 := Time.get_ticks_usec()
	var lines: Array[String] = []
	var base := 0.0
	for name in SpecSim.PRIORITIES:
		var bot := SpecSim.new()
		var r = bot.run(name, HP)
		if base == 0.0:
			base = r["dps"]
		lines.append("[cell]%s  [/cell][cell]%.0f  [/cell][cell]%.0f s  [/cell][cell]%d  [/cell][cell]%+.1f%%[/cell]"
			% [name, r["dps"], r["time"], r["wasted"], 100.0 * (r["dps"] / base - 1.0)])
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	report = "[table=5][cell][b]priority list[/b]  [/cell][cell][b]dps[/b]  [/cell]"
	report += "[cell][b]kill time[/b]  [/cell][cell][b]procs wasted[/b]  [/cell][cell][b]vs first[/b][/cell]"
	for l in lines:
		report += l
	report += "[/table]\n[color=#888888]four ten-minute fights simulated in %.0f ms[/color]" % ms


func _hud() -> void:
	var t := "[b]Marksmanship, Shadowlands.[/b]  AP %.0f, vers %.0f%%, mastery %.0f%%\n" % [
		sim.attack_power, sim.versatility * 100.0, sim.mastery * 100.0]
	t += "target %.0f%%   focus %.0f/100\n\n" % [
		100.0 * sim.target_hp / sim.target_max, sim.focus]
	var buffs := ""
	for name in sim.buffs:
		var n: int = sim.stacks(name)
		if n > 0:
			buffs += "[color=#ffd479]%s x%d[/color]   " % [name, n]
	t += "buffs: %s\n\n" % ("none" if buffs == "" else buffs)
	t += report + "\n\n"
	t += "1..7 fire    A robot plays: %s    T list: [color=#ffd479]%s[/color]\n" % [
		"ON" if autopilot else "off", list_name]
	t += "S run the four fights again    R reset the dummy"
	$Ui/Info.text = t
