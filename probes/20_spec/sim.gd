class_name SpecSim
extends RefCounted
## 20 — a spec, as data. Marksmanship Hunter, Shadowlands numbers.
##
##   physical:  AP * coef * versatility * mastery(spenders only) * loneWolf * 0.70
##   magic:     AP * coef * versatility * mastery(spenders only) * loneWolf
##
## Armour is 30% off physical only. Arcane Shot is nature damage and skips it, which
## is why a 0.534 coefficient competes with a 2.475 one once the proc is up.
##
## The thing this file has that probe 19 did not: BUFFS. An ability that changes what
## the next ability does. Without them an action bar is six independent timers; with
## them there is a priority, and a priority is what a rotation actually is.
##
## Nothing here touches a node, which is why it can be run headless a thousand times.

## Seconds every ability locks every other one for.
const GCD := 1.5
## What is left of physical damage after armour.
const ARMOUR := 0.70
## Simulation step, seconds.
const TICK := 0.01

## coef     multiplies attack power
## cast     seconds, 0 = instant. A channel fires `ticks` shots over `cast`
## focus    negative spends, positive generates
## cooldown seconds. charges > 1 means this is the RECHARGE of one charge
##
## Values marked ESTIMATE were not in the source table and are a guess. Getting one
## of them wrong costs one field and zero lines of code — which is the whole point of
## probe 15 arriving before this one.
const ABILITIES: Array[Dictionary] = [
	# cooldown ESTIMATE
	{"name": "Aimed Shot", "key": "1", "coef": 2.475, "cast": 2.5, "focus": -35.0,
		"cooldown": 12.0, "charges": 2, "ticks": 1, "colour": Color(0.95, 0.72, 0.3)},
	# cooldown ESTIMATE
	{"name": "Rapid Fire", "key": "2", "coef": 1.414, "cast": 2.0, "focus": 15.0,
		"cooldown": 20.0, "charges": 1, "ticks": 7, "colour": Color(0.95, 0.45, 0.3)},
	{"name": "Arcane Shot", "key": "3", "coef": 0.534, "cast": 0.0, "focus": -15.0,
		"cooldown": 0.0, "charges": 1, "ticks": 1, "magic": true,
		"colour": Color(0.55, 0.7, 1.0)},
	{"name": "Multi-Shot", "key": "4", "coef": 0.372, "cast": 0.0, "focus": -20.0,
		"cooldown": 0.0, "charges": 1, "ticks": 1, "colour": Color(0.6, 0.85, 0.95)},
	{"name": "Steady Shot", "key": "5", "coef": 0.300, "cast": 1.75, "focus": 10.0,
		"cooldown": 0.0, "charges": 1, "ticks": 1, "colour": Color(0.75, 0.78, 0.82)},
	{"name": "Kill Shot", "key": "6", "coef": 2.000, "cast": 0.0, "focus": -10.0,
		"cooldown": 10.0, "charges": 1, "ticks": 1, "colour": Color(1.0, 0.35, 0.35)},
	{"name": "Trueshot", "key": "7", "coef": 0.0, "cast": 0.0, "focus": 0.0,
		"cooldown": 120.0, "charges": 1, "ticks": 1, "colour": Color(0.9, 0.85, 0.45)},
]

const AIMED := 0
const RAPID := 1
const ARCANE := 2
const MULTI := 3
const STEADY := 4
const KILL := 5
const TRUESHOT := 6

## A priority list IS the rotation. These are data, and swapping them is the
## experiment the probe exists for.
const PRIORITIES := {
	"сначала тратить прок": [TRUESHOT, KILL, ARCANE, RAPID, AIMED, STEADY],
	"Aimed по откату": [TRUESHOT, KILL, RAPID, AIMED, ARCANE, STEADY],
	"прок не тратить вовсе": [TRUESHOT, KILL, RAPID, AIMED, STEADY],
	"без больших откатов": [KILL, RAPID, AIMED, ARCANE, STEADY],
}

## Shadowlands season 4, top gear.
@export var attack_power := 2200.0
@export var versatility := 0.15
## Sniper Training: focus SPENDERS only.
@export var mastery := 0.25
## Focus per second. ESTIMATE.
@export var focus_regen := 10.0
## The source formula has no crit. Turn it on to taste.
@export var crit := 0.0
@export var targets := 1

@export_group("Talents and passives")
## Aimed Shot +50% above 80% target hp.
@export var careful_aim := true
## +10% all damage with no pet.
@export var lone_wolf := true
## Aimed grants 2 stacks, Arcane and Multi spend one for +75%.
@export var precise_shots := true

var focus := 100.0
var focus_max := 100.0
## Simulated time, seconds.
var now := 0.0
var gcd_until := 0.0
var busy_until := 0.0
var casting := -1
var cast_from := 0.0
var channel_next := 0.0
var channel_left := 0

var charges := PackedInt32Array()
var recharge_at := PackedFloat64Array()
## Buff name to {stacks, until}.
var buffs := {}

var target_hp := 1.0
var target_max := 1.0
var damage := 0.0
var used := PackedInt32Array()
var wasted_procs := 0
## Seconds the robot had nothing it was allowed to press.
var starved := 0.0

var _random := RandomNumberGenerator.new()


func reset(hp: float, seed_value := 1) -> void:
	focus = 100.0
	now = 0.0
	gcd_until = 0.0
	busy_until = 0.0
	casting = -1
	channel_left = 0
	charges = PackedInt32Array()
	recharge_at = PackedFloat64Array()
	used = PackedInt32Array()
	charges.resize(ABILITIES.size())
	recharge_at.resize(ABILITIES.size())
	used.resize(ABILITIES.size())
	for i in ABILITIES.size():
		charges[i] = ABILITIES[i]["charges"]
	buffs.clear()
	target_max = hp
	target_hp = hp
	damage = 0.0
	wasted_procs = 0
	starved = 0.0
	_random.seed = seed_value


func stacks(buff: String) -> int:
	var held: Dictionary = buffs.get(buff, {})
	if held.is_empty() or now >= held["until"]:
		return 0
	return held["stacks"]


func grant(buff: String, count: int, seconds: float) -> void:
	if not precise_shots and buff == "Precise Shots":
		return
	if buff == "Precise Shots" and stacks(buff) > 0:
		wasted_procs += stacks(buff)
	buffs[buff] = {"stacks": count, "until": now + seconds}


func consume(buff: String) -> bool:
	var held := stacks(buff)
	if held <= 0:
		return false
	buffs[buff]["stacks"] = held - 1
	return true


func step() -> void:
	now += TICK
	focus = minf(focus + focus_regen * TICK, focus_max)
	for i in ABILITIES.size():
		var ability: Dictionary = ABILITIES[i]
		if charges[i] < ability["charges"] and now >= recharge_at[i]:
			charges[i] += 1
			if charges[i] < ability["charges"]:
				recharge_at[i] = now + _cooldown_of(i)
	if channel_left > 0 and now >= channel_next:
		var per_tick := float(ABILITIES[RAPID]["ticks"])
		_hit(RAPID, float(ABILITIES[RAPID]["coef"]) / per_tick)
		channel_left -= 1
		channel_next = now + float(ABILITIES[RAPID]["cast"]) / per_tick
		if channel_left == 0:
			casting = -1
	elif casting >= 0 and casting != RAPID and now >= busy_until:
		var slot := casting
		casting = -1
		_land(slot)


func cast_time(slot: int) -> float:
	var seconds: float = ABILITIES[slot]["cast"]
	if stacks("Trueshot") > 0 and (slot == AIMED or slot == STEADY):
		seconds *= 0.5
	return seconds


func can_use(slot: int) -> bool:
	if now < gcd_until or casting >= 0 or now < busy_until:
		return false
	if charges[slot] <= 0:
		return false
	if focus + float(ABILITIES[slot]["focus"]) < 0.0:
		return false
	if slot == KILL and target_hp > target_max * 0.20:
		return false
	if slot == ARCANE and precise_shots and stacks("Precise Shots") == 0:
		# Arcane Shot is a PROC SPENDER, not a filler. Without a stack it is a worse
		# Steady Shot that also costs focus. This one condition is what turns six
		# buttons into a rotation.
		return false
	return true


func use(slot: int) -> void:
	if not can_use(slot):
		return
	var ability: Dictionary = ABILITIES[slot]
	var lock := GCD
	if stacks("Trueshot") > 0 and slot == RAPID:
		lock *= 0.5
	gcd_until = now + lock
	if float(ability["cooldown"]) > 0.0:
		charges[slot] -= 1
		if charges[slot] == int(ability["charges"]) - 1:
			recharge_at[slot] = now + _cooldown_of(slot)
	var seconds := cast_time(slot)
	if seconds > 0.0:
		casting = slot
		cast_from = now
		busy_until = now + seconds
		if slot == RAPID:
			# A channel never reaches _land, so its bookkeeping happens here.
			channel_left = ability["ticks"]
			channel_next = now
			used[slot] += 1
			focus = clampf(focus + float(ability["focus"]), 0.0, focus_max)
		return
	_land(slot)


## The robot. Presses the first thing in the list it is allowed to press.
func auto(priority: Array) -> void:
	if now < gcd_until or casting >= 0 or now < busy_until:
		return
	for entry in priority:
		var slot: int = entry
		if can_use(slot):
			use(slot)
			return
	starved += TICK


## One clean hit: no procs, no execute window, no crit. This is the number to hold
## against a published table, ability by ability.
func plain(slot: int) -> float:
	var ability: Dictionary = ABILITIES[slot]
	var multiplier := 1.10 if lone_wolf else 1.0
	if float(ability["focus"]) < 0.0:
		multiplier *= 1.0 + mastery
	if not ability.get("magic", false):
		multiplier *= ARMOUR
	return attack_power * float(ability["coef"]) * (1.0 + versatility) * multiplier


## One whole fight, headless, as fast as the machine will go.
func run(list_name: String, hp: float, max_seconds := 600.0) -> Dictionary:
	reset(hp)
	var priority: Array = PRIORITIES[list_name]
	while target_hp > 0.0 and now < max_seconds:
		auto(priority)
		step()
	return {
		"dps": damage / maxf(now, 0.001),
		"time": now,
		"killed": target_hp <= 0.0,
		"starved": starved,
		"wasted": wasted_procs,
		"used": used.duplicate(),
	}


func _cooldown_of(slot: int) -> float:
	var seconds: float = ABILITIES[slot]["cooldown"]
	if slot == RAPID and stacks("Trueshot") > 0:
		seconds *= 0.5
	return seconds


func _land(slot: int) -> void:
	var ability: Dictionary = ABILITIES[slot]
	focus = clampf(focus + float(ability["focus"]), 0.0, focus_max)
	used[slot] += 1
	if slot == TRUESHOT:
		grant("Trueshot", 1, 15.0)
		return
	_hit(slot, ability["coef"])


func _hit(slot: int, coef: float) -> void:
	var ability: Dictionary = ABILITIES[slot]
	var multiplier := 1.0
	if lone_wolf:
		multiplier *= 1.10
	if float(ability["focus"]) < 0.0:
		# Sniper Training touches spenders only.
		multiplier *= 1.0 + mastery
	if slot == AIMED and careful_aim and target_hp > target_max * 0.80:
		multiplier *= 1.50
	if (slot == ARCANE or slot == MULTI) and precise_shots and consume("Precise Shots"):
		multiplier *= 1.75
	if slot == AIMED:
		grant("Precise Shots", 2, 15.0)
	if crit > 0.0 and _random.randf() < crit:
		multiplier *= 2.0
	var struck := targets if slot == MULTI else 1
	if not ability.get("magic", false):
		multiplier *= ARMOUR
	var dealt := attack_power * coef * (1.0 + versatility) * multiplier * struck
	damage += dealt
	target_hp = maxf(target_hp - dealt, 0.0)
