class_name SpecSim
extends RefCounted

# 20 — a spec, as data. Marksmanship Hunter, Shadowlands numbers.
#
#   physical:  AP * coef * versatility * mastery(spenders only) * loneWolf * 0.70
#   magic:     AP * coef * versatility * mastery(spenders only) * loneWolf
#
# Armour is 30% off physical only. Arcane Shot is nature damage and skips it, which
# is why a 0.534 coefficient competes with a 2.475 one once the proc is up.
#
# Everything below the line ESTIMATE was not in the source table and is my guess.
# Getting one of them wrong costs one field and zero lines of code — which is the
# whole point of probe 15 arriving before this one.
#
# The thing this file has that probe 19 did not: BUFFS. An ability that changes what
# the next ability does. Without them an action bar is six independent timers; with
# them there is a priority, and a priority is what a rotation actually is.

const GCD := 1.5
const ARMOUR := 0.70
const TICK := 0.01

# --- the abilities ------------------------------------------------------------
#  coef      x AP
#  cast      seconds, 0 = instant. channel = fires `ticks` shots over `cast`
#  focus     negative spends, positive generates
#  cd        seconds. charges > 1 means cd is the RECHARGE of one charge
const ABILITIES := [
	{"name": "Aimed Shot", "key": "1", "coef": 2.475, "cast": 2.5, "focus": -35.0,
		"cd": 12.0, "charges": 2, "ticks": 1, "col": Color(0.95, 0.72, 0.3)},      # cd ESTIMATE
	{"name": "Rapid Fire", "key": "2", "coef": 1.414, "cast": 2.0, "focus": 15.0,
		"cd": 20.0, "charges": 1, "ticks": 7, "col": Color(0.95, 0.45, 0.3)},      # cd ESTIMATE
	{"name": "Arcane Shot", "key": "3", "coef": 0.534, "cast": 0.0, "focus": -15.0,
		"cd": 0.0, "charges": 1, "ticks": 1, "magic": true, "col": Color(0.55, 0.7, 1.0)},
	{"name": "Multi-Shot", "key": "4", "coef": 0.372, "cast": 0.0, "focus": -20.0,
		"cd": 0.0, "charges": 1, "ticks": 1, "col": Color(0.6, 0.85, 0.95)},
	{"name": "Steady Shot", "key": "5", "coef": 0.300, "cast": 1.75, "focus": 10.0,
		"cd": 0.0, "charges": 1, "ticks": 1, "col": Color(0.75, 0.78, 0.82)},
	{"name": "Kill Shot", "key": "6", "coef": 2.000, "cast": 0.0, "focus": -10.0,
		"cd": 10.0, "charges": 1, "ticks": 1, "col": Color(1.0, 0.35, 0.35)},
	{"name": "Trueshot", "key": "7", "coef": 0.0, "cast": 0.0, "focus": 0.0,
		"cd": 120.0, "charges": 1, "ticks": 1, "col": Color(0.9, 0.85, 0.45)},
]

const AIMED := 0
const RAPID := 1
const ARCANE := 2
const MULTI := 3
const STEADY := 4
const KILL := 5
const TRUESHOT := 6

# a priority list IS the rotation. these are data, and swapping them is the experiment.
const PRIORITIES := {
	"spend the proc first": [TRUESHOT, KILL, ARCANE, RAPID, AIMED, STEADY],
	"aimed on cooldown": [TRUESHOT, KILL, RAPID, AIMED, ARCANE, STEADY],
	"never spend the proc": [TRUESHOT, KILL, RAPID, AIMED, STEADY],
	"no cooldowns at all": [KILL, RAPID, AIMED, ARCANE, STEADY],
}

@export var attack_power := 2200.0        # Shadowlands season 4, top gear
@export var versatility := 0.15
@export var mastery := 0.25            # Sniper Training: focus SPENDERS only
@export var focus_regen := 10.0        # ESTIMATE, per second
@export var crit := 0.0                # the source formula has no crit. turn it on to taste.
@export var targets := 1

@export_group("Talents and passives")
@export var careful_aim := true         # Aimed Shot +50% above 80% target hp
@export var lone_wolf := true           # +10% all damage with no pet
@export var precise_shots := true       # Aimed grants 2 stacks, Arcane/Multi spend one for +75%

var focus := 100.0
var focus_max := 100.0
var now := 0.0
var gcd_until := 0.0
var busy_until := 0.0
var casting := -1
var cast_from := 0.0
var channel_next := 0.0
var channel_left := 0

var charges := PackedInt32Array()
var recharge_at := PackedFloat64Array()
var buffs := {}                         # name -> {"stacks": int, "until": float}

var target_hp := 1.0
var target_max := 1.0
var damage := 0.0
var used := PackedInt32Array()
var wasted_procs := 0
var starved := 0.0

var _rng := RandomNumberGenerator.new()


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
	_rng.seed = seed_value


# --- buffs --------------------------------------------------------------------

func stacks(name: String) -> int:
	var b: Dictionary = buffs.get(name, {})
	if b.is_empty() or now >= b["until"]:
		return 0
	return b["stacks"]


func grant(name: String, n: int, secs: float) -> void:
	if precise_shots == false and name == "Precise Shots":
		return
	if stacks(name) > 0 and name == "Precise Shots":
		wasted_procs += stacks(name)
	buffs[name] = {"stacks": n, "until": now + secs}


func consume(name: String) -> bool:
	var n := stacks(name)
	if n <= 0:
		return false
	buffs[name]["stacks"] = n - 1
	return true


# --- the clock ----------------------------------------------------------------

func step() -> void:
	now += TICK
	focus = minf(focus + focus_regen * TICK, focus_max)
	for i in ABILITIES.size():
		var a: Dictionary = ABILITIES[i]
		if charges[i] < a["charges"] and now >= recharge_at[i]:
			charges[i] += 1
			if charges[i] < a["charges"]:
				recharge_at[i] = now + _cd_of(i)
	if channel_left > 0 and now >= channel_next:
		_hit(RAPID, float(ABILITIES[RAPID]["coef"]) / float(ABILITIES[RAPID]["ticks"]))
		channel_left -= 1
		channel_next = now + float(ABILITIES[RAPID]["cast"]) / float(ABILITIES[RAPID]["ticks"])
		if channel_left == 0:
			casting = -1
	elif casting >= 0 and casting != RAPID and now >= busy_until:
		var s := casting
		casting = -1
		_land(s)


func _cd_of(i: int) -> float:
	var cd: float = ABILITIES[i]["cd"]
	if i == RAPID and stacks("Trueshot") > 0:
		cd *= 0.5
	return cd


func cast_time(i: int) -> float:
	var t: float = ABILITIES[i]["cast"]
	if stacks("Trueshot") > 0 and (i == AIMED or i == STEADY):
		t *= 0.5
	return t


func can_use(i: int) -> bool:
	if now < gcd_until or casting >= 0 or now < busy_until:
		return false
	if charges[i] <= 0:
		return false
	if focus + float(ABILITIES[i]["focus"]) < 0.0:
		return false
	if i == KILL and target_hp > target_max * 0.20:
		return false
	if i == ARCANE and precise_shots and stacks("Precise Shots") == 0:
		# Arcane Shot is a PROC SPENDER, not a filler. Without a stack it is a worse
		# Steady Shot that also costs focus. This one condition is what turns six
		# buttons into a rotation.
		return false
	return true


func use(i: int) -> void:
	if not can_use(i):
		return
	var a: Dictionary = ABILITIES[i]
	var g := GCD
	if stacks("Trueshot") > 0 and i == RAPID:
		g *= 0.5
	gcd_until = now + g
	if float(a["cd"]) > 0.0:
		charges[i] -= 1
		if charges[i] == int(a["charges"]) - 1:
			recharge_at[i] = now + _cd_of(i)
	var ct := cast_time(i)
	if ct > 0.0:
		casting = i
		cast_from = now
		busy_until = now + ct
		if i == RAPID:
			# a channel never reaches _land, so its bookkeeping happens here
			channel_left = a["ticks"]
			channel_next = now
			used[i] += 1
			focus = clampf(focus + float(a["focus"]), 0.0, focus_max)
		return
	_land(i)


func _land(i: int) -> void:
	var a: Dictionary = ABILITIES[i]
	focus = clampf(focus + float(a["focus"]), 0.0, focus_max)
	used[i] += 1
	if i == TRUESHOT:
		grant("Trueshot", 1, 15.0)
		return
	_hit(i, a["coef"])


func _hit(i: int, coef: float) -> void:
	var a: Dictionary = ABILITIES[i]
	var mult := 1.0
	if lone_wolf:
		mult *= 1.10
	if float(a["focus"]) < 0.0:
		mult *= 1.0 + mastery          # Sniper Training touches spenders only
	if i == AIMED and careful_aim and target_hp > target_max * 0.80:
		mult *= 1.50
	if (i == ARCANE or i == MULTI) and precise_shots and consume("Precise Shots"):
		mult *= 1.75
	if i == AIMED:
		grant("Precise Shots", 2, 15.0)
	if crit > 0.0 and _rng.randf() < crit:
		mult *= 2.0
	var hits := targets if (i == MULTI) else 1
	if not a.get("magic", false):
		mult *= ARMOUR
	var dmg := attack_power * coef * (1.0 + versatility) * mult * hits
	damage += dmg
	target_hp = maxf(target_hp - dmg, 0.0)


# --- the robot that plays it --------------------------------------------------

func auto(list: Array) -> void:
	if now < gcd_until or casting >= 0 or now < busy_until:
		return
	for i in list:
		if can_use(i):
			use(i)
			return
	starved += TICK


## one clean hit, no procs, no execute window — for checking the model against a table
func plain(i: int) -> float:
	var a: Dictionary = ABILITIES[i]
	var mult := 1.10 if lone_wolf else 1.0
	if float(a["focus"]) < 0.0:
		mult *= 1.0 + mastery
	if not a.get("magic", false):
		mult *= ARMOUR
	return attack_power * float(a["coef"]) * (1.0 + versatility) * mult


func run(list_name: String, hp: float, max_seconds := 600.0) -> Dictionary:
	reset(hp)
	var list: Array = PRIORITIES[list_name]
	while target_hp > 0.0 and now < max_seconds:
		auto(list)
		step()
	return {
		"dps": damage / maxf(now, 0.001),
		"time": now,
		"killed": target_hp <= 0.0,
		"starved": starved,
		"wasted": wasted_procs,
		"used": used.duplicate(),
	}
