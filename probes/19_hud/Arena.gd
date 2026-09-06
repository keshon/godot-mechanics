extends Node3D

# 19 — the combat HUD. Two halves that look like one thing and are not.
#
#   the bar     an interface made of clocks. cooldowns, a global cooldown, charges,
#               a cast that a step can break.
#   the overlay an interface made of geometry. the world projected onto the screen,
#               and everything that goes wrong when the target is behind you.
#
# WASD moves and breaks a cast. 1..6 use abilities. C swaps the cooldown to the wrong
# way of counting. U takes away the behind-the-camera guard. TAB spins the camera.

@export_range(4, 200) var count := 10
@export var spin := 0.0

var enemies: Array[Dictionary] = []
var hero := Vector3.ZERO
var hits := 0
var yaw := 0.0
var clock := 0.0
var awake := true

var _rng := RandomNumberGenerator.new()
var _bar: HudBar
var _over: HudOverlay


func _ready() -> void:
	_bar = $Ui/Root/Bar
	_over = $Ui/Overlay
	_over.arena = self
	_over.cam = $Rig/Camera
	_bar.cast_done.connect(_use)
	_spawn()


func _spawn() -> void:
	_rng.seed = 8
	enemies.clear()
	for i in count:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(4.0, 17.0)
		enemies.append({"pos": Vector3(cos(a) * d, 0.0, sin(a) * d),
			"hp": 60.0, "max": 60.0, "phase": _rng.randf() * TAU})
	hits = 0


func _process(delta: float) -> void:
	_move(delta)
	_wander(delta)
	clock += delta
	_bar.tick(clock, awake)
	_over.tick(delta)
	yaw += spin * delta
	$Rig.rotation.y = yaw
	$Rig.position = hero
	$Hero.position = hero + Vector3(0, 0.9, 0)
	_paint()
	_hud()


func _move(delta: float) -> void:
	var v := Vector3(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		0.0,
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward"))
	if v == Vector3.ZERO:
		return
	# moving breaks a cast. one line, and it is most of what casting FEELS like.
	_bar.break_cast()
	hero += Basis.from_euler(Vector3(0, yaw, 0)) * v.normalized() * 7.0 * delta


func _wander(delta: float) -> void:
	for e in enemies:
		if e["hp"] <= 0.0:
			continue
		e["phase"] += delta * 0.7
		var to: Vector3 = hero - e["pos"]
		var away := to.length()
		var drift := Vector3(cos(e["phase"]), 0.0, sin(e["phase"])) * 1.2
		if away > 6.0:
			e["pos"] += (to.normalized() * 2.0 + drift) * delta
		else:
			e["pos"] += drift * delta


func _use(slot: int) -> void:
	var a: Dictionary = HudBar.ABILITIES[slot]
	if a["name"] == "Dash":
		hero += Basis.from_euler(Vector3(0, yaw, 0)) * Vector3(0, 0, -5.0)
		_over.pop(hero + Vector3(0, 1.6, 0), "dash", Color(0.6, 0.95, 0.7))
		return
	if float(a["dmg"]) <= 0.0:
		_over.pop(hero + Vector3(0, 1.6, 0), "+30", Color(0.5, 0.95, 0.55))
		return
	var reach := 14.0 if a["aoe"] else 7.0
	var struck := 0
	for e in enemies:
		if e["hp"] <= 0.0 or e["pos"].distance_to(hero) > reach:
			continue
		var dmg: float = float(a["dmg"]) * _rng.randf_range(0.85, 1.15)
		var crit: bool = _rng.randf() < 0.2
		if crit:
			dmg *= 2.0
		e["hp"] = maxf(e["hp"] - dmg, 0.0)
		_over.pop(e["pos"] + Vector3(0, 1.7, 0), "%d%s" % [roundi(dmg), "!" if crit else ""],
			Color(1, 0.9, 0.35) if crit else Color(1, 1, 1))
		struck += 1
		hits += 1
		if not a["aoe"]:
			break
	if struck == 0:
		_over.pop(hero + Vector3(0, 1.9, 0), "out of reach", Color(1, 0.5, 0.45))


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			_bar.press(event.keycode - KEY_1)
		KEY_C:
			_bar.countdown_mode = not _bar.countdown_mode
		KEY_U:
			_over.guard = not _over.guard
		KEY_TAB:
			spin = 0.0 if spin != 0.0 else 0.9
		KEY_R:
			_spawn()
		KEY_SPACE:
			count = 10 if count > 60 else 120
			_spawn()


func _paint() -> void:
	var mm: MultiMesh = $Foes.multimesh
	mm.instance_count = enemies.size()
	for i in enemies.size():
		var e: Dictionary = enemies[i]
		var alive: bool = e["hp"] > 0.0
		mm.set_instance_transform(i, Transform3D(
			Basis.IDENTITY.scaled(Vector3.ONE * (1.0 if alive else 0.001)),
			e["pos"] + Vector3(0, 0.7, 0)))
		mm.set_instance_color(i, Color(0.9, 0.4, 0.35))


func _hud() -> void:
	var alive := 0
	for e in enemies:
		if e["hp"] > 0.0:
			alive += 1
	var t := "[b]%d enemies, %d alive[/b]    %d hits landed\n\n" % [
		enemies.size(), alive, hits]
	t += "[b]C  how the cooldown is counted:[/b]  %s\n" % (
		"[color=#ff8a6a]left -= delta   (drifts, and stops if the bar hides)[/color]"
		if _bar.countdown_mode else "[color=#7fe08a]a moment it ends[/color]")
	t += "[b]H  bar updated:[/b]  %s
" % (
		"[color=#7fe08a]yes[/color]" if awake else
		"[color=#ff8a6a]NO — hold a cooldown, press H, wait, press H again[/color]")
	t += "[b]U  behind-the-camera guard:[/b]  %s\n" % (
		"[color=#7fe08a]on[/color]" if _over.guard else "[color=#ff8a6a]off — look away from them[/color]")
	t += "   behind the camera right now: %d    arrows on the rim: %d\n\n" % [
		_over.behind_now, _over.arrows_now]
	t += "floating numbers alive %d, pool %d\n\n" % [_over.live(), _over.floats.size()]
	t += "WASD move (breaks a cast)   1..6 abilities   TAB spin the camera\n"
	t += "SPACE 10 or 120 enemies   R reset"
	$Ui/Root/Info.text = t
